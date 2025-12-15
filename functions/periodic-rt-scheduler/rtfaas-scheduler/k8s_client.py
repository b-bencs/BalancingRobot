from kubernetes import client, config
from kubernetes.client.rest import ApiException
import time
import threading

_config_lock = threading.Lock()
_config_loaded = False


def load_config():
    global _config_loaded
    if _config_loaded:
        return
    with _config_lock:
        if _config_loaded:
            return
        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()
        _config_loaded = True


def core_v1():
    load_config()
    return client.CoreV1Api()


def list_nodes():
    v1 = core_v1()
    return v1.list_node().items


def get_node_cpu_count(node):
    cpu_str = (node.status.capacity or {}).get("cpu", "1")
    try:
        return int(cpu_str)
    except (ValueError, TypeError):
        return 1


def bind_pod_to_node(pod, node_name):
    if not node_name:
        raise ValueError("node_name is empty or None")

    pod_name = pod.metadata.name
    ns = pod.metadata.namespace or "default"

    if getattr(pod.spec, "node_name", None):
        return

    node_name = str(node_name)

    body = {
            "apiVersion": "v1",
            "kind": "Binding",
            "metadata": {
                "name": pod_name
            },
            "target": {
                "apiVersion": "v1",
                "kind": "Node",
                "name": node_name
            }
        }
    
    core = core_v1()
    api_client = core.api_client

    path = f"/api/v1/namespaces/{ns}/pods/{pod_name}/binding"

    try:
        api_client.call_api(
            path,
            "POST",
            body=body,
            response_type="V1Binding",
            auth_settings=["BearerToken"],
            _preload_content=False,
        )
    except ApiException as e:
        if e.status == (409, 422):
            return
        raise RuntimeError(f"Binding failed (status={e.status}): {e.reason} body={getattr(e,'body', None)}") from e


def list_pending_pods_for_scheduler(scheduler_name):
    v1 = core_v1()
    pods = v1.list_pod_for_all_namespaces(field_selector="status.phase=Pending").items
    result = []

    for p in pods:
        if not p or not p.status or not p.spec:
            continue
        if p.spec.scheduler_name != scheduler_name:
            continue
        if getattr(p.spec, "node_name", None):
            continue
        if getattr(p.metadata, "deletion_timestamp", None):
            continue

        result.append(p)

    return result


def list_all_pods():
    v1 = core_v1()
    return v1.list_pod_for_all_namespaces().items


def wait(seconds):
    time.sleep(seconds)
