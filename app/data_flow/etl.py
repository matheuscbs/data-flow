import json
import logging
import os
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
TOPIC_NAME = "data-topic"
os.environ['PYSPARK_PYTHON'] = "/usr/local/bin/python"
os.environ['PYSPARK_DRIVER_PYTHON'] = "/usr/local/bin/python"

def create_kafka_producer():
    """ Cria e retorna um produtor Kafka. """
    try:
        producer = KafkaProducer(bootstrap_servers=[KAFKA_BROKER], value_serializer=lambda x: json.dumps(x).encode('utf-8'))
        return producer
    except KafkaError as e:
        logging.error(f"Error creating Kafka producer: {e}")
        return None

def send_data_to_kafka(producer, data, topic):
    """ Envia dados para o Kafka. """
    for record in data:
        try:
            producer.send(topic, value=record).get(timeout=10)
            logging.info(f"Sent data to Kafka: {record}")
        except KafkaError as e:
            logging.error(f"Failed to send data to Kafka: {e}")

def job():
    """ Função que define a tarefa agendada. """
    spark = SparkSession.builder.appName("Data Extraction and Kafka Example").getOrCreate()
    producer = create_kafka_producer()
    if producer:
        data = [{"id": 1, "name": "Alice", "age": 30}, {"id": 2, "name": "Bob", "age": 25}, {"id": 3, "name": "Charlie", "age": 35}]
        send_data_to_kafka(producer, data, TOPIC_NAME)
        producer.close()  # Fecha o produtor após o envio dos dados
        logging.info("Kafka producer closed successfully.")
    spark.stop()  # Encerra a sessão Spark após a tarefa
    logging.info("Spark session stopped.")

schedule.every(1).minutes.do(job)

while True:
    schedule.run_pending()
    time.sleep(1)
