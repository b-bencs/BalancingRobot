from . import state_manager
from . import k8s_client

NODE_BLACKLIST = {
    "node1.rtkube.cloudnet-pg0.wisc.cloudlab.us",
}

def _matches_node_selector(pod, node) -> bool:
    sel = getattr(pod.spec, "node_selector", None) or {}
    if not sel:
        return True
    labels = getattr(node.metadata, "labels", None) or {}
    for k, v in sel.items():
        if labels.get(k) != v:
            return False
    return True

def is_nonrt_pod(pod):
    labels = pod.metadata.labels or {}
    crit = labels.get("criticality", "be")
    return crit != "rt"

def select_node_for_nonrt(pod, nodes):
    rt_util_node = state_manager.rt_util_per_node()
    candidates = []

    for node in nodes:
        node_name = getattr(node.metadata, "name", None)
        if not node_name:
            continue
        if node_name in NODE_BLACKLIST:
            continue

        if not _matches_node_selector(pod, node):
            continue

        conds = getattr(node.status, "conditions", []) or []
        ready = any(c.type == "Ready" and c.status == "True" for c in conds)
        if not ready:
            continue

        u = rt_util_node.get(node_name, 0.0)
        cpu_count = k8s_client.get_node_cpu_count(node)
        candidates.append((u, -cpu_count, node_name))

    if not candidates:
        return None

    candidates.sort()
    return candidates[0][2]
