# PID Mode Measurements - 2026-06-03

This folder contains three 120 s robot measurement windows after a 10 s warmup per mode: BE, GD, and EDF. Robot ran on gamma; PID server ran on beta in every measured mode. EDF required the live rt-faas scheduler annotation patch so the OpenFaaS node-selector annotation was honored.

Key result: no mode produced a fall in this clean no-stress window. EDF had zero timeout samples and the best latency/sample-rate behavior. BE had 2 timeout samples and one robot container restart. GD had 9 timeout samples and lower effective sample rate, but no restart.

Files:

- `pid_modes_summary.csv`: computed summary table.
- `pid_modes_angle.png`: angle over time for BE/GD/EDF.
- `pid_modes_abs_angle_zoom.png`: absolute angle zoomed near zero.
- `pid_modes_summary_bars.png`: max angle, timeout count, p95 PID latency, and effective sample rate.
- Per-mode folders contain raw Influx CSV, robot logs, pod placement, and scheduler tail logs.
