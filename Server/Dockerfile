FROM python:slim-bullseye
RUN pip install flask
WORKDIR /pidserver
COPY pidserver.py ./pidserver.py
CMD ["python3", "pidserver.py"]
