#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

GATEWAY="${GATEWAY:-http://127.0.0.1:31112}"
FPS="${FPS:-100}"
WARMUP_SECONDS="${WARMUP_SECONDS:-10}"
MEASURE_SECONDS="${MEASURE_SECONDS:-120}"
STRESS_CPU_REQUEST="${STRESS_CPU_REQUEST:-3500m}"
STRESS_MEMORY_REQUEST="${STRESS_MEMORY_REQUEST:-64Mi}"
STRESS_MEMORY_LIMIT="${STRESS_MEMORY_LIMIT:-256Mi}"
STRESS_PROCESSES="${STRESS_PROCESSES:-4}"
STRESS_WORKERS="$(seq -s ' ' 1 "$STRESS_PROCESSES")"
STRESS_NODE="${STRESS_NODE:-beta}"
STRESS_IMAGE="${STRESS_IMAGE:-botondbencs/edf-pidserver:latest}"
PRIORITY_CLASS="${PRIORITY_CLASS:-rtfaas-high-priority-stressor}"
TIMEOUT_SEQUENCE=(${TIMEOUT_SEQUENCE:-60 50})
MODES=(gd edf)

TS="$(date +%Y%m%d_%H%M%S)"
OUTDIR="$REPO_ROOT/measurements/pid_modes_k8s_highprio_cpu_timeout_boundary_${TS}"
mkdir -p "$OUTDIR"

ORIGINAL_ROBOT_COMMAND="$(kubectl get deploy robot -o jsonpath='{.spec.template.spec.containers[0].command}')"

cleanup() {
  kubectl delete pod -l app=rtfaas-cpu-stressor --ignore-not-found --wait=false >/dev/null 2>&1 || true
  if [[ -n "${ORIGINAL_ROBOT_COMMAND:-}" ]]; then
    kubectl patch deploy robot --type=json \
      -p='[{"op":"replace","path":"/spec/template/spec/containers/0/command","value":'"$ORIGINAL_ROBOT_COMMAND"'}]' \
      >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

cat > "$OUTDIR/run_config.txt" <<EOF
outdir=$OUTDIR
measure_seconds=$MEASURE_SECONDS
warmup_seconds=$WARMUP_SECONDS
modes=${MODES[*]}
timeout_sequence=${TIMEOUT_SEQUENCE[*]}
robot_fps=$FPS
stress_type=kubernetes_high_priority_pod
stress_node=$STRESS_NODE
priority_class=$PRIORITY_CLASS
stress_cpu_request=$STRESS_CPU_REQUEST
stress_memory_request=$STRESS_MEMORY_REQUEST
stress_memory_limit=$STRESS_MEMORY_LIMIT
stress_processes=$STRESS_PROCESSES
stress_image=$STRESS_IMAGE
gateway=$GATEWAY
original_robot_command=$ORIGINAL_ROBOT_COMMAND
EOF

kubectl get priorityclass "$PRIORITY_CLASS" -o yaml > "$OUTDIR/priorityclass.yaml"
kubectl get deploy robot -o yaml > "$OUTDIR/robot_deployment_before.yaml"
kubectl get deploy pidserver -n openfaas-fn -o yaml > "$OUTDIR/pidserver_deployment_before.yaml"
kubectl get pods -o wide > "$OUTDIR/pods_before.txt"
kubectl get pods -n openfaas-fn -o wide > "$OUTDIR/openfaas_fn_pods_before.txt"

OPENFAAS_USER="$(kubectl get secret -n openfaas basic-auth -o jsonpath='{.data.basic-auth-user}' | base64 -d)"
OPENFAAS_PASS="$(kubectl get secret -n openfaas basic-auth -o jsonpath='{.data.basic-auth-password}' | base64 -d)"
printf '%s' "$OPENFAAS_PASS" | faas-cli login --gateway "$GATEWAY" --username "$OPENFAAS_USER" --password-stdin > "$OUTDIR/faas_login.log" 2>&1

delete_stressor() {
  kubectl delete pod -l app=rtfaas-cpu-stressor --ignore-not-found --wait=true >/dev/null 2>&1 || true
}

write_stressor_yaml() {
  local timeout="$1"
  local mode="$2"
  local name="$3"
  local mode_dir="$4"

  cat > "$mode_dir/stressor_pod.yaml" <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: $name
  labels:
    app: rtfaas-cpu-stressor
    measurement: k8s-highprio-cpu-timeout-boundary
    timeout_ms: "$timeout"
    mode: "$mode"
spec:
  restartPolicy: Never
  priorityClassName: $PRIORITY_CLASS
  nodeSelector:
    kubernetes.io/hostname: $STRESS_NODE
  containers:
  - name: stressor
    image: $STRESS_IMAGE
    imagePullPolicy: IfNotPresent
    command:
    - sh
    - -c
    - |
      echo starting k8s high-priority CPU stressor mode=$mode timeout_ms=$timeout
      for i in $STRESS_WORKERS; do python -c "while True: pass" &
      done
      wait
    resources:
      requests:
        cpu: $STRESS_CPU_REQUEST
        memory: $STRESS_MEMORY_REQUEST
      limits:
        memory: $STRESS_MEMORY_LIMIT
EOF
}

deploy_pidserver() {
  local mode="$1"
  local mode_dir="$2"
  local yaml="pidserver_${mode}.yaml"

  (
    cd "$REPO_ROOT/functions"
    faas-cli deploy -f "$yaml" --gateway "$GATEWAY"
  ) > "$mode_dir/faas_deploy.log" 2>&1
  kubectl -n openfaas-fn rollout status deploy/pidserver --timeout=180s > "$mode_dir/pidserver_rollout.log" 2>&1
  kubectl -n openfaas-fn patch deploy pidserver --type=merge \
    -p '{"spec":{"template":{"spec":{"nodeSelector":{"kubernetes.io/hostname":"'"$STRESS_NODE"'"}}}}}' \
    > "$mode_dir/pidserver_force_node_patch.log" 2>&1
  kubectl -n openfaas-fn rollout restart deploy/pidserver > "$mode_dir/pidserver_force_node_restart.log" 2>&1
  kubectl -n openfaas-fn rollout status deploy/pidserver --timeout=180s > "$mode_dir/pidserver_force_node_rollout.log" 2>&1
  kubectl -n openfaas-fn get deploy pidserver -o yaml > "$mode_dir/pidserver_deployment.yaml"
  kubectl -n openfaas-fn get pods -l faas_function=pidserver -o wide > "$mode_dir/pidserver_pods_wide.txt"
  local pid_node
  pid_node="$(kubectl -n openfaas-fn get pods -l faas_function=pidserver --sort-by=.metadata.creationTimestamp -o wide | awk 'NR>1 {node=$7} END {print node}')"
  printf '%s\n' "$pid_node" > "$mode_dir/pidserver_node.txt"
  if [[ "$pid_node" != "$STRESS_NODE" ]]; then
    echo "pidserver landed on $pid_node, expected $STRESS_NODE" >&2
    return 1
  fi
}

patch_robot_command() {
  local timeout="$1"
  kubectl patch deploy robot --type=json \
    -p='[{"op":"replace","path":"/spec/template/spec/containers/0/command","value":["./myapp","'"$timeout"'","'"$FPS"'","true"]}]' \
    >/dev/null
}

restart_robot() {
  local mode_dir="$1"

  kubectl rollout restart deploy/robot > "$mode_dir/robot_rollout_restart.log" 2>&1
  kubectl rollout status deploy/robot --timeout=180s > "$mode_dir/robot_rollout_status.log" 2>&1
  sleep 3
  kubectl get pods -l app=robot --sort-by=.metadata.creationTimestamp -o name | tail -n1 | sed 's#pod/##'
}

capture_robot_restart_count() {
  local pod="$1"
  kubectl get pod "$pod" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || printf 'unknown'
}

query_influx() {
  local robot_pod="$1"
  local start_iso="$2"
  local end_iso="$3"
  local mode_dir="$4"

  kubectl exec influxdb-0 -- influx -database robot -format csv -execute \
    "SELECT value,timeout,delta_time FROM angle WHERE robotname = '$robot_pod' AND time >= '$start_iso' AND time <= '$end_iso'" \
    > "$mode_dir/angle.csv" 2> "$mode_dir/angle_query.err" || true

  kubectl exec influxdb-0 -- influx -database robot -format csv -execute \
    "SELECT total_ms,response_code,name_lookup_ms,connect_ms,start_transfer_ms FROM pid_http_request WHERE robotname = '$robot_pod' AND time >= '$start_iso' AND time <= '$end_iso'" \
    > "$mode_dir/pid_http_request.csv" 2> "$mode_dir/pid_http_request_query.err" || true

  kubectl exec influxdb-0 -- influx -database robot -format csv -execute \
    "SELECT latency_ms,timeout,late,applied FROM pid_correction WHERE robotname = '$robot_pod' AND time >= '$start_iso' AND time <= '$end_iso'" \
    > "$mode_dir/pid_correction.csv" 2> "$mode_dir/pid_correction_query.err" || true
}

run_one_mode() {
  local timeout="$1"
  local mode="$2"
  local timeout_dir="$OUTDIR/timeout${timeout}"
  local mode_dir="$timeout_dir/$mode"
  local stressor_name="rtfaas-cpu-boundary-${mode}-${timeout}-$(date +%s)"

  mkdir -p "$mode_dir"
  echo "=== mode=$mode timeout_ms=$timeout ===" | tee "$mode_dir/progress.log"

  delete_stressor
  deploy_pidserver "$mode" "$mode_dir"

  write_stressor_yaml "$timeout" "$mode" "$stressor_name" "$mode_dir"
  kubectl apply -f "$mode_dir/stressor_pod.yaml" > "$mode_dir/stressor_apply.log" 2>&1
  kubectl wait --for=condition=Ready "pod/$stressor_name" --timeout=120s > "$mode_dir/stressor_wait.log" 2>&1
  kubectl describe pod "$stressor_name" > "$mode_dir/stressor_describe_start.txt" 2>&1 || true
  kubectl get pod "$stressor_name" -o yaml > "$mode_dir/stressor_pod_live.yaml" 2>&1 || true

  patch_robot_command "$timeout"
  local robot_pod
  robot_pod="$(restart_robot "$mode_dir")"
  printf '%s\n' "$robot_pod" > "$mode_dir/robot_pod.txt"
  kubectl get pod "$robot_pod" -o wide > "$mode_dir/robot_pod_wide_start.txt" 2>&1 || true
  kubectl describe pod "$robot_pod" > "$mode_dir/robot_describe_start.txt" 2>&1 || true
  capture_robot_restart_count "$robot_pod" > "$mode_dir/robot_restarts_before.txt"

  echo "warmup ${WARMUP_SECONDS}s" | tee -a "$mode_dir/progress.log"
  sleep "$WARMUP_SECONDS"
  local start_iso
  start_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '%s\n' "$start_iso" > "$mode_dir/measurement_start_utc.txt"

  echo "measure ${MEASURE_SECONDS}s" | tee -a "$mode_dir/progress.log"
  sleep "$MEASURE_SECONDS"
  local end_iso
  end_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '%s\n' "$end_iso" > "$mode_dir/measurement_end_utc.txt"

  capture_robot_restart_count "$robot_pod" > "$mode_dir/robot_restarts_after.txt"
  kubectl get pod "$robot_pod" -o wide > "$mode_dir/robot_pod_wide_end.txt" 2>&1 || true
  kubectl describe pod "$robot_pod" > "$mode_dir/robot_describe_end.txt" 2>&1 || true
  kubectl logs "$robot_pod" > "$mode_dir/robot.log" 2> "$mode_dir/robot_log.err" || true
  kubectl logs "$robot_pod" --previous > "$mode_dir/robot_previous.log" 2> "$mode_dir/robot_previous_log.err" || true

  kubectl get pod "$stressor_name" -o wide > "$mode_dir/stressor_pod_wide_end.txt" 2>&1 || true
  kubectl describe pod "$stressor_name" > "$mode_dir/stressor_describe_end.txt" 2>&1 || true
  kubectl logs "$stressor_name" > "$mode_dir/stressor.log" 2> "$mode_dir/stressor_log.err" || true
  kubectl top pod "$stressor_name" > "$mode_dir/stressor_top.txt" 2> "$mode_dir/stressor_top.err" || true
  kubectl top pod -n openfaas-fn -l faas_function=pidserver > "$mode_dir/pidserver_top.txt" 2> "$mode_dir/pidserver_top.err" || true

  query_influx "$robot_pod" "$start_iso" "$end_iso" "$mode_dir"

  delete_stressor
}

analyze_outdir() {
  python3 - "$OUTDIR" <<'PY'
import csv
import math
import re
import statistics
import sys
from pathlib import Path

outdir = Path(sys.argv[1])
rows = []

def read_csv(path):
    if not path.exists() or path.stat().st_size == 0:
        return []
    with path.open(newline="") as f:
        return list(csv.DictReader(f))

def p95(values):
    values = sorted(v for v in values if math.isfinite(v))
    if not values:
        return ""
    idx = math.ceil(0.95 * len(values)) - 1
    return values[max(0, min(idx, len(values) - 1))]

def num(x):
    try:
        return float(x)
    except (TypeError, ValueError):
        return math.nan

def read_text(path):
    try:
        return path.read_text(errors="replace")
    except FileNotFoundError:
        return ""

for timeout_dir in sorted(outdir.glob("timeout*")):
    if not timeout_dir.is_dir():
        continue
    timeout_ms = timeout_dir.name.replace("timeout", "")
    for mode_dir in sorted(timeout_dir.iterdir()):
        if not mode_dir.is_dir():
            continue
        mode = mode_dir.name
        robot_pod = read_text(mode_dir / "robot_pod.txt").strip()
        angle = read_csv(mode_dir / "angle.csv")
        http = read_csv(mode_dir / "pid_http_request.csv")
        correction = read_csv(mode_dir / "pid_correction.csv")
        log_text = read_text(mode_dir / "robot.log") + "\n" + read_text(mode_dir / "robot_previous.log")

        angle_values = [num(r.get("value")) for r in angle if r.get("value") not in (None, "")]
        angle_times = [int(float(r["time"])) for r in angle if r.get("time")]
        abs_values = [abs(v) for v in angle_values if math.isfinite(v)]
        delta_times = [num(r.get("delta_time")) for r in angle if r.get("delta_time") not in (None, "")]
        influx_timeouts = sum(1 for r in angle if str(r.get("timeout", "")).strip() not in ("", "0", "0.0"))
        fall_samples = sum(1 for v in abs_values if v >= 0.785)
        duration_s = ""
        sample_hz = ""
        if len(angle_times) >= 2:
            duration_s = (max(angle_times) - min(angle_times)) / 1e9
            sample_hz = len(angle_times) / duration_s if duration_s > 0 else ""

        http_total = [num(r.get("total_ms")) for r in http if r.get("total_ms") not in (None, "")]
        http_ok = sum(1 for r in http if str(r.get("status", "")).strip() == "ok")
        http_error = sum(1 for r in http if str(r.get("status", "")).strip() == "error")
        corr_latency = [num(r.get("latency_ms")) for r in correction if r.get("latency_ms") not in (None, "")]
        corr_timeouts = sum(1 for r in correction if str(r.get("timeout", "")).strip() not in ("", "0", "0.0"))
        corr_errors = sum(1 for r in correction if str(r.get("status", "")).strip() == "error")

        log_main_timeouts = len(re.findall(r"main_thread_timeout=true", log_text))
        log_exceptions = len(re.findall(r"request exception|worker catch|timeoutCorrection catch", log_text))
        log_pid_ok_ms = [float(m.group(1)) for m in re.finditer(r"request ok duration_ms=([0-9.]+)", log_text)]

        before = read_text(mode_dir / "robot_restarts_before.txt").strip()
        after = read_text(mode_dir / "robot_restarts_after.txt").strip()

        rows.append({
            "condition": "k8s_highprio_cpu_timeout_boundary",
            "timeout_ms": timeout_ms,
            "fps": "100",
            "mode": mode,
            "robot_pod": robot_pod,
            "samples": len(angle_values),
            "duration_s": f"{duration_s:.3f}" if isinstance(duration_s, float) else "",
            "sample_hz": f"{sample_hz:.3f}" if isinstance(sample_hz, float) else "",
            "min_angle": f"{min(angle_values):.9g}" if angle_values else "",
            "max_angle": f"{max(angle_values):.9g}" if angle_values else "",
            "max_abs_angle": f"{max(abs_values):.9g}" if abs_values else "",
            "fell": "yes" if fall_samples > 0 else "no",
            "fall_samples_abs_ge_0_785": fall_samples,
            "influx_timeout_samples": influx_timeouts,
            "pid_correction_timeout_samples": corr_timeouts,
            "pid_correction_error_samples": corr_errors,
            "log_main_thread_timeouts": log_main_timeouts,
            "log_exceptions_or_worker_catches": log_exceptions,
            "mean_delta_time_s": f"{statistics.mean(delta_times):.9g}" if delta_times else "",
            "p95_delta_time_s": f"{p95(delta_times):.9g}" if delta_times else "",
            "pid_http_count": len(http_total),
            "pid_http_ok_count": http_ok,
            "pid_http_error_count": http_error,
            "pid_http_mean_ms": f"{statistics.mean(http_total):.3f}" if http_total else "",
            "pid_http_p95_ms": f"{p95(http_total):.3f}" if http_total else "",
            "pid_http_max_ms": f"{max(http_total):.3f}" if http_total else "",
            "pid_correction_count": len(corr_latency),
            "pid_correction_mean_ms": f"{statistics.mean(corr_latency):.3f}" if corr_latency else "",
            "pid_correction_p95_ms": f"{p95(corr_latency):.3f}" if corr_latency else "",
            "pid_correction_max_ms": f"{max(corr_latency):.3f}" if corr_latency else "",
            "log_pid_request_count": len(log_pid_ok_ms),
            "log_pid_request_mean_ms": f"{statistics.mean(log_pid_ok_ms):.3f}" if log_pid_ok_ms else "",
            "log_pid_request_p95_ms": f"{p95(log_pid_ok_ms):.3f}" if log_pid_ok_ms else "",
            "log_pid_request_max_ms": f"{max(log_pid_ok_ms):.3f}" if log_pid_ok_ms else "",
            "robot_restarts_before_after": f"{before}->{after}",
        })

fields = [
    "condition", "timeout_ms", "fps", "mode", "robot_pod", "samples",
    "duration_s", "sample_hz", "min_angle", "max_angle", "max_abs_angle",
    "fell", "fall_samples_abs_ge_0_785", "influx_timeout_samples",
    "pid_correction_timeout_samples", "pid_correction_error_samples",
    "log_main_thread_timeouts", "log_exceptions_or_worker_catches",
    "mean_delta_time_s", "p95_delta_time_s", "pid_http_count",
    "pid_http_ok_count", "pid_http_error_count", "pid_http_mean_ms",
    "pid_http_p95_ms", "pid_http_max_ms", "pid_correction_count",
    "pid_correction_mean_ms", "pid_correction_p95_ms",
    "pid_correction_max_ms", "log_pid_request_count",
    "log_pid_request_mean_ms", "log_pid_request_p95_ms",
    "log_pid_request_max_ms", "robot_restarts_before_after",
]
summary_path = outdir / "k8s_highprio_cpu_timeout_boundary_summary.csv"
with summary_path.open("w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=fields)
    writer.writeheader()
    writer.writerows(rows)

readme = outdir / "README.md"
lines = [
    "# Kubernetes high-priority CPU timeout-boundary measurement",
    "",
    "This run keeps the high-priority CPU stressor fixed on beta and compares only GD and EDF while tightening the robot correction timeout.",
    "",
    "Fixed parameters:",
    f"- FPS: 100",
    f"- Warmup: see run_config.txt",
    f"- Measurement window: see run_config.txt",
    f"- Stressor: Kubernetes pod with priorityClassName=rtfaas-high-priority-stressor on beta",
    f"- Stressor CPU request: 3500m",
    "",
    "Summary:",
    "",
]
if rows:
    lines.append("| timeout ms | mode | fell | max abs angle | Influx timeouts | main-thread timeouts | debug-log PID p95 | restarts |")
    lines.append("| --- | --- | --- | ---: | ---: | ---: | ---: | --- |")
    for r in rows:
        lines.append(
            f"| {r['timeout_ms']} | {r['mode'].upper()} | {r['fell']} | "
            f"{r['max_abs_angle']} | {r['influx_timeout_samples']} | "
            f"{r['log_main_thread_timeouts']} | {r['log_pid_request_p95_ms']} ms | "
            f"{r['robot_restarts_before_after']} |"
        )
lines.extend([
    "",
    "Files:",
    "- `k8s_highprio_cpu_timeout_boundary_summary.csv`: computed summary table.",
    "- Per-mode subfolders: raw robot logs, Influx CSV exports, pod descriptions, PID server deploy logs, and stressor evidence.",
])
readme.write_text("\n".join(lines) + "\n")

try:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    grouped = {}
    for timeout_dir in sorted(outdir.glob("timeout*")):
        for mode_dir in sorted(timeout_dir.iterdir()):
            if not mode_dir.is_dir():
                continue
            data = read_csv(mode_dir / "angle.csv")
            if not data:
                continue
            t0 = None
            xs, ys = [], []
            for r in data:
                if not r.get("time") or not r.get("value"):
                    continue
                t = int(float(r["time"]))
                if t0 is None:
                    t0 = t
                xs.append((t - t0) / 1e9)
                ys.append(num(r["value"]))
            grouped[f"{timeout_dir.name} {mode_dir.name.upper()}"] = (xs, ys)
    if grouped:
        fig, ax = plt.subplots(figsize=(10, 5))
        for label, (xs, ys) in grouped.items():
            ax.plot(xs, ys, label=label, linewidth=1.5)
        ax.axhline(0.785, color="crimson", linestyle="--", linewidth=1, label="fall threshold")
        ax.axhline(-0.785, color="crimson", linestyle="--", linewidth=1)
        ax.set_title("K8s high-priority CPU timeout-boundary angle")
        ax.set_xlabel("seconds from measurement start")
        ax.set_ylabel("angle")
        ax.grid(True, alpha=0.25)
        ax.legend()
        fig.tight_layout()
        fig.savefig(outdir / "k8s_highprio_cpu_timeout_boundary_angle.png", dpi=160)
        plt.close(fig)

    if rows:
        labels = [f"{r['timeout_ms']} {r['mode'].upper()}" for r in rows]
        max_abs = [float(r["max_abs_angle"]) if r["max_abs_angle"] else 0 for r in rows]
        p95 = [float(r["pid_http_p95_ms"]) if r["pid_http_p95_ms"] else 0 for r in rows]
        timeouts = [int(r["pid_correction_timeout_samples"]) for r in rows]
        fig, axes = plt.subplots(1, 3, figsize=(12, 4))
        axes[0].bar(labels, max_abs, color="#4c78a8")
        axes[0].axhline(0.785, color="crimson", linestyle="--", linewidth=1)
        axes[0].set_title("max abs angle")
        axes[1].bar(labels, p95, color="#f58518")
        axes[1].set_title("PID HTTP p95 ms")
        axes[2].bar(labels, timeouts, color="#54a24b")
        axes[2].set_title("correction timeouts")
        for ax in axes:
            ax.tick_params(axis="x", rotation=20)
            ax.grid(axis="y", alpha=0.25)
        fig.tight_layout()
        fig.savefig(outdir / "k8s_highprio_cpu_timeout_boundary_summary.png", dpi=160)
        plt.close(fig)
except Exception as exc:
    (outdir / "plot_error.txt").write_text(str(exc) + "\n")

print(summary_path)
for r in rows:
    print(
        f"timeout={r['timeout_ms']} mode={r['mode']} fell={r['fell']} "
        f"max_abs={r['max_abs_angle']} corr_timeouts={r['pid_correction_timeout_samples']} "
        f"pid_http_p95_ms={r['pid_http_p95_ms']} restarts={r['robot_restarts_before_after']}"
    )
PY
}

run_timeout_set() {
  local timeout="$1"
  for mode in "${MODES[@]}"; do
    run_one_mode "$timeout" "$mode"
  done
  analyze_outdir
}

should_try_next_timeout() {
  local timeout="$1"
  python3 - "$OUTDIR/k8s_highprio_cpu_timeout_boundary_summary.csv" "$timeout" <<'PY'
import csv
import sys
path, timeout = sys.argv[1], sys.argv[2]
rows = []
try:
    with open(path, newline="") as f:
        rows = list(csv.DictReader(f))
except FileNotFoundError:
    print("yes")
    raise SystemExit
gd = [r for r in rows if r.get("timeout_ms") == timeout and r.get("mode") == "gd"]
print("yes" if not gd or gd[0].get("fell") != "yes" else "no")
PY
}

echo "Writing measurement to $OUTDIR"
for idx in "${!TIMEOUT_SEQUENCE[@]}"; do
  timeout="${TIMEOUT_SEQUENCE[$idx]}"
  run_timeout_set "$timeout"
  if [[ "$idx" -lt "$((${#TIMEOUT_SEQUENCE[@]} - 1))" ]]; then
    if [[ "$(should_try_next_timeout "$timeout")" != "yes" ]]; then
      echo "GD already fell at timeout=${timeout}ms; skipping stricter timeout(s)."
      break
    fi
  fi
done

kubectl get deploy robot -o yaml > "$OUTDIR/robot_deployment_after.yaml" 2>&1 || true
kubectl get deploy pidserver -n openfaas-fn -o yaml > "$OUTDIR/pidserver_deployment_after.yaml" 2>&1 || true
kubectl get pods -o wide > "$OUTDIR/pods_after.txt" 2>&1 || true
kubectl get pods -n openfaas-fn -o wide > "$OUTDIR/openfaas_fn_pods_after.txt" 2>&1 || true
printf '%s\n' "$OUTDIR" > "$REPO_ROOT/measurements/LAST_PID_MODES_K8S_HIGHPRIO_CPU_TIMEOUT_BOUNDARY.txt"

echo "Done: $OUTDIR"
