# RT-FaaS Scheduler

This directory contains the custom RT-FaaS scheduler used by the balancing robot measurements.

The scheduler watches pending pods whose `spec.schedulerName` is `rtfaas-scheduler`. RT pods are identified by:

```yaml
metadata:
  labels:
    criticality: rt
  annotations:
    rt-q-ms: "4"
    rt-p-ms: "10"
```

For RT pods it computes utilization:

```text
U = rt-q-ms / rt-p-ms
```

In `cpu` mode, it places the pod on the first CPU where the accumulated utilization stays at or below `1.0`. In `node` mode, it checks the node-level bound `(m + 1) / 2`, where `m` is the node CPU count.

The CPU count comes from the Kubernetes Node object:

```python
node.status.capacity["cpu"]
```

## Build

```bash
cd /home/muuurk/rt-faas/BalancingRobot/rtfaas-scheduler
docker build -t botondbencs/rtfaas-scheduler:min-cpu .
docker push botondbencs/rtfaas-scheduler:min-cpu
```

## Deploy

```bash
cd /home/muuurk/rt-faas/BalancingRobot/rtfaas-scheduler
kubectl apply -f k8s/rbac.yaml
kubectl apply -f k8s/deployment.yaml
kubectl -n kube-system rollout status deploy/rtfaas-scheduler
```

## Verify

```bash
kubectl -n kube-system get deploy rtfaas-scheduler -o wide
kubectl -n kube-system get pod -l app=rtfaas-scheduler -o wide
kubectl -n kube-system logs -f deploy/rtfaas-scheduler --tail=100
```

## Use With OpenFaaS EDF Function

Deploy the EDF PID server:

```bash
cd /home/muuurk/rt-faas/BalancingRobot/functions
faas-cli deploy -f pidserver_edf.yaml --gateway http://127.0.0.1:31112
kubectl -n openfaas-fn rollout status deploy/pidserver
```

Check that the function pod is handled by this scheduler:

```bash
kubectl -n openfaas-fn get deploy pidserver -o yaml | \
  grep -E "schedulerName|criticality|rt-q-ms|rt-p-ms|EDFRUNTIME|EDFDEADLINE|EDFPERIOD|cpu:" -C 2
```

Expected important fields:

```text
criticality: rt
rt-q-ms: "4"
rt-p-ms: "10"
schedulerName: rtfaas-scheduler
cpu: 400m
```

## Runtime Settings

The deployment supports these environment variables:

```text
SCHEDULER_NAME=rtfaas-scheduler
EDF_MODE=cpu
RECHECK_INTERVAL_SEC=10.0
RT_STATE_FILE=/state/rt_state.txt
```

`/state` is mounted as an `emptyDir`; the scheduler rebuilds state from existing RT pods on startup.
