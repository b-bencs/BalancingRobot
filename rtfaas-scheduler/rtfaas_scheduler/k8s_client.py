import os
import threading
import time

from kubernetes import client, config
from kubernetes.client.rest import ApiException

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
    token_path = "/var/run/secrets/kubernetes.io/serviceaccount/token"
    ca_path = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"

    if os.path.exists(token_path):
        token = open(token_path).read().strip()

        cfg = client.Configuration()
        cfg.host = f"https://{os.environ['KUBERNETES_SERVICE_HOST']}:{os.environ['KUBERNETES_SERVICE_PORT']}"
        cfg.ssl_ca_cert = ca_path
        cfg.verify_ssl = True

        api_client = client.ApiClient(cfg)
        api_client.set_default_header("Authorization", "Bearer " + token)

        return client.CoreV1Api(api_client)

    config.load_kube_config()
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

    core = core_v1()
    body = client.V1Binding(
        metadata=client.V1ObjectMeta(name=pod_name),
        target=client.V1ObjectReference(
            api_version="v1",
            kind="Node",
            name=node_name,
        ),
    )

    try:
        core.create_namespaced_pod_binding(
            name=pod_name,
            namespace=ns,
            body=body,
            _preload_content=False,
        )
    except ApiException as e:
        if e.status in (409, 422):
            return
        raise RuntimeError(
            f"Binding failed (status={e.status}): {e.reason} body={getattr(e, 'body', None)}"
        ) from e


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
