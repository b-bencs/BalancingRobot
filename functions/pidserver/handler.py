import json

def handle(req):
    d = json.loads(req)
    error = d["set_point"] - d["current_value"]

    P_value = d["Kp"] * error
    tau = 3 * d["expected_dt"]
    alpha = d["dt"] / (d["dt"] + tau)

    previous_error = d["Derivator"]
    raw_derivative = (error - previous_error) / d["dt"]
    D_value = (1.0 - alpha) * d["D_value"] + alpha * raw_derivative
    Derivator = error
    D_term = d["Kd"] * D_value

    Integrator = d["Integrator"] + 0.5 * (error + previous_error) * d["dt"]

    if Integrator > d["Integrator_max"]:
        Integrator = d["Integrator_max"]
    elif Integrator < d["Integrator_min"]:
        Integrator = d["Integrator_min"]

    I_value = Integrator * d["Ki"]

    PID = P_value + I_value + D_term

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
