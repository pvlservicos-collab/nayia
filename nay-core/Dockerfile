FROM python:3.12-slim

WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends make curl \
    && rm -rf /var/lib/apt/lists/*

COPY . .
RUN pip install --no-cache-dir ".[dev]"

# o webhook e a saúde; o worker (rajada, mídia, turno, refresh das visões)
# sobe como outro serviço com a mesma imagem, ver docker-compose.yml
EXPOSE 8000
CMD ["uvicorn", "nay.entrada.webhook:app", "--host", "0.0.0.0", "--port", "8000"]
