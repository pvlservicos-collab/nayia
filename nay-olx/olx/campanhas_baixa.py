"""O AVISO DE BAIXA DE PREÇO (595): "depois de falar com os donos em que o imóvel está parado, avisar quem recebeu o imóvel
quando o dono baixar o preço" (Pedro, 03/11/2026).

O GATILHO é a equipe: crm_campanha_baixa_confirmar(código, valor novo, quem). Nada de olhar `imoveis` sozinho: o valor
muda também pela captação, pela sincronização e por engano de digitação, e um aviso errado vai a dezenas de clientes. E
a confirmação sozinha não basta: o aviso só sai quando o CADASTRO já mostra o valor novo (ou menor) e o imóvel segue
Disponível. Confirmada e o cadastro não mudou em 7 dias: 'expirada'. Saiu de Disponível: 'cancelada'.

Quem recebe (campanha_baixa_destinatarios): o lead da Nay Leads que recebeu o card desse imóvel nos últimos
`campanha_baixa_dias`, sem a equipe na conversa, sem visita em andamento, que não é da casa nem o dono e a quem a Nay
ainda não avisou deste imóvel (UMA vez por pessoa por imóvel: privado.campanha_baixa_aviso). Sai pela Nay Leads
(whatsapp.mandar_texto: a mesma conversa, o mesmo "não repetir"), um por vez, no horário comercial, com
`campanha_baixa_intervalo_s` entre um e outro. A resposta dele é da Nay Leads, como qualquer mensagem do lead.
Chave `campanha_baixa_avisar`: nao (nasce assim) | teste (só os números de whatsapp_teste) | sim.
"""
from __future__ import annotations

import logging
import random
import time

from olx import banco, campanhas

log = logging.getLogger("olx.campanhas.baixa")
_PROXIMO = [0.0]


def dinheiro(v) -> str:
    return "R$ " + f"{int(round(float(v))):,}".replace(",", ".")


def texto_da_baixa(lead: dict, nome_imovel: str, codigo: int, antes, novo, finalidade: str) -> str:
    """Curto e de gente: o imóvel pelo nome, de quanto para quanto, e a pergunta da visita."""
    from olx import whatsapp
    vocativo, pronome = whatsapp.tratamento(lead)
    oi = f"Oi, {vocativo}!" if vocativo else "Oi!"
    mes = " por mês" if finalidade == "locacao" else ""
    para = {"a senhora": "que mandei para a senhora", "o senhor": "que mandei para o senhor"}.get(pronome, "que te mandei")
    quer = {"a senhora": "A senhora quer", "o senhor": "O senhor quer"}.get(pronome, "Quer")
    return (f"{oi} Boa notícia: {nome_imovel} (cód. {codigo}), {para}, baixou de {dinheiro(antes)} para "
            f"{dinheiro(novo)}{mes}. {quer} agendar uma visita?")


def _teste(cfg: dict) -> set[str]:
    from olx import whatsapp
    return whatsapp._lista(cfg.get("whatsapp_teste"))


def conferir_baixas(conn) -> None:
    """confirmada -> avisando quando o cadastro já mostra o valor; sai de Disponível -> cancelada; 7 dias -> expirada."""
    for b in banco.linhas(conn, """
            SELECT b.id, b.estado, b.valor_novo, b.confirmada_em < now() - interval '7 days' AS velha,
                   i.status = 'Disponível' AND i.disponivel AS disponivel,
                   CASE WHEN b.finalidade = 'locacao' THEN i.valor_aluguel ELSE i.valor_venda END AS atual
              FROM privado.campanha_baixa b JOIN imoveis i ON i.codigo = b.codigo
             WHERE b.estado IN ('confirmada', 'avisando')"""):
        if not b["disponivel"]:
            novo, motivo = "cancelada", "o imóvel saiu de Disponível"
        elif b["atual"] is None or float(b["atual"]) > float(b["valor_novo"]) * 1.001:
            if b["estado"] == "avisando":
                novo, motivo = "cancelada", "o valor do cadastro voltou a subir"
            elif b["velha"]:
                novo, motivo = "expirada", "o cadastro não mostrou o valor novo em 7 dias"
            else:
                continue                                    # espera a equipe mudar o cadastro
        elif b["estado"] == "confirmada":
            novo, motivo = "avisando", None
        else:
            continue
        banco.um(conn, "UPDATE privado.campanha_baixa SET estado = %s, motivo = %s, atualizado_em = now() WHERE id = %s",
                 (novo, motivo, b["id"]))


def avisar_um(conn, cfg: dict) -> bool:
    from olx import visita, whatsapp
    teste = _teste(cfg) if campanhas.modo(cfg, "campanha_baixa_avisar") == "teste" else None
    for b in banco.linhas(conn, """SELECT b.*, campanha_imovel_nome(b.codigo, false) AS nome FROM privado.campanha_baixa b
                                    WHERE b.estado = 'avisando' ORDER BY b.id"""):
        dest = banco.linhas(conn, "SELECT * FROM campanha_baixa_destinatarios(%s)", (b["id"],))
        if not dest:
            banco.um(conn, "UPDATE privado.campanha_baixa SET estado = 'avisada', atualizado_em = now() WHERE id = %s", (b["id"],))
            continue
        for d in dest:
            if teste is not None and d["tel8"] not in teste:
                continue
            if visita.ativa(conn, d["lead"]):
                continue                                    # visita andando: a baixa fica para a conversa da visita
            if banco.um(conn, """SELECT EXISTS (SELECT 1 FROM captacao_mensagens WHERE direcao = 'recebida'
                                    AND right(regexp_replace(coalesce(telefone, ''), '\\D', '', 'g'), 8) = %s
                                    AND criada_em > now() - interval '10 minutes')""", (d["tel8"],)):
                continue                                    # ele está conversando agora: a Nay Leads responde primeiro
            aid = banco.um(conn, """INSERT INTO privado.campanha_baixa_aviso (baixa, codigo, lead, tel8) VALUES (%s, %s, %s, %s)
                                    ON CONFLICT (codigo, tel8) DO NOTHING RETURNING id""", (b["id"], b["codigo"], d["lead"], d["tel8"]))
            if not aid:
                continue
            lead = whatsapp._lead(conn, d["lead"])
            texto = texto_da_baixa(lead, b["nome"], b["codigo"], b["valor_antes"], b["valor_novo"], b["finalidade"])
            try:
                mid = whatsapp.mandar_texto(conn, lead, texto)
                banco.um(conn, """UPDATE privado.campanha_baixa_aviso SET estado = %s, texto = %s, message_id = %s, enviado_em = now(),
                                         erro = %s WHERE id = %s""",
                         ("enviado" if mid else "erro", texto, mid or None, None if mid else "texto repetido segurado", aid))
                if mid:
                    banco.um(conn, "SELECT nay_aviso_equipe('nay-olx', 'nota', 'Nay avisou a baixa', %s, %s)",
                             (f"Nay avisou a baixa do {b['codigo']} ({dinheiro(b['valor_antes'])} -> {dinheiro(b['valor_novo'])}), "
                              f"confirmada por {b['quem']}.", lead.get("telefone")))
                    log.info("baixa #%s: avisado o lead %s", b["id"], d["lead"])
            except Exception as e:  # noqa: BLE001 -- não repete (a linha do aviso fica com o erro)
                banco.um(conn, "UPDATE privado.campanha_baixa_aviso SET estado = 'erro', erro = %s WHERE id = %s", (str(e)[:300], aid))
                log.warning("baixa #%s: o aviso ao lead %s falhou: %s", b["id"], d["lead"], e)
            return True
    return False


def atender(conn, cfg: dict) -> int:
    if campanhas.modo(cfg, "campanha_baixa_avisar") == "nao":
        return 0
    conferir_baixas(conn)
    if not campanhas.no_horario(cfg.get("campanha_horario") or "8-12,13:30-18") or time.time() < _PROXIMO[0]:
        return 0
    from olx import whatsapp
    if not whatsapp.conectada():
        return 0
    if avisar_um(conn, cfg):
        a, b = campanhas.intervalo(cfg.get("campanha_baixa_intervalo_s"), (60, 150))
        _PROXIMO[0] = time.time() + random.uniform(a, b)
        return 1
    return 0
