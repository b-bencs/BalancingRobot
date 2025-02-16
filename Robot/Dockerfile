FROM influxtmp
WORKDIR cppapp
COPY webclient.cpp .
COPY pid.cpp .
COPY http_pid.cpp .
COPY ibalancingbot.cpp .
COPY influxdbwriter.cpp .
COPY json.hpp .
COPY main.cpp .
RUN g++ -std=c++17 -o myapp main.cpp -I/usr/local/include/InfluxDB -L/usr/local/lib -lInfluxDB -lcurl -g
RUN ldconfig
CMD "./myapp"
