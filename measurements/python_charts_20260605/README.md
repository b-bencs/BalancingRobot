# Python Charts

Generated from the saved measurement CSVs with:

```bash
python3 measurements/python_charts_20260605/generate_charts.py
```

## Files

- `summary_metric_grid.png`: main comparison for max angle, timeout samples, PID p95 latency, and sample rate.
- `fall_restart_health_matrix.png`: easiest chart to explain overall health. Green means clean, yellow means degraded, red means fell.
- `angle_traces_by_condition.png`: full-scale angle traces with fall thresholds.
- `angle_zoom_nonfallen_runs.png`: zoomed angle traces for runs that did not fall.
- `pid_latency_comparison.png`: PID p95 and max HTTP latency from robot debug logs.
- `network_degradation_trend.png`: clean -> 10 ms -> 20 ms network degradation trend.
- `k8s_highprio_cpu_focus.png`: focused chart for the Kubernetes high-priority CPU stress measurement.
- `combined_chart_input.csv`: normalized summary data used by the script.

Important caveat: high sample rate is not always healthy. In fall cases the robot can keep writing the saturated angle (`+/-2.03`) without normal PID correction.
