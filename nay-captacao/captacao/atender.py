"""Um turno da captação, do começo ao fim: reservar, juntar, perguntar ao modelo, filtrar, enviar e registrar.

É o caminho "Reservar mensagens -> Juntar mensagens -> AI Agent -> Preparar resposta -> Loop resposta -> Pausa ->
Ainda é da IA? -> Enviar resposta (oficial) -> Registrar saida" do fluxo do n8n, na mesma ordem.

`enviar=False` é o ensaio: nada sai, e quem chama desfaz a transação no fim.
"""
from __future__ import annotations

import logging
import re
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Callable

from captacao import banco, config, envio, ferramentas, modelo, olx, resposta, turno, venda

log = logging.getLogger("captacao.atender")
HISTORICO = 20   # o mesmo tamanho da memória do agente no fluxo

# Pedro, 22/10: o botão "Excluir meu contato" dos modelos outro_imovel_sair_* ("quem clica nisso a Nay não responde
# mais, como uma opção do cliente desligar sem ele precisar denunciar para a Meta"). Vale a linha que é só o botão.
EXCLUIR_CONTATO = re.compile(r"^\W*excluir\s+meu\s+contato\W*$", re.I | re.M)
SAIR_DA_LISTA = """
WITH l AS (
  UPDATE captacao_leads
     SET opt_out = true, status = 'concluido', etapa = 'concluido', pergunta_pendente = NULL,
         motivo_fim = 'opt_out', fechado_em = coalesce(fechado_em, now()), atualizado_em = now()
   WHERE telefone_chave = nay_fone_chave(%(tel)s)
  RETURNING id
)
INSERT INTO captacao_nao_disparar (telefone_chave, motivo)
VALUES (nay_fone_chave(%(tel)s), 'clicou em Excluir meu contato')
ON CONFLICT (telefone_chave) DO UPDATE SET motivo = EXCLUDED.motivo
RETURNING (SELECT count(*) FROM l) AS leads
"""


def pediu_excluir_contato(texto: str) -> bool:
    return bool(EXCLUIR_CONTATO.search(texto or ""))


@dataclass
class Feito:
    telefone: str
    motivo: str = ""                 # por que não respondeu, quando não respondeu
    recebido: str = ""
    ferramentas: list[dict] = field(default_factory=list)
    baloes: list[str] = field(default_factory=list)
    falhou_envio: int = 0


def _prompt(conn, t: turno.Turno) -> str:
    """478 (Pedro, 23/10: "salva o estado dela como uma nay ligada à lista de proprietários ... quando eu for mudar de
    lista só troca o modelo da nay"): o perfil do lead diz qual prompt vivo e qual roteiro do código valem."""
    p = banco.linhas(conn, "SELECT * FROM captacao_nay_perfil_do_lead(%s)", (t.telefone,))
    if not p or not p[0]["prompt"]:
        raise RuntimeError(f"o perfil da Nay deste lead não tem prompt (captacao_nay_perfil_do_lead): {p}")
    roteiro = ROTEIROS.get(p[0]["roteiro"])
    if roteiro is None:
        raise RuntimeError(f"o roteiro {p[0]['roteiro']!r} do perfil {p[0]['nome']!r} não existe no nay-captacao")
    return roteiro(conn, t, p[0]["prompt"])


def _roteiro_proprietarios(conn, t: turno.Turno, prompt: str) -> str:
    """O prompt vivo do banco, mais o que só vale no número oficial (o modelo que abriu a conversa e a indicação)."""
    r = banco.linhas(conn, """
        SELECT m.texto FROM captacao_mensagens m
         WHERE nay_fone_chave(m.telefone) = nay_fone_chave(%s) AND m.direcao = 'enviada' AND m.origem = 'disparo'
           AND m.status <> 'Falhou' ORDER BY m.id DESC LIMIT 1""", (t.telefone,))
    abertura = (r[0]["texto"] if r else "") or "(o primeiro contato desta conversa nao foi por modelo)"
    # a pergunta da indicação é montada pelo banco, com o nome dele e o tipo do imóvel (320)
    r = banco.linhas(conn, "SELECT captacao_indicacao_frase(%s) AS f, captacao_honorarios_frase(%s) AS h",
                     (t.telefone, t.telefone))[0]
    # a última pergunta (324): só quando há valor de venda para pôr na frase
    honorarios = modelo.HONORARIOS_COM_VALOR.replace("{frase}", r["h"]) if r["h"] else modelo.HONORARIOS_SEM_VALOR
    # 447/455: o lead que recebeu o modelo do "outro imóvel" tem a abertura da campanha dele: lista 5 (imóvel alugado
    # por nós: o contrato e o outro imóvel) ou listas 3 e 4 (removido/arquivado e só vendido: imóvel para vender)
    lead = banco.linhas(conn, """
        SELECT coalesce(l.modelo_abertura, '') LIKE 'outro\\_imovel%%' AS outro, coalesce(l.campanha, 'alugado') AS campanha,
               l.tipo_imovel, l.imovel_desc, l.condominio, l.bairro
          FROM captacao_leads l WHERE l.telefone_chave = nay_fone_chave(%s)""", (t.telefone,))
    if lead and lead[0]["outro"]:
        d = lead[0]
        onde = d["imovel_desc"] or d["condominio"] or d["bairro"] or ""
        imovel = " ".join(x for x in ((d["tipo_imovel"] or "").strip().lower(), onde) if x) or "o imovel do cadastro"
        base = (modelo.ACRESCIMO_OUTRO_VENDER.replace("{situacao_antiga}", modelo.SITUACAO_ANTIGA[d["campanha"]])
                if d["campanha"] in modelo.SITUACAO_ANTIGA else modelo.ACRESCIMO_OUTRO_IMOVEL)
        return (prompt + base.replace("{modelo}", abertura).replace("{imovel}", imovel)
                .replace("{indicacao}", r["f"]).replace("{honorarios}", honorarios))
    return (prompt + modelo.ACRESCIMO.replace("{modelo}", abertura).replace("{indicacao}", r["f"])
            .replace("{honorarios}", honorarios)
            # o imóvel dele está no cadastro para VENDA: a pergunta do valor da locação não cabe (12/10, venda.py)
            + venda.secao(venda.do_cadastro(conn, banco, t.telefone), venda.sem_imovel(conn, banco, t.telefone)))



# o roteiro de cada perfil (captacao_nay_perfil.roteiro). Perfil novo (a Nay dos corretores) = um roteiro novo aqui.
ROTEIROS = {"proprietarios": _roteiro_proprietarios}

def _historico(conn, t: turno.Turno) -> list[dict]:
    r = banco.linhas(conn, banco.HISTORICO, (t.telefone, min(t.ids), HISTORICO))
    return [{"role": "assistant" if m["direcao"] == "enviada" else "user", "content": m["texto"]} for m in r]


def _avisar_tel(conn, aviso: str, telefone: str = "") -> None:
    """O aviso de escalada, foto e mídia. Desde 24/10 (Pedro: "a escalada para o número de captação") vai ao GRUPO da equipe
    pela linha de captação (8595), não ao PV do Tel (482). O telefone de TESTE nunca gera aviso."""
    de_teste = bool(telefone) and banco.linhas(conn, """
        SELECT nay_fone_chave(%s) = nay_fone_chave((SELECT valor FROM captacao_config WHERE chave = 'telefone_teste')) AS t""",
        (telefone,))[0]["t"]
    if not config.AVISAR_TEL or de_teste:
        log.info("aviso ao Tel NÃO enviado (%s): %s", "telefone de teste" if de_teste else "CAPTACAO_AVISAR_TEL=nao",
                 aviso.replace("\n", " ")[:160])
        return
    try:
        if not envio.grupo_da_equipe("🔔 " + aviso):
            log.warning("o aviso à equipe não saiu: %s", aviso.replace("\n", " ")[:160])
    except Exception as e:  # noqa: BLE001 -- perder o aviso é ruim; derrubar o turno do proprietário é pior
        log.warning("não consegui avisar a equipe: %s", e)


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
    if pediu_excluir_contato(t.texto):
        # sai da lista e do disparo, sem resposta nenhuma (nem o "desculpe" do opt_out pelo modelo)
        banco.linhas(conn, SAIR_DA_LISTA, {"tel": t.telefone})
        feito.recebido = t.texto
        feito.motivo = "clicou em Excluir meu contato: saiu da lista, sem resposta"
        log.info("…%s clicou em Excluir meu contato: opt_out e fora do disparo", t.telefone[-4:])
        return feito
    if not t.prompt:
        raise RuntimeError("o prompt da captação não veio do banco (nai_prompt_de('captacao'))")
    if len(envio.so_digitos(t.telefone)) < 12:
        feito.motivo = "telefone incompleto"
        return feito
    feito.recebido = t.texto

    agora = agora or datetime.now(timezone.utc)
    # o proprietário que veio da OLX (370): o prompt, o turno e as ferramentas são os da Nay proprietários da OLX
    d = olx.dados(conn, t.telefone)
    if d:
        prompt, texto, defs, executor = olx.PROMPT, olx.cabecalho(t, d, agora), olx.definicoes(), olx.executar
    else:
        prompt, texto, defs, executor = _prompt(conn, t), turno.cabecalho(t, agora), ferramentas.definicoes(), ferramentas.executar
    saida, feito.ferramentas = modelo.responder(
        prompt, _historico(conn, t), texto, defs,
        lambda nome, args: executor(
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
        elif r[0]["canal"] == "parceria":
            # 374: a Nay proprietários da OLX conversa pela Parceria (Z-API), pela caixa da Nay
            mid = envio.parceria(conn, t.telefone, t.nome, b.texto)
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
