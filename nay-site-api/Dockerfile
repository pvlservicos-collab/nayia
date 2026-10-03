FROM python:3.12-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
# Os blueprints sao COPIADOS UM A UM de proposito (nao `COPY . .`): assim um
# arquivo solto na pasta do servidor -- backup, .env, app.py.bk_* -- nunca
# entra na imagem por acidente. O preco e lembrar de acrescentar a linha ao
# criar um blueprint novo; sem ela o import falha com "No module named" e o
# try/except do app.py deixa a rota fora do ar de forma silenciosa.
COPY trace_api.py .
COPY treino_api.py .
COPY vagas_api.py .
COPY estrutura_api.py .
COPY imoveis_api.py .
COPY disparo_api.py .
# a captacao pela OLX (28/09) e o tradutor do anuncio, copiado do nay-publicador
COPY captacao_campos.py .
COPY olx_api.py .
# a biblioteca de fotos do cadastro (03/10): subir, reordenar e excluir
COPY fotos_api.py .

RUN useradd -m site-api
USER site-api

EXPOSE 8092
# timeout 90 (era 30): o disparo pela API oficial manda card e fotos um a um (28/09).
CMD ["python", "-m", "gunicorn", "--bind", "0.0.0.0:8092", "--workers", "2", "--timeout", "90", "app:app"]
