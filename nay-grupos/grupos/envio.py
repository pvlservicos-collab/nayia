"""O ENVIO AUTOMÁTICO (modo "ativo", Pedro 19/10/2026).

Pedro, 09/10: "TREINO: lê, extrai, pontua e mostra. NUNCA envia ... Não prossiga para o modo ATIVO até eu confirmar".
Pedro, 19/10, confirmando: "pode ativar um envio automático para o corretor que pediu, em imóveis com a nota acima de
88, com uma mensagem bacana: 'Oi, vi seu pedido lá no grupo, veja se esse imóvel serve' ... pode botar para chamar o
corretor no PV pelo número da Parceria no automático".

Este módulo não fala com a rede: escolhe os pedidos e chama, para cada um, a MESMA função do botão "Enviar ao corretor"
(`site_captacao_grupos_enviar`, 339), que põe a mensagem, o card e as fotos na caixa de saída da Nay (número da
Parceria) com todas as travas dela: janela de 48 h, um envio por card, o imóvel tem de ter casado com o pedido, e as
paredes da caixa da Nay (imóvel de parceiro nunca sai para corretor).

As travas daqui, a mais:
  - só com modo "ativo" em config.json; só pedido com nota ACIMA de `nota_min_automatico` (88), o melhor imóvel dele;
  - só pedido chegado depois de `automatico_desde` (o envio liga do momento em diante, não varre o que já passou);
  - nunca a quem é da equipe; nunca de um grupo nosso (`privado.grupo_fora`, 418);
  - um corretor recebe no máximo um envio automático por hora, e nunca o mesmo imóvel duas vezes;
  - no máximo `automatico_max_dia` envios automáticos por dia;
  - só entre `automatico_das` e `automatico_ate` (hora de Manaus): o pedido da noite sai de manhã, se ainda na janela;
  - o pedido que o banco recusou não é tentado de novo até o serviço reiniciar.
"""
from __future__ import annotations

import datetime
import logging

log = logging.getLogger("grupos.envio")
QUEM = "automático"
MANAUS = datetime.timezone(datetime.timedelta(hours=-4))
_RECUSADOS: set[int] = set()

CANDIDATOS = """
SELECT * FROM (
  SELECT DISTINCT ON (coalesce(j.card, q.id)) q.id, q.melhor_codigo, q.nota, q.remetente, q.enviada_em,
         right(regexp_replace(coalesce(q.remetente, ''), '\\D', '', 'g'), 8) AS quem
    FROM privado.grupo_pedido q
    LEFT JOIN privado.grupo_pedido_junto j ON j.pedido_id = q.id
   WHERE q.fonte = 'grupo' AND q.estado = 'novo' AND q.pontuado_em IS NOT NULL
     AND q.melhor_codigo IS NOT NULL AND q.nota > %(nota)s
     AND q.enviada_em > now() - make_interval(hours => %(janela)s)
     AND q.enviada_em >= %(desde)s::timestamptz
     AND nai_chave(q.remetente) IS NOT NULL
     AND NOT privado.grupo_e_nosso(q.grupo_id, q.grupo_nome)
     -- o card inteiro (cópias e partes): se alguém já enviou ou rejeitou, não vai
     AND NOT EXISTS (SELECT 1 FROM privado.grupo_pedido_junto jc JOIN privado.grupo_pedido c ON c.id = jc.pedido_id
                      WHERE jc.card = j.card AND c.estado IN ('enviado', 'rejeitado'))
     AND NOT EXISTS (SELECT 1 FROM nai_contato k WHERE k.chave = nai_chave(q.remetente) AND nai_e_da_equipe_contato(k.id))
     -- o mesmo imóvel nunca vai duas vezes ao mesmo corretor (ele pede o mesmo em vários grupos, em mensagens diferentes)
     AND NOT EXISTS (SELECT 1 FROM privado.grupo_pedido_oferta o
                      WHERE o.codigo = q.melhor_codigo AND nai_chave(o.telefone) = nai_chave(q.remetente))
   ORDER BY coalesce(j.card, q.id), q.nota DESC, q.enviada_em DESC) x
 ORDER BY x.enviada_em
"""

ENVIADOS_HOJE = """
SELECT count(*) AS n FROM privado.grupo_pedido_oferta
 WHERE quem = %(quem)s AND enviado_em >= date_trunc('day', now() AT TIME ZONE 'America/Manaus') AT TIME ZONE 'America/Manaus'
"""

CORRETOR_NA_ULTIMA_HORA = """
SELECT EXISTS (SELECT 1 FROM privado.grupo_pedido_oferta
                WHERE quem = %(quem)s AND nai_chave(telefone) = nai_chave(%(fone)s) AND enviado_em > now() - interval '1 hour') AS ja
"""


def no_horario(r: dict, agora: datetime.datetime | None = None) -> bool:
    h = (agora or datetime.datetime.now(MANAUS)).astimezone(MANAUS).hour
    return r["automatico_das"] <= h < r["automatico_ate"]


def ligado(r: dict) -> bool:
    return r.get("modo") == "ativo" and bool(r.get("envio_manual")) and bool(str(r.get("automatico_desde") or "").strip())


def automatico(conn, r: dict, linhas) -> int:
    """Uma passada do envio automático. `linhas` é a de grupos.banco. Devolve quantos saíram."""
    if not ligado(r) or not no_horario(r):
        return 0
    feitos_hoje = linhas(conn, ENVIADOS_HOJE, {"quem": QUEM})[0]["n"]
    sobra = r["automatico_max_dia"] - feitos_hoje
    if sobra <= 0:
        return 0
    candidatos = linhas(conn, CANDIDATOS, {"nota": r["nota_min_automatico"], "janela": r["janela_h"],
                                           "desde": r["automatico_desde"]})
    saiu, nesta_passada = 0, set()
    for c in candidatos:
        if saiu >= sobra:
            break
        if c["id"] in _RECUSADOS or c["quem"] in nesta_passada:
            continue
        if linhas(conn, CORRETOR_NA_ULTIMA_HORA, {"quem": QUEM, "fone": c["remetente"]})[0]["ja"]:
            continue
        res = linhas(conn, "SELECT site_captacao_grupos_enviar(%s, %s, %s, %s) AS r",
                     (c["id"], c["melhor_codigo"], r["mensagem_automatica"], QUEM))[0]["r"] or {}
        conn.commit()
        if res.get("ok"):
            saiu += 1
            nesta_passada.add(c["quem"])
            log.info("envio automático: pedido %s, imóvel %s (nota %s) para ...%s: %s", c["id"], c["melhor_codigo"],
                     c["nota"], c["quem"][-4:], res.get("resumo"))
        else:
            _RECUSADOS.add(c["id"])
            log.warning("envio automático recusado: pedido %s, imóvel %s: %s", c["id"], c["melhor_codigo"], res.get("erro"))
    return saiu
