#!/bin/bash

# Definições de variáveis
KAFKA_BROKER="kafka:29092"
MONGO_URI="mongodb://admin:admin@mongo:27017"
TOPIC_NAME="spark-etl-topic"
CONNECT_URI="http://connect:8083"

# Instalação de dependências necessárias
apt-get update && apt-get install -y curl jq docker.io

# Função para verificar a existência de um conector
check_connector_existence() {
  local connector_name=$1
  local check_response=$(curl -s -o /dev/null -w "%{http_code}" "$CONNECT_URI/connectors/$connector_name")
  if [ "$check_response" -eq 200 ]; then
    echo "1" # Conector existe
  else
    echo "0" # Conector não existe
  fi
}

# Função para verificar a existência de um tópico Kafka
check_topic_existence() {
  local topic_name=$1
  local check_response=$(curl -s "http://kafka:29092/topics" | grep -c "\"$topic_name\"")
  if [ "$check_response" -eq 1 ]; then
    echo "1" # Tópico existe
  else
    echo "0" # Tópico não existe
  fi
}

# Função para verificar a resposta do Kafka Connect
check_response() {
  if [ "$1" -eq 201 ] || [ "$1" -eq 200 ]; then
    echo "Conector configurado com sucesso."
  else
    echo "Falha ao configurar o conector. Resposta HTTP: $1"
    echo "Detalhes do erro:"
    cat response.txt
    exit 1
  fi
}

# Função para esperar o Kafka Connect ficar disponível
wait_for_kafka_connect() {
  echo "Aguardando o Kafka Connect em $CONNECT_URI ficar disponível..."
  max_attempts=30
  wait_time=10 # Inicia com 1 segundo
  attempt=1
  while [ $attempt -le $max_attempts ]; do
    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "$CONNECT_URI/")
    if [ "$RESPONSE" -eq 200 ]; then
      echo "Kafka Connect disponível!"
      break
    else
      echo "Tentativa $attempt de $max_attempts falhou: Kafka Connect não está disponível (Resposta HTTP: $RESPONSE). Tentando novamente em $wait_time segundos..."
      sleep $wait_time
      ((wait_time*=2)) # Dobrar o tempo de espera para o próximo ciclo
    fi
    ((attempt++))
  done

  if [ $attempt -gt $max_attempts ]; then
    echo "Falha ao conectar ao Kafka Connect após $max_attempts tentativas."
    exit 1
  fi
}

check_and_create_topic() {
  echo "Verificando a existência do tópico Kafka: $TOPIC_NAME"
  if ! docker exec kafka kafka-topics --bootstrap-server kafka:29092 --list | grep -qw $TOPIC_NAME; then
    echo "Tópico $TOPIC_NAME não existe. Criando tópico..."
    docker exec kafka kafka-topics --create --topic $TOPIC_NAME --partitions 3 --replication-factor 1 --if-not-exists --bootstrap-server kafka:29092
    if [ $? -ne 0 ]; then
      echo "Falha ao criar o tópico Kafka."
      exit 1
    else
      echo "Tópico Kafka criado com sucesso."
    fi
  else
    echo "Tópico $TOPIC_NAME já existe, pulando a criação."
  fi
}

# Prepare JSON data for connector source configuration
SINK_JSON_DATA=$(cat <<EOF
{
  "name": "mongo-sink",
  "config": {
    "connector.class": "com.mongodb.kafka.connect.MongoSinkConnector",
    "topics": "$TOPIC_NAME",
    "connection.uri": "$MONGO_URI",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": false,
    "database": "power",
    "collection": "energy"
  }
}
EOF
)

# Configuração do Conector HDFS Sink
HDFS_JSON_DATA=$(cat <<EOF
{
  "name": "hdfs-sink",
  "config": {
    "connector.class": "io.confluent.connect.hdfs.HdfsSinkConnector",
    "tasks.max": "3",
    "topics": "$TOPIC_NAME",
    "hdfs.url": "hdfs://hadoop-namenode:8020",
    "flush.size": "100",
    "rotate.interval.ms": "1000",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": "false"
  }
}
EOF
)

# Configuração e envio de conectores
declare -A connectors=(
  ["hdfs-sink"]="$HDFS_JSON_DATA"
  ["mongo-sink"]="$SINK_JSON_DATA"
)

configure_connectors() {
  for connector_name in "${!connectors[@]}"; do
    echo "Configurando o Conector $connector_name no Kafka Connect"
    echo "Configuração JSON:"
    echo "${connectors[$connector_name]}" | jq '.' # Formatar o JSON para melhor legibilidade

    RESPONSE=$(curl -s -o response.txt -w "%{http_code}" -X POST -H "Content-Type: application/json" --data "${connectors[$connector_name]}" "$CONNECT_URI/connectors")

    if [ "$(check_connector_existence $connector_name)" -eq "0" ]; then
      check_response $RESPONSE response.txt
    else
      echo "Conector $connector_name já existe, pulando a configuração."
    fi
  done
}

# Aguarda Kafka Connect estar disponível
wait_for_kafka_connect
check_and_create_topic $TOPIC_NAME
configure_connectors

# Cria o arquivo de flag para indicar que o pipeline de configuração foi concluído
touch /app/pipeline_complete.flag
echo "Pipeline de configuração concluída com sucesso." > /app/pipeline_complete.flag
