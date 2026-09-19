FROM python:3.12-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .

# Usuário sem privilégio -- o container não precisa de root para nada aqui.
RUN useradd -m painel
USER painel

EXPOSE 8091
CMD ["python", "-m", "gunicorn", "--bind", "0.0.0.0:8091", "--workers", "2", "--timeout", "10", "app:app"]
