FROM ubuntu
RUN apt update -y && apt install -y g++ cmake libcurl4-openssl-dev libboost-all-dev git
RUN git clone https://github.com/libcpr/cpr.git
WORKDIR /cpr
RUN mkdir build
WORKDIR /cpr/build
RUN cmake .. -DCPR_USE_SYSTEM_CURL=ON -DBUILD_SHARED_LIBS=OFF -DCPR_ENABLE_SSL=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON
RUN cmake --build . --parallel
RUN cmake --install .
WORKDIR /influxdb
RUN git clone https://github.com/offa/influxdb-cxx
WORKDIR /influxdb/influxdb-cxx
RUN mkdir build
WORKDIR /influxdb/influxdb-cxx/build
RUN cmake -D INFLUXCXX_TESTING:BOOL=OFF ..
RUN make install
