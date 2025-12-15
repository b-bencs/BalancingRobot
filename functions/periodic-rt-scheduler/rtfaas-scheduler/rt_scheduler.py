from . import state_manager
from . import k8s_client

NODE_BLACKLIST = {
    "node1.rtkube.cloudnet-pg0.wisc.cloudlab.us",
}

def is_rt_pod(pod):
    labels = pod.metadata.labels or {}
    return labels.get("criticality") == "rt"


def _safe_float(val, default):
    if val is None:
        return default
    try:
        s = str(val).strip()
        if s == "":
            return default
        return float(s)
    except ValueError:
        return default


def get_rt_params(pod):
    ann = pod.metadata.annotations or {}
    if "rt-q-ms" not in ann or "rt-p-ms" not in ann:
        return None, None
    q_ms = _safe_float(ann.get("rt-q-ms"), None)
    p_ms = _safe_float(ann.get("rt-p-ms"), None)
    if q_ms is None or p_ms is None or p_ms <= 0:
        return None, None
    u = q_ms / p_ms
    return u, p_ms


def filter_nodes_for_rt(pod, nodes):
    """
    Itt lehetne CPU/memoria predicate
    TODO
    """
    result = []
    for n in nodes:
        node_name = getattr(n.metadata, "name", None)
        if not node_name:
            continue
        if node_name in NODE_BLACKLIST:
            continue
        conds = getattr(n.status, "conditions", []) or []
        ready = any(c.type == "Ready" and c.status == "True" for c in conds)
        if not ready:
            continue

        result.append(n)
    return result


def can_place_on_node_cpu_mode(node_name, cpu_count, u_new):
    node_cpu_map, _u_unknown = _cpu_map_with_unknown(node_name, cpu_count)
    for cpu_idx in range(cpu_count):
        u_cur = node_cpu_map.get(cpu_idx, 0.0)
        if u_cur + u_new <= 1.0:
            return True
    return False


def choose_cpu_on_node_cpu_mode(node_name, cpu_count, u_new):
    node_cpu_map, _u_unknown = _cpu_map_with_unknown(node_name, cpu_count)

    best_cpu = None
    best_u = None

    for cpu_idx in range(cpu_count):
        u_cur = node_cpu_map.get(cpu_idx, 0.0)
        if u_cur + u_new <= 1.0:
            if best_u is None or u_cur < best_u:
                best_u = u_cur
                best_cpu = cpu_idx

    return best_cpu


def can_place_on_node_node_mode(node_name, cpu_count, u_new):
    node_map = state_manager.rt_util_per_node()
    u_node = node_map.get(node_name, 0.0)
    # ΣU_i <= (m+1)/2  (m = cpu_count)
    limit = (cpu_count + 1) / 2.0
    return u_node + u_new <= limit


"""
1) node filtering
2) kettos celfv: RT esetben minel kevesebb node-ot hasznaljunk.
"""
def select_node_for_rt(pod, nodes, mode="cpu"):
    u_new, deadline = get_rt_params(pod)

    if u_new is None or deadline is None:
        return None, None, None, None
    if u_new > 1.0 + 1e-9:
        return None, None, None, None

    nodes = filter_nodes_for_rt(pod, nodes)

    if mode == "node":
        for node in nodes:
            node_name = node.metadata.name
            cpu_count = k8s_client.get_node_cpu_count(node)
            # node-mode-ban CPU indexet nem hasznaljuk
            if can_place_on_node_node_mode(node_name, cpu_count, u_new):
                return node_name, None, u_new, deadline
        return None, None, None, None

    # mode == "cpu"
    for node in nodes:
        node_name = node.metadata.name
        cpu_count = k8s_client.get_node_cpu_count(node)

        if can_place_on_node_cpu_mode(node_name, cpu_count, u_new):
            cpu_idx = choose_cpu_on_node_cpu_mode(node_name, cpu_count, u_new)
            if cpu_idx is None:
                continue
            return node_name, cpu_idx, u_new, deadline

    return None, None, None, None  # nem talaltunk megfelelo node-ot


def _cpu_map_with_unknown(node_name: str, cpu_count: int):
    raw = state_manager.rt_util_per_node_cpu().get(node_name, {})
    u_unknown = raw.get(-1, 0.0)

    if cpu_count <= 0:
        return {}, u_unknown

    add = u_unknown / float(cpu_count)

    cooked = {}
    for cpu_idx in range(cpu_count):
        cooked[cpu_idx] = raw.get(cpu_idx, 0.0) + add

    return cooked, u_unknown
