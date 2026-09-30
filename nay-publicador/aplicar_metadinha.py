"""Põe a METADINHA (não commitada) de volta no `publicador.py` novo.

O arquivo do repositório não a tem -- ela vive só no servidor, e já se perdeu
uma vez por cópia por cima. Então o deploy deste arquivo é: copiar o novo
como `publicador_novo.py`, rodar isto (que traz a metadinha do arquivo que
está EM PRODUÇÃO para dentro dele), conferir, e só então trocar.
"""
import io
import re

ATUAL = "/root/nay-publicador/publicador.py"
NOVO = "/root/nay-publicador/publicador_novo.py"

atual = io.open(ATUAL, encoding="utf-8").read()
novo = io.open(NOVO, encoding="utf-8").read()

if "_colagem_do_imovel" not in atual:
    raise SystemExit("ABORTADO: a metadinha não está no arquivo em produção")
if "_colagem_do_imovel" in novo:
    raise SystemExit("o arquivo novo já tem a metadinha -- nada a fazer")

# 1. as duas funções, inteiras, como estão em produção
i = atual.index("def _colagem_do_imovel(conn, codigo):")
j = atual.index("def _avisos_dados_incompletos(imovel):")
bloco = atual[i:j]
if "_fotos_para_grupo(conn, imovel, grupo)" not in bloco:
    raise SystemExit("ABORTADO: o bloco da metadinha não tem a forma esperada")

# 2. troca a versão do repositório pela de produção
alvo_i = novo.index("def _fotos_para_grupo(imovel, grupo):")
alvo_j = novo.index("def _avisos_dados_incompletos(imovel):")
novo = novo[:alvo_i] + bloco + novo[alvo_j:]

# 3. as chamadas passam a levar a conexão
antes = novo.count("_fotos_para_grupo(imovel, grupo)")
novo = novo.replace("_fotos_para_grupo(imovel, grupo)",
                    "_fotos_para_grupo(conn, imovel, grupo)")
if antes != 2:
    raise SystemExit(f"ABORTADO: esperava 2 chamadas a trocar, achei {antes}")
if "_fotos_para_grupo(imovel" in novo:
    raise SystemExit("ABORTADO: sobrou chamada sem a conexão")

io.open(NOVO, "w", encoding="utf-8").write(novo)
print("metadinha aplicada no arquivo novo")
print("  _colagem_do_imovel:", novo.count("def _colagem_do_imovel"))
print("  chamadas com conn:", novo.count("_fotos_para_grupo(conn, imovel, grupo)"))
