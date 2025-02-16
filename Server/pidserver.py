# import flast module
from flask import Flask
from flask import request
import json
#import time
import scheddl
import os

rt = bool(os.getenv("RT", False))
runtime = int(os.getenv("RUNTIME", 100))
deadline = int(os.getenv("DEADLINE", 100))
period = int(os.getenv("PERIOD", 100))
threaded = bool(os.getenv("THREADED", False))

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
        #print(d.decode())
        d = json.loads(d.decode())
        #print(type(d))
        #t = time.clock_gettime(time.CLOCK_TAI)*10**9
        #diff = int(t - d["time"])
        #app.logger.info("diff %d", diff)
        #dl_args = (
        #    7 * 1000 * 1000, # runtime in nanoseconds
        #    10 * 1000 * 1000, # deadline in nanoseconds
        #    10 * 1000 * 1000  # time period in nanoseconds
        #)

        #scheddl.set_deadline(*dl_args)
        try:
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
        finally:
            #scheddl.sched_yield()
            pass

if __name__ == '__main__':  
    #param = os.sched_param(os.sched_get_priority_max(os.SCHED_FIFO))
    #os.sched_setscheduler(0, os.SCHED_FIFO, param)
    if rt:
        dl_args = (
            runtime  * 1000 * 1000, # runtime in nanoseconds
            deadline * 1000 * 1000, # deadline in nanoseconds
            period   * 1000 * 1000  # time period in nanoseconds
        )
        scheddl.set_deadline(*dl_args)
        app.run("0.0.0.0", port=5000, threaded=False)
    else:
        if not threaded:
            app.run("0.0.0.0", port=5000, threaded=False)
        else:
            app.run("0.0.0.0", port=5000, threaded=False, processes=16)
    #app.run("0.0.0.0", port=5000, threaded=False, processes=16)
