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
