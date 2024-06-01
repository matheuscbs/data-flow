# Usar a imagem oficial do Debian Buster
FROM debian:buster-slim

# Configurações de ambiente para evitar interações durante a instalação
ENV DEBIAN_FRONTEND=noninteractive

# Instalar dependências básicas e o build essentials para compilação de Python e outras bibliotecas
RUN apt-get update && apt-get install -y \
    curl \
    docker.io \
    ca-certificates \
    build-essential \
    libssl-dev \
    zlib1g-dev \
    libbz2-dev \
    libreadline-dev \
    libsqlite3-dev \
    wget \
    llvm \
    libncurses5-dev \
    libncursesw5-dev \
    xz-utils \
    tk-dev \
    libffi-dev \
    liblzma-dev \
    git \
    && rm -rf /var/lib/apt/lists/*

# Instalar pyenv
RUN curl https://pyenv.run | bash

# Configurar o ambiente para pyenv
ENV PYENV_ROOT="/root/.pyenv"
ENV PATH="$PYENV_ROOT/bin:$PYENV_ROOT/shims:$PATH"

# Instalar Python 3.9 usando pyenv
RUN pyenv install 3.9.6
RUN pyenv global 3.9.6

# Configuração de variáveis de ambiente do PySpark para garantir a mesma versão do Python
ENV PYSPARK_PYTHON=$PYENV_ROOT/shims/python
ENV PYSPARK_DRIVER_PYTHON=$PYENV_ROOT/shims/python

# Instalar Poetry
RUN curl -sSL https://install.python-poetry.org | python3 -

# Limpar cache do apt para reduzir tamanho da imagem
RUN apt-get clean && rm -rf /var/lib/apt/lists/*

# Definir o diretório de trabalho
WORKDIR /app

# Copiar o pyproject.toml e poetry.lock* para o diretório de trabalho
COPY pyproject.toml poetry.lock* ./

# Instalar dependências do projeto usando Poetry
RUN poetry install --no-interaction --no-ansi

# Copiar o resto do código fonte para o container
COPY . .

# Instalar cron e configurar o trabalho cron
RUN apt-get update && apt-get install -y cron \
    && mkdir -p /etc/cron.d \
    && echo "* * * * * cd /app && poetry run python etl.py >> /var/log/cron.log 2>&1" > /etc/cron.d/etl-cron \
    && chmod 0644 /etc/cron.d/etl-cron \
    && touch /var/log/cron.log

# Inicia o cron junto com o container
CMD ["cron", "-f"]
