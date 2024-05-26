#!/bin/bash

# Definições de variáveis
KAFKA_BROKER="kafka:29092"
MONGO_URI="mongodb://mongo:27017"
TOPIC_NAME="spark-etl-topic"
CONNECT_URI="http://connect:8083"

# Função para verificar a resposta do Kafka Connect
check_response() {
    if [ "$1" -eq 201 ]; then
        echo "Conector configurado com sucesso."
    else
        echo "Falha ao configurar o conector. Resposta HTTP: $1"
        echo "Detalhes do erro:"
        cat $2
        exit 1
    fi
}

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

# Configuração do Conector MongoDB Source
SOURCE_JSON_DATA=$(cat <<EOF
{
  "name": "mongo-source",
  "config": {
    "connector.class": "io.debezium.connector.mongodb.MongoDbConnector",
    "tasks.max": "1",
    "mongodb.connection.string": "$MONGO_URI",
    "topic.prefix": "mongo",
    "mongodb.name": "power",
    "database.whitelist": "power",
    "collection.whitelist": "energy",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": "false"
  }
}
EOF
)

# Enviando configuração do conector Source
# echo "Configurando o Conector Kafka Connect Source para MongoDB"
# RESPONSE=$(curl -s -o response.txt -w "%{http_code}" -X POST -H "Content-Type: application/json" --data "$SOURCE_JSON_DATA" "$CONNECT_URI/connectors")
# check_response $RESPONSE response.txt

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

# Enviando configuração do conector HDFS Sink
# echo "Configurando o Conector HDFS Sink no Kafka Connect"
# HDFS_RESPONSE=$(curl -s -o hdfs_response.txt -w "%{http_code}" -X POST -H "Content-Type: application/json" --data "$HDFS_JSON_DATA" "$CONNECT_URI/connectors")
# check_response $HDFS_RESPONSE hdfs_response.txt

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

# Enviando configuração do conector Mongo Sink
echo "Configurando o Conector Mongo Sink no Kafka Connect"
SINK_RESPONSE=$(curl -s -o mongo_sink.txt -w "%{http_code}" -X POST -H "Content-Type: application/json" --data "$SINK_JSON_DATA" "$CONNECT_URI/connectors")
check_response $SINK_RESPONSE mongo_sink.txt
