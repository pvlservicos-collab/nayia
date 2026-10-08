"""O banco da Nay (naydb), como o serviço da captação fala com ele.

Os comandos são os dos nós do fluxo do n8n ("Reservar mensagens", "Registrar saida", "Ainda é da IA?",
"Registrar envio", "Gravar escalada"), com UMA diferença: a mensagem que chega para o serviço novo entra como
'Recebido py' (gatilho da migração 315), e é esse status que ele reserva. O fluxo antigo só reserva 'Recebido'.

As regras continuam no banco: aqui não há regra de negócio, só a chamada.
"""
from __future__ import annotations

import itertools

import psycopg2
import psycopg2.extras

from captacao import config

# quem tem mensagem esperando e já ficou em silêncio o bastante (a "Janela de 20s" do fluxo)
FILA = """
SELECT max(m.telefone) AS telefone
  FROM captacao_mensagens m
 WHERE m.direcao = 'recebida' AND m.status = 'Recebido py'
 GROUP BY nay_fone_chave(m.telefone)
HAVING max(m.criada_em) < now() - make_interval(secs => %s)
 ORDER BY min(m.id)
"""

# "Reservar mensagens": quem pegou, pegou. Devolve o lote e o estado do lead para o prompt.
RESERVAR = """
WITH seg AS (
  SELECT EXISTS (
    SELECT 1 FROM captacao_mensagens e
     WHERE nay_fone_chave(e.telefone) = nay_fone_chave(%(tel)s) AND e.direcao = 'enviada'
       AND e.criada_em > (
         SELECT min(i.criada_em) FROM captacao_mensagens i
          WHERE nay_fone_chave(i.telefone) = nay_fone_chave(%(tel)s)
            AND i.direcao = 'recebida' AND i.origem = 'imagem' AND i.status NOT LIKE 'Recebido%%'
            AND i.criada_em > coalesce((SELECT max(t.criada_em) FROM captacao_mensagens t
                                         WHERE nay_fone_chave(t.telefone) = nay_fone_chave(%(tel)s)
                                           AND t.direcao = 'recebida' AND t.origem <> 'imagem'
                                           AND t.status NOT LIKE 'Recebido%%'), '-infinity'::timestamptz))) AS ja
), tel AS (
  SELECT coalesce((SELECT humano_assumiu_em IS NOT NULL FROM captacao_leads
                    WHERE telefone_chave = nay_fone_chave(%(tel)s)), false) AS assumiu
), res AS (
  UPDATE captacao_mensagens
     SET status = CASE WHEN (SELECT assumiu FROM tel) THEN 'Com o Tel' ELSE 'Processando' END
   WHERE nay_fone_chave(telefone) = nay_fone_chave(%(tel)s)
     AND direcao = 'recebida' AND status = 'Recebido py'
     AND NOT EXISTS (SELECT 1 FROM captacao_mensagens n
                      WHERE nay_fone_chave(n.telefone) = nay_fone_chave(%(tel)s)
                        AND n.direcao = 'recebida' AND n.criada_em > now() - interval '17 seconds')
  RETURNING id, telefone, origem, texto, criada_em, status
)
SELECT r.id, r.telefone, r.origem, r.texto, r.criada_em,
       l.id AS lead_id, l.nome, l.tratamento, l.imovel_desc, l.condominio, l.bairro, l.etapa, l.situacao,
       l.contrato_ate, coalesce(l.opt_out, true) AS opt_out,
       (SELECT string_agg(x->>'codigo' || ' - ' || coalesce(nullif(x->>'condominio',''), nullif(x->>'endereco',''), 'sem endereco'), '; ')
          FROM jsonb_array_elements(l.imoveis_prop) x WHERE x->>'codigo' IS DISTINCT FROM l.codigo) AS outros_nossos,
       l.pergunta_pendente,
       (SELECT ja FROM seg) AS ja_seguiu_depois_de_foto,
       captacao_ficha_aviso(l.id) AS ficha,
       nai_prompt_de('captacao') AS prompt,
       -- o mesmo portão do "Gravar na fila": resposta pausada cala todo mundo, menos o telefone de teste
       (coalesce((SELECT valor = 'sim' FROM captacao_config WHERE chave = 'resposta_pausada'), true)
        AND NOT EXISTS (SELECT 1 FROM captacao_config c WHERE c.chave = 'telefone_teste'
                           AND nay_fone_chave(c.valor) = nay_fone_chave(r.telefone))) AS pausado
  FROM res r
  LEFT JOIN captacao_leads l ON l.telefone_chave = nay_fone_chave(r.telefone)
 WHERE r.status = 'Processando'
 ORDER BY r.id
"""

# a conversa até aqui (o que ela e ele disseram), para o modelo ter o fio. Inclui o modelo do disparo.
HISTORICO = """
SELECT direcao, texto FROM (
  SELECT m.id, m.direcao, m.texto FROM captacao_mensagens m
   WHERE nay_fone_chave(m.telefone) = nay_fone_chave(%s) AND m.id < %s
     AND coalesce(btrim(m.texto), '') <> '' AND m.status <> 'Falhou'
   ORDER BY m.id DESC LIMIT %s) x
 ORDER BY id
"""

AINDA_E_DA_IA = """
SELECT captacao_ainda_e_da_ia(%(tel)s) AS segue,
       coalesce((SELECT l.canal FROM captacao_leads l WHERE l.id = captacao_lead_por_contato(%(tel)s)), 'zapi') AS canal
"""

# "Registrar saida": uma linha por balão, e a pergunta do turno guardada no lead
REGISTRAR_SAIDA = """
WITH s AS (
  INSERT INTO captacao_mensagens (lead_id, telefone, direcao, origem, texto, status, message_id)
  SELECT (SELECT id FROM captacao_leads WHERE telefone_chave = nay_fone_chave(%(tel)s)),
         %(tel)s, 'enviada', 'resposta', %(texto)s,
         CASE WHEN nullif(btrim(%(mid)s), '') IS NULL THEN 'Falhou' ELSE 'Enviado' END, nullif(btrim(%(mid)s), '')
  RETURNING 1
), p AS (
  UPDATE captacao_leads SET pergunta_pendente = nullif(btrim(%(pergunta)s), ''), atualizado_em = now()
   WHERE telefone_chave = nay_fone_chave(%(tel)s) AND nullif(btrim(%(pergunta)s), '') IS NOT NULL
  RETURNING 1
)
SELECT (SELECT count(*) FROM s) AS saida, (SELECT count(*) FROM p) AS pendencia
"""

# "Registrar envio": o disparo (aqui, o modelo oficial). Sem id da mensagem, o envio não aconteceu.
REGISTRAR_DISPARO = """
WITH ins AS (
  INSERT INTO captacao_mensagens (lead_id, telefone, direcao, origem, texto, status, message_id)
  SELECT %(lead)s, %(tel)s, 'enviada', 'disparo', %(texto)s,
         CASE WHEN nullif(btrim(%(mid)s), '') IS NULL THEN 'Falhou' ELSE 'Enviado' END, nullif(btrim(%(mid)s), '')
  RETURNING id
)
UPDATE captacao_leads
   SET status = CASE WHEN nullif(btrim(%(mid)s), '') IS NULL THEN 'erro' ELSE 'enviado' END,
       etapa = CASE WHEN etapa IS NULL OR etapa = 'novo' THEN 'aguardando_situacao' ELSE etapa END,
       pergunta_pendente = coalesce(pergunta_pendente, 'qual é a situação do seu imóvel: disponível, alugado ou vendido?'),
       canal = 'oficial', tentativas = tentativas + 1, ultimo_envio_em = now(), atualizado_em = now()
 WHERE id = %(lead)s
RETURNING id, status, tentativas
"""

# "Gravar escalada" do sub-fluxo `Nay - escalar (captacao)`: grava, cala a IA nesse chat e devolve a ordem
ESCALAR = """
WITH nova AS (
  INSERT INTO captacao_escalacoes (lead_id, telefone, nome, assunto, disse)
  SELECT l.id, %(tel)s, nullif(btrim(%(nome)s), ''), nullif(btrim(%(assunto)s), ''), nullif(btrim(%(disse)s), '')
    FROM (SELECT 1) x LEFT JOIN captacao_leads l ON l.telefone_chave = nay_fone_chave(%(tel)s)
   WHERE nullif(btrim(%(assunto)s), '') IS NOT NULL
  RETURNING id, assunto, disse, telefone AS telefone_esc
), para AS (
  UPDATE captacao_leads
     SET humano_assumiu_em = coalesce(humano_assumiu_em, now()),
         humano_motivo = coalesce(humano_motivo, 'escalou ao Tel: ' || coalesce((SELECT assunto FROM nova LIMIT 1), '')),
         atualizado_em = now()
   WHERE telefone_chave = nay_fone_chave(%(tel)s) AND EXISTS (SELECT 1 FROM nova)
  RETURNING id
)
SELECT n.id AS id_escalada, n.assunto, n.disse,
       CASE WHEN a.id IS NOT NULL THEN 'complemento da escalada ' || a.id ELSE 'escalada ' || n.id END AS titulo,
       'ESCALADO. NAO diga NADA sobre isso ao proprietario: nao avise que passou para o Tel, nao diga que vai verificar, '
       || 'nao prometa retorno, prazo nem contato. O Tel responde direto. Se esta era a unica coisa da mensagem dele, '
       || 'responda exatamente SILENCIO. Se ele falou tambem de algo do roteiro, responda so essa parte, sem citar o Tel.'
         AS instrucao_para_voce,
       (SELECT count(*) FROM para) AS parou_de_responder
  FROM nova n
  LEFT JOIN LATERAL (
    SELECT x.id FROM captacao_escalacoes x
     WHERE x.telefone = n.telefone_esc AND x.id < n.id AND NOT x.resolvida AND x.criada_em > now() - interval '48 hours'
     ORDER BY x.id LIMIT 1) a ON true
"""

_contador = itertools.count(1)


def conectar(autocommit: bool = True):
    conn = psycopg2.connect(config.DATABASE_URL, connect_timeout=10, application_name="nay-captacao",
                            options="-c statement_timeout=30000 -c lock_timeout=5000")
    conn.autocommit = autocommit
    return conn


def linhas(conn, sql: str, params=None) -> list[dict]:
    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(sql, params)
        return [dict(r) for r in cur.fetchall()] if cur.description else []


def rodar_do_fluxo(conn, sql: str, valores: list[str]) -> list[dict]:
    """Roda um SQL escrito para o n8n ($1, $2...), sem reescrever nada dele: PREPARE + EXECUTE."""
    nome = f"captacao_f{next(_contador)}"
    # no ensaio tudo roda numa transação só: o erro de uma ferramenta não pode derrubar a transação inteira
    em_transacao = not conn.autocommit
    preparado = False
    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        if em_transacao:
            cur.execute("SAVEPOINT ferramenta")
        try:
            cur.execute(f"PREPARE {nome} AS " + sql)   # sem parâmetros: o psycopg não toca nos % do texto
            preparado = True
            cur.execute(f"EXECUTE {nome}" + (" (" + ", ".join(["%s"] * len(valores)) + ")" if valores else ""), valores or None)
            saida = [dict(r) for r in cur.fetchall()] if cur.description else []
            if em_transacao:
                cur.execute("RELEASE SAVEPOINT ferramenta")
            return saida
        except Exception:
            if em_transacao:
                cur.execute("ROLLBACK TO SAVEPOINT ferramenta")
            raise
        finally:
            if preparado:
                cur.execute(f"DEALLOCATE {nome}")
