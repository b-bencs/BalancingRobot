#ifndef HTTP_PID_CPP
#define HTTP_PID_CPP

#include "pid.cpp"
#include "webclient.cpp"
#include <time.h>
#include <string>
#include <sstream>
#include <iostream>
#include <stdexcept>
#include "json.hpp"

using json = nlohmann::json;
using std::to_string;

struct HTTP_PID : PID {
    std::string serveraddr;
    static WebClient wc;
    //HTTP_PID() {}
    HTTP_PID(std::string pidserver, long double P=7.0, long double I=0.1, long double D=6.0, long double Derivator=0, long double Integrator=0, long double Integrator_max=3, long double Integrator_min=-3) : \
    PID(P, I, D, Derivator, Integrator, Integrator_max, Integrator_min) {
	serveraddr = pidserver;
	//wc = WebClient("http://localhost:31500/pid");
    }
    
    HTTP_PID(const HTTP_PID& p) : PID(p) {
	serveraddr = p.serveraddr;
	//wc = WebClient(serveraddr);
    }
    
    HTTP_PID& operator=(const HTTP_PID& p) {
    if(this != &p) {
        (PID)*this = (PID)p;
        serveraddr = p.serveraddr;
	}
	return *this;
    }
    
    long double update(long double current_value, long double dt, long double expected_dt) {
    struct timespec ts;
    timespec_get(&ts, CLOCK_TAI);
	json data = json::object({
	                {"time", 1000000000*ts.tv_sec+ts.tv_nsec},
				    {"current_value", current_value},
					{"expected_dt", expected_dt},
					{"dt", dt},
				    {"set_point", set_point},
				    {"Kp", Kp},
				    {"Ki", Ki},
				    {"Kd", Kd},
				    {"Integrator_min", Integrator_min},
				    {"Integrator_max", Integrator_max},
				    {"Integrator", Integrator},
				    {"Derivator", Derivator},
					{"D_value", D_value}
				});
	wc.post(to_string(data));

	//std::stringstream buffer;
	/* buffer << "{" << "\"current_value\": " << current_value << ", \"set_point\": " \
	       << this->set_point << ", \"error\": " << this->error \
	       << ", \"Kp\": " << this->Kp << ", \"Ki\": " << this->Ki <<  ", \"Kd\": " << this->Kd \
	       << ", \"Integrator_min\": " << this->Integrator_min << ", \"Integrator_max\": " << this->Integrator_max \
	       << ", \"Integrator\": " << this->Integrator << ", \"Derivator\": " << this->Derivator << "}"; */
        //wc.post(buffer.str());
	
	//std::stringstream ss(wc.getResponse());
	json return_data;
	try {
	    return_data = json::parse(wc.getResponse());
	}
	catch (json::parse_error& error) {
	    throw std::runtime_error("parse error");
	}
	error = return_data["error"];
	P_value = return_data["P_value"];
	I_value = return_data["I_value"];
	D_value = return_data["D_value"];
	Integrator = return_data["Integrator"];
	Derivator = return_data["Derivator"];
	
	//std::cout<<to_string(return_data)<<std::endl;
	//std::cout<<ss.str();
	return return_data["PID"];
    }
};

WebClient HTTP_PID::wc = WebClient("http://pidserver.default.svc.cluster.local:5000/pid");
//WebClient HTTP_PID::wc = WebClient("http://pidserver.openfaas-fn.svc.cluster.local:8080/pid");

#endif
