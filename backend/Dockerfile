FROM python:3.12-bookworm

WORKDIR /autour

COPY . /autour

RUN apt update
RUN apt install -y libhdf5-dev postgresql postgresql-client
RUN pip install --upgrade -r requirements.txt

CMD ["python", "main.py"]
