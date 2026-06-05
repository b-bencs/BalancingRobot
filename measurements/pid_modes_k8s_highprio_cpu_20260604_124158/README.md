# Kubernetes High-Priority CPU Stress Measurements

This run compares BE, GD, and EDF PID server modes while a Kubernetes high-priority CPU stressor pod ran on `beta`, the PID node.

Stressor setup:

- `priorityClassName=rtfaas-high-priority-stressor`
- priority value `1000000`
- `preemptionPolicy=PreemptLowerPriority`
- node: `beta`
- CPU request: `3500m`
- memory request/limit: `64Mi` / `256Mi`
- image: `botondbencs/edf-pidserver:latest`
- workload: four Python CPU-burn loops in one pod

Each mode used a fresh PID deployment, a fresh stressor pod, and a fresh robot pod. The stressor pod started before the robot restart, then the robot warmed up for 10 seconds and was measured for 120 seconds. The stressor pod was deleted after each mode.

Summary:

| mode | fell | timeouts | max abs angle | PID p95 | restarts |
|---|---:|---:|---:|---:|---:|
| BE | yes | 0 | 2.03 | 380 ms | 0->0 |
| GD | no | 4 | 0.0350 | 26.0 ms | 0->1 |
| EDF | no | 0 | 0.00125 | 15.5 ms | 0->0 |

Main result: this is the CPU-stress result needed for the scheduling argument. BE failed under the high-priority Kubernetes stressor. GD survived but degraded and restarted once. EDF stayed clean: no fall, no timeout samples, no restart, and the smallest angle.

Generated files:

- `pid_modes_k8s_highprio_cpu_summary.csv`: summary for this run.
- `k8s_highprio_cpu_angle.png`: angle curves for BE/GD/EDF.
- `k8s_highprio_cpu_summary_bars.png`: summary bar charts.
- `combined_all_measurements_with_k8s_cpu_summary.csv`: clean, network, host CPU, and Kubernetes high-priority CPU combined summary.
- `combined_with_k8s_cpu_*.png`: comparison plots across all saved measurement types.
- Per-mode folders contain raw Influx data, robot logs, PID pod YAML, stressor pod YAML, and scheduler logs.
