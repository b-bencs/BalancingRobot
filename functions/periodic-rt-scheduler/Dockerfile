FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY rtfaas-scheduler ./rtfaas_scheduler

ENV SCHEDULER_NAME=rtfaas-scheduler
ENV EDF_MODE=cpu
ENV RT_STATE_FILE=/state/rt_state.txt

# state volume mount-hoz
RUN mkdir -p /state

CMD ["python", "-u","-m", "rtfaas_scheduler.main"]
