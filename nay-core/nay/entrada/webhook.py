"""FastAPI. POST /webhook grava o corpo cru em core_evento_bruto (ON CONFLICT no message_id)
e devolve 200 em menos de 50 ms. GET /saude para o healthcheck. Nada mais roda aqui.
"""
