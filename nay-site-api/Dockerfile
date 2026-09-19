FROM python:3.12-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .

RUN useradd -m site-api
USER site-api

EXPOSE 8092
CMD ["python", "-m", "gunicorn", "--bind", "0.0.0.0:8092", "--workers", "2", "--timeout", "10", "app:app"]
