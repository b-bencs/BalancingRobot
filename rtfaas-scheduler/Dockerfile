FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY rtfaas_scheduler ./rtfaas_scheduler
RUN mkdir -p /state

CMD ["python", "-m", "rtfaas_scheduler.main"]
