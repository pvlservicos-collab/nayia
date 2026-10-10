"""O banco da Nay (naydb), como o serviço dos grupos fala com ele: o que há para ler e o que ele grava."""
from __future__ import annotations

import json

import psycopg2
import psycopg2.extras

from grupos import config

# O QUE HÁ PARA LER: mensagem de grupo com texto (ou legenda), de outra pessoa, dentro da janela, ainda não lida;
# a que veio de conversa EXPORTADA do WhatsApp (337: a Z-API não devolve histórico de grupo); e o que ele colou
# na tela para treinar. O teste primeiro (ele está olhando a tela), depois a mais antiga.
PENDENTES = """
SELECT * FROM (
  SELECT 'grupo' AS fonte, c.message_id AS ref, c.grupo_id, c.grupo_nome, c.remetente, c.remetente_nome,
         c.enviada_em, c.texto
    FROM privado.grupo_conversa c
   WHERE NOT c.de_mim AND nullif(btrim(c.texto), '') IS NOT NULL
     AND c.enviada_em > now() - make_interval(hours => %(janela)s)
     AND NOT EXISTS (SELECT 1 FROM privado.grupo_mensagem_lida l WHERE l.fonte = 'grupo' AND l.ref = c.message_id
                        AND NOT (l.erro IS NOT NULL AND l.tentativas < 5 AND l.lida_em < now() - interval '10 minutes'))
  UNION ALL
  SELECT 'grupo', g.ref, NULL, g.grupo_nome, g.remetente, g.remetente_nome, g.enviada_em, g.texto
    FROM privado.grupo_importada g
   WHERE g.enviada_em > now() - make_interval(hours => %(janela)s)
     AND NOT EXISTS (SELECT 1 FROM privado.grupo_mensagem_lida l WHERE l.fonte = 'grupo' AND l.ref = g.ref
                        AND NOT (l.erro IS NOT NULL AND l.tentativas < 5 AND l.lida_em < now() - interval '10 minutes'))
  UNION ALL
  SELECT 'teste', t.id::text, NULL, 'Teste colado na tela', NULL, t.nome, t.criado_em, t.texto
    FROM privado.grupo_pedido_teste t
   WHERE NOT EXISTS (SELECT 1 FROM privado.grupo_mensagem_lida l WHERE l.fonte = 'teste' AND l.ref = t.id::text
                        AND NOT (l.erro IS NOT NULL AND l.tentativas < 5 AND l.lida_em < now() - interval '10 minutes'))
) x
 ORDER BY (fonte = 'teste') DESC, enviada_em
 LIMIT %(limite)s
"""

# os pedidos da janela que ainda não têm conta (ou todos, quando é para refazer)
A_PONTUAR = """
SELECT q.id, q.ficha, q.grupo_nome
  FROM privado.grupo_pedido q
 WHERE q.enviada_em > now() - make_interval(hours => %(janela)s) AND q.estado IN ('novo', 'rejeitado')
   AND (%(todos)s OR q.pontuado_em IS NULL)
 ORDER BY q.id
"""


def conectar():
    conn = psycopg2.connect(config.DATABASE_URL, connect_timeout=10, application_name="nay-grupos",
                            options="-c statement_timeout=30000 -c lock_timeout=5000")
    conn.autocommit = False
    return conn


def linhas(conn, sql: str, params=None) -> list[dict]:
    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(sql, params)
        return [dict(r) for r in cur.fetchall()] if cur.description else []


# quantas mensagens de grupo a IA já leu hoje (as que nem foram à IA ficam com `modelo` nulo e não contam)
LEITURAS_DE_HOJE = """
SELECT count(*) AS n FROM privado.grupo_mensagem_lida
 WHERE fonte = 'grupo' AND modelo IS NOT NULL AND lida_em >= date_trunc('day', now())
"""


def marcar_lida(conn, m: dict, pedidos: int, motivo: str | None = None, erro: str | None = None, pela_ia: bool = True) -> None:
    with conn.cursor() as cur:
        cur.execute("""INSERT INTO privado.grupo_mensagem_lida (fonte, ref, pedidos, motivo, erro, modelo)
                       VALUES (%s, %s, %s, %s, %s, %s)
                       ON CONFLICT (fonte, ref) DO UPDATE SET pedidos = excluded.pedidos, motivo = excluded.motivo,
                                                             erro = excluded.erro, lida_em = now(),
                                                             tentativas = privado.grupo_mensagem_lida.tentativas + 1""",
                    (m["fonte"], m["ref"], pedidos, motivo, erro, config.MODELO if pela_ia else None))


def gravar_pedidos(conn, m: dict, fichas: list[dict]) -> int:
    """Cada pedido da mensagem vira uma linha (parte 1, 2, ...). Devolve quantos entraram."""
    n = 0
    with conn.cursor() as cur:
        for parte, ficha in enumerate(fichas, start=1):
            duvidosos = ficha.pop("duvidosos", [])
            ficha["duvidosos_da_leitura"] = duvidosos        # os de lugar entram depois, na conta (gravar_conta)
            cur.execute("""INSERT INTO privado.grupo_pedido
                             (fonte, ref, parte, grupo_id, grupo_nome, remetente, remetente_nome, enviada_em, texto, ficha, duvidosos)
                           VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                           ON CONFLICT (fonte, ref, parte) DO NOTHING""",
                        (m["fonte"], m["ref"], parte, m.get("grupo_id"), m.get("grupo_nome"), m.get("remetente"),
                         m.get("remetente_nome"), m["enviada_em"], m["texto"],
                         json.dumps(ficha, ensure_ascii=False), duvidosos))
            n += cur.rowcount
    return n


def gravar_conta(conn, pedido_id: int, local: dict, duvidosos_de_lugar: list[str], resultado: dict, faixa: str | None,
                 pares: list[dict]) -> None:
    """A conta de um pedido: o melhor, as alternativas e por que não houve, quando não houve."""
    melhor = pares[0] if pares else None
    with conn.cursor() as cur:
        cur.execute("DELETE FROM privado.grupo_pedido_par WHERE pedido_id = %s", (pedido_id,))
        for p in pares:
            cur.execute("""INSERT INTO privado.grupo_pedido_par (pedido_id, codigo, posicao, nota, detalhe, acima_do_teto, imovel)
                           VALUES (%s, %s, %s, %s, %s, %s, %s)""",
                        (pedido_id, p["codigo"], p["posicao"], p["nota"], json.dumps(p["detalhe"], ensure_ascii=False),
                         p["acima_do_teto"], json.dumps(p["imovel"], ensure_ascii=False)))
        # os duvidosos de LUGAR são refeitos a cada conta (o apelido novo tira a dúvida); os da leitura ficam
        cur.execute("""UPDATE privado.grupo_pedido q
                          SET local = %s, melhor_codigo = %s, nota = %s, faixa = %s, sem_match_motivo = %s, funil = %s,
                              pontuado_em = now(),
                              duvidosos = (SELECT coalesce(array_agg(DISTINCT d ORDER BY d), '{}') FROM (
                                             SELECT jsonb_array_elements_text(coalesce(q.ficha->'duvidosos_da_leitura', '[]'::jsonb)) AS d
                                             UNION SELECT unnest(%s::text[])) x)
                        WHERE q.id = %s""",
                    (json.dumps(local, ensure_ascii=False), melhor["codigo"] if melhor else None,
                     melhor["nota"] if melhor else None, faixa if melhor else "sem_match",
                     None if melhor else resultado.get("motivo"), json.dumps(resultado.get("funil") or {}),
                     duvidosos_de_lugar, pedido_id))


def publicar_estado(conn, regras: dict, aviso: str | None) -> bool:
    """Diz à tela como o serviço está rodando. Devolve se alguém pediu para refazer as contas."""
    with conn.cursor() as cur:
        cur.execute("""UPDATE privado.grupo_captacao_estado
                          SET config = %s, batimento = clock_timestamp(), aviso = %s WHERE id = 1 RETURNING repontuar""",
                    (json.dumps(regras, ensure_ascii=False), aviso))
        linha = cur.fetchone()
        refazer = bool(linha and linha[0])
        if refazer:
            cur.execute("UPDATE privado.grupo_captacao_estado SET repontuar = false WHERE id = 1")
    conn.commit()
    return refazer
