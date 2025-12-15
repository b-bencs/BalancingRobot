import os
import threading

STATE_FILE = os.environ.get("RT_STATE_FILE", "/state/rt_state.txt")
_lock = threading.Lock()


def read_state():
    """
    Visszaad: lista dict-ekkel:
    [
      {"node": "nodeA", "cpu": 0, "pod": "pod-rt-1", "u": 0.3, "deadline": 50},
      ...
    ]
    """
    entries = []
    if not os.path.exists(STATE_FILE):
        return entries

    with _lock:
        with open(STATE_FILE, "r") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                parts = line.split(",")
                if len(parts) < 5:
                    continue
                node, cpu_str, pod, u_str, dl_str = parts[:5]
                try:
                    cpu = int(cpu_str)
                    u = float(u_str)
                    dl = float(dl_str)
                except ValueError:
                    continue
                entries.append(
                    {"node": node, "cpu": cpu, "pod": pod, "u": u, "deadline": dl}
                )
    return entries


def write_state(entries):
    """
    entries: ugyanaz a lista, mint amit read_state visszaad.
    """
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    tmp = STATE_FILE + ".tmp"
    with _lock:
        with open(tmp, "w") as f:
            for e in entries:
                f.write(
                    f"{e['node']},{e['cpu']},{e['pod']},{e['u']},{e['deadline']}\n"
                )
        os.rename(tmp, STATE_FILE)

def add_entry(node, cpu, pod_name, u, deadline):
    entries = read_state()
    entries = [e for e in entries if e["pod"] != pod_name]
    entries.append(
        {"node": node, "cpu": cpu, "pod": pod_name, "u": float(u), "deadline": float(deadline)}
    )
    entries.sort(key=lambda x: x["pod"])
    write_state(entries)


def remove_entry(pod_name):
    entries = read_state()
    entries = [e for e in entries if e["pod"] != pod_name]
    write_state(entries)


def rt_util_per_node():
    """
    node -> ΣU_i
    """
    res = {}
    for e in read_state():
        res[e["node"]] = res.get(e["node"], 0.0) + e["u"]
    return res


def rt_util_per_node_cpu():
    """
    node -> {cpu_index -> ΣU_i}
    """
    res = {}
    for e in read_state():
        node_map = res.setdefault(e["node"], {})
        node_map[e["cpu"]] = node_map.get(e["cpu"], 0.0) + e["u"]
    return res
