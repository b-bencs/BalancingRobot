FROM python:slim-bullseye
RUN pip install flask setuptools
RUN apt-get update -y && apt-get install -y git g++
RUN git clone https://github.com/dahallgren/scheddl.git
WORKDIR scheddl
RUN python setup.py install
WORKDIR /pidserver
COPY pidserver.py ./pidserver.py
CMD ["python3", "-u", "pidserver.py"]
