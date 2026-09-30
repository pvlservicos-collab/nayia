"""Junta as mensagens do mesmo contato até RAJADA_SEGUNDOS sem mensagem nova. Roda no
worker, fora do caminho do webhook: esperar não ocupa vaga de nada (pergunta 6).
"""
