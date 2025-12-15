#!/bin/bash
# TESZT1 futtató script

# -- Paraméterek (igény szerint módosíthatóak) --
REPLICAS=1               # Robotok száma (állítsuk a kísérlethez)
TIMEOUT=1               # Timeout a robot programban (ms)
FPS=10                   # FPS érték a robot programban

# 1. YAML frissítése a kívánt példányszámmal
sed -i "s/replicas:.*/replicas: $REPLICAS/" /users/szefoka/Dec/BalancingRobot/Robot/deployment_rt.yaml

# 2. Telepítés indítása
echo "Robot telepítés indítása: replicas=$REPLICAS, timeout=$TIMEOUT, fps=$FPS"
kubectl apply -f /users/szefoka/Dec/BalancingRobot/Robot/deployment_rt.yaml
sleep 5  # várakozás a podok elindulására

# (Opcionális) 3. CPU stressz indítása a teszt időtartamára
# Például egy távoli gépen: stress_cpu_remote.sh használata (ha szükséges)
# bash stress_cpu_remote.sh --cpu 4 --load 80 --time 60s --host nodeX

# 4. Adatok gyűjtése InfluxDB-ből
POD_NAME="influxdb-0"      # InfluxDB pod neve (ellenőrizzük a pontos nevet)
END=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
START=$(date -u -d "-20 seconds" +"%Y-%m-%dT%H:%M:%SZ")
# Lekérdezzük a 'angle' mérést az utolsó 20 másodpercből CSV formátumban
CMD="influx -database robot -execute \"SELECT * FROM angle WHERE time >= '$START' AND time <= '$END'\" -format csv > /var/lib/influxdb/export/result.csv"
kubectl exec -i "$POD_NAME" -- bash -c "mkdir -p /var/lib/influxdb/export; $CMD"
echo "InfluxDB lekérdezés kész: időtartam $START - $END."

# 5. Eredmények lekérése a helyi gépre
mkdir -p ./export
kubectl cp "$POD_NAME":/var/lib/influxdb/export/result.csv ./export/result.csv
echo "Adatok lokálisan: ./export/result.csv"

# 6. Dőlt robotok számának meghatározása és CSV export
# Feltételezzük, hogy a CSV utolsó (pl. 4.) oszlopa a tilt szög (angle). 
# Megszámoljuk, hány sorban az érték >2 vagy < -2 (dőlt robot):​:contentReference[oaicite:2]{index=2}
FALLEN=$(awk -F, 'NR>2 && ($4 > 2 || $4 < -2) {count++} END {print count}' ./export/result.csv)
echo "Eldőlt robotok száma: $FALLEN"

# 7. Eredmények CSV-be írása (bejövő paraméterek és dőlés)
echo "replicas,schedulerName,fallen" > test1_results.csv
echo "$REPLICAS,rtfaas-scheduler,$FALLEN" >> test1_results.csv
echo "Eredmények mentve: test1_results.csv"

