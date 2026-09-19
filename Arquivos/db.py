"""
Conexão com o Postgres do publicador (vagas, grupos, imoveis), via
DATABASE_URL. Mesmo padrão de erro claro das variáveis ZAPI_*.

Cursores desta conexão devolvem linhas como dict (RealDictRow), não
tupla -- é o formato que os módulos puros já esperam (vaga["codigos"],
g["aceita_venda"], etc.).
"""
import os

import psycopg2
import psycopg2.extras


def conectar():
    dsn = os.environ.get("DATABASE_URL")
    if not dsn:
        raise RuntimeError(
            "DATABASE_URL não configurada no ambiente. Copie .env.example "
            "para .env, preencha o valor, e carregue no ambiente antes de "
            "rodar."
        )
    return psycopg2.connect(dsn, cursor_factory=psycopg2.extras.RealDictCursor)
