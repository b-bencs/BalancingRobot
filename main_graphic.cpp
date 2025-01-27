#include <iostream>
#include <chrono>
#include <thread>
#include <mutex>
#include <condition_variable>

#include <stdio.h>
#include <GL/glut.h>
#include <GL/freeglut.h>
#include <GL/gl.h>
#include <math.h>
#include <thread>
#include "ibalancingbot.cpp"
#include "pid.cpp"
#include "http_pid.cpp"
# define M_PI           3.14159265358979323846  /* pi */

int ref_time = 0;
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

GLUquadricObj* quadric = gluNewQuadric();
//gluQuadricNormals(quadric, GLU_SMOOTH);

GLfloat rotation = 90.0;
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
bool use_pid;
float F[] = {0.0,0.0};

HTTP_PID myPIDphi = HTTP_PID("http://localhost:5000/pid");
HTTP_PID myPIDx = HTTP_PID("http://localhost:5000/pid");
HTTP_PID myPIDpsi = HTTP_PID("http://localhost:5000/pid");

using namespace std::literals::chrono_literals;

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
	    if(!(rand()%20)) {
		std::this_thread::sleep_for(11ms);
	    }
	    cv.notify_one();
	}
	catch (...) {
	    std::this_thread::sleep_for(20ms);
	}
    });
    
    t.detach();

    std::unique_lock<std::mutex> l(m);
    if(cv.wait_for(l, 10ms) == std::cv_status::timeout) {
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
	    //delete &copyMyPIDx;
	    //delete &copyMyPIDpsi;
	    //delete &copyMyPIDphi;
	}
}

void threadCorrection() {
    while(true) {
	if (glutGet(GLUT_ELAPSED_TIME)-ref_time > (1.0/FPS)*1000) {
	    correction();
	}
    }
}

void animation() {
    // Function to compute the robot state at each time step and to draw it in the world

    // FPS expressed in ms between 2 consecutive frame
    float delta_t = 0.001; // the time step for the computation of the robot state
    if (glutGet(GLUT_ELAPSED_TIME)-ref_time > (1.0/FPS)*1000) {
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
        glutPostRedisplay();  // refresh the display
        ref_time=glutGet(GLUT_ELAPSED_TIME);
	std::this_thread::sleep_for(10ms);
	std::cout<<myBot.phi<<std::endl;
    }
}

void Timer(int value)
{
	glutPostRedisplay();      // Post re-paint request to activate display()
	glutTimerFunc(16, Timer, 0); // next Timer call milliseconds later
}

void drawGround(){

    int nb_rows = 20;
    int nb_cols = 20;
    //for r in range(0,nb_rows):
    for(int r = 0; r < nb_rows; r++) {
        for (int c = 0; c < nb_cols; c++) {
            if((r%2 && c%2!=0) || (r%2!=0 && c%2)) {
                glColor3d(0.3,0.3,0.3);
	    }
            else {
                glColor3d(0.1,0.1,0.1);
	    }
            glBegin( GL_QUADS );
            glVertex3f(c-nb_cols/2, 0, r-nb_rows/2);
            glVertex3f(c-nb_cols/2+1, 0, r-nb_rows/2);
            glVertex3f(c-nb_cols/2+1, 0, r-nb_rows/2+1);
            glVertex3f(c-nb_cols/2, 0, r-nb_rows/2+1);
            glEnd();
	}
    }
}

void drawWheel(float size, float width) {
    /*Function to draw a wheel (a cylinder and two disks to close it)
        size : size of the wheel (radius)
        width : width of the wheel (width of the cylinder)
    */
    
    //draw cylinder of the wheel
    glPushMatrix();
    glColor3d(0.4,0.4,0.4);
    glTranslatef(0,0,-width/2);
    gluCylinder(quadric, size, size, width,32,16);
    glPopMatrix();
    //draw the first disk to close the cylinder
    glPushMatrix();
    glColor3d(0.6,0.6,0.6);
    glTranslatef(0,0,-width/2);
    gluDisk(quadric, 0,size,32,32);
    glPopMatrix();
    //draw the second disk to close the cylinder
    glPushMatrix();
    glColor3d(0.6,0.6,0.6);
    glTranslatef(0,0,width/2);
    gluDisk(quadric, 0,size,32,32);
    glPopMatrix();
}

void drawWheels(float dst_wheels, float width_wheel, float radius_wheel) {
    /*Function to draw the robot's wheels
        dst_wheels : distances between the two wheels
        width_wheel : width of the wheels
        radius_wheel : radius of the wheels
    */
    // draw the first wheel
    glPushMatrix();
    glTranslatef(0, 0, -dst_wheels/2);
    drawWheel(radius_wheel/2, width_wheel) ;
    glPopMatrix();
    //draw the second wheel
    glPushMatrix();
    glTranslatef(0, 0, dst_wheels/2);
    drawWheel(radius_wheel/2, width_wheel);
    glPopMatrix();
}

void drawBase(float dst_wheels, float radius_pipe) {
    /*Function to draw the body of the robot (a cylinder between the wheels)
        dst_wheels : distance between the wheels
        radius_pipe : the width of the cylinder body
    */
    
    glPushMatrix();
    glColor3d(0.4,0.4,1);
    glTranslatef(0, 0, -dst_wheels/2);
    gluCylinder(quadric,radius_pipe/2, radius_pipe/2, dst_wheels,32,16);
    glPopMatrix();
}

void drawPendulum(float height_pendulum, float radius_pipe, float center_pendulum) {
    /*Function to draw the pendulum of the robot (a cylinder up)
        height_pendulum : height of the pendulum from the center of the wheels
        radius_pipe : the width of the pendulum cylinder
        center_pendulum :  height of the center of mass of the pendulum from the center of the wheels
    */
    
    // draw the pendulum
    glPushMatrix();
    glColor3d(1,0.4,0.4);
    glRotatef(90,-1,0,0);
    gluCylinder(quadric,radius_pipe/2, radius_pipe/2, height_pendulum,32,16);
    glPopMatrix();
    //draw the center of mass
    glPushMatrix();
    glColor3d(0.4,1,0.4);
    glTranslatef(0, center_pendulum, 0);
    glutSolidSphere(radius_pipe, 32, 32);
    glPopMatrix();
}

void drawIBot(IBalancingBot ibot) {
    /* Function to draw the robot
        ibot: the robot (IBalancingBot) to draw
    */
    //global myBot
    drawWheels(ibot.d_dstw, ibot.d_widthw, ibot.d_rw);  // draw the wheels
    drawBase(ibot.d_dstw, ibot.d_widthp);  // draw the robot body
    drawPendulum(ibot.d_heightp, ibot.d_widthp, ibot.d_centerp);  // draw the pendulum
}

void Displayfct() {
    /* Function to draw the world
    */

    float scaleCoeff = 10;  // to scale the robot display

    glClearColor(0,0,0,0);  // background color
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    // Projection
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glFrustum(-1,1,-1,1,1,80.);

    // Camera position and orientation
    //global CameraPosX, CameraPosY, CameraPosZ, CenterX, CenterY, CenterZ, ViewUpX, ViewUpY, ViewUpZ
    //global myBot, posx, posz, follow_robot
    
    if(follow_robot) {
        CenterX = -posx*scaleCoeff;
        CenterZ = -posz*scaleCoeff;
    }
    gluLookAt(CameraPosX, CameraPosY , CameraPosZ, CenterX, CenterY, CenterZ, ViewUpX, ViewUpY, ViewUpZ);

    // Draw the objects and geometrical transformations
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();


    // draw the ground
    glPushMatrix();
    glScalef(scaleCoeff, scaleCoeff, scaleCoeff);  // to scale the ground as the robot
    glTranslatef(0,-myBot.d_rw/2,0);
    drawGround();
    glPopMatrix();

    // draw the robot
    glPushMatrix();
    glScalef(scaleCoeff, scaleCoeff, scaleCoeff);  // to scale the robot
    glTranslatef(-posx,0,-posz);
    glRotatef(myBot.psi*180/M_PI, 0, 1, 0);  // psi rotation (robot)
    glRotatef(myBot.phi*180/M_PI, 0, 0, 1);  // phi rotation (pendulum)
    drawIBot(myBot);
    glPopMatrix();

    // To efficient display
    glutSwapBuffers();
}

void ReshapeFunc(int w, int h) {
    // Function calls when reshaping the window
    glViewport(0,0,w,h);
}

int rotate_camera(float angle) {
    /* Function to rotate the camera according to an angle
        angle : step angle for the camera rotation
    */
    Theta+=angle;
    CameraPosZ=Radius*cos(Theta);
    CameraPosX=Radius*sin(Theta);
    return 0;
}

void zoom_camera(float factor) {
    /* Function to zoom the camera according to a factor
        factor : zoom factor
    */
    // Update camera center
    CameraPosX = factor*CameraPosX;
    CameraPosY = factor*CameraPosY;
    CameraPosZ = factor*CameraPosZ;
    // Update radius (for next rotations)
    Radius = sqrt( pow(CameraPosX,2) + pow(CameraPosZ,2) );
}

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
}

int main(int argc, char** argv) {
	//std::thread correctionThread(threadCorrection);
	srand((unsigned)time(0));
    	glutInit(&argc, argv);
	glutInitWindowPosition(100,100);
	glutInitWindowSize(250,250);
	glutInitDisplayMode(GLUT_RGBA |GLUT_DOUBLE | GLUT_DEPTH);
	glutCreateWindow("IBBot simulator");

	glClearColor(0.0,0.0,0.0,0.0);
	glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
	glEnable(GL_DEPTH_TEST);

	glutDisplayFunc(Displayfct);
	glutReshapeFunc(ReshapeFunc);
	glutSpecialFunc(SpecialFunc);
	glutMainLoop();
}
