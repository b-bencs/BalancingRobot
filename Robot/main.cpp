#include <iostream>
#include <chrono>
#include <thread>
#include <mutex>
#include <condition_variable>

#include <stdio.h>
#include <math.h>
#include <thread>
#include <unistd.h>
#include <limits.h>
#include "ibalancingbot.cpp"
#include "pid.cpp"
#include "http_pid.cpp"
#include "influxdbwriter.cpp"
#define M_PI 3.14159265358979323846 /* pi */

long double ref_time = 0.0;
long double update_ref_time = 0.0;
long long response_timeout = 1;
int FPS = 10;
long double dt = 1.0f / FPS;
long double delta_time;
long double update_delta_time;

long double CameraPosX = 0.0;
long double CameraPosY = 3;
long double CameraPosZ = 10.0;
long double ViewUpX = 0.0;
long double ViewUpY = 1.0;
long double ViewUpZ = 0.0;
long double CenterX = 0.0;
long double CenterY = 0.0;
long double CenterZ = 0.0;
bool follow_robot = false; // so that the camera will follow the robot or not

long double posx = 0;
long double posz = 0;

long double Theta = 0.0;
long double dtheta = 2 * M_PI / 100.0;
long double Radius = sqrt(pow(CameraPosX, 2) + pow(CameraPosZ, 2));

// GLUquadricObj* quadric = gluNewQuadric();
// gluQuadricNormals(quadric, GLU_SMOOTH);

long double rotation = 90.0;
long double posX = 0, posY = 0, posZ = 0;
long double move_unit = 3;
long double rate = 1.0f;
long double angle = -0.0f;
long double RotateX = 0.f, RotateY = 45.f;
IBalancingBot myBot;

long double speed = 0.0;
long double current_speed = 0.0;
long double turn = 0.0;
long double current_turn = 0.0;
bool use_pid = true;
long double F[] = {0.0, 0.0};

auto start_t = std::chrono::high_resolution_clock::now();

HTTP_PID myPIDphi = HTTP_PID("http://10.44.0.7:5000/pid");
HTTP_PID myPIDx = HTTP_PID("http://10.44.0.7:5000/pid");
HTTP_PID myPIDpsi = HTTP_PID("http://10.44.0.7:5000/pid");
InfluxDBWriter influxdbwriter;
bool timeout_happened = false;

using namespace std::literals::chrono_literals;

long double getElapsedTime() {
    auto end = std::chrono::high_resolution_clock::now();
    std::chrono::duration<long double, std::ratio<1>> duration = end - start_t;
    return duration.count();
}

void initPIDs()
{
    // Function that initializes the PIDs parameters (Kp, Ki, Kd)

    myPIDphi.setKp(7.0);
    myPIDphi.setKi(0.1);
    myPIDphi.setKd(6.0);
    myPIDphi.setPoint(0);

    myPIDx.setKp(0.01);
    myPIDx.setKi(0.05 * dt);
    myPIDx.setKd(0.1 * dt);
    myPIDx.setPoint(0);

    myPIDpsi.setKp(1);
    myPIDpsi.setKi(1);
    myPIDpsi.setKd(0);
    myPIDpsi.setPoint(0);
}

void correction()
{
    std::mutex m;
    std::condition_variable cv;

    // correctionReturnStruct ret;
    HTTP_PID copyMyPIDx(myPIDx);
    HTTP_PID copyMyPIDpsi(myPIDpsi);
    HTTP_PID copyMyPIDphi(myPIDphi);
    long double copyRotation = rotation;
    long double copyF[2];
    copyF[0] = F[0];
    copyF[1] = F[1];

    // std::thread t([&cv, &copyMyPIDx, &copyMyPIDpsi, &copyMyPIDphi, &copyRotation, &copyF]() {
    std::thread t([&cv]()
                  {
    	try {
    	    long double pidx_value = myPIDx.update(myBot.xp, update_delta_time, dt);  // Pid over linear a speed
    	    long double pidpsi_value = myPIDpsi.update(-myBot.psip, update_delta_time, dt);  // Pid over psi angular speed rotation


    	    long double tilt = - pidx_value + myBot.phi;
    	    rotation = pidpsi_value;
    	    //copyRotation = pidpsi_value;

    	    long double pidphi_value = myPIDphi.update(tilt, update_delta_time, dt);  // pid over the pendulum angle phi
    	    //long double pidphi_value = copyMyPIDphi.update(tilt);  // pid over the pendulum angle phi

    	    F[0] = -pidphi_value-rotation;
    	    F[1] = -pidphi_value+rotation;
    	    //copyF[0] = -pidphi_value-copyRotation;
    	    //copyF[1] = -pidphi_value+copyRotation;
    	    // Since there is no webserver, we simulate the missed requests randomly
    	    /*if(!(rand()%20)) {
    		std::this_thread::sleep_for(11ms);
    	    }*/
    	    cv.notify_one();
    	}
    	//Cetches JSON parse error, and sleeps until the timeout passes
    	catch (...) {
    	    std::this_thread::sleep_for(std::chrono::milliseconds(response_timeout));
    	    //std::this_thread::sleep_for(5ms);
    	} });

    t.detach();

    std::unique_lock<std::mutex> l(m);
    // if(cv.wait_for(l, 20ms) == std::cv_status::timeout) {
    if (cv.wait_for(l, std::chrono::milliseconds(response_timeout)) == std::cv_status::timeout)
    {
        // t.join();
        // printf("runtime_error timeout\n");
        // throw std::runtime_error("Timeout");
        // t.join();
        std::cout << response_timeout << std::endl;
        throw std::exception();
        // throw std::runtime_error("Timeout");
    }
    /*myPIDx = copyMyPIDx;
    myPIDpsi = copyMyPIDpsi;
    myPIDphi = copyMyPIDphi;
    rotation = copyRotation;
    F[0] = copyF[0];
    F[1] = copyF[1];*/
}

void timeoutCorrection()
{
    if (current_speed != speed)
    {
        current_speed = speed;
        myPIDx.setPoint(speed); // we only want to reset the PID when the speed changes
    }

    if (current_turn != turn)
    {
        current_turn = turn;
        myPIDpsi.setPoint(turn); // we only want to reset the PID when the rotation changes
    }

    HTTP_PID copyMyPIDx(myPIDx);
    HTTP_PID copyMyPIDpsi(myPIDpsi);
    HTTP_PID copyMyPIDphi(myPIDphi);
    long double copyRotation = rotation;
    long double copyF[2];
    copyF[0] = F[0];
    copyF[1] = F[1];
    try
    {
        correction();
    }
    // catch(std::runtime_error& e) {
    catch (...)
    {
        // printf("runtime_error timeout\n");
        std::this_thread::sleep_for(10ms);
        timeout_happened = true;
        myPIDx = copyMyPIDx;
        myPIDpsi = copyMyPIDpsi;
        myPIDphi = copyMyPIDphi;
        rotation = copyRotation;
        F[0] = copyF[0];
        F[1] = copyF[1];
    }
}

void threadCorrection()
{
    while (true)
    {
        // if (glutGet(GLUT_ELAPSED_TIME)-ref_time > (1.0/FPS)*1000) {
            if (getElapsedTime()-ref_time > 1.0/FPS) {
                correction();
            }
    }
}

void animation(){
    double current_time = getElapsedTime();
    delta_time = current_time-ref_time;
    update_delta_time = current_time-update_ref_time;
    if (delta_time > 1.0/FPS){
        if (myBot.phi < 0.00001 && myBot.phi > -0.00001 && myBot.phip < 0.00001 && myBot.phip > -0.00001){
            std::cout<<"Evertything is zero."<<std::endl;
            myBot.initRobot();
        }

        if (myBot.phi <= 0.785 && myBot.phi >= -0.785){
            long double dst = 0;
            myBot.dynamics(delta_time, F);
            dst = (myBot.xp * delta_time);
            posx += dst*cos(myBot.psi);
            posz += (-dst*sin(myBot.psi));
            timeoutCorrection();
        } else if (myBot.phi > 0.785){
            myBot.phi = 2.03;
        } else {
            myBot.phi = -2.03;
        }
        ref_time = getElapsedTime();
        if (timeout_happened == false) update_ref_time = getElapsedTime();
        influxdbwriter.Write(myBot.phi, timeout_happened, update_delta_time);
        timeout_happened = false;
    }
}

int main(int argc, char **argv)
{
    char hostname[HOST_NAME_MAX];
    gethostname(hostname, HOST_NAME_MAX);
    // influxdbwriter = InfluxDBWriter(std::string("http://influxdb.default.svc.cluster.local:8086"), std::string("robot"));
    influxdbwriter = InfluxDBWriter(std::string("http://influxdb.default.svc.cluster.local:8086"), std::string("robot"), std::string(hostname));
    // influxdbwriter = InfluxDBWriter("http://influxdb.default.svc.cluster.local:8086", "robot", hostname);
    if (argc > 1)
    {
        response_timeout = std::atoll(argv[1]);
        FPS = std::atoll(argv[2]);
    }
    dt = 1.0f / FPS;
    // std::thread correctionThread(threadCorrection);
    srand((unsigned)time(0));
    initPIDs();
    while (1){
        animation();
    }
}
