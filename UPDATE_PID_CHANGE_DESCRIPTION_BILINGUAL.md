# Update pid change description / Update pid valtozasleiras

This file describes the changes made on top of commit `47773d2`
(`Update pid`). Line numbers refer to the current working tree after these
changes.

Ez a dokumentum a `47773d2` (`Update pid`) commitra epulo valtozasokat irja
le. A sorszamok a jelenlegi munkakonyvtar allapotara vonatkoznak.

## Summary / Osszefoglalo

| File | Lines | English | Magyar |
| --- | --- | --- | --- |
| `Robot/Dockerfile` | 10 | Link the robot binary explicitly with pthread support. | A robot binarist explicit pthread tamogatassal linkeljuk. |
| `Robot/main.cpp` | 73-156, 178-257, 294, 359-371 | Add optional debug mode and PID/correction timing logs. | Opcionális debug mód és PID/correction idozitesi logok bekerultek. |
| `Robot/main.cpp` | 354 | Only read both CLI arguments when both are present. | Csak akkor olvassuk be a ket CLI argumentumot, ha mindketto megvan. |
| `Robot/pid.cpp` | 75-85 | Fix the C++ PID integral update to use the previous error, not the already overwritten current error. | Javitas: a C++ PID integral tagja az elozo hibat hasznalja, ne a mar felulirt aktualis hibat. |
| `Server/pidserver.py` | 44-51 | Apply the same PID math fix in the direct Flask PID server. | Ugyanez a PID matematikai javitas bekerult a kozvetlen Flask PID szerverbe is. |
| `functions/pidserver/handler.py` | 8-26 | Bring the OpenFaaS handler up to the same filtered-derivative, time-aware PID formula. | Az OpenFaaS handler ugyanazt a szurt derivalt, idoalapu PID kepletet hasznalja, mint a tobbi komponens. |
| `functions/pidserver/handler_test.py` | 1-49 | Replace the placeholder test with real numeric checks for the PID formula and integral clamp. | A placeholder tesztet valodi numerikus ellenorzesek valtjak fel a PID kepletre es az integral korlatra. |

## `Robot/Dockerfile`

### Line 10

Before:

```dockerfile
RUN g++ -std=c++17 -o myapp main.cpp -I/usr/local/include/InfluxDB -L/usr/local/lib -lInfluxDB -lcurl -g
```

After:

```dockerfile
RUN g++ -std=c++17 -o myapp main.cpp -I/usr/local/include/InfluxDB -L/usr/local/lib -lInfluxDB -lcurl -pthread -g
```

English:

- Added `-pthread` to the compiler/linker command.
- The robot uses `std::thread`, `std::mutex` and `std::condition_variable`.
- On many Linux toolchains C++ thread support should be linked explicitly.
- This makes the Docker build less dependent on implicit linker behavior.

Magyar:

- Hozzaadtuk a `-pthread` kapcsolot a forditasi/linkelesi parancshoz.
- A robot kod hasznal `std::thread`, `std::mutex` es  `std::condition_variable` elemeket.
- Linuxon a C++ thread tamogatast erdemes explicit modon linkelni.
- Igy a Docker build kevesbe fugg az implicit linker viselkedestol.

## `Robot/main.cpp`

### Lines 73-74

Added:

```cpp
bool debug_mode = false;
std::mutex debug_log_mutex;
```

English:

- `debug_mode` is false by default, so normal robot logs stay quiet.
- `debug_log_mutex` serializes debug output from the main loop and the
  correction worker thread.

Magyar:

- A `debug_mode` alapertelmezetten false, tehat a normal robot log nem lesz
  zajosabb.
- A `debug_log_mutex` sorosítja a debug kimenetet a main loop es a correction
  worker thread kozott.

### Lines 84-99

Added:

```cpp
std::string lowerString(std::string value)
bool parseDebugFlag(const char* value)
```

English:

- `lowerString` normalizes the debug flag text.
- `parseDebugFlag` treats `1`, `true`, `yes` and `on` as enabled values.
- Any other value, including `false` and `0`, leaves debug logging disabled.

Magyar:

- A `lowerString` normalizalja a debug flag szoveget.
- A `parseDebugFlag` a `1`, `true`, `yes` es `on` ertekeket tekinti
  bekapcsolt allapotnak.
- Minden mas ertek, peldaul `false` vagy `0`, kikapcsolt debug logot jelent.

### Lines 101-109

Added:

```cpp
void debugLog(const std::string& message)
```

English:

- Central debug logging helper.
- If `debug_mode` is false, it returns immediately.
- If debug mode is true, it prints to `stderr` with a prefix like
  `[robot-debug t=1.234s]`.
- The timestamp is robot process elapsed time from `getElapsedTime()`.

Magyar:

- Kozponti debug logolo segedfuggveny.
- Ha a `debug_mode` false, azonnal visszater.
- Ha a debug mod true, `stderr`-re ir ilyen prefixszel:
  `[robot-debug t=1.234s]`.
- Az idobelyeg a robot process inditasa ota eltelt ido a `getElapsedTime()`
  szerint.

### Lines 111-156

Added:

```cpp
long double timedPidUpdate(...)
```

English:

- Wraps a single remote PID update call.
- Logs the PID axis (`x`, `psi`, `phi`) at request start.
- Logs `current_value`, `update_delta_time` and `expected_dt`.
- Measures wall-clock request duration with `std::chrono`.
- On success, logs `duration_ms` and returned PID result.
- On `std::exception`, logs `duration_ms` and `error.what()`, then rethrows.
- On unknown exception, logs `duration_ms`, then rethrows.

Magyar:

- Egyetlen tavoli PID update hivast csomagol be.
- A request elejen logolja a PID tengelyt (`x`, `psi`, `phi`).
- Logolja a `current_value`, `update_delta_time` es `expected_dt` ertekeket.
- `std::chrono` segitsegevel meri a request falioras idejet.
- Siker eseten logolja a `duration_ms` erteket es a visszakapott PID
  eredmenyt.
- `std::exception` eseten logolja a `duration_ms` erteket es az
  `error.what()` uzenetet, majd ujradobja a kivetelt.
- Ismeretlen kivetel eseten logolja a `duration_ms` erteket, majd ujradobja a
  kivetelt.

### Lines 180-182

Added:

```cpp
debugLog("correction start timeout_ms=...");
```

English:

- Logs the configured correction timeout at the beginning of each correction
  attempt.
- This makes it clear which timeout value was active for that cycle.

Magyar:

- Minden correction probalkozas elejen logolja az aktiv timeout erteket.
- Igy egyertelmu, melyik timeout ertek volt ervenyes az adott ciklusban.

### Lines 200-208

Changed:

```cpp
timedPidUpdate("x", ...)
timedPidUpdate("psi", ...)
timedPidUpdate("phi", ...)
```

English:

- The three serial PID requests now go through the timing wrapper.
- The control behavior is unchanged: the calls are still made in order.
- The new information is only debug timing and error visibility.

Magyar:

- A harom soros PID request most az idomeresi wrapperen megy at.
- A vezerles viselkedese nem valtozik: a hivasok tovabbra is sorrendben
  futnak.
- Az uj informacio csak debug idozites es hibalathatosag.

### Lines 222-237

Changed:

```cpp
catch (const std::exception& error) { ... }
catch (...) { ... }
```

English:

- The worker catch block is now split into known and unknown exceptions.
- Known exceptions log the exception text via `error.what()`.
- Both branches log that the worker will sleep for `response_timeout`
  milliseconds.
- This is the better log for the old catch block near line 138 in the earlier
  file layout.

Magyar:

- A worker catch blokk most ismert es ismeretlen kivetelekre van szetvalasztva.
- Ismert kivetel eseten logolja az `error.what()` szoveget.
- Mindket ag logolja, hogy a worker `response_timeout` milliszekundumig fog
  aludni.
- Ez a jobb log a korabbi fajlelhelyezes szerinti 138. sor kornyeki catch
  blokkhoz.

### Lines 243-257

Changed:

```cpp
if (cv.wait_for(...) == std::cv_status::timeout) {
    debugLog("correction wait result main_thread_timeout=true ...");
    ...
}
debugLog("correction wait result main_thread_timeout=false");
```

English:

- This directly answers whether the main thread timed out at the wait point.
- If the `wait_for` call times out, the log contains
  `main_thread_timeout=true`.
- If the worker notifies before timeout, the log contains
  `main_thread_timeout=false`.

Magyar:

- Ez kozvetlenul megvalaszolja, hogy a main thread timeoutolt-e a varakozasi
  ponton.
- Ha a `wait_for` timeouttal ter vissza, a logban
  `main_thread_timeout=true` szerepel.
- Ha a worker idoben notify-ol, a logban `main_thread_timeout=false` szerepel.

### Line 294

Added:

```cpp
debugLog("timeoutCorrection catch: restoring PID state and motor forces");
```

English:

- Logs when the outer timeout handler restores the saved PID state and motor
  forces.
- This marks the point where the failed correction becomes a robot-level
  timeout sample.

Magyar:

- Logolja, amikor a kulso timeout handler visszaallitja a mentett PID
  allapotot es motoreroket.
- Ez jeloli azt a pontot, ahol a sikertelen correction robot szintu timeout
  mintava valik.

### Line 354

Before:

```cpp
if (argc > 1)
```

After:

```cpp
if (argc > 2)
```

English:

- The program reads `argv[1]` as `response_timeout` and `argv[2]` as `FPS`.
- The old guard checked only that `argv[1]` existed.
- If the program was started with exactly one argument, it could still read
  missing `argv[2]`.
- The new guard requires both arguments before reading either value.

Magyar:

- A program az `argv[1]` erteket `response_timeout`kent, az `argv[2]` erteket
  pedig `FPS`kent olvassa.
- A regi feltetel csak azt ellenorizte, hogy az `argv[1]` letezik-e.
- Ha a program pontosan egy argumentummal indult, akkor is megprobalhatta
  beolvasni a hianyzo `argv[2]` erteket.
- Az uj feltetel csak akkor olvassa be az ertekeket, ha mindket argumentum
  jelen van.

### Lines 359-371

Added:

```cpp
const char* debug_env = std::getenv("ROBOT_DEBUG");
...
if (argc > 3) {
    debug_mode = parseDebugFlag(argv[3]);
}
...
debugLog("debug enabled ...");
```

English:

- Debug mode can be enabled with the `ROBOT_DEBUG` environment variable.
- It can also be enabled with an optional third CLI argument.
- Example environment use: `ROBOT_DEBUG=true`.
- Example CLI use: `./myapp 1200 10 true`.
- The CLI argument wins if both the environment variable and CLI argument are
  present.
- When debug is enabled, startup logs the active timeout, FPS and `dt`.

Magyar:

- A debug mod bekapcsolhato a `ROBOT_DEBUG` kornyezeti valtozoval.
- Bekapcsolhato opcionális harmadik CLI argumentummal is.
- Kornyezeti pelda: `ROBOT_DEBUG=true`.
- CLI pelda: `./myapp 1200 10 true`.
- Ha a kornyezeti valtozo es a CLI argumentum is jelen van, a CLI argumentum
  dont.
- Bekapcsolt debug modnal indulaskor logolja az aktiv timeoutot, FPS-t es
  `dt` erteket.

## `Robot/pid.cpp`

### Line 75

Added:

```cpp
long double previous_error = this->Derivator;
```

English:

- Stores the old derivative memory before `Derivator` is overwritten.
- In this codebase `Derivator` means the previous PID error.
- This value is needed by both the derivative term and the trapezoidal
  integral term.

Magyar:

- Elmenti a regi derivalt memoriat, mielott a `Derivator` felulirodik.
- Ebben a kodbazisban a `Derivator` az elozo PID hibat jelenti.
- Erre az ertekre a derivalt taghoz es a trapez alapu integral taghoz is
  szukseg van.

### Line 76

Before:

```cpp
long double raw_derivative = (this->error - this->Derivator) / dt;
```

After:

```cpp
long double raw_derivative = (this->error - previous_error) / dt;
```

English:

- The derivative is now calculated from current error minus previous error.
- This is behavior-preserving relative to the old line, but it makes the
  ordering explicit.
- The next line still applies the low-pass filter:
  `D_value = (1 - alpha) * old_D_value + alpha * raw_derivative`.

Magyar:

- A derivalt most az aktualis hiba es az elozo hiba kulonbsegebol szamolodik.
- Ez a regi sorhoz kepest ugyanazt a derivalt jelenteset tartja meg, de
  explicitte teszi a sorrendet.
- A kovetkezo sor tovabbra is az alulatereszto szurot hasznalja:
  `D_value = (1 - alpha) * regi_D_value + alpha * raw_derivative`.

### Line 80

Existing line:

```cpp
this->Derivator = this->error;
```

English:

- This line is intentionally still here.
- It updates the PID state so the next call can use the current error as the
  previous error.
- The important change is that the integral calculation no longer depends on
  this already-overwritten value.

Magyar:

- Ez a sor szandekosan megmaradt.
- Frissiti a PID allapotot, hogy a kovetkezo hivasban az aktualis hiba legyen
  az elozo hiba.
- A lenyegi javitas az, hogy az integral szamitas mar nem erre a felulirt
  ertekre tamaszkodik.

### Line 85

Before:

```cpp
this->Integrator += 0.5 * (this->error + this->Derivator) * dt;
```

After:

```cpp
this->Integrator += 0.5 * (this->error + previous_error) * dt;
```

English:

- Fixes the trapezoidal integral update.
- The old expression used `this->Derivator` after line 80 had already set it
  equal to `this->error`.
- Therefore the old formula effectively became `error * dt`.
- The new formula correctly uses `0.5 * (current_error + previous_error) * dt`.
- This keeps the C++ PID math consistent with a trapezoidal integration step.

Magyar:

- Javítja a trapez alapu integral frissitest.
- A regi kifejezes a `this->Derivator` erteket akkor hasznalta, amikor a 80.
  sor mar atallitotta azt `this->error` ertekre.
- Emiatt a regi keplet gyakorlatilag `error * dt` lett.
- Az uj keplet helyesen ezt hasznalja:
  `0.5 * (aktualis_hiba + elozo_hiba) * dt`.
- Igy a C++ PID matematika megfelel a trapez integralasi lepesnek.

## `Server/pidserver.py`

### Line 44

Added:

```python
previous_error = d["Derivator"]
```

English:

- Stores the previous error from the request payload.
- Mirrors the C++ `previous_error` variable in `Robot/pid.cpp`.
- Keeps the direct Flask PID server numerically aligned with the robot-side
  PID implementation.

Magyar:

- Elmenti a keres payloadjabol az elozo hibat.
- Ez megfelel a C++ oldali `previous_error` valtozonak a `Robot/pid.cpp`
  fajlban.
- Igy a kozvetlen Flask PID szerver numerikusan ugyanazt szamolja, mint a
  robot oldali PID implementacio.

### Line 45

Before:

```python
raw_derivative = (error - d["Derivator"]) / d["dt"]
```

After:

```python
raw_derivative = (error - previous_error) / d["dt"]
```

English:

- The derivative is calculated from current error and saved previous error.
- This matches `Robot/pid.cpp` line 76.

Magyar:

- A derivalt az aktualis hibabol es az elmentett elozo hibabol szamolodik.
- Ez megfelel a `Robot/pid.cpp` 76. soranak.

### Line 51

Before:

```python
Integrator = d["Integrator"] + 0.5 * (error + Derivator) * d["dt"]
```

After:

```python
Integrator = d["Integrator"] + 0.5 * (error + previous_error) * d["dt"]
```

English:

- Fixes the same update-order bug as in the C++ PID.
- `Derivator` is assigned to the current error on line 48.
- The integral step must use the previous error, not the newly assigned
  current error.

Magyar:

- Ugyanazt a sorrendi hibat javitja, mint a C++ PID oldalon.
- A `Derivator` a 48. sorban az aktualis hibara all be.
- Az integral lepesnek az elozo hibat kell hasznalnia, nem az ujonnan
  beallitott aktualis hibat.

## `functions/pidserver/handler.py`

This file is the OpenFaaS PID handler. Before these changes it still used the
older PID formula, while `Robot/pid.cpp` and `Server/pidserver.py` already used
the newer filtered-derivative, `dt`-aware formula.

Ez a fajl az OpenFaaS PID handler. A valtoztatasok elott meg a regi PID
kepletet hasznalta, mikozben a `Robot/pid.cpp` es a `Server/pidserver.py` mar
az ujabb, szurt derivaltat es `dt`-t hasznalo kepletre volt atallitva.

### Lines 8-9

Added:

```python
tau = 3 * d["expected_dt"]
alpha = d["dt"] / (d["dt"] + tau)
```

English:

- Introduces the same derivative filter parameters as the C++ and Flask PID
  implementations.
- `tau` is derived from the expected loop period.
- `alpha` determines how much of the raw derivative enters the filtered
  derivative state.

Magyar:

- Bevezeti ugyanazokat a derivalt szuroparametereket, amelyeket a C++ es a
  Flask PID implementacio is hasznal.
- A `tau` az elvart ciklusidobol szarmazik.
- Az `alpha` hatarozza meg, hogy a nyers derivalt mekkora resze kerul be a
  szurt derivalt allapotba.

### Lines 11-13

Before:

```python
D_value = d["Kd"] * ( error - d["Derivator"])
```

After:

```python
previous_error = d["Derivator"]
raw_derivative = (error - previous_error) / d["dt"]
D_value = (1.0 - alpha) * d["D_value"] + alpha * raw_derivative
```

English:

- Replaces the old derivative calculation with the filtered derivative state.
- The request payload already contains `D_value`, `dt`, `expected_dt` and
  `Derivator`; the handler now actually uses them.
- The returned `D_value` is the new filtered derivative state, not the final
  derivative contribution to PID.

Magyar:

- A regi derivalt szamitast lecsereli a szurt derivalt allapotra.
- A request payload mar tartalmazta a `D_value`, `dt`, `expected_dt` es
  `Derivator` ertekeket; a handler most mar valoban hasznalja ezeket.
- A visszaadott `D_value` az uj szurt derivalt allapot, nem a PID vegso
  derivalt hozzajarulasa.

### Lines 14-15

Added/kept:

```python
Derivator = error
D_term = d["Kd"] * D_value
```

English:

- `Derivator` is updated to the current error for the next PID call.
- `D_term` is the actual derivative contribution used in the final PID output.
- This separation matches `Robot/pid.cpp`, where `D_value` stores the filtered
  derivative and `D_term` applies `Kd`.

Magyar:

- A `Derivator` az aktualis hibara frissul a kovetkezo PID hivas szamara.
- A `D_term` a vegso PID kimenetben hasznalt derivalt hozzajarulas.
- Ez a szetvalasztas megfelel a `Robot/pid.cpp` logikajanak: a `D_value` a
  szurt derivalt allapot, a `D_term` pedig erre alkalmazza a `Kd` erteket.

### Line 17

Before:

```python
Integrator = d["Integrator"] + error
```

After:

```python
Integrator = d["Integrator"] + 0.5 * (error + previous_error) * d["dt"]
```

English:

- Converts the OpenFaaS handler from an unscaled integral update to the same
  trapezoidal, time-scaled update used by the C++ and Flask implementations.
- This makes OpenFaaS BE/GD/EDF measurements comparable with the direct server
  path.

Magyar:

- Az OpenFaaS handler integral frissitese a korabbi, ido nelkuli osszegzesrol
  ugyanarra a trapez, idoalapu frissitesre valt, mint amit a C++ es Flask
  implementacio hasznal.
- Igy az OpenFaaS BE/GD/EDF meresek osszehasonlithatobbak a kozvetlen szerver
  utvonallal.

### Line 24

Before:

```python
I_value = d["Integrator"] * d["Ki"]
```

After:

```python
I_value = Integrator * d["Ki"]
```

English:

- Fixes the integral output to use the updated and clamped integrator.
- Previously, if the integrator was clamped, `I_value` could still be computed
  from the old unclamped input value.

Magyar:

- Az integral kimenet most a frissitett es korlatozott integrator ertekbol
  szamolodik.
- Korabban, ha az integrator clampelve lett, az `I_value` meg mindig a regi,
  bemeneti ertekbol szamolodhatott.

### Line 26

Before:

```python
PID = P_value + I_value + D_value
```

After:

```python
PID = P_value + I_value + D_term
```

English:

- Uses the derivative contribution after multiplying the filtered derivative
  by `Kd`.
- Keeps the meaning of `D_value` consistent: it is state, while `D_term` is the
  output contribution.

Magyar:

- A vegso PID kimenet a `Kd`-vel szorzott szurt derivalt hozzajarulast
  hasznalja.
- Igy a `D_value` jelentese kovetkezetes marad: allapot, mig a `D_term` a
  kimeneti hozzajarulas.

## `functions/pidserver/handler_test.py`

### Lines 1-2

Added:

```python
import json
import math
```

English:

- `json` is used to build the same string payload shape that the OpenFaaS
  handler receives.
- `math.isclose` is used because floating-point results should not be compared
  with exact decimal equality.

Magyar:

- A `json` ugyanazt a string payload formatumot allitja elo, amit az OpenFaaS
  handler kap.
- A `math.isclose` azert kell, mert a lebegopontos eredmenyeket nem jo pontos
  decimalis egyenloseggel osszehasonlitani.

### Lines 7-23

Added:

```python
def invoke(**overrides):
    ...
```

English:

- Adds a helper that creates a representative PID request.
- Default values include all fields required by the updated handler:
  `expected_dt`, `dt`, `D_value`, `Derivator`, `Integrator` and PID gains.
- `overrides` allows each test to modify only the fields relevant to that
  scenario.

Magyar:

- Hozzaad egy segedfuggvenyt, amely reprezentativ PID requestet epit.
- Az alapertelmezett ertekek tartalmazzak az uj handlerhez szukseges osszes
  mezot: `expected_dt`, `dt`, `D_value`, `Derivator`, `Integrator` es PID
  gain ertekek.
- Az `overrides` segitsegevel minden teszt csak az adott esethez fontos
  mezoket modositja.

### Lines 26-32

Added:

```python
def test_handle_uses_filtered_derivative_and_trapezoidal_integral():
    ...
```

English:

- Verifies the normal PID update path.
- Expected values for the default request:
  - `D_value = 1.05`
  - `Integrator = 0.22`
  - `I_value = 0.022`
  - `PID = 8.772`
- This proves that the handler uses filtered derivative state and trapezoidal
  integral update.

Magyar:

- Ellenorzi a normal PID frissitesi utat.
- Az alap request vart ertekei:
  - `D_value = 1.05`
  - `Integrator = 0.22`
  - `I_value = 0.022`
  - `PID = 8.772`
- Ez bizonyitja, hogy a handler a szurt derivalt allapotot es a trapez alapu
  integral frissitest hasznalja.

### Lines 35-49

Added:

```python
def test_handle_uses_clamped_integrator_for_i_value():
    ...
```

English:

- Verifies the integral clamp path.
- The request starts close to the maximum integrator value and uses a large
  positive error.
- Expected result:
  - `Integrator = 3`
  - `I_value = 6`
  - `PID = 6`
- This specifically prevents the old bug where the returned `Integrator` was
  clamped but `I_value` was still computed from the old integrator.

Magyar:

- Ellenorzi az integral clamp utat.
- A request a maximalis integrator ertek kozelebol indul, nagy pozitiv hibaval.
- Vart eredmeny:
  - `Integrator = 3`
  - `I_value = 6`
  - `PID = 6`
- Ez konkretan megakadalyozza a regi hibat, amikor a visszaadott `Integrator`
  mar clampelve volt, de az `I_value` meg a regi integratorbol szamolodott.

## Verification / Ellenorzes

English:

- Robot Docker image builds successfully with the updated Dockerfile.
- OpenFaaS shrinkwrap copies the updated handler and tests into
  `functions/build/pidserver`.
- OpenFaaS Docker `test` stage runs `tox`; lint passes and both handler tests
  pass.
- A C++ PID probe, a direct Flask PID probe and the OpenFaaS handler produce
  the same representative PID output.
- Kubernetes client-side dry-run accepts the direct robot/server manifests.

Magyar:

- A robot Docker image sikeresen fordul az uj Dockerfile-lal.
- Az OpenFaaS shrinkwrap bemasolja a frissitett handlert es teszteket a
  `functions/build/pidserver` ala.
- Az OpenFaaS Docker `test` stage lefuttatja a `tox` parancsot; a lint
  sikeres es mindket handler teszt atmegy.
- A C++ PID probe, a kozvetlen Flask PID probe es az OpenFaaS handler ugyanazt
  a reprezentativ PID kimenetet adja.
- A Kubernetes client-side dry-run elfogadja a kozvetlen robot/szerver
  manifesteket.

## Deliberately not changed / Szandekosan nem modositott reszek

English:

- `Robot/webclient.cpp` still has no libcurl timeout and no HTTP status-code
  validation.
- The robot still detaches the correction worker and waits on a condition
  variable; a timed-out worker can continue running.
- PID requests and InfluxDB writes are still synchronous with respect to the
  robot loop.
- Historical image names and node names are still present in the old manifests.

Magyar:

- A `Robot/webclient.cpp` tovabbra sem allit be libcurl timeoutot es nem
  ellenorzi a HTTP status code-ot.
- A robot tovabbra is detach-eli a correction workert es condition variable-on
  var; egy timeoutolt worker tovabb futhat.
- A PID requestek es az InfluxDB irasok tovabbra is szinkron hatasuak a robot
  loop szempontjabol.
- A regi manifestekben tovabbra is torteneti image nevek es node nevek vannak.
