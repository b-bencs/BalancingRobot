# PID Mode Measurements / PID meresek

## English

### Purpose

These measurements compare the robot with three PID server scheduling modes:

- **BE**: Best-effort OpenFaaS PID server, no explicit CPU reservation.
- **GD**: Guaranteed/degraded-style PID server with `300m` CPU request and limit.
- **EDF / RT**: RT-FaaS scheduled PID server with `runtime=4`, `deadline=10`, `period=10`, therefore utilization `U=0.4`.

The main question is how the robot behaves when the PID server is affected by network delay or CPU pressure. The expected good case is: the robot stays below the fall threshold, produces few or no timeout samples, and has stable PID request latency.

### Common Setup

- Robot pod: scheduled on `gamma`.
- PID server pod: scheduled on `beta`.
- RT-FaaS scheduler: running on `alpha`.
- Robot runtime parameters: `ROBOT_TIMEOUT=100 ms`, `FPS=100`, debug logging enabled.
- Warmup per mode: `10 s`.
- Requested measurement window per mode: `120 s`.
- Data source: InfluxDB measurement `angle`, filtered by the fresh robot pod name for each run.
- Captured files per mode: raw Influx CSV, robot logs, pod placement, scheduler logs, restart counts.

The EDF placement required a live scheduler patch so `rtfaas-scheduler` honors the OpenFaaS node-selector annotation. Without this patch EDF pods were schedulable, but landed on `alpha` instead of `beta`, which was not fair for these measurements.

### Metric Meaning

- **fell**: `yes` if `abs(angle) >= 0.785 rad` appeared in the measurement window.
- **max abs angle**: largest absolute robot angle in radians.
- **timeouts**: number of Influx `angle.timeout = 1` samples.
- **PID p95**: 95th percentile PID HTTP request duration from robot debug logs.
- **restarts**: robot container restart counter before and after the measured window.
- **sample Hz**: effective saved Influx samples per second for that robot pod.

### Clean Baseline

Folder: `pid_modes_20260603_203614`

No artificial network or CPU degradation was applied.

| mode | fell | timeouts | max abs angle | PID p95 | restarts |
|---|---:|---:|---:|---:|---:|
| BE | no | 2 | 0.0351 | 9.55 ms | 0->1 |
| GD | no | 9 | 0.00245 | 71.0 ms | 0->0 |
| EDF | no | 0 | 0.00117 | 8.89 ms | 0->0 |

Interpretation: all modes stayed balanced. EDF was the cleanest baseline: no timeout samples, smallest angle, and low PID latency.

### Network Degradation

Network degradation was applied on `beta`, interface `flannel.1`, using Linux `tc netem`. This affects pod-network traffic from the PID node. The qdisc was removed after each run; the saved `tc_after_cleanup.txt` files show `noqueue`.

#### Mild Network Degradation: `10ms +/- 2ms`

Folder: `pid_modes_netdeg10_20260603_210000`

| mode | fell | timeouts | max abs angle | PID p95 | restarts |
|---|---:|---:|---:|---:|---:|
| BE | no | 20 | 0.00243 | 34.2 ms | 0->0 |
| GD | no | 23 | 0.0351 | 35.5 ms | 0->3 |
| EDF | no | 5 | 0.00290 | 32.8 ms | 0->0 |

Interpretation: this is the most useful network-degradation point. None of the modes crossed the fall threshold. EDF had the fewest timeout samples and no restart. GD did not fall, but the robot container restarted three times during the run, so it is less healthy than the angle alone suggests.

#### Strong Network Degradation: `20ms +/- 5ms`

Folder: `pid_modes_netdeg_20260603_205128`

| mode | fell | timeouts | max abs angle | PID p95 | restarts |
|---|---:|---:|---:|---:|---:|
| BE | yes | 397 | 2.03 | 60.9 ms | 0->2 |
| GD | yes | 0 | 2.03 | 56.5 ms | 0->0 |
| EDF | yes | 0 | 2.03 | 61.3 ms | 0->0 |

Interpretation: this degradation was too strong for the current robot/PID implementation. All modes fell. For GD and EDF, the timeout count is misleadingly zero because they fell almost immediately and then kept writing the saturated fall angle (`+/-2.03`) without normal PID correction.

### CPU Stress

Primary folder: `pid_modes_k8s_highprio_cpu_20260604_124158`

CPU stress was applied as a **Kubernetes high-priority stressor pod** on `beta`, the same node where the PID server ran. The stressor used:

- `priorityClassName=rtfaas-high-priority-stressor`
- Kubernetes priority value `1000000`
- `preemptionPolicy=PreemptLowerPriority`
- `cpu request=3500m`
- four Python CPU-burn processes in one pod
- image `botondbencs/edf-pidserver:latest`

The stressor pod was created before the robot pod restart for each mode and deleted after the measurement window. This is the CPU measurement that best matches the intended Kubernetes high-priority stressor scenario.

| mode | fell | timeouts | max abs angle | PID p95 | restarts |
|---|---:|---:|---:|---:|---:|
| BE | yes | 0 | 2.03 | 380 ms | 0->0 |
| GD | no | 4 | 0.0350 | 26.0 ms | 0->1 |
| EDF | no | 0 | 0.00125 | 15.5 ms | 0->0 |

Interpretation: this run gives the clearest CPU-stress result. BE failed under the high-priority Kubernetes stressor. GD did not fall, but had timeout samples and one restart. EDF stayed clean: no fall, no timeout samples, no restart, and the smallest angle.

Reference folder for the older host-level CPU check: `pid_modes_cpu4_100_20260603_211115`. That run used host `stress-ng` directly on beta. It is kept as a preliminary comparison, but the Kubernetes high-priority pod result above is the stronger result for the scheduling argument.

### Main Conclusion

The strongest result is not that EDF is immune to all degradation; the 20 ms network test shows that the current robot is very sensitive to network delay. The useful result is more specific:

- With mild network degradation, EDF had fewer timeout samples than BE/GD and no restart.
- With Kubernetes high-priority CPU stress on the PID node, BE failed, GD degraded but did not fall, and EDF stayed clean.
- With strong network degradation, all modes failed, so future work should improve the robot/PID communication path, timeout handling, and recovery after failed PID calls.

### Important Caveats

- The robot code still has a known restart/crash tendency over longer runs. Restart counts are therefore part of the result, not just noise.
- The primary CPU result uses a Kubernetes high-priority stressor pod. The older host-level `stress-ng` run is kept only as a preliminary comparison.
- The network degradation was applied to `beta/flannel.1`, so it targets the PID node pod network path.
- In fall cases, timeout samples can become misleading because once the robot saturates at `+/-2.03`, normal PID correction is no longer happening.

## Magyar

### Cel

Ezek a meresek a robot viselkedeset hasonlitjak ossze harom PID szerver utemezesi modban:

- **BE**: best-effort OpenFaaS PID szerver, explicit CPU foglalas nelkul.
- **GD**: garantalt/degradalt jellegu PID szerver `400m` CPU request es limit ertekkel.
- **EDF / RT**: RT-FaaS scheduler altal utemezett PID szerver, `runtime=4`, `deadline=10`, `period=10`, vagyis `U=0.4`.

A fo kerdes az volt, hogyan viselkedik a robot, ha a PID szervert halozati kesleltetes vagy CPU terheles eri. A jo eset az, amikor a robot nem eri el az esesi kuszobot, keves vagy nulla timeout minta keletkezik, es a PID keresi ido stabil marad.

### Kozos beallitas

- Robot pod: `gamma` node-on futott.
- PID szerver pod: `beta` node-on futott.
- RT-FaaS scheduler: `alpha` node-on futott.
- Robot parameterek: `ROBOT_TIMEOUT=100 ms`, `FPS=100`, debug log bekapcsolva.
- Bemelegites modonkent: `10 s`.
- Kert meresi ablak modonkent: `120 s`.
- Adatforras: InfluxDB `angle` measurement, mindig az aktualis friss robot pod nevere szurve.
- Mentett fajlok modonkent: nyers Influx CSV, robot log, pod elhelyezes, scheduler log, restart szamlalok.

Az EDF korrekt elhelyezesehez kellett egy live scheduler patch: az `rtfaas-scheduler` igy mar figyelembe veszi az OpenFaaS node-selector annotaciot. Enelkul az EDF pod mukodott, de `alpha` node-ra kerult `beta` helyett, ami nem lett volna fair meres.

### Metrikak jelentese

- **fell**: `yes`, ha a meresi ablakban volt `abs(angle) >= 0.785 rad`.
- **max abs angle**: a legnagyobb abszolut robot szog radianban.
- **timeouts**: azoknak az Influx `angle.timeout = 1` mintaknak a szama, amelyekben timeout tortent.
- **PID p95**: a PID HTTP keresi idok 95. percentilise a robot debug logokbol.
- **restarts**: robot container restart szamlalo a meres elott es utan.
- **sample Hz**: effektiv Influx mintaveteli frekvencia az adott robot podra.

### Tiszta baseline

Mappa: `pid_modes_20260603_203614`

Nem volt mesterseges halozati vagy CPU degradacio.

| mode | elesett | timeout | max abs angle | PID p95 | restart |
|---|---:|---:|---:|---:|---:|
| BE | nem | 2 | 0.0351 | 9.55 ms | 0->1 |
| GD | nem | 9 | 0.00245 | 71.0 ms | 0->0 |
| EDF | nem | 0 | 0.00117 | 8.89 ms | 0->0 |

Ertelmezes: mindharom mod stabil maradt. Az EDF volt a legtisztabb baseline: nem volt timeout, a szog nagyon kicsi maradt, es a PID latency is alacsony volt.

### Halozati degradacio

A halozati degradaciot `beta` node-on, a `flannel.1` interfeszen allitottuk be Linux `tc netem` segitsegevel. Ez a PID node pod-halozati forgalmat erinti. A qdisc minden meres utan torolve lett; a mentett `tc_after_cleanup.txt` fajlokban `noqueue` lathato.

#### Enyhe halozati degradacio: `10ms +/- 2ms`

Mappa: `pid_modes_netdeg10_20260603_210000`

| mode | elesett | timeout | max abs angle | PID p95 | restart |
|---|---:|---:|---:|---:|---:|
| BE | nem | 20 | 0.00243 | 34.2 ms | 0->0 |
| GD | nem | 23 | 0.0351 | 35.5 ms | 0->3 |
| EDF | nem | 5 | 0.00290 | 32.8 ms | 0->0 |

Ertelmezes: ez a leghasznosabb halozati degradacios pont. Egyik mod sem erte el az esesi kuszobot. Az EDF adta a legkevesebb timeout mintat es nem restartolt. A GD nem esett el, de a robot container haromszor restartolt, ezert a puszta szogerteknel rosszabb allapotot jelez.

#### Eros halozati degradacio: `20ms +/- 5ms`

Mappa: `pid_modes_netdeg_20260603_205128`

| mode | elesett | timeout | max abs angle | PID p95 | restart |
|---|---:|---:|---:|---:|---:|
| BE | igen | 397 | 2.03 | 60.9 ms | 0->2 |
| GD | igen | 0 | 2.03 | 56.5 ms | 0->0 |
| EDF | igen | 0 | 2.03 | 61.3 ms | 0->0 |

Ertelmezes: ez a degradacio tul eros volt a jelenlegi robot/PID implementacionak. Mindharom mod elesett. GD es EDF eseteben a nulla timeout felrevezeto: a robot szinte azonnal elesett, utana pedig a telitett esesi szoget (`+/-2.03`) irta tovabb, normal PID korrekcio nelkul.

### CPU terheles

Fo mappa: `pid_modes_k8s_highprio_cpu_20260604_124158`

A CPU terheles **Kubernetes high-priority stressor podkent** futott `beta` node-on, vagyis ugyanazon a node-on, ahol a PID szerver volt. A stressor beallitasai:

- `priorityClassName=rtfaas-high-priority-stressor`
- Kubernetes priority ertek: `1000000`
- `preemptionPolicy=PreemptLowerPriority`
- `cpu request=3500m`
- negy Python CPU-burn process egy podban
- image: `botondbencs/edf-pidserver:latest`

A stressor pod modonkent a robot pod restartja elott indult, es a meresi ablak utan torolve lett. Ez az a CPU meres, amely legjobban megfelel a Kubernetes high-priority stressor forgatokonyvnek.

| mode | elesett | timeout | max abs angle | PID p95 | restart |
|---|---:|---:|---:|---:|---:|
| BE | igen | 0 | 2.03 | 380 ms | 0->0 |
| GD | nem | 4 | 0.0350 | 26.0 ms | 0->1 |
| EDF | nem | 0 | 0.00125 | 15.5 ms | 0->0 |

Ertelmezes: ez adja a legtisztabb CPU-stressz eredmenyt. BE elbukott a high-priority Kubernetes stressor alatt. GD nem esett el, de volt timeout es egy restart. EDF tiszta maradt: nincs eses, nincs timeout minta, nincs restart, es a legkisebb szoget adta.

Referencia mappa a korabbi host-szintu CPU ellenorzeshez: `pid_modes_cpu4_100_20260603_211115`. Az a meres kozvetlenul a beta hoston futtatta a `stress-ng`-t. Elso osszehasonlitasnak megtartjuk, de az utemezesi erveleshez a fenti Kubernetes high-priority podos eredmeny az erosebb.

### Fo kovetkeztetes

A legerosebb tanulsag nem az, hogy az EDF minden degradaciot kibir; a 20 ms halozati teszt megmutatta, hogy a jelenlegi robot nagyon erzekeny a halozati kesleltetesre. A pontosabb kovetkeztetes:

- Enyhe halozati degradacio mellett az EDF kevesebb timeout mintat adott, mint BE/GD, es nem restartolt.
- PID node-on futtatott Kubernetes high-priority CPU stressz alatt BE elbukott, GD degradalodott de nem esett el, EDF pedig tiszta maradt.
- Eros halozati degradacio mellett mindharom mod elbukott, ezert kovetkezo lepeskent a robot/PID kommunikaciot, timeout kezelest es hibas PID valasz utani recovery-t kell javitani.

### Fontos megjegyzesek

- A robot kodban tovabbra is van egy hosszabb futasnal jelentkezo restart/crash hajlam. Ezert a restart szamlalo a meres resze, nem csak zaj.
- Az elsoleges CPU eredmeny Kubernetes high-priority stressor poddal keszult. A korabbi host-szintu `stress-ng` meres csak elozetes osszehasonlitas.
- A halozati degradacio `beta/flannel.1` interfeszen volt, vagyis a PID node pod-halozati utjat terhelte.
- Esesi esetekben a timeout minta felrevezeto lehet, mert ha a robot mar `+/-2.03` szogon telitodik, akkor nem normal PID korrekcios mukodes folyik tovabb.
