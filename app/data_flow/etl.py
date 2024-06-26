import json
import logging
import os
import signal
import sys
import time

import schedule
from kafka import KafkaProducer
from kafka.errors import KafkaError, NoBrokersAvailable
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
TOPIC_NAME = "spark-etl-topic"
os.environ['PYSPARK_PYTHON'] = "/usr/local/bin/python"
os.environ['PYSPARK_DRIVER_PYTHON'] = "/usr/local/bin/python"

# Criação do Spark Session e Kafka Producer fora do escopo das funções
spark = SparkSession.builder.appName("Data Extraction and Kafka Example").getOrCreate()
producer = None

def create_kafka_producer():
    global producer
    max_attempts = 10
    wait_time = 10
    for attempt in range(max_attempts):
        try:
            producer = KafkaProducer(bootstrap_servers=[KAFKA_BROKER], value_serializer=lambda x: json.dumps(x).encode('utf-8'))
            logging.info("Kafka producer created successfully.")
            break
        except NoBrokersAvailable as e:
            logging.error(f"Attempt {attempt+1} failed: NoBrokersAvailable with this error {e}. Retrying in {wait_time} seconds...")
            time.sleep(wait_time)
            wait_time *= 2
        if attempt == max_attempts - 1:
            logging.error("Failed to create Kafka producer after several attempts.")
            sys.exit(1)

def send_data_to_kafka(data, topic):
    global producer
    if producer is None:
        create_kafka_producer()
    for record in data:
        try:
            producer.send(topic, value=record).get(timeout=10)
            logging.info(f"Sent data to Kafka: {record}")
        except KafkaError as e:
            logging.error(f"Failed to send data to Kafka: {e}")

def job():
    data = [{"id": 1, "name": "Alice", "age": 30}, {"id": 2, "name": "Bob", "age": 25}, {"id": 3, "name": "Charlie", "age": 35}]
    send_data_to_kafka(data, TOPIC_NAME)

def graceful_exit(signal_num, frame):
    global producer
    if producer:
        logging.info("Closing Kafka producer.")
        producer.close()
    logging.info("Stopping Spark session.")
    spark.stop()
    sys.exit(0)

signal.signal(signal.SIGINT, graceful_exit)
signal.signal(signal.SIGTERM, graceful_exit)

create_kafka_producer()
schedule.every(1).minutes.do(job)

while True:
    schedule.run_pending()
    time.sleep(1)
