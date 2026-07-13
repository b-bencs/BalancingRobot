# Measurement Runners

## Kubernetes High-Priority CPU Timeout Boundary

The reusable CPU stress measurement script is:

```bash
./measurements/run_k8s_cpu_timeout_boundary.sh
```

Run it from the `BalancingRobot` directory:

```bash
cd /home/muuurk/rt-faas/BalancingRobot
GATEWAY=http://127.0.0.1:31112 \
TIMEOUT_SEQUENCE="60 50" \
WARMUP_SECONDS=10 \
MEASURE_SECONDS=120 \
FPS=100 \
STRESS_NODE=beta \
./measurements/run_k8s_cpu_timeout_boundary.sh
```

The script compares the `gd` and `edf` PID function deployments while a Kubernetes high-priority CPU stressor runs on the PID node. It logs into OpenFaaS, deploys the selected PID mode, starts and removes the stressor pod, patches the robot timeout/FPS command, restarts the robot, captures logs and Kubernetes state, exports InfluxDB data, and writes summary CSV/PNG/README files.

The output goes to a timestamped folder like:

```text
BalancingRobot/measurements/pid_modes_k8s_highprio_cpu_timeout_boundary_YYYYMMDD_HHMMSS
```

The latest timeout-boundary result path is also written to:

```text
BalancingRobot/measurements/LAST_PID_MODES_K8S_HIGHPRIO_CPU_TIMEOUT_BOUNDARY.txt
```

### Useful CPU Overrides

```bash
GATEWAY=http://127.0.0.1:31112
TIMEOUT_SEQUENCE="60 50"
WARMUP_SECONDS=10
MEASURE_SECONDS=120
FPS=100
STRESS_NODE=beta
STRESS_CPU_REQUEST=3500m
STRESS_PROCESSES=4
STRESS_IMAGE=botondbencs/edf-pidserver:latest
PRIORITY_CLASS=rtfaas-high-priority-stressor
```

Example short smoke run:

```bash
cd /home/muuurk/rt-faas/BalancingRobot
TIMEOUT_SEQUENCE="60" WARMUP_SECONDS=3 MEASURE_SECONDS=10 ./measurements/run_k8s_cpu_timeout_boundary.sh
```

## Network Degradation

The reusable network degradation script is:

```bash
./measurements/run_network_degradation.sh
```

Run the 10 ms network degradation measurement from the `BalancingRobot` directory:

```bash
cd /home/muuurk/rt-faas/BalancingRobot
GATEWAY=http://127.0.0.1:31112 \
TC_HOST=beta \
TC_INTERFACE=flannel.1 \
TC_DELAY=10ms \
TC_JITTER=2ms \
TC_DISTRIBUTION=normal \
ROBOT_TIMEOUT=100 \
FPS=100 \
WARMUP_SECONDS=10 \
MEASURE_SECONDS=120 \
./measurements/run_network_degradation.sh
```

Run the stronger 20 ms degradation:

```bash
cd /home/muuurk/rt-faas/BalancingRobot
TC_DELAY=20ms \
TC_JITTER=5ms \
CONDITION=net20 \
OUTDIR_LABEL=pid_modes_netdeg20 \
./measurements/run_network_degradation.sh
```

The script applies `tc netem` on the PID node over SSH, deploys the `be`, `gd`, and `edf` PID function modes, restarts the robot for each mode, captures robot/PID/Kubernetes/Influx data, writes a summary CSV/README/PNG files, then removes the `tc` rule during cleanup.

The output goes to a timestamped folder like:

```text
BalancingRobot/measurements/pid_modes_netdeg10_YYYYMMDD_HHMMSS
```

The latest network degradation result path is also written to:

```text
BalancingRobot/measurements/LAST_PID_MODES_NETWORK_DEGRADATION.txt
```

### Useful Network Overrides

```bash
GATEWAY=http://127.0.0.1:31112
MODES="be gd edf"
ROBOT_TIMEOUT=100
FPS=100
WARMUP_SECONDS=10
MEASURE_SECONDS=120
PID_NODE=beta
TC_HOST=beta
TC_INTERFACE=flannel.1
TC_DELAY=10ms
TC_JITTER=2ms
TC_DISTRIBUTION=normal
CONDITION=net10
OUTDIR_LABEL=pid_modes_netdeg10
```

Example short smoke run:

```bash
cd /home/muuurk/rt-faas/BalancingRobot
MODES="edf" WARMUP_SECONDS=3 MEASURE_SECONDS=10 ./measurements/run_network_degradation.sh
```

## Commands Not In The Script

These commands prepare or verify the environment. The measurement script assumes this setup already exists.

### Check Kubernetes And Tools

```bash
kubectl cluster-info
kubectl get nodes -o wide
helm version
faas-cli version
python3 --version
ssh beta 'sudo tc qdisc show dev flannel.1'
```

### Label The Measurement Nodes

The saved measurements used `gamma` for the robot and `beta` for the PID server/stressor.

```bash
kubectl label node gamma job=robot --overwrite
kubectl label node beta job=pid --overwrite
```

### Install OpenFaaS

```bash
curl -sSLf https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
kubectl apply -f /home/muuurk/rt-faas/FaaS/faas-netes/namespaces.yml
helm repo add openfaas https://openfaas.github.io/faas-netes/
helm repo update
helm upgrade openfaas --install openfaas/openfaas \
  --namespace openfaas \
  --set functionNamespace=openfaas-fn \
  --set generateBasicAuth=true \
  --set openfaasPRO=false \
  --set faasnetes.image=szefoka/faas-netes:latest \
  --set openfaasImagePullPolicy=Always
```

If the gateway is not exposed on `127.0.0.1:31112`, keep this port-forward running in another terminal:

```bash
kubectl -n openfaas port-forward svc/gateway 31112:8080
```

Manual OpenFaaS login check:

```bash
OPENFAAS_USER="$(kubectl get secret -n openfaas basic-auth -o jsonpath='{.data.basic-auth-user}' | base64 -d)"
OPENFAAS_PASS="$(kubectl get secret -n openfaas basic-auth -o jsonpath='{.data.basic-auth-password}' | base64 -d)"
printf '%s' "$OPENFAAS_PASS" | faas-cli login --gateway http://127.0.0.1:31112 --username "$OPENFAAS_USER" --password-stdin
```

### Build Or Install The Patched FaaS CLI

Only needed when `faas-cli` is missing or not the EDF-aware patched version.

```bash
cd /home/muuurk/rt-faas/FaaS/faas-cli
go build
sudo cp faas-cli /usr/local/bin/faas-cli
```

### Build And Push Images After Code Changes

Robot image:

```bash
cd /home/muuurk/rt-faas/BalancingRobot/Robot
bash build.sh
```

PID server/stressor image:

```bash
cd /home/muuurk/rt-faas/BalancingRobot/Server
bash build.sh
```

OpenFaaS function images:

```bash
cd /home/muuurk/rt-faas/BalancingRobot/functions
faas-cli build -f pidserver_gd.yaml
faas-cli push -f pidserver_gd.yaml
faas-cli build -f pidserver_edf.yaml
faas-cli push -f pidserver_edf.yaml
```

The script runs `faas-cli deploy` for each mode, so deploy is not required here unless you want to test manually.

### Install InfluxDB, Grafana, And Robot

```bash
cd /home/muuurk/rt-faas/BalancingRobot/Influxdb
bash influxdb_install.sh
```

```bash
kubectl apply -f /home/muuurk/rt-faas/BalancingRobot/Grafana/grafana.yaml
kubectl apply -f /home/muuurk/rt-faas/BalancingRobot/Robot/deployment.yaml
```

### Create The High-Priority Stressor Class

The script expects this `PriorityClass` to exist.

```bash
kubectl apply -f - <<'EOF'
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: rtfaas-high-priority-stressor
value: 1000000
globalDefault: false
preemptionPolicy: PreemptLowerPriority
description: High-priority CPU stressor used by RT-FaaS measurements.
EOF
```

### Verify Before Running Measurements

```bash
kubectl get deploy robot -o wide
kubectl get pod -l app=robot -o wide
kubectl get priorityclass rtfaas-high-priority-stressor
kubectl get pods -n openfaas-fn -o wide
kubectl exec influxdb-0 -- influx -execute 'SHOW DATABASES'
ssh beta 'sudo tc qdisc show dev flannel.1'
```

### Older Manual Degradation Commands

These are the manual equivalents of what `run_network_degradation.sh` now automates.

Network delay on the PID node:

```bash
ssh beta 'sudo tc qdisc add dev flannel.1 root netem delay 10ms 2ms distribution normal'
ssh beta 'sudo tc qdisc show dev flannel.1'
ssh beta 'sudo tc qdisc del dev flannel.1 root'
```

Stronger network delay:

```bash
ssh beta 'sudo tc qdisc add dev flannel.1 root netem delay 20ms 5ms distribution normal'
ssh beta 'sudo tc qdisc del dev flannel.1 root'
```

Host-level CPU stress:

```bash
ssh beta 'stress-ng --cpu 4 --cpu-load 100 --timeout 180s --metrics-brief'
```

### Inspect Results

CPU timeout-boundary result:

```bash
latest="$(cat /home/muuurk/rt-faas/BalancingRobot/measurements/LAST_PID_MODES_K8S_HIGHPRIO_CPU_TIMEOUT_BOUNDARY.txt)"
ls "$latest"
sed -n '1,120p' "$latest/README.md"
column -s, -t "$latest/k8s_highprio_cpu_timeout_boundary_summary.csv"
```

Network degradation result:

```bash
latest="$(cat /home/muuurk/rt-faas/BalancingRobot/measurements/LAST_PID_MODES_NETWORK_DEGRADATION.txt)"
ls "$latest"
sed -n '1,120p' "$latest/README.md"
column -s, -t "$latest/pid_modes_network_degradation_summary.csv"
```

For the written-up results and interpretation, see:

```text
BalancingRobot/measurements/MEASUREMENT_DOCUMENTATION_BILINGUAL.md
```
