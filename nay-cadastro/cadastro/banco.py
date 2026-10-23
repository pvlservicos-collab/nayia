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
# O CHAT PAUSADO PELO TEL (20/10, a Raquel): a porta manda a resposta para o Tel ('Com o Tel') antes do bloco do
# cadastro. A resposta à pergunta que está no ar ainda é do cadastro: vem daqui, da caixa de entrada (mensagens), uma vez.
DO_CHAT_PAUSADO = """
WITH aberta AS (
  SELECT c.id, c.pergunta_em,
         ARRAY(SELECT k2.chave FROM nai_contato k1
                 CROSS JOIN LATERAL unnest(coalesce(nai_contato_irmaos(k1.id), ARRAY[k1.id])) AS i(id)
                 JOIN nai_contato k2 ON k2.id = i.id
                WHERE k1.chave = nai_chave(c.contato_tel)) AS chaves
    FROM privado.cadastro_whats c
   WHERE c.estado = 'perguntando' AND c.pergunta_em IS NOT NULL
), novas AS (
  SELECT a.id AS cadastro_id, m.id, m.texto, m.midia_url, m.origem
    FROM aberta a JOIN mensagens m ON nai_chave(m.telefone) = ANY (a.chaves)
   WHERE m.direcao = 'recebida' AND m.status = 'Com o Tel' AND m.criada_em > a.pergunta_em
     AND NOT EXISTS (SELECT 1 FROM privado.cadastro_whats_entrada e WHERE m.id = ANY (e.ids))
)
INSERT INTO privado.cadastro_whats_entrada (cadastro_id, texto, midias, ids)
SELECT cadastro_id,
       string_agg(texto, E'\\n' ORDER BY id) FILTER (WHERE nullif(btrim(texto), '') IS NOT NULL),
       coalesce(array_agg(midia_url ORDER BY id) FILTER (WHERE origem = 'imagem' AND midia_url IS NOT NULL), '{}'),
       array_agg(id::bigint ORDER BY id)
  FROM novas GROUP BY cadastro_id
RETURNING cadastro_id
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

# ── 479: o número de LEADS (8595, Z-API da captação), cuja conversa mora em captacao_mensagens ────────────────────
# TODO contato (corretor, proprietário, quem não se sabe) é perguntado pelo 8595 (Pedro, 23/10: "quero tudo pelo número
# de leads mesmo de captação, tinha pedido errado antes"; antes o proprietário ia pela Parceria). Só fica na Parceria o
# dono que é lead da CAPTAÇÃO (oficial ou 8595): a resposta dele no 8595 cai na conversa da Nay de captação, que
# responderia junto.
CANAL_DO_CONTATO = """
SELECT CASE WHEN EXISTS (SELECT 1 FROM captacao_leads l WHERE l.telefone_chave = nay_fone_chave(%(tel)s))
            THEN 'parceria' ELSE 'leads' END AS canal
"""
# alguém da equipe escreveu para ele pelo 8595 há pouco: a conversa é dela
GENTE_NO_8595 = """
SELECT EXISTS (SELECT 1 FROM captacao_mensagens m
                WHERE m.direcao = 'enviada' AND m.origem = 'humano' AND nay_fone_chave(m.telefone) = nay_fone_chave(%(tel)s)
                  AND m.criada_em > now() - make_interval(mins => %(min)s)) AS sim
"""
# o que ele escreveu pelo 8595 depois da pergunta vira a resposta da ficha (só texto: a foto já veio no encaminhamento)
DO_8595 = """
WITH novas AS (
  SELECT c.id AS cadastro_id, m.id, m.texto
    FROM privado.cadastro_whats c
    JOIN captacao_mensagens m ON nay_fone_chave(m.telefone) = nay_fone_chave(c.contato_tel)
   WHERE c.canal = 'leads' AND c.estado = 'perguntando' AND c.pergunta_em IS NOT NULL
     AND m.direcao = 'recebida' AND m.criada_em > c.pergunta_em AND nullif(btrim(m.texto), '') IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM privado.cadastro_whats_entrada e WHERE e.fonte = 'captacao' AND m.id = ANY (e.ids))
)
INSERT INTO privado.cadastro_whats_entrada (cadastro_id, texto, ids, fonte)
SELECT cadastro_id, string_agg(texto, E'\\n' ORDER BY id), array_agg(id::bigint ORDER BY id), 'captacao'
  FROM novas GROUP BY cadastro_id
RETURNING cadastro_id
"""
# o que ele disse, no 8595 E na Parceria, de 3 h antes da ficha até agora (Tel, 23/10: a Ana disse "É andar alto /
# Oitavo" no 8595 às 12:25 e às 12:31 foi perguntada "Em qual andar ele fica?"). Corretor fala de vários imóveis: a
# janela é a do encaminhamento, não a conversa toda.
CONVERSA_RECENTE = """
SELECT string_agg(x.texto, E'\\n' ORDER BY x.em) AS texto FROM (
  SELECT m.texto, m.criada_em AS em FROM captacao_mensagens m
   WHERE m.direcao = 'recebida' AND nay_fone_chave(m.telefone) = nay_fone_chave(%(tel)s)
     AND m.criada_em > %(desde)s - interval '3 hours' AND nullif(btrim(m.texto), '') IS NOT NULL
  UNION ALL
  SELECT m.texto, m.criada_em FROM mensagens m
   WHERE m.direcao = 'recebida' AND nai_chave(m.telefone) = nai_chave(%(tel)s)
     AND m.criada_em > %(desde)s - interval '3 hours' AND nullif(btrim(m.texto), '') IS NOT NULL
) x
"""
