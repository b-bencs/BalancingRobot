import json

def handle(req):
    d = json.loads(req)
    error = d["set_point"] - d["current_value"]

    P_value = d["Kp"] * error
    D_value = d["Kd"] * ( error - d["Derivator"])
    Derivator = error

    Integrator = d["Integrator"] + error

    if Integrator > d["Integrator_max"]:
        Integrator = d["Integrator_max"]
    elif Integrator < d["Integrator_min"]:
        Integrator = d["Integrator_min"]

    I_value = d["Integrator"] * d["Ki"]

    PID = P_value + I_value + D_value

    ret_dict = {
        "error": error,
        "P_value": P_value,
        "D_value": D_value,
        "Derivator": Derivator,
        "Integrator": Integrator,
        "I_value": I_value,
        "PID": PID
    }

    return json.dumps(ret_dict)
