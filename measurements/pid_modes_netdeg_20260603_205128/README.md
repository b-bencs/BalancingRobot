# PID Mode Network Degradation Measurements - 20 ms

This folder contains BE, GD, and EDF robot measurements under beta `flannel.1` network delay of `20ms +/- 5ms` with normal distribution. Robot ran on gamma; PID server ran on beta. Each mode had a 10 s warmup and a 120 s requested measurement window. The `tc` rule was removed after the run and `tc_after_cleanup.txt` confirms `flannel.1` returned to `noqueue`.

Main result: this degradation was too harsh for the current robot/PID implementation. All three modes fell. BE recorded many timeout samples and restarted twice. GD and EDF fell immediately and then kept writing the saturated fall angle (`+/-2.03`) without Influx timeout samples because after the fall the robot no longer performs normal PID correction. Robot logs still show startup correction timeouts and parse-error cascades.

Files:

- `pid_modes_degradation_summary.csv`: summary for this 20 ms degraded run.
- `net20_angle.png`, `net20_summary_bars.png`: plots for this run.
- Per-mode folders contain raw Influx data, robot logs, pod placement, and scheduler logs.
