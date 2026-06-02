import json
import math

from .handler import handle


def invoke(**overrides):
    request = {
        "set_point": 0.25,
        "current_value": -0.1,
        "Kp": 7.0,
        "Ki": 0.1,
        "Kd": 6.0,
        "Integrator": 0.2,
        "Integrator_min": -3.0,
        "Integrator_max": 3.0,
        "Derivator": 0.05,
        "D_value": 0.4,
        "dt": 0.1,
        "expected_dt": 0.1,
    }
    request.update(overrides)
    return json.loads(handle(json.dumps(request)))


def test_handle_uses_filtered_derivative_and_trapezoidal_integral():
    response = invoke()

    assert math.isclose(response["D_value"], 1.05)
    assert math.isclose(response["Integrator"], 0.22)
    assert math.isclose(response["I_value"], 0.022)
    assert math.isclose(response["PID"], 8.772)


def test_handle_uses_clamped_integrator_for_i_value():
    response = invoke(
        set_point=0,
        current_value=-10,
        Kp=0,
        Ki=2,
        Kd=0,
        Integrator=2.5,
        Derivator=10,
        D_value=0,
    )

    assert response["Integrator"] == 3
    assert response["I_value"] == 6
    assert response["PID"] == 6
