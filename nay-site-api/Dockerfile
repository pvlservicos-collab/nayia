FROM python:3.12-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
# a leitura de numero do cadastro (03/10): app.py e olx_api.py importam daqui
COPY numeros.py .
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
# o blog (406, 17/10): a API e os modelos das paginas (Jinja)
COPY blog_api.py .
COPY blog_templates/ ./blog_templates/
# o Scrap (407, 18/10): listas de nome + telefone
COPY scrap_api.py .
# WhatsApp > Mensagens (410, 18/10): etiquetas dos modelos da Meta
COPY whats_api.py .
# Chaves na Mão (458, 21/10): o XML dos imóveis e os leads do portal
COPY chavesnamao_api.py .
COPY chavesnamao_envio_api.py .
COPY zap_api.py .
# Modelos (470, 22/10): os gastos por nó de modelo de IA e a troca do modelo
COPY modelos_api.py .
# Inteligências gerais dos agentes (495, 25/10): a aba de baixo da página Agentes
COPY inteligencias_api.py .
# Biblioteca de conversas (498, 25/10): a aba Biblioteca da página Inteligência
COPY biblioteca_api.py .
# Ideias refinadas (514, 28/10): a aba de ideias da página Aprendizado
COPY aprendizado_api.py .

RUN useradd -m site-api
USER site-api

EXPOSE 8092
# timeout 90 (era 30): o disparo pela API oficial manda card e fotos um a um (28/09).
# threads 4 (29/10, a busca de Todos os Imóveis demorava): com 2 processos de um pedido cada, abrir a tela (a lista, as
# 4 contas dos atalhos, as opções) ocupava os dois e a busca digitada esperava na fila. Quase todo o tempo de um
# pedido é esperando o banco, então 4 linhas por processo atendem 8 pedidos de uma vez sem pesar mais na CPU.
CMD ["python", "-m", "gunicorn", "--bind", "0.0.0.0:8092", "--workers", "2", "--threads", "4", "--timeout", "90", "app:app"]
