# CPU Stress Measurements

This run compares BE, GD, and EDF PID server modes while `beta`, the PID node, was loaded with:

```bash
stress-ng --cpu 4 --cpu-load 100 --timeout 180s --metrics-brief
```

Each mode used a fresh PID deployment and a fresh robot pod. The stress process started before the robot restart, then the robot warmed up for 10 seconds and was measured for 120 seconds. Stress was stopped after each mode.

Summary:

| mode | fell | timeouts | max abs angle | PID p95 | restarts |
|---|---:|---:|---:|---:|---:|
| BE | no | 3 | 0.0352 | 11.5 ms | 0->1 |
| GD | no | 15 | 0.0351 | 19.5 ms | 0->1 |
| EDF | no | 0 | 0.00106 | 10.8 ms | 0->0 |

Main result: all modes stayed below the fall threshold, but EDF was clearly cleanest: no timeout samples, lowest angle, low PID latency, and no restart during the measured window.

Generated files:

- `pid_modes_cpu_summary.csv`: CPU stress summary table.
- `cpu4_100_angle.png`: angle curves for BE/GD/EDF.
- `cpu4_100_summary_bars.png`: summary bar charts.
- `combined_all_measurements_summary.csv`: clean, network, and CPU combined summary.
- `combined_all_*.png`: comparison plots across clean, network degradation, and CPU stress.
