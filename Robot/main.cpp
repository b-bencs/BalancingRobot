#include <iostream>
#include <chrono>
#include <thread>
#include <mutex>
#include <condition_variable>

#include <stdio.h>
#include <math.h>
#include <thread>
#include "ibalancingbot.cpp"
#include "pid.cpp"
#include "http_pid.cpp"
# define M_PI           3.14159265358979323846  /* pi */

long long ref_time = 0;
long long response_timeout = 1;
int FPS = 10;

float CameraPosX = 0.0;
float CameraPosY = 3;
float CameraPosZ = 10.0;
float ViewUpX = 0.0;
float ViewUpY = 1.0;
float ViewUpZ = 0.0;
float CenterX = 0.0;
float CenterY = 0.0;
float CenterZ = 0.0;
bool follow_robot = false; //so that the camera will follow the robot or not

float posx = 0;
float posz = 0;

float Theta = 0.0;
float dtheta=2*M_PI/100.0;
float Radius = sqrt( pow(CameraPosX,2)+pow(CameraPosZ,2));

//GLUquadricObj* quadric = gluNewQuadric();
//gluQuadricNormals(quadric, GLU_SMOOTH);

float rotation = 90.0;
float posX = 0, posY = 0, posZ = 0;
float move_unit = 3;
float rate = 1.0f;
float angle = -0.0f;
float RotateX = 0.f, RotateY = 45.f;
IBalancingBot myBot;

float speed = 0.0;
float current_speed = 0.0;
float turn = 0.0;
float current_turn = 0.0;
bool use_pid = true;
float F[] = {0.0,0.0};

auto start_t = std::chrono::steady_clock::now();

HTTP_PID myPIDphi = HTTP_PID("http://10.44.0.7:5000/pid");
HTTP_PID myPIDx = HTTP_PID("http://10.44.0.7:5000/pid");
HTTP_PID myPIDpsi = HTTP_PID("http://10.44.0.7:5000/pid");

using namespace std::literals::chrono_literals;

//std::chrono::milliseconds getElapsedTime() {
long long getElapsedTime() {
    auto end = std::chrono::steady_clock::now();
    return std::chrono::duration_cast<std::chrono::milliseconds>(end - start_t).count();
}

void initPIDs() {
    // Function that initializes the PIDs parameters (Kp, Ki, Kd)

    myPIDphi.setKp(7.0);
    myPIDphi.setKi(0.1);
    myPIDphi.setKd(6.0);
    myPIDphi.setPoint(0);

    myPIDx.setKp(0.01);
    myPIDx.setKi(0.005);
    myPIDx.setKd(0.01);
    myPIDx.setPoint(0);

    myPIDpsi.setKp(1);
    myPIDpsi.setKi(1);
    myPIDpsi.setKd(0);
    myPIDpsi.setPoint(0);
}

void _correction() {
    /* Function that uses the PID and the robot state to generate a new 
        command according to the speed and turn objectives
    */

    if(use_pid) {
        if(current_speed != speed) {
            current_speed = speed;
            myPIDx.setPoint(speed);  // we only want to reset the PID when the speed changes
	}

        if(current_turn != turn) {
            current_turn = turn;
            myPIDpsi.setPoint(turn);  // we only want to reset the PID when the rotation changes
	}

        float pidx_value = myPIDx.update(myBot.xp);  // Pid over linear a speed
        float pidpsi_value = myPIDpsi.update(-myBot.psip);  // Pid over psi angular speed rotation

        float tilt = - pidx_value + myBot.phi;
        rotation = pidpsi_value;

        float pidphi_value = myPIDphi.update(tilt);  // pid over the pendulum angle phi

        F[0] = -pidphi_value-rotation;
	F[1] = -pidphi_value+rotation;
    }
    else {
        F[0] = 0.0;
	F[1] = 0.0;
    }
}

void correction() {
    std::mutex m;
    std::condition_variable cv;
    
    std::thread t([&cv]() {
	try {
	    float pidx_value = myPIDx.update(myBot.xp);  // Pid over linear a speed
	    float pidpsi_value = myPIDpsi.update(-myBot.psip);  // Pid over psi angular speed rotation

	    float tilt = - pidx_value + myBot.phi;
	    rotation = pidpsi_value;

	    float pidphi_value = myPIDphi.update(tilt);  // pid over the pendulum angle phi

	    F[0] = -pidphi_value-rotation;
	    F[1] = -pidphi_value+rotation;
	    // Since there is no webserver, we simulate the missed requests randomly
	    /*if(!(rand()%20)) {
		std::this_thread::sleep_for(11ms);
	    }*/
	    cv.notify_one();
	}
	catch (...) {
	    std::this_thread::sleep_for(std::chrono::milliseconds(response_timeout));
	    //std::this_thread::sleep_for(5ms);
	}
    });
    
    t.detach();

    std::unique_lock<std::mutex> l(m);
    if(cv.wait_for(l, 20ms) == std::cv_status::timeout) {
	//t.join();
	printf("runtime_error timeout\n");
	//throw std::runtime_error("Timeout");
	throw std::exception();
    }
}

void timeoutCorrection() {
    if(current_speed != speed) {
	current_speed = speed;
	myPIDx.setPoint(speed);  // we only want to reset the PID when the speed changes
    }

    if(current_turn != turn) {
	current_turn = turn;
	myPIDpsi.setPoint(turn);  // we only want to reset the PID when the rotation changes
    }

    HTTP_PID copyMyPIDx(myPIDx);
    HTTP_PID copyMyPIDpsi(myPIDpsi);
    HTTP_PID copyMyPIDphi(myPIDphi);
    float copyRotation = rotation;
    float copyF[2];
    copyF[0] = F[0];
    copyF[1] = F[1];
    try {
	correction();
    }
    //catch(std::runtime_error& e) {
    catch(...) {
	//printf("runtime_error timeout\n");
	myPIDx = copyMyPIDx;
	myPIDpsi = copyMyPIDpsi;
	myPIDphi = copyMyPIDphi;
	rotation = copyRotation;
	F[0] = copyF[0];
	F[1] = copyF[1];
    }
}

void threadCorrection() {
    while(true) {
	//if (glutGet(GLUT_ELAPSED_TIME)-ref_time > (1.0/FPS)*1000) {
	if (getElapsedTime()-ref_time > (1.0/FPS)*1000) {
	    correction();
	}
    }
}

void animation() {
    // Function to compute the robot state at each time step and to draw it in the world

    // FPS expressed in ms between 2 consecutive frame
    float delta_t = 0.001; // the time step for the computation of the robot state
    //if (glutGet(GLUT_ELAPSED_TIME)-ref_time > (1.0/FPS)*1000) {
    if (getElapsedTime()-ref_time > (1.0/FPS)*1000) {
        // at each redisplay (new display frame)
        float dst = 0;
        for (int i = 0; i < 100; i++) {
            // we want the computation of the robot state to be faster than the 
            // display to limit the compution errors
            // display : new frame at each 100ms
            // deltat : 1ms for the differential equation evaluation
            myBot.dynamics(delta_t, F);
            // we also compute the new x and z position of the robot in the world
            dst = (myBot.xp * delta_t);
            posx += dst*cos(myBot.psi);
            posz += (-dst*sin(myBot.psi));
	}
        //correction();  // calls the PIDs if enable
	timeoutCorrection();
        //glutPostRedisplay();  // refresh the display
        ref_time=getElapsedTime(); //glutGet(GLUT_ELAPSED_TIME);
	std::this_thread::sleep_for(10ms);
	std::cout<<myBot.phi<<std::endl;
    }
}

/*
void SpecialFunc(int skey, int x, int y) {
    //Function to handle the keybord keys

    if (glutGetModifiers() == GLUT_ACTIVE_SHIFT) {
        // SHIFT pressed
        if (skey == GLUT_KEY_UP) {
            CameraPosY+=0.3;  // put the camera higher
	}
        if (skey == GLUT_KEY_DOWN) {
            CameraPosY-=0.3;  // put the camera lower
	}
    }
    else {
        // standard
        if (skey == GLUT_KEY_LEFT) {
            rotate_camera(-dtheta);
	}
        else if (skey == GLUT_KEY_RIGHT) {
            rotate_camera(dtheta);
	}
        else if (skey == GLUT_KEY_UP) {
            zoom_camera(0.9);
	}
        else if (skey == GLUT_KEY_DOWN) {
            zoom_camera(1.1);
	}
        else if (skey == GLUT_KEY_PAGE_DOWN) {
            printf("\tSimulation ON\n");
            glutIdleFunc(animation);
	}
        else if (skey == GLUT_KEY_PAGE_UP) {
            //print("\tSimulation PAUSE");
            glutIdleFunc(NULL);
	}
        else if (skey == GLUT_KEY_F1) {
            speed = 0.15;
	}
        else if (skey == GLUT_KEY_F2) {
            speed = -0.15;
	}
        else if (skey == GLUT_KEY_F3) {
            turn = 0.3;
	}
        else if (skey == GLUT_KEY_F4) {
            speed = 0;
            turn = 0;
	}
        else if (skey == GLUT_KEY_F5) {
            use_pid = !use_pid;
            printf("\tUsing PID\n");
            if(use_pid == true) {
                initPIDs();
	    }
	}
        else if (skey == GLUT_KEY_F6) {
            posx = posz = 0;
            myBot.initRobot();
            initPIDs();
	}
        else if (skey == GLUT_KEY_F7) {
            myBot.phi += (10*M_PI/180);
	}
        else if (skey == GLUT_KEY_F8) {
            myBot.phi += (-20*M_PI/180);
	}
        else if (skey == GLUT_KEY_F9) {
            follow_robot = not(follow_robot);
            //print("\tFollowing robot : " + str(follow_robot));
	}
    }
    glutPostRedisplay();
}*/

int main(int argc, char** argv) {
    if(argc > 1) {
        response_timeout = std::atoll(argv[1]);
    }
    //std::thread correctionThread(threadCorrection);
    srand((unsigned)time(0));
    initPIDs();
    while(1) {
	animation();
    }
}
