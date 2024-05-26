#!/bin/bash

# Definições de variáveis
KAFKA_BROKER="kafka:29092"
MONGO_URI="mongodb://mongo:27017"
TOPIC_NAME="spark-etl-topic"
CONNECT_URI="http://connect:8083"

# Instalação de dependências necessárias
apt-get update && apt-get install -y curl docker.io

# Função para verificar a existência de um conector
check_connector_existence() {
    local connector_name=$1
    local check_response=$(curl -s -o /dev/null -w "%{http_code}" "$CONNECT_URI/connectors/$connector_name")
    if [ "$check_response" -eq 200 ]; then
        echo "1"  # Conector existe
    else
        echo "0"  # Conector não existe
    fi
}

# Função para verificar a resposta do Kafka Connect
check_response() {
    if [ "$1" -eq 201 ] || [ "$1" -eq 200 ]; then
        echo "Conector configurado com sucesso."
    else
        echo "Falha ao configurar o conector. Resposta HTTP: $1"
        echo "Detalhes do erro:"
        cat $2
        exit 1
    fi
}

# Função para esperar o Kafka Connect ficar disponível
wait_for_kafka_connect() {
    echo "Aguardando o Kafka Connect em $CONNECT_URI ficar disponível..."
    max_attempts=30
    wait_time=10
    attempt=1
    while [ $attempt -le $max_attempts ]; do
        RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "$CONNECT_URI/")
        if [ "$RESPONSE" -eq 200 ]; then
            echo "Kafka Connect disponível!"
            break
        else
            echo "Tentativa $attempt de $max_attempts falhou: Kafka Connect não está disponível (Resposta HTTP: $RESPONSE). Tentando novamente em $wait_time segundos..."
            sleep $wait_time
        fi
        ((attempt++))
    done

    if [ $attempt -gt $max_attempts ]; then
        echo "Falha ao conectar ao Kafka Connect após $max_attempts tentativas."
        exit 1
    fi
}

# Aguarda Kafka Connect estar disponível
wait_for_kafka_connect

# Verificando a conectividade com o Kafka Connect
echo "Verificando a conectividade com o Kafka Connect em $CONNECT_URI"
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "$CONNECT_URI/")
if [ "$RESPONSE" -ne 200 ]; then
    echo "Não foi possível conectar ao Kafka Connect em $CONNECT_URI. Resposta HTTP: $RESPONSE"
    exit 1
fi

echo "Conectividade com o Kafka Connect verificada."

# Criando o tópico Kafka
echo "Criando tópico Kafka: $TOPIC_NAME"
docker exec kafka kafka-topics --create --topic $TOPIC_NAME --partitions 3 --replication-factor 1 --if-not-exists --zookeeper zookeeper:2181

# Verificando o resultado da criação do tópico
if [ $? -ne 0 ]; then
    echo "Falha ao criar o tópico Kafka."
    exit 1
fi

echo "Tópico Kafka criado com sucesso."

# # Configuração do Conector MongoDB Source
# SOURCE_JSON_DATA=$(cat <<EOF
# {
#   "name": "mongo-source",
#   "config": {
#     "connector.class": "io.debezium.connector.mongodb.MongoDbConnector",
#     "tasks.max": "1",
#     "mongodb.connection.string": "$MONGO_URI",
#     "topic.prefix": "mongo",
#     "mongodb.name": "power",
#     "database.whitelist": "power",
#     "collection.whitelist": "energy",
#     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
#     "value.converter": "org.apache.kafka.connect.json.JsonConverter",
#     "value.converter.schemas.enable": "false"
#   }
# }
# EOF
# )

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
    "hdfs.url": "hdfs://hadoop-namenode:9000",
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
    # ["mongo-source"]="$SOURCE_JSON_DATA"
    ["hdfs-sink"]="$HDFS_JSON_DATA"
    ["mongo-sink"]="$SINK_JSON_DATA"
)

for connector_name in "${!connectors[@]}"; do
    if [ "$(check_connector_existence $connector_name)" -eq "0" ]; then
        echo "Configurando o Conector $connector_name no Kafka Connect"
        RESPONSE=$(curl -s -o response.txt -w "%{http_code}" -X POST -H "Content-Type: application/json" --data "${connectors[$connector_name]}" "$CONNECT_URI/connectors")
        check_response $RESPONSE response.txt
    else
        echo "Conector $connector_name já existe, pulando a configuração."
    fi
done
