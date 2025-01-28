g++ -std=c++14 -Wall -c main.cpp  -g -pthread -lcurl
g++ -std=c++14 -Wall -o main main.o -g -pthread -lrt -g -lcurl
