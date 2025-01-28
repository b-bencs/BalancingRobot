#include <math.h>
#define M_PI           3.14159265358979323846  /* pi */

struct IBalancingBot {
        float Mb = 0;  // kg      mass of main body (pendulum)
        float Mw = 0;  // kg      mass of wheels
        float d = 0;  // m       center of mass from base
        float R = 0;   // m       Radius of wheel
        float L = 0;   // m       Distance between the wheels
        float Ix = 0;  // kg.m^2  Moment of inertia of body x-axis
	float Iy = 0;  // kg.m^2  Moment of inertia of body y-axis
        float Iz = 0;  // kg.m^2  Moment of inertia of body z-axis
        float Ia = 0;  // kg.m^2  Moment of inertia of wheel according to center
        float g = 0;   // m/s^2   Acceleration due to gravity

        // variables for dynamic evaluation
        float phi = 0;    // angle of the pendulum
        float phip = 0;   // angular speed of the pendulum
        float phipp = 0;  // angular acceleration of the pendulum
        float x = 0;      // x position of the robot
        float xp = 0;     // linear x speed of the robot
        float xpp = 0;    // linear x acceleration of the robot
        float psi = 0;    // rotation of the robot
        float psip = 0;   // rotation angular speed of the robot
        float psipp = 0;  // rotation angular acceleration of the robot

        // variables for the drawing
        float d_rw = 0;       // wheel radius
        float d_dstw = 0;     // distance between the wheels
        float d_widthw = 0;   // width of a wheel
        float d_heightp = 0;  // height of the pendulum
        float d_centerp = 0;  // distance between the wheel and the pendulum center
        float d_widthp = 0;   // width of the robot pipes
	float phimin = 0;
	float phimax = 0;

    struct f_return {
	float phip;
	float phipp;
	float xp;
	float xpp;
	float psip;
	float psipp;
    };

    IBalancingBot () {
        this->initRobot();  // to initialize all the parameters of the system
    }
    
    void initRobot() {
        this->Mb = 13.3;    // kg      mass of main body (pendulum)
        this->Mw = 1.89;    // kg      mass of wheels
        this->d = 0.13;     // m       center of mass from base
        this->R = 0.130;    // m       Radius of wheel
        this->L = 0.325;    // m       Distance between the wheels
        this->Ix = 0.1935;  // kg.m^2  Moment of inertia of body x-axis
        this->Iz = 0.3379;  // kg.m^2  Moment of inertia of body z-axis
        this->Iy = 0.3379;  // kg.m^2  Moment of inertia of body y-axis : NOT A VALUE FROM THE PAPER
        this->Ia = 0.1229;  // kg.m^2  Moment of inertia of wheel according to center
        this->g = 9.81;     // m/s^2   Acceleration due to gravity  

        this->phi = 2*M_PI/180;  // the pendulum is initially unstable 
        this->phip = 0;

        this->x = 0;
        this->xp = 0;

        this->psi = 0;
        this->psip = 0;

        //variables for the drawing
        this->d_rw = this->R;
        this->d_dstw = this->L;
        this->d_widthw = 0.01;
        this->d_heightp = this->d;
        this->d_centerp = this->d;
        this->d_widthp = 0.01;

        //to deal with the fact that the pendulum can not be lower than the ground
        //we compute the maximal possible angle for the pendulum
        this->phimax = M_PI/2 + atan(this->R/(2*this->d));
        this->phimin = -M_PI/2 - atan(this->R/(2*this->d));
    }
    struct f_return f(float phi, float phip, float x, float xp, float psi, float psip, float deltat, float* F) {
        /*  Function to evaluate the new state of the system according to:
            - the mathematical model (phipp=, xpp=, psipp=)
            - the current state (phi, phip, x, xp, psi, psip)
            - the time step deltat
            - the command F=[tau1, tau2] (constant over deltat)
            It returns phip, phipp, xp, xpp, psip, psipp
        */

        float tau1 = F[0];
        float tau2 = F[1];
        
        //to ease the reading
        float Mb = this->Mb;
        float Mw = this->Mw;
        float d  = this->d;
        float R  = this->R;
        float L  = this->L;
        float Ix = this->Ix;
        float Iz = this->Iz;
        float Iy = this->Iy;
        float Ia = this->Ia;
        float g  = this->g;

        float R2 = pow(R, 2);
        float d2 = pow(d, 2);

        //computation of phipp
        float den_phipp = (pow(R*Mb*d*sin(phi),2))+((Mb+2*Mw)*(R2)+2*Ia)*Ix+2*Mb*d2*(Mw*R2+Ia);

        float phipp = ((Mb*d2+Iy-Iz)*(Mb*R2+2*Mw*R2+2*Ia)*sin(phi)*cos(phi))*(pow(psip,2))/den_phipp \
                - (pow(Mb,2))*d2*R2*sin(phi)*cos(phi)*(pow(phip,2))/den_phipp \
                + (Mb*R2+2*Mw*R2+2*Ia)*Mb*g*d*sin(phi)/den_phipp \
                - ((Mb*R2+2*Mw*R2+2*Ia)+Mb*d*R*cos(phi))*(tau1+tau2)/den_phipp;
                
        //computation of xpp
        float den_xpp = (Mb*d2+Ix)*(Mb*R2+2*Mw*R2+2*Ia)-(pow((Mb*d*R*cos(phi)),2));

        float xpp = (Mb*d*R*cos(phi)*(Mb*d2+Iy-Iz)*sin(phi)*cos(phi)*(pow(psip,2)))/den_xpp \
              - ((pow(Mb,2))*d2*g*R2*sin(phi)*cos(phi))/den_xpp \
              + (R2*(Mb*d2+Ix)*Mb*d*sin(phi)*(pow(phip,2)))/den_xpp \
              + (R*(Mb*d2+Ix+Mb*d*R*cos(phi))*(tau1+tau2))/den_xpp;
        //computation of psipp
        float den_psipp = 2*(Mw+Ia/R2)*(pow(L,2))+Iy*(pow(sin(phi),2))+Iz*(pow(cos(phi),2))+Mb*d2*sin(phi);

        float psipp = (L*(tau1-tau2))/(R*den_psipp) \
                - (2*(Mb*d2+Iy-Iz)*sin(phi)*cos(phi)*psip*phip)/den_psipp;

        return f_return { phip*deltat, phipp*deltat, xp*deltat, xpp*deltat, psip*deltat, psipp*deltat };
    }

    void runge_kutta(float deltat, float* F) {
	    /* Function that call the f() function defined above, and uses a 
            runge-kutta approach to deal with the differential equations */
        //k1phip, k1phipp, k1xp, k1xpp, k1psip, k1psipp =
        f_return k1 = this->f(this->phi, this->phip, this->x, this->xp, this->psi, this->psip, deltat, F);
        //k2phip, k2phipp, k2xp, k2xpp, k2psip, k2psipp =
        f_return k2 = this->f(this->phi + k1.phip/2, this->phip + k1.phipp/2, this->x + k1.xp/2, this->xp + k1.xpp/2, this->psi + k1.psip/2, this->psip + k1.psipp/2, deltat, F);
        //k3phip, k3phipp, k3xp, k3xpp, k3psip, k3psipp =
        f_return k3 = this->f(this->phi + k2.phip/2, this->phip + k2.phipp/2, this->x + k2.xp/2, this->xp + k2.xpp/2, this->psi + k2.psip/2, this->psip + k2.psipp/2, deltat, F);
        //k4phip, k4phipp, k4xp, k4xpp, k4psip, k4psipp =
	f_return k4 = this->f(this->phi + k3.phip, this->phip + k3.phipp, this->x + k3.xp, this->xp + k3.xpp, this->psi + k3.psip, this->psip + k3.psipp, deltat, F);

        this->phi = this->phi + 1/6.0*(k1.phip+2*k2.phip+2*k3.phip+k4.phip);
        this->phip = this->phip + 1/6.0*(k1.phipp+2*k2.phipp+2*k3.phipp+k4.phipp);

        this->xp = this->xp + 1/6.0*(k1.xpp+2*k2.xpp+2*k3.xpp+k4.xpp);
        this->x = this->x + 1/6.0*(k1.xp+2*k2.xp+2*k3.xp+k4.xp);

        this->psip = this->psip + 1/6.0*(k1.psipp+2*k2.psipp+2*k3.psipp+k4.psipp);
        this->psi = this->psi + 1/6.0*(k1.psip+2*k2.psip+2*k3.psip+k4.psip);

        //to deal with the fact that the pendulum can not be lower than the ground.
        //we also put the acceleration to 0 to avoid that the robot moves
        //when the pendulum is down
        if (this->phi > this->phimax) {
            this->phi = this->phimax;
            this->phip = 0;
            this->xp = 0;
	}
        if (this->phi < this->phimin) {
            this->phi = this->phimin;
            this->phip = 0;
            this->xp = 0;
	}
    }
    
    void dynamics(float deltat, float* F) {
        this->runge_kutta(deltat, F);
    }
};
