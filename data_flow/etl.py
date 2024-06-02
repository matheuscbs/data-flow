import json
import logging
import os
from io import StringIO

import pandas as pd
import requests
from bs4 import BeautifulSoup
from dotenv import load_dotenv
from kafka import KafkaProducer
from pyspark.sql import SparkSession
from requests.adapters import HTTPAdapter
from requests.packages.urllib3.util.retry import Retry

load_dotenv()

# Configurar o diretório e o arquivo de log
log_directory = os.path.expanduser("~/data-flow-logs")
os.makedirs(log_directory, exist_ok=True)
log_file_path = os.path.join(log_directory, "etl.log")

# Carregar configurações de ambiente ou arquivo de configuração
KAFKA_BROKER = "localhost:9092"
TOPIC_NAME = os.getenv("TOPIC_NAME", "data-topic")
FTP_URL = os.getenv("FTP_URL")
API_URL = os.getenv("API_URL")
WIKI_URL = os.getenv("WIKI_URL")
PYSPARK_PYTHON = os.getenv("PYSPARK_PYTHON", "/Users/matheuscbs/.pyenv/versions/3.9.18/bin/python")
PYSPARK_DRIVER_PYTHON = os.getenv("PYSPARK_DRIVER_PYTHON", "/Users/matheuscbs/.pyenv/versions/3.9.18/bin/python")

# Define o mesmo Python para o driver e os workers
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

# Configuração de retry para requests
session = requests.Session()
retries = Retry(total=5, backoff_factor=0.1, status_forcelist=[500, 502, 503, 504])
session.mount('http://', HTTPAdapter(max_retries=retries))
session.mount('https://', HTTPAdapter(max_retries=retries))

# Configurar o produtor Kafka
try:
    producer = KafkaProducer(bootstrap_servers=[KAFKA_BROKER], value_serializer=lambda x: json.dumps(x).encode('utf-8'))
except Exception as e:
    print(f"Error connecting to Kafka: {e}")

def download_data(url):
    """Tenta baixar dados de uma URL e determina automaticamente o formato."""
    try:
        response = session.get(url)
        response.raise_for_status()
        try:
            return pd.read_json(StringIO(response.text))
        except ValueError:
            return pd.read_csv(StringIO(response.text))
    except requests.RequestException as e:
        logging.error(f"Failed to download data from {url}: {e}")
        return pd.DataFrame()
    except Exception as e:
        logging.error(f"Error processing data from {url}: {e}")
        return pd.DataFrame()

def perform_web_crawling(url):
    """Realiza web crawling em uma URL especificada."""
    try:
        response = session.get(url)
        response.raise_for_status()
        soup = BeautifulSoup(response.text, 'html.parser')
        data = [element.text for element in soup.select("div.div-col li")]
        return pd.DataFrame(data, columns=['Programming Language'])
    except requests.RequestException as e:
        logging.error(f"Failed to perform web crawling on {url}: {e}")
        return pd.DataFrame()

def send_data_to_kafka(df, topic):
    """Envia dados para o Kafka."""
    for index, row in df.iterrows():
        try:
            producer.send(topic, value=row.to_dict())
            producer.flush()
            logging.info(f"Sent data to Kafka: {row.to_dict()}")
        except Exception as e:
            logging.error(f"Failed to send data to Kafka: {e}")

def close_kafka():
    """Fecha o produtor Kafka."""
    try:
        producer.close()
        logging.info("Kafka producer closed successfully.")
    except Exception as e:
        logging.error(f"Failed to close Kafka producer: {e}")

# Extração e envio dos dados
try:
    ftp_data = download_data(FTP_URL)
    api_data = download_data(API_URL)
    crawler_data = perform_web_crawling(WIKI_URL)

    # Criar DataFrames Spark
    ftp_df = spark.createDataFrame(ftp_data)
    api_df = spark.createDataFrame(api_data)
    crawler_df = spark.createDataFrame(crawler_data)

    # Enviar dados para o Kafka
    for df in [ftp_df, api_df, crawler_df]:
        send_data_to_kafka(df.toPandas(), TOPIC_NAME)

finally:
    # Encerrar a sessão Spark e fechar o produtor Kafka
    spark.stop()
    close_kafka()
