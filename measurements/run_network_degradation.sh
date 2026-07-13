#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

GATEWAY="${GATEWAY:-http://127.0.0.1:31112}"
FPS="${FPS:-100}"
ROBOT_TIMEOUT="${ROBOT_TIMEOUT:-100}"
WARMUP_SECONDS="${WARMUP_SECONDS:-10}"
MEASURE_SECONDS="${MEASURE_SECONDS:-120}"
PID_NODE="${PID_NODE:-beta}"
TC_HOST="${TC_HOST:-$PID_NODE}"
TC_INTERFACE="${TC_INTERFACE:-flannel.1}"
TC_DELAY="${TC_DELAY:-10ms}"
TC_JITTER="${TC_JITTER:-2ms}"
TC_DISTRIBUTION="${TC_DISTRIBUTION:-normal}"
CONDITION="${CONDITION:-net${TC_DELAY%ms}}"
OUTDIR_LABEL="${OUTDIR_LABEL:-pid_modes_netdeg${TC_DELAY%ms}}"
read -r -a MODES <<< "${MODES:-be gd edf}"

TS="$(date +%Y%m%d_%H%M%S)"
OUTDIR="$REPO_ROOT/measurements/${OUTDIR_LABEL}_${TS}"
mkdir -p "$OUTDIR"

ORIGINAL_ROBOT_COMMAND="$(kubectl get deploy robot -o jsonpath='{.spec.template.spec.containers[0].command}')"

remote_tc() {
  ssh "$TC_HOST" sudo tc "$@"
}

clear_tc() {
  remote_tc qdisc del dev "$TC_INTERFACE" root >/dev/null 2>&1 || true
}

show_tc() {
  remote_tc qdisc show dev "$TC_INTERFACE"
}

show_tc_stats() {
  remote_tc -s qdisc show dev "$TC_INTERFACE"
}

cleanup() {
  clear_tc
  if [[ -n "${ORIGINAL_ROBOT_COMMAND:-}" ]]; then
    kubectl patch deploy robot --type=json \
      -p='[{"op":"replace","path":"/spec/template/spec/containers/0/command","value":'"$ORIGINAL_ROBOT_COMMAND"'}]' \
      >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

cat > "$OUTDIR/run_config.txt" <<EOF
outdir=$OUTDIR
condition=$CONDITION
measure_seconds=$MEASURE_SECONDS
warmup_seconds=$WARMUP_SECONDS
modes=${MODES[*]}
robot_timeout_ms=$ROBOT_TIMEOUT
robot_fps=$FPS
pid_node=$PID_NODE
tc_host=$TC_HOST
tc_interface=$TC_INTERFACE
netem_delay=$TC_DELAY
netem_jitter=$TC_JITTER
netem_distribution=$TC_DISTRIBUTION
gateway=$GATEWAY
original_robot_command=$ORIGINAL_ROBOT_COMMAND
EOF

show_tc > "$OUTDIR/tc_before.txt" 2>&1 || true
kubectl get deploy robot -o yaml > "$OUTDIR/robot_deployment_before.yaml"
kubectl get deploy pidserver -n openfaas-fn -o yaml > "$OUTDIR/pidserver_deployment_before.yaml" 2>&1 || true
kubectl get pods -o wide > "$OUTDIR/pods_before.txt"
kubectl get pods -n openfaas-fn -o wide > "$OUTDIR/openfaas_fn_pods_before.txt" 2>&1 || true

OPENFAAS_USER="$(kubectl get secret -n openfaas basic-auth -o jsonpath='{.data.basic-auth-user}' | base64 -d)"
OPENFAAS_PASS="$(kubectl get secret -n openfaas basic-auth -o jsonpath='{.data.basic-auth-password}' | base64 -d)"
printf '%s' "$OPENFAAS_PASS" | faas-cli login --gateway "$GATEWAY" --username "$OPENFAAS_USER" --password-stdin > "$OUTDIR/faas_login.log" 2>&1

apply_netem() {
  clear_tc
  remote_tc qdisc add dev "$TC_INTERFACE" root netem delay "$TC_DELAY" "$TC_JITTER" distribution "$TC_DISTRIBUTION"
  show_tc > "$OUTDIR/tc_during.txt" 2>&1 || true
}

deploy_pidserver() {
  local mode="$1"
  local mode_dir="$2"
  local yaml="pidserver_${mode}.yaml"

  (
    cd "$REPO_ROOT/functions"
    faas-cli deploy -f "$yaml" --gateway "$GATEWAY"
  ) > "$mode_dir/faas_deploy.txt" 2>&1

  kubectl -n openfaas-fn rollout status deploy/pidserver --timeout=180s >> "$mode_dir/status.txt" 2>&1
  kubectl -n openfaas-fn patch deploy pidserver --type=merge \
    -p '{"spec":{"template":{"spec":{"nodeSelector":{"kubernetes.io/hostname":"'"$PID_NODE"'"}}}}}' \
    > "$mode_dir/pidserver_force_node_patch.log" 2>&1
  kubectl -n openfaas-fn rollout restart deploy/pidserver > "$mode_dir/pidserver_force_node_restart.log" 2>&1
  kubectl -n openfaas-fn rollout status deploy/pidserver --timeout=180s >> "$mode_dir/status.txt" 2>&1
  kubectl -n openfaas-fn get deploy pidserver -o wide > "$mode_dir/pidserver_wide.txt" 2>&1 || true
  kubectl -n openfaas-fn get pod -l faas_function=pidserver --sort-by=.metadata.creationTimestamp -o yaml | tail -n +1 > "$mode_dir/pidserver_pod.yaml" 2>&1 || true
  kubectl -n openfaas-fn get pods -l faas_function=pidserver -o wide >> "$mode_dir/pidserver_wide.txt" 2>&1 || true

  local pid_node
  pid_node="$(kubectl -n openfaas-fn get pods -l faas_function=pidserver --sort-by=.metadata.creationTimestamp -o wide | awk 'NR>1 {node=$7} END {print node}')"
  printf '%s\n' "$pid_node" > "$mode_dir/pidserver_node.txt"
  if [[ "$pid_node" != "$PID_NODE" ]]; then
    echo "pidserver landed on $pid_node, expected $PID_NODE" >&2
    return 1
  fi
}

patch_robot_command() {
  kubectl patch deploy robot --type=json \
    -p='[{"op":"replace","path":"/spec/template/spec/containers/0/command","value":["./myapp","'"$ROBOT_TIMEOUT"'","'"$FPS"'","true"]}]' \
    >/dev/null
}

restart_robot() {
  local mode_dir="$1"

  kubectl rollout restart deploy/robot >> "$mode_dir/status.txt" 2>&1
  kubectl rollout status deploy/robot --timeout=180s >> "$mode_dir/status.txt" 2>&1
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

capture_scheduler_logs() {
  local mode_dir="$1"
  kubectl -n kube-system logs deploy/rtfaas-scheduler --tail=250 > "$mode_dir/rtfaas_scheduler_tail.log" 2>&1 || true
}

run_one_mode() {
  local mode="$1"
  local mode_dir="$OUTDIR/$mode"
  mkdir -p "$mode_dir"

  {
    echo "=== mode=$mode deploy=pidserver_${mode}.yaml ==="
  } | tee "$mode_dir/status.txt"

  deploy_pidserver "$mode" "$mode_dir"
  patch_robot_command

  local robot_pod
  robot_pod="$(restart_robot "$mode_dir")"
  printf 'robot_pod=%s\n' "$robot_pod" | tee -a "$mode_dir/status.txt"
  printf '%s\n' "$robot_pod" > "$mode_dir/robot_pod.txt"

  kubectl get pod "$robot_pod" -o wide > "$mode_dir/robot_wide.txt" 2>&1 || true
  kubectl describe pod "$robot_pod" > "$mode_dir/robot_describe.txt" 2>&1 || true
  capture_robot_restart_count "$robot_pod" > "$mode_dir/robot_restart_count_before.txt"

  echo "warmup ${WARMUP_SECONDS}s" | tee -a "$mode_dir/status.txt"
  sleep "$WARMUP_SECONDS"
  local start_iso
  start_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'start_utc=%s\n' "$start_iso" | tee -a "$mode_dir/status.txt"
  printf '%s\n' "$start_iso" > "$mode_dir/measurement_start_utc.txt"

  echo "measure ${MEASURE_SECONDS}s" | tee -a "$mode_dir/status.txt"
  sleep "$MEASURE_SECONDS"
  local end_iso
  end_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'end_utc=%s\n' "$end_iso" | tee -a "$mode_dir/status.txt"
  printf '%s\n' "$end_iso" > "$mode_dir/measurement_end_utc.txt"

  capture_robot_restart_count "$robot_pod" > "$mode_dir/robot_restart_count_after.txt"
  kubectl get pod "$robot_pod" -o wide > "$mode_dir/robot_wide_end.txt" 2>&1 || true
  kubectl describe pod "$robot_pod" > "$mode_dir/robot_describe_end.txt" 2>&1 || true
  kubectl logs "$robot_pod" > "$mode_dir/robot.log" 2> "$mode_dir/robot_log.err" || true
  kubectl logs "$robot_pod" --previous > "$mode_dir/robot_previous.log" 2> "$mode_dir/robot_previous.err" || true
  kubectl top pod "$robot_pod" > "$mode_dir/robot_top.txt" 2> "$mode_dir/robot_top.err" || true
  kubectl top pod -n openfaas-fn -l faas_function=pidserver > "$mode_dir/pidserver_top.txt" 2> "$mode_dir/pidserver_top.err" || true
  show_tc_stats > "$mode_dir/tc_stats_after_mode.txt" 2>&1 || true
  capture_scheduler_logs "$mode_dir"
  query_influx "$robot_pod" "$start_iso" "$end_iso" "$mode_dir"
}

analyze_outdir() {
  python3 - "$OUTDIR" "$CONDITION" "$FPS" "$ROBOT_TIMEOUT" "$TC_DELAY" "$TC_JITTER" "$TC_DISTRIBUTION" <<'PY'
import csv
import math
import re
import statistics
import sys
from pathlib import Path

outdir = Path(sys.argv[1])
condition = sys.argv[2]
fps = sys.argv[3]
robot_timeout = sys.argv[4]
tc_delay = sys.argv[5]
tc_jitter = sys.argv[6]
tc_distribution = sys.argv[7]
rows = []

def read_csv(path):
    if not path.exists() or path.stat().st_size == 0:
        return []
    with path.open(newline="") as f:
        return list(csv.DictReader(f))

def read_text(path):
    try:
        return path.read_text(errors="replace")
    except FileNotFoundError:
        return ""

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

for mode_dir in sorted(p for p in outdir.iterdir() if p.is_dir()):
    mode = mode_dir.name
    robot_pod = read_text(mode_dir / "robot_pod.txt").strip()
    pid_node = read_text(mode_dir / "pidserver_node.txt").strip()
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
    corr_latency = [num(r.get("latency_ms")) for r in correction if r.get("latency_ms") not in (None, "")]
    corr_timeouts = sum(1 for r in correction if str(r.get("timeout", "")).strip() not in ("", "0", "0.0"))

    log_main_timeouts = len(re.findall(r"main_thread_timeout=true", log_text))
    log_exceptions = len(re.findall(r"request exception|worker catch|timeoutCorrection catch", log_text))
    log_pid_ok_ms = [float(m.group(1)) for m in re.finditer(r"request ok duration_ms=([0-9.]+)", log_text)]

    before = read_text(mode_dir / "robot_restart_count_before.txt").strip()
    after = read_text(mode_dir / "robot_restart_count_after.txt").strip()

    rows.append({
        "condition": condition,
        "mode": mode,
        "robot_timeout_ms": robot_timeout,
        "fps": fps,
        "tc_delay": tc_delay,
        "tc_jitter": tc_jitter,
        "tc_distribution": tc_distribution,
        "robot_pod": robot_pod,
        "pid_node": pid_node,
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
        "log_main_thread_timeouts": log_main_timeouts,
        "log_exceptions_or_worker_catches": log_exceptions,
        "mean_delta_time_s": f"{statistics.mean(delta_times):.9g}" if delta_times else "",
        "p95_delta_time_s": f"{p95(delta_times):.9g}" if delta_times else "",
        "pid_http_count": len(http_total),
        "pid_http_mean_ms": f"{statistics.mean(http_total):.3f}" if http_total else "",
        "pid_http_p95_ms": f"{p95(http_total):.3f}" if http_total else "",
        "pid_http_max_ms": f"{max(http_total):.3f}" if http_total else "",
        "pid_correction_count": len(corr_latency),
        "pid_correction_mean_ms": f"{statistics.mean(corr_latency):.3f}" if corr_latency else "",
        "pid_correction_p95_ms": f"{p95(corr_latency):.3f}" if corr_latency else "",
        "pid_correction_max_ms": f"{max(corr_latency):.3f}" if corr_latency else "",
        "pid_request_count_from_logs": len(log_pid_ok_ms),
        "pid_request_mean_ms": f"{statistics.mean(log_pid_ok_ms):.3f}" if log_pid_ok_ms else "",
        "pid_request_p95_ms": f"{p95(log_pid_ok_ms):.3f}" if log_pid_ok_ms else "",
        "pid_request_max_ms": f"{max(log_pid_ok_ms):.3f}" if log_pid_ok_ms else "",
        "robot_restarts_before_after": f"{before}->{after}",
    })

fields = [
    "condition", "mode", "robot_timeout_ms", "fps", "tc_delay", "tc_jitter",
    "tc_distribution", "robot_pod", "pid_node", "samples", "duration_s",
    "sample_hz", "min_angle", "max_angle", "max_abs_angle", "fell",
    "fall_samples_abs_ge_0_785", "influx_timeout_samples",
    "pid_correction_timeout_samples", "log_main_thread_timeouts",
    "log_exceptions_or_worker_catches", "mean_delta_time_s",
    "p95_delta_time_s", "pid_http_count", "pid_http_mean_ms",
    "pid_http_p95_ms", "pid_http_max_ms", "pid_correction_count",
    "pid_correction_mean_ms", "pid_correction_p95_ms",
    "pid_correction_max_ms", "pid_request_count_from_logs",
    "pid_request_mean_ms", "pid_request_p95_ms", "pid_request_max_ms",
    "robot_restarts_before_after",
]
summary_path = outdir / "pid_modes_network_degradation_summary.csv"
with summary_path.open("w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=fields)
    writer.writeheader()
    writer.writerows(rows)

readme = outdir / "README.md"
lines = [
    f"# PID Mode Network Degradation Measurements - {tc_delay}",
    "",
    f"This run compares BE, GD, and EDF under `{tc_delay} +/- {tc_jitter}` network delay with `{tc_distribution}` distribution on the PID node pod-network interface.",
    "",
    "Fixed parameters:",
    f"- Robot timeout: {robot_timeout} ms",
    f"- FPS: {fps}",
    "- Warmup: see `run_config.txt`",
    "- Measurement window: see `run_config.txt`",
    f"- Condition: {condition}",
    "",
    "Summary:",
    "",
]
if rows:
    lines.append("| mode | fell | max abs angle | Influx timeouts | main-thread timeouts | PID p95 from logs | restarts |")
    lines.append("| --- | --- | ---: | ---: | ---: | ---: | --- |")
    for r in rows:
        p95_label = f"{r['pid_request_p95_ms']} ms" if r["pid_request_p95_ms"] else "n/a"
        lines.append(
            f"| {r['mode'].upper()} | {r['fell']} | {r['max_abs_angle']} | "
            f"{r['influx_timeout_samples']} | {r['log_main_thread_timeouts']} | "
            f"{p95_label} | {r['robot_restarts_before_after']} |"
        )
lines.extend([
    "",
    "Files:",
    "- `pid_modes_network_degradation_summary.csv`: computed summary table.",
    "- Per-mode folders: raw robot logs, Influx CSV exports, pod descriptions, PID server deploy logs, scheduler tail logs, and `tc` evidence.",
    "- `tc_before.txt`, `tc_during.txt`, `tc_after_cleanup.txt`: network qdisc state before, during, and after cleanup.",
])
readme.write_text("\n".join(lines) + "\n")

try:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    grouped = {}
    for mode_dir in sorted(p for p in outdir.iterdir() if p.is_dir()):
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
        grouped[mode_dir.name.upper()] = (xs, ys)

    if grouped:
        fig, ax = plt.subplots(figsize=(10, 5))
        for label, (xs, ys) in grouped.items():
            ax.plot(xs, ys, label=label, linewidth=1.5)
        ax.axhline(0.785, color="crimson", linestyle="--", linewidth=1, label="fall threshold")
        ax.axhline(-0.785, color="crimson", linestyle="--", linewidth=1)
        ax.set_title(f"PID modes under network delay: {tc_delay} +/- {tc_jitter}")
        ax.set_xlabel("seconds from measurement start")
        ax.set_ylabel("angle")
        ax.grid(True, alpha=0.25)
        ax.legend()
        fig.tight_layout()
        fig.savefig(outdir / f"{condition}_angle.png", dpi=160)
        plt.close(fig)

    if rows:
        labels = [r["mode"].upper() for r in rows]
        max_abs = [float(r["max_abs_angle"]) if r["max_abs_angle"] else 0 for r in rows]
        p95_logs = [float(r["pid_request_p95_ms"]) if r["pid_request_p95_ms"] else 0 for r in rows]
        timeouts = [int(r["influx_timeout_samples"]) for r in rows]
        fig, axes = plt.subplots(1, 3, figsize=(12, 4))
        axes[0].bar(labels, max_abs, color="#4c78a8")
        axes[0].axhline(0.785, color="crimson", linestyle="--", linewidth=1)
        axes[0].set_title("max abs angle")
        axes[1].bar(labels, p95_logs, color="#f58518")
        axes[1].set_title("PID request p95 ms")
        axes[2].bar(labels, timeouts, color="#54a24b")
        axes[2].set_title("Influx timeout samples")
        for ax in axes:
            ax.grid(axis="y", alpha=0.25)
        fig.tight_layout()
        fig.savefig(outdir / f"{condition}_summary_bars.png", dpi=160)
        plt.close(fig)
except Exception as exc:
    (outdir / "plot_error.txt").write_text(str(exc) + "\n")

print(summary_path)
for r in rows:
    print(
        f"mode={r['mode']} fell={r['fell']} max_abs={r['max_abs_angle']} "
        f"influx_timeouts={r['influx_timeout_samples']} "
        f"pid_p95_ms={r['pid_request_p95_ms']} restarts={r['robot_restarts_before_after']}"
    )
PY
}

echo "Writing measurement to $OUTDIR"
echo "Applying tc netem on $TC_HOST:$TC_INTERFACE delay=$TC_DELAY jitter=$TC_JITTER distribution=$TC_DISTRIBUTION"
apply_netem

for mode in "${MODES[@]}"; do
  run_one_mode "$mode"
  analyze_outdir
done

clear_tc
show_tc > "$OUTDIR/tc_after_cleanup.txt" 2>&1 || true

kubectl get deploy robot -o yaml > "$OUTDIR/robot_deployment_after.yaml" 2>&1 || true
kubectl get deploy pidserver -n openfaas-fn -o yaml > "$OUTDIR/pidserver_deployment_after.yaml" 2>&1 || true
kubectl get pods -o wide > "$OUTDIR/pods_after.txt" 2>&1 || true
kubectl get pods -n openfaas-fn -o wide > "$OUTDIR/openfaas_fn_pods_after.txt" 2>&1 || true
printf '%s\n' "$OUTDIR" > "$REPO_ROOT/measurements/LAST_PID_MODES_NETWORK_DEGRADATION.txt"
printf '%s\n' "$OUTDIR" > "$REPO_ROOT/measurements/LAST_PID_MODES_NETDEG_MEASUREMENT.txt"
if [[ "$CONDITION" == "net10" ]]; then
  printf '%s\n' "$OUTDIR" > "$REPO_ROOT/measurements/LAST_PID_MODES_NETDEG10_MEASUREMENT.txt"
fi

echo "Done: $OUTDIR"
