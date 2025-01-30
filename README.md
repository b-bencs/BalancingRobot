# BalancingRobot

## Run the simulator in Kubernetes
1. Build the robot simulator in Docker
   ```
   cd Influxdb
   docker build . -t influxtmp
   cd ../Robot
   bash build.sh
   ```
2. Install InfluxDB
   ```
   cd Influxdb
   bash influxdb_install.sh
   ```
3. Install Grafana
   ```
   cd Grafana
   kubectl apply -f grafana.yaml
   ```
4. Run the robot simulator
   ```
   cd Robot
   kubectl apply -f deployment.yaml
   ```
5. The pid response timeout of the robot can be adjusted in the command section of the container in the deployment.yaml file
6. The robot needs a server that calculates the PID values to start the PID server issue the following commands
   ```
   cd Server
   bash build.sh
   kubectl apply -f deployment.yaml
   kubectl apply -f service.yaml
   ```

## Adjusting the robot's response timeout
The completion time of PID calculation does not depend on the input parameters, therefore it uses almost the same amount of CPU ticks in  each invocation.
Almost, because parsing the input and building the output json strings can vary a bit.
To have an idea of the completion time of an invocation we can measure it by using the Linux Perf tool and Hey, that is an HTTP load generator application.
Here you can find 6 example json strings that can be received by the pid server
```
{"Derivator":-0.7239541411399841,"Integrator":-3.0,"Integrator_max":3.0,"Integrator_min":-3.0,"Kd":6.0,"Ki":0.10000000149011612,"Kp":7.0,"current_value":0.08886042982339859,"set_point":0.0}
{"Derivator":1.4746179580688477,"Integrator":0.2876659631729126,"Integrator_max":3.0,"Integrator_min":-3.0,"Kd":6.0,"Ki":0.10000000149011612,"Kp":7.0,"current_value":-1.6177839040756226,"set_point":0.0}
{"Derivator":-2.405780792236328,"Integrator":-3.0,"Integrator_max":3.0,"Integrator_min":-3.0,"Kd":0.009999999776482582,"Ki":0.004999999888241291,"Kp":0.009999999776482582,"current_value":2.1491098403930664,"set_point":0.0}
{"Derivator":-0.42415735125541687,"Integrator":-3.0,"Integrator_max":3.0,"Integrator_min":-3.0,"Kd":0.009999999776482582,"Ki":0.004999999888241291,"Kp":0.009999999776482582,"current_value":-0.16618366539478302,"set_point":0.0}
{"Derivator":1.042830228805542,"Integrator":3.0,"Integrator_max":3.0,"Integrator_min":-3.0,"Kd":0.009999999776482582,"Ki":0.004999999888241291,"Kp":0.009999999776482582,"current_value":0.05838686227798462,"set_point":0.0}
{"Derivator":-0.6928533315658569,"Integrator":2.211747169494629,"Integrator_max":3.0,"Integrator_min":-3.0,"Kd":0.009999999776482582,"Ki":0.004999999888241291,"Kp":0.009999999776482582,"current_value":2.1661009788513184,"set_point":0.0}
```
Passing one of these to hey we can fake a robot calling the PID server by the following command
```
./hey_linux_amd64 -c 1 -n 10 -q 1 -m POST -d {"Derivator":-0.7239541411399841,"Integrator":-3.0,"Integrator_max":3.0,"Integrator_min":-3.0,"Kd":6.0,"Ki":0.10000000149011612,"Kp":7.0,"current_value":0.08886042982339859,"set_point":0.0} -o csv http://10.96.52.184:5000/pid
```
Command explanation:
1. -c 1 - concurrency is 1, let's not overcomplicate our job
2. -n 10 - 10 measurements
3. -q 1 - 1 request / sec
4. -m POST - Using HTTP POST method
5. -d .... - request body
6. -o csv - csv output for the sake of legibility
7. address of the server, this can be acquired by issuing
   ```
   kubectl get services
   ```

## Robot with graphical output - Only for local testing

To compile the robot issue the following two commands
``` 
g++ -std=c++14 -Wall -c main_graphic.cpp  -g -pthread -lrt -g -lGL -lGLU -lglut  -lGLEW -lcurl
g++ -std=c++14 -Wall -o main_graphic main_graphic.o -g -pthread -lrt -g -lGL -lGLU -lglut -lGLEW -lcurl
```

### Run tests with the graphical robot

To run the testbench open two terminal windows. In one run the compiled c++ application
```
./main_graphic
```
In the other terminal window run pidserver.py by issuing
```
python3 pidserver.py
```
