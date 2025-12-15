import os
import time
import traceback

from . import k8s_client
from . import rt_scheduler
from . import nonrt_scheduler
from . import state_manager

SCHEDULER_NAME = os.environ.get("SCHEDULER_NAME", "rtfaas-scheduler")
EDF_MODE = os.environ.get("EDF_MODE", "cpu")  # "cpu" vagy "node"

# double-check periodus (sec)
RECHECK_INTERVAL_SEC = float(os.environ.get("RECHECK_INTERVAL_SEC", "10.0"))


def classify_pod(pod):
    labels = pod.metadata.labels or {}
    crit = labels.get("criticality", "be")
    if crit == "rt":
        return "rt"
    else:
        return "nonrt"


def schedule_one_pod(pod, nodes):
    if pod.spec.node_name is not None:
        return None
    if pod.status.phase != "Pending":
        return None
    if pod.spec.scheduler_name != SCHEDULER_NAME:
        return None
    pod_type = classify_pod(pod)
    if pod_type == "rt":
        node_name, cpu_idx, u_new, deadline = rt_scheduler.select_node_for_rt(
            pod, nodes, mode=EDF_MODE
        )
        return pod_type, node_name, {"cpu": cpu_idx, "u": u_new, "deadline": deadline}
    else:
        node_name = nonrt_scheduler.select_node_for_nonrt(pod, nodes)
        return pod_type, node_name, None


def bootstrap_state_from_cluster():
    """
    scheduler ujraindulaskor a state fajl ures lehet, mikozben RT podok mar futnak. Ezeket probaljuk visszatenni a state-be.

    Egyszeru PoC:
    -csak a sajat schedulerhez tartozo, Running vagy Pending RT podok,
    -CPU index mindig 0,
    -terheles-becsles uj utemezeshez.
    """
    existing_entries = state_manager.read_state()
    known_pods = {e["pod"] for e in existing_entries}

    pods = k8s_client.list_all_pods()
    new_entries = list(existing_entries)
    changed = False

    for p in pods:
        if not rt_scheduler.is_rt_pod(p):
            continue
        if p.spec.scheduler_name != SCHEDULER_NAME:
            continue
        if p.status.phase not in ("Pending", "Running"):
            continue

        name = p.metadata.name
        if name in known_pods:
            continue

        node_name = p.spec.node_name
        if not node_name:
            continue

        u, deadline = rt_scheduler.get_rt_params(p)

        cpu_idx = -1 if EDF_MODE == "cpu" else -1
        new_entries.append(
            {
                "node": node_name,
                "cpu": cpu_idx,
                "pod": name,
                "u": float(u),
                "deadline": float(deadline),
            }
        )
        changed = True
        print(
            f"[BOOTSTRAP] recovered RT pod from cluster: pod={name}, node={node_name}, u={u:.3f}, deadline={deadline}"
        )

    if changed:
        state_manager.write_state(new_entries)
        print(f"[BOOTSTRAP] state rebuilt with {len(new_entries)} RT entries")


def periodic_recheck():
    """
    Double-check:
    -state-bol kidobjuk a nem letezo / mas schedulerhez tartozo / befejezett RT-podokat
    -frissitjuk a node-neveket
    -kiirjuk ΣU ertekeket, es figyelmeztetunk, ha a hatarfeltetelek serulnek.
    """
    pods = k8s_client.list_all_pods()
    pod_by_name = {p.metadata.name: p for p in pods if p.metadata and p.metadata.name}

    entries = state_manager.read_state()
    new_entries = []

    removed = 0

    for e in entries:
        pod_name = e["pod"]
        p = pod_by_name.get(pod_name)
        if p is None:
            removed += 1
            continue

        # scheduler RT-podjai
        if p.spec.scheduler_name != SCHEDULER_NAME:
            removed += 1
            continue
        if not rt_scheduler.is_rt_pod(p):
            removed += 1
            continue
        if p.status.phase in ("Succeeded", "Failed"):
            removed += 1
            continue

        node_name = p.spec.node_name
        if not node_name:
            removed += 1
            continue

        e2 = dict(e)
        e2["node"] = node_name
        new_entries.append(e2)

    if removed > 0:
        print(f"[RECHECK] cleaned {removed} stale RT entries from state")

    # state frissitese
    if removed > 0 or len(new_entries) != len(entries):
        state_manager.write_state(new_entries)

    # diagnosztika: ΣU node-onkent es CPU-nkent
    util_node = state_manager.rt_util_per_node()
    util_node_cpu = state_manager.rt_util_per_node_cpu()

    for node, u in util_node.items():
        print(f"[RECHECK] node={node} ΣU={u:.3f}")

    # hatarfeltetel-ellenorzes
    for node, cpu_map in util_node_cpu.items():
        for cpu_idx, u in cpu_map.items():
            if cpu_idx < 0:
                continue
            if u > 1.0 + 1e-9:
                print(
                    f"[WARN] node={node} cpu={cpu_idx} EDF CPU-mode utilization exceeded: U={u:.3f} > 1.0"
                )

    # node-mode
    if EDF_MODE == "node":
        nodes = k8s_client.list_nodes()
        node_by_name = {n.metadata.name: n for n in nodes}
        for node_name, u in util_node.items():
            node = node_by_name.get(node_name)
            if not node:
                continue
            m = k8s_client.get_node_cpu_count(node)
            limit = (m + 1) / 2.0
            if u > limit + 1e-9:
                print(
                    f"[WARN] node={node_name} node-mode utilization exceeded: ΣU={u:.3f} > (m+1)/2={limit:.3f}"
                )

def _rt_deadline(p):
    if classify_pod(p) != "rt":
        return float("inf")
    _, dl = rt_scheduler.get_rt_params(p)
    if dl is None:
        return float("inf")
    return float(dl)

def run():
    print(f"Starting scheduler {SCHEDULER_NAME} with EDF_MODE={EDF_MODE}")

    # state vissza toltes
    bootstrap_state_from_cluster()

    last_recheck = time.time()

    while True:
        try:
            now = time.time()
            if now - last_recheck >= RECHECK_INTERVAL_SEC:
                periodic_recheck()
                last_recheck = now

            pending_pods = k8s_client.list_pending_pods_for_scheduler(SCHEDULER_NAME)
            if not pending_pods:
                k8s_client.wait(1.0)
                continue    
            pending_pods.sort(key=_rt_deadline)

            nodes = k8s_client.list_nodes()

            for pod in pending_pods:
                pod_name = pod.metadata.name
                pod_type = classify_pod(pod)

                print(f"Scheduling pod {pod_name} (type={pod_type})")

                result = schedule_one_pod(pod, nodes)
                if result is None:
                    continue

                pod_type, node_name, rt_info = result
                if node_name is None:
                    print(f"No suitable node found for pod {pod_name}, will retry")
                    continue

                try:
                    k8s_client.bind_pod_to_node(pod, node_name)
                    print(f"Bound pod {pod_name} to node {node_name}")
                    if pod_type == "rt" and rt_info is not None:
                        cpu_idx = rt_info["cpu"]
                        if cpu_idx is None:
                            cpu_idx = -1
                        state_manager.add_entry(
                            node=node_name,
                            cpu=cpu_idx,
                            pod_name=pod_name,
                            u=rt_info["u"],
                            deadline=rt_info["deadline"],
                        )
                        break
                except Exception as e:
                    msg = str(e)
                    if "409" in msg or "already assigned" in msg:
                        print(f"Pod {pod_name} already assigned, skipping")
                        continue
                    if pod_type == "rt":
                        state_manager.remove_entry(pod_name)
                    print(f"Error binding pod {pod_name} to {node_name}: {e}")

            k8s_client.wait(10.0)

        except Exception as e:
            print("[FATAL] Main loop error:", repr(e))
            print(traceback.format_exc())
            k8s_client.wait(10.0)


if __name__ == "__main__":
    run()
