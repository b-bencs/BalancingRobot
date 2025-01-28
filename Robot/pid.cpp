#ifndef PID_CPP
#define PID_CPP

struct PID {
    float Kp;
    float Ki;
    float Kd;
    float Derivator;
    float Integrator;
    float Integrator_max;
    float Integrator_min;

    float set_point=0.0;
    float error=0.0;
    
    float P_value = 0.0;
    float D_value = 0.0;
    float I_value = 0.0;
    
    PID(float P=7.0, float I=0.1, float D=6.0, float Derivator=0, float Integrator=0, float Integrator_max=3, float Integrator_min=-3): \
	Kp(P), Ki(I), Kd(D), Derivator(Derivator), Integrator(Integrator), Integrator_max(Integrator_max), Integrator_min(Integrator_min) {
        this->set_point=0.0;
        this->error=0.0;
    }

    PID(const PID& p) {
	Kp = p.Kp;
	Ki = p.Ki;
	Kd = p.Kd;
	Derivator = p.Derivator;
	Integrator = p.Integrator;
	Integrator_max = p.Integrator_max;
	Integrator_min = p.Integrator_min;
	
	set_point=p.set_point;
	error=p.error;
	
	P_value = p.P_value;
	D_value = p.D_value;
	I_value = p.I_value;
    }

    PID& operator=(const PID& p) {
	if(this != &p) {
	    Kp = p.Kp;
	    Ki = p.Ki;
	    Kd = p.Kd;
	    Derivator = p.Derivator;
	    Integrator = p.Integrator;
	    Integrator_max = p.Integrator_max;
	    Integrator_min = p.Integrator_min;
	    
	    set_point=p.set_point;
	    error=p.error;
	    
	    P_value = p.P_value;
	    D_value = p.D_value;
	    I_value = p.I_value;
	}
	return *this;
    }

    virtual float update(float current_value) {
        // Calculate PID output value for given reference input and feedback

        this->error = this->set_point - current_value;

        this->P_value = this->Kp * this->error;
        this->D_value = this->Kd * ( this->error - this->Derivator);
        this->Derivator = this->error;

        this->Integrator = this->Integrator + this->error;

        if (this->Integrator > this->Integrator_max) {
            this->Integrator = this->Integrator_max;
	}
        else if (this->Integrator < this->Integrator_min) {
            this->Integrator = this->Integrator_min;
	}

        this->I_value = this->Integrator * this->Ki;

        float pid = this->P_value + this->I_value + this->D_value;

        return pid;
    }

    void setPoint(float set_point) {
        // Initilize the setpoint of PID
        this->set_point = set_point;
        this->Integrator = 0;
        this->Derivator = 0;
    }

    void setIntegrator(float Integrator) {
        this->Integrator = Integrator;
    }

    void setDerivator(float Derivator) {
        this->Derivator = Derivator;
    }

    void setKp(float P) {
        this->Kp = P;
    }

    void setKi(float I) {
        this->Ki = I;
    }

    void setKd(float D) {
        this->Kd = D;
    }

    float getPoint() {
        return this->set_point;
    }
    
    float getError() {
        return this->error;
    }

    float getIntegrator() {
        return this->Integrator;
    }
    float getDerivator() {
        return this->Derivator;
    }
};

#endif
