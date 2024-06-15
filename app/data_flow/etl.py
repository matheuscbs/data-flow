import json
import logging
import os
import signal
import sys
import time

import schedule
from kafka import KafkaProducer
from kafka.errors import KafkaError
from pyspark.sql import SparkSession

# Configuração do diretório e arquivo de log
log_directory = os.path.expanduser("~/data-flow-logs")
if not os.path.exists(log_directory):
    os.makedirs(log_directory)
log_file_path = os.path.join(log_directory, "etl.log")

# Configuração de logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s', handlers=[logging.FileHandler(log_file_path), logging.StreamHandler()])

# Constantes
KAFKA_BROKER = "kafka:29092"
TOPIC_NAME = "data-topic"
os.environ['PYSPARK_PYTHON'] = "/usr/local/bin/python"
os.environ['PYSPARK_DRIVER_PYTHON'] = "/usr/local/bin/python"

# Cria e retorna um produtor Kafka.
producer = KafkaProducer(bootstrap_servers=[KAFKA_BROKER], value_serializer=lambda x: json.dumps(x).encode('utf-8'))
spark = SparkSession.builder.appName("Data Extraction and Kafka Example").getOrCreate()

def send_data_to_kafka(data, topic):
    """ Envia dados para o Kafka. """
    for record in data:
        try:
            producer.send(topic, value=record).get(timeout=10)
            logging.info(f"Sent data to Kafka: {record}")
        except KafkaError as e:
            logging.error(f"Failed to send data to Kafka: {e}")

def job():
    """ Função que define a tarefa agendada. """
    data = [{"id": 1, "name": "Alice", "age": 30}, {"id": 2, "name": "Bob", "age": 25}, {"id": 3, "name": "Charlie", "age": 35}]
    send_data_to_kafka(data, TOPIC_NAME)

def graceful_exit(signal_num, frame):
    """ Encerra as conexões de forma adequada. """
    logging.info("Closing Kafka producer and Spark session.")
    producer.close()
    spark.stop()
    sys.exit(0)

signal.signal(signal.SIGINT, graceful_exit)
signal.signal(signal.SIGTERM, graceful_exit)

schedule.every(1).minutes.do(job)

while True:
    schedule.run_pending()
    time.sleep(1)
