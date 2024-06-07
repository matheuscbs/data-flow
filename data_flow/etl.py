import json
import logging
import os

from kafka import KafkaProducer
from pyspark.sql import SparkSession

# Configurar o diretório e o arquivo de log
log_directory = os.path.expanduser("~/data-flow-logs")
os.makedirs(log_directory, exist_ok=True)
log_file_path = os.path.join(log_directory, "etl.log")

# Carregar configurações de ambiente ou arquivo de configuração
KAFKA_BROKER = "localhost:9092"
TOPIC_NAME = "data-topic"

# Define o Python para o driver e os workers (ajustar conforme seu ambiente)
PYSPARK_PYTHON = "/usr/local/bin/python"
PYSPARK_DRIVER_PYTHON = "/usr/local/bin/python"
os.environ['PYSPARK_PYTHON'] = PYSPARK_PYTHON
os.environ['PYSPARK_DRIVER_PYTHON'] = PYSPARK_DRIVER_PYTHON

spark = SparkSession.builder \
    .appName("Data Extraction and Kafka Example") \
    .getOrCreate()

print(f"Using Kafka broker at {KAFKA_BROKER}")

# Configuração de logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(log_file_path),
        logging.StreamHandler()
    ]
)

# Configurar o produtor Kafka
try:
    producer = KafkaProducer(bootstrap_servers=[KAFKA_BROKER], value_serializer=lambda x: json.dumps(x).encode('utf-8'))
except Exception as e:
    logging.error(f"Error connecting to Kafka: {e}")

def send_data_to_kafka(data, topic):
    """Envia dados mockados para o Kafka."""
    for record in data:
        try:
            producer.send(topic, value=record)
            producer.flush()
            logging.info(f"Sent data to Kafka: {record}")
        except Exception as e:
            logging.error(f"Failed to send data to Kafka: {e}")

def close_kafka():
    """Fecha o produtor Kafka."""
    try:
        producer.close()
        logging.info("Kafka producer closed successfully.")
    except Exception as e:
        logging.error(f"Failed to close Kafka producer: {e}")

# Criar dados mockados
data = [
    {"id": 1, "name": "Alice", "age": 30},
    {"id": 2, "name": "Bob", "age": 25},
    {"id": 3, "name": "Charlie", "age": 35}
]

# Enviar dados para o Kafka
send_data_to_kafka(data, TOPIC_NAME)

# Encerrar a sessão Spark e fechar o produtor Kafka
spark.stop()
close_kafka()
