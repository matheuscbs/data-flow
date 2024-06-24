#!/bin/bash

# Configurações
KAFKA_BROKER="kafka:9092"
TOPIC_NAME="spark-etl-topic"
MONGODB_URI="mongodb://admin:admin@mongo:27017"
HDFS_NAMENODE_URI="hdfs://namenode:9000"
DATABASE_NAME="power"
COLLECTION_NAME="energy"
LOG_FILE="data_flow_test.log"
HDFS_DATA_DIR="/user/appuser/data/topics/+tmp/spark-etl-topic/*"

## Inicializando o arquivo de log
echo "Iniciando teste de fluxo de dados - $(date)" > $LOG_FILE

# Consumindo mensagens do Kafka usando kafka-console-consumer
echo "Consumindo mensagens do tópico Kafka '$TOPIC_NAME' com kafka-console-consumer..." | tee -a $LOG_FILE
kafka_messages=$(docker exec -t kafka kafka-console-consumer --bootstrap-server $KAFKA_BROKER --topic $TOPIC_NAME --from-beginning --timeout-ms 10000 --max-messages 10)

# Verificar se mensagens foram recebidas do Kafka
if [[ -z "$kafka_messages" ]]; then
    echo "Nenhuma mensagem foi recebida do Kafka." | tee -a $LOG_FILE
else
    echo "Mensagens recebidas do Kafka:" | tee -a $LOG_FILE
    echo "$kafka_messages" | tee -a $LOG_FILE
fi

# Verificando dados no MongoDB
echo "Verificando dados no MongoDB..." | tee -a $LOG_FILE
mongo_output=$(docker exec -t mongo mongo $MONGODB_URI/$DATABASE_NAME --authenticationDatabase admin --eval "printjson(db.$COLLECTION_NAME.find().toArray());" --quiet)

# Verificar se dados existem no MongoDB
if [[ -z "$mongo_output" ]]; then
    echo "Nenhuma dado foi encontrado no MongoDB." | tee -a $LOG_FILE
else
    echo "Dados encontrados no MongoDB:" | tee -a $LOG_FILE
    echo "$mongo_output" | tee -a $LOG_FILE
fi

## Verificando dados no HDFS
echo "Verificando dados no HDFS..." | tee -a $LOG_FILE
hdfs_output=$(docker exec -u root -t namenode /opt/hadoop-3.2.1/bin/hdfs dfs -ls $HDFS_DATA_DIR 2>&1)

if [ $? -ne 0 ]; then
  echo "Erro ao listar arquivos no HDFS: $hdfs_output" | tee -a $LOG_FILE
#   echo "Tentando criar o diretório novamente..."
#   docker exec -u root -t namenode /opt/hadoop-3.2.1/bin/hdfs dfs -mkdir -p $HDFS_DATA_DIR
#   docker exec -u root -t namenode /opt/hadoop-3.2.1/bin/hdfs dfs -chown -R appuser:appuser $HDFS_DATA_DIR
else
  # Verificar se dados existem no HDFS
  if [[ -z "$hdfs_output" ]]; then
      echo "Nenhum dado foi encontrado no HDFS." | tee -a $LOG_FILE
  else
      echo "Dados encontrados no HDFS:" | tee -a $LOG_FILE
      echo "$hdfs_output" | tee -a $LOG_FILE
  fi
fi
