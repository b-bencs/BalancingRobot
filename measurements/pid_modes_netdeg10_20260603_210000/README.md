# PID Mode Network Degradation Measurements - 10 ms

This folder contains BE, GD, and EDF robot measurements under beta `flannel.1` network delay of `10ms +/- 2ms` with normal distribution. Robot ran on gamma; PID server ran on beta. Each mode had a 10 s warmup and a 120 s requested measurement window. The `tc` rule was removed after the run and `tc_after_cleanup.txt` confirms `flannel.1` returned to `noqueue`.

Main result: 10 ms degradation did not make BE or EDF fall, but GD restarted three times and had much worse effective sampling. EDF stayed stable with no restarts and no Influx timeout samples.

Files:

- `pid_modes_degradation_summary.csv`: summary for this 10 ms degraded run.
- `combined_clean_net10_net20_summary.csv`: clean, 10 ms, and 20 ms comparison.
- `net10_angle.png`, `net10_summary_bars.png`: plots for this run.
- `combined_*.png`: comparison plots across clean/10 ms/20 ms.
- Per-mode folders contain raw Influx data, robot logs, pod placement, and scheduler logs.
