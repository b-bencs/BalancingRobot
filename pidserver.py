# import flast module
from flask import Flask
from flask import request
import json
import time

# instance of flask application
app = Flask(__name__)

# home route that returns below text when root url is accessed
@app.route("/")
def hello_world():
    return "<p>Hello, World!</p>"

@app.route("/pid", methods=['GET', 'POST'])
def pid():
    """
    Calculate PID output value for given reference input and feedback
    """
    if request.method == 'POST':
        d = request.get_data()
        print(d.decode())
        d = json.loads(d.decode())
        print(type(d))

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

if __name__ == '__main__':  
   app.run("0.0.0.0", port=5000)  
