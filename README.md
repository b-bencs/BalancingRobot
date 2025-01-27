# BalancingRobot

## Compile

Only text output:
 
g++ -std=c++14 -Wall -c main.cpp  -g -pthread -lcurl
 
g++ -std=c++14 -Wall -o main main.o -g -pthread -lrt -g -lcurl
 
Graphical output:
 
g++ -std=c++14 -Wall -c main_graphic.cpp  -g -pthread -lrt -g -lGL -lGLU -lglut  -lGLEW -lcurl
 
g++ -std=c++14 -Wall -o main_graphic main_graphic.o -g -pthread -lrt -g -lGL -lGLU -lglut -lGLEW -lcurl

## Run tests

To run the testbench open two terminal windows. In one run the compiled c++ application

./main

In the other terminal window run pidserver.py by issuing

python3 pidserver.py
