"""O banco da Nay (naydb). As tabelas do serviço estão em privado.cadastro_whats* (migração 428)."""
from __future__ import annotations

import psycopg2
import psycopg2.extras

from cadastro import config


def conectar(autocommit: bool = True):
    conn = psycopg2.connect(config.DATABASE_URL, connect_timeout=10, application_name="nay-cadastro",
                            options="-c statement_timeout=30000 -c lock_timeout=5000 -c TimeZone=America/Manaus")
    conn.autocommit = autocommit
    return conn


def linhas(conn, sql: str, params=None) -> list[dict]:
    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(sql, params)
        return [dict(r) for r in cur.fetchall()] if cur.description else []


def uma(conn, sql: str, params=None) -> dict | None:
    r = linhas(conn, sql, params)
    return r[0] if r else None


def json(valor):
    return psycopg2.extras.Json(valor)


# o serviço está ligado? (nai_config.cadastro_whats = 'nao' para tudo na hora)
LIGADO = "SELECT coalesce(nai_cfg('cadastro_whats', 'sim'), 'sim') <> 'nao' AS ligado"

# as mensagens do grupo que ainda não foram lidas: nem as nossas (postada), nem as já lidas
NOVAS_DO_GRUPO = """
SELECT g.message_id, g.enviada_em, g.tipo, g.texto, g.midia_url, g.remetente, g.citado_id
  FROM privado.grupo_conversa g
 WHERE g.grupo_id = %(grupo)s AND g.enviada_em > now() - make_interval(secs => %(desde)s)
   AND NOT EXISTS (SELECT 1 FROM privado.cadastro_whats_lida l WHERE l.message_id = g.message_id)
   AND NOT EXISTS (SELECT 1 FROM privado.cadastro_whats_postada p WHERE p.message_id = g.message_id)
   AND g.tipo IN ('texto', 'imagem')
 ORDER BY g.enviada_em, g.message_id
"""
MARCAR_LIDAS = """
INSERT INTO privado.cadastro_whats_lida (message_id, cadastro_id)
SELECT unnest(%(ids)s::text[]), %(cadastro)s ON CONFLICT (message_id) DO NOTHING
"""

# quem é corretor: está em corretores (pelo número, com ou sem o 9)
E_CORRETOR = "SELECT EXISTS (SELECT 1 FROM corretores WHERE nai_chave(telefone) = nai_chave(%s)) AS sim"

CONDOMINIO = "SELECT * FROM cadastro_whats_condominio(%s, %s)"
# a taxa já está na ficha do condomínio para este número de quartos: não pergunta
TAXA_NO_CONDOMINIO = """
SELECT EXISTS (SELECT 1 FROM condominio_ficha f, jsonb_array_elements(f.taxas) t
                WHERE f.condominio_id = %(id)s AND nullif(t->>'condominio', '') IS NOT NULL
                  AND (%(quartos)s::int IS NULL OR t->>'quartos' IS NULL OR t->>'quartos' = %(quartos)s::text)) AS sim
"""

# a resposta dele: as entradas da ficha aberta, depois do silêncio
RESERVAR_RESPOSTA = """
WITH pronta AS (
  SELECT e.cadastro_id FROM privado.cadastro_whats_entrada e
    JOIN privado.cadastro_whats c ON c.id = e.cadastro_id AND c.estado = 'perguntando'
   WHERE e.status = 'Recebido'
   GROUP BY e.cadastro_id
  HAVING max(e.criada_em) < now() - make_interval(secs => %(silencio)s)
   ORDER BY min(e.criada_em) LIMIT 1
)
UPDATE privado.cadastro_whats_entrada e SET status = 'Processando'
  FROM pronta WHERE e.cadastro_id = pronta.cadastro_id AND e.status = 'Recebido'
RETURNING e.id, e.cadastro_id, e.texto, e.midias, e.criada_em
"""
# reiniciou no meio: o que ficou reservado volta
RECUPERAR = """
UPDATE privado.cadastro_whats_entrada SET status = 'Recebido'
 WHERE status = 'Processando' AND criada_em > now() - interval '1 day'
"""
FEITAS = "UPDATE privado.cadastro_whats_entrada SET status = 'Feito' WHERE id = ANY(%s)"

# a pessoa já está respondendo outra ficha? (uma conversa de cada vez por pessoa)
OCUPADO = """
SELECT EXISTS (SELECT 1 FROM privado.cadastro_whats c
                WHERE c.estado = 'perguntando' AND c.id <> %(id)s AND nai_chave(c.contato_tel) = nai_chave(%(tel)s)) AS sim
"""
# gente da equipe está com a conversa (o Tel escreveu há pouco): espera
TEL_COM_A_CONVERSA = """
SELECT coalesce(bool_or(nai_tel_com_a_conversa(k.id)), false) AS sim FROM nai_contato k WHERE k.chave = nai_chave(%s)
"""
