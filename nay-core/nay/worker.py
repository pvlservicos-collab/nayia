"""O processo de fundo: pega core_evento_bruto não processado, normaliza (entrada.dedupe),
lê mídia (entrada.midia), fecha rajadas (entrada.rajada), roda o turno e faz o REFRESH
CONCURRENTLY de core_imovel_busca e core_imovel_dono a cada REFRESH_IMOVEL_MIN minutos.
"""
