# Usar a imagem oficial do Debian Buster Slim
FROM debian:buster-slim

# Evitar interações durante a instalação
ENV DEBIAN_FRONTEND=noninteractive

# Atualizar a lista de pacotes e instalar as dependências necessárias
RUN apt-get update && apt-get install -y \
    curl \
    docker.io \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Configurar o ambiente para pyenv
ENV PYENV_ROOT="/root/.pyenv"
ENV PATH="$PYENV_ROOT/bin:$PYENV_ROOT/shims:$PATH"

# Instalar Python e ferramentas de gerenciamento de pacotes
RUN curl https://pyenv.run | bash \
    && pyenv install 3.9.6 \
    && pyenv global 3.9.6 \
    && curl -sSL https://install.python-poetry.org | python3 -

# Definir o diretório de trabalho
WORKDIR /app

# Copiar o projeto e os arquivos de configuração necessários
COPY pyproject.toml poetry.lock ./

# Instalar o Poetry e as dependências do projeto sem criar ambientes virtuais separados
RUN pip3 install poetry \
    && poetry config virtualenvs.create false \
    && poetry install --no-interaction --no-ansi

# Copiar o resto do código do projeto
COPY . .

# Adicionar e configurar o trabalho cron, se necessário
RUN echo "0 * * * * cd /app && poetry run python etl.py >> /var/log/cron.log 2>&1" > /etc/cron.d/etl-cron \
    && chmod 0644 /etc/cron.d/etl-cron \
    && touch /var/log/cron.log

# Comando padrão para manter o container em execução
CMD ["cron", "-f"]
