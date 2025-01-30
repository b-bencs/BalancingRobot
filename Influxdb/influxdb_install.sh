helm repo add influxdata https://helm.influxdata.com/
helm repo update
helm install influxdb influxdata/influxdb -f influxdb-values.yaml

