"""Um turno da captação, do começo ao fim: reservar, juntar, perguntar ao modelo, filtrar, enviar e registrar.

É o caminho "Reservar mensagens -> Juntar mensagens -> AI Agent -> Preparar resposta -> Loop resposta -> Pausa ->
Ainda é da IA? -> Enviar resposta (oficial) -> Registrar saida" do fluxo do n8n, na mesma ordem.

`enviar=False` é o ensaio: nada sai, e quem chama desfaz a transação no fim.
"""
from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Callable

from captacao import banco, config, envio, ferramentas, modelo, resposta, turno

log = logging.getLogger("captacao.atender")
HISTORICO = 20   # o mesmo tamanho da memória do agente no fluxo


@dataclass
class Feito:
    telefone: str
    motivo: str = ""                 # por que não respondeu, quando não respondeu
    recebido: str = ""
    ferramentas: list[dict] = field(default_factory=list)
    baloes: list[str] = field(default_factory=list)
    falhou_envio: int = 0


def _prompt(conn, t: turno.Turno) -> str:
    """O prompt vivo do banco, mais o que só vale no número oficial (o modelo que abriu a conversa e a indicação)."""
    r = banco.linhas(conn, """
        SELECT m.texto FROM captacao_mensagens m
         WHERE nay_fone_chave(m.telefone) = nay_fone_chave(%s) AND m.direcao = 'enviada' AND m.origem = 'disparo'
           AND m.status <> 'Falhou' ORDER BY m.id DESC LIMIT 1""", (t.telefone,))
    abertura = (r[0]["texto"] if r else "") or "(o primeiro contato desta conversa nao foi por modelo)"
    # a pergunta da indicação é montada pelo banco, com o nome dele e o tipo do imóvel (320)
    frase = banco.linhas(conn, "SELECT captacao_indicacao_frase(%s) AS f", (t.telefone,))[0]["f"]
    return t.prompt + modelo.ACRESCIMO.replace("{modelo}", abertura).replace("{indicacao}", frase)


def _historico(conn, t: turno.Turno) -> list[dict]:
    r = banco.linhas(conn, banco.HISTORICO, (t.telefone, min(t.ids), HISTORICO))
    return [{"role": "assistant" if m["direcao"] == "enviada" else "user", "content": m["texto"]} for m in r]


def _avisar_tel(conn, aviso: str, telefone: str = "") -> None:
    """Manda o aviso ao Tel pela caixa da Nay (crm_avisar_tel). O telefone de TESTE nunca gera aviso."""
    de_teste = bool(telefone) and banco.linhas(conn, """
        SELECT nay_fone_chave(%s) = nay_fone_chave((SELECT valor FROM captacao_config WHERE chave = 'telefone_teste')) AS t""",
        (telefone,))[0]["t"]
    if not config.AVISAR_TEL or de_teste:
        log.info("aviso ao Tel NÃO enviado (%s): %s", "telefone de teste" if de_teste else "CAPTACAO_AVISAR_TEL=nao",
                 aviso.replace("\n", " ")[:160])
        return
    try:
        banco.linhas(conn, "SELECT * FROM crm_avisar_tel(%s, 'captacao')", (aviso,))
    except Exception as e:  # noqa: BLE001 -- perder o aviso é ruim; derrubar o turno do proprietário é pior
        log.warning("não consegui avisar o Tel: %s", e)


def _encaminhar_indicacao(conn, texto: str, telefone: str) -> None:
    """A indicação vai na hora para quem recebe o relatório da captação (Pedro, 08/10/2026: "que o número ao menos
    encaminhe para mim, não podemos perder o contato assim"). Sai pelo número oficial; se não sair (fora da janela de
    24 h de quem recebe), vai como aviso ao Tel. Ela já está gravada em privado.captacao_indicacao de qualquer jeito."""
    r = banco.linhas(conn, """
        SELECT regexp_replace(coalesce(valor, ''), '[^0-9]', '', 'g') AS t FROM captacao_config WHERE chave = 'telefone_relatorio'""")
    destino = r[0]["t"] if r else ""
    if len(destino) in (10, 11):
        destino = "55" + destino
    try:
        if len(destino) >= 12 and envio.texto(destino, texto):
            log.info("indicação de …%s encaminhada para …%s", telefone[-4:], destino[-4:])
            return
    except Exception as e:  # noqa: BLE001 -- o encaminhamento não derruba o turno do proprietário
        log.warning("não consegui encaminhar a indicação pelo número oficial: %s", e)
    _avisar_tel(conn, texto, telefone)


def atender(conn, telefone: str, enviar: bool = True, agora: datetime | None = None,
            dormir: Callable[[float], None] = time.sleep) -> Feito:
    feito = Feito(telefone=telefone)
    itens = banco.linhas(conn, banco.RESERVAR, {"tel": telefone})
    if not itens:
        feito.motivo = "nada para reservar (ele ainda está escrevendo, ou o Tel assumiu a conversa)"
        return feito
    p = itens[0]
    # o portão do fluxo, que falha fechado: sem lead, com opt-out ou com a resposta pausada, nada sai
    if p["lead_id"] is None or p["opt_out"] or p["pausado"]:
        feito.motivo = ("não está na lista da captação" if p["lead_id"] is None
                        else "pediu para não receber" if p["opt_out"] else "a resposta automática está pausada")
        return feito
    t = turno.juntar(itens)
    if t is None:
        feito.motivo = "mensagem sem texto (figurinha, reação): não vira turno"
        return feito
    if t.aviso_ao_tel:
        _avisar_tel(conn, t.aviso_ao_tel, t.telefone)
    if not t.texto:
        feito.motivo = "só foto, e ela já tinha seguido o atendimento depois das fotos anteriores"
        return feito
    if not t.prompt:
        raise RuntimeError("o prompt da captação não veio do banco (nai_prompt_de('captacao'))")
    if len(envio.so_digitos(t.telefone)) < 12:
        feito.motivo = "telefone incompleto"
        return feito
    feito.recebido = t.texto

    saida, feito.ferramentas = modelo.responder(
        _prompt(conn, t), _historico(conn, t), turno.cabecalho(t, agora or datetime.now(timezone.utc)),
        ferramentas.definicoes(),
        lambda nome, args: ferramentas.executar(
            conn, nome, args, t.telefone, t.nome,
            avisar=lambda aviso: _avisar_tel(conn, aviso, t.telefone),
            encaminhar=(lambda texto: _encaminhar_indicacao(conn, texto, t.telefone)) if enviar else None))

    for b in resposta.baloes(saida):
        dormir(b.pausa)
        r = banco.linhas(conn, banco.AINDA_E_DA_IA, {"tel": t.telefone})
        if not r or not r[0]["segue"]:
            feito.motivo = "o Tel assumiu a conversa (ou ela foi escalada): o resto não saiu"
            break
        if not enviar:
            mid = "ensaio"
        elif r[0]["canal"] != "oficial":
            log.warning("…%s está no canal %s: este serviço só envia pelo número oficial", t.telefone[-4:], r[0]["canal"])
            mid = None
        else:
            mid = envio.texto(t.telefone, b.texto)
        banco.linhas(conn, banco.REGISTRAR_SAIDA, {"tel": t.telefone, "texto": b.texto, "mid": mid or "",
                                                   "pergunta": b.pergunta or ""})
        feito.baloes.append(b.texto)
        feito.falhou_envio += 0 if mid else 1
    if not feito.baloes and not feito.motivo:
        feito.motivo = "ela escolheu não responder (SILENCIO)"
    return feito
