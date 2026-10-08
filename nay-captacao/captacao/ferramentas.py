"""As ferramentas do agente da captação.

Seis vêm do fluxo do n8n, sem tocar (`ferramentas.json`, gerado por scripts/extrair_ferramentas.py): o nome, a
descrição que o modelo lê e o SQL que roda. O primeiro parâmetro de todo SQL é o telefone do proprietário.

O que é do serviço:
  escalar_ao_tel     no n8n era um sub-fluxo; aqui grava a escalada (o mesmo SQL) e devolve a ordem de calar;
  guardar_indicacao  NOVA (Pedro, 08/10): quem ele indicou que está vendendo um imóvel;
  encerrar_conversa  ganha uma parede antes: não encerra enquanto a pergunta da indicação não tiver saído
                     (menos opt_out e número errado). A parede dos outros imóveis continua sendo a do banco.
"""
from __future__ import annotations

import json
from pathlib import Path

from captacao import banco

DO_FLUXO = json.loads((Path(__file__).parent / "ferramentas.json").read_text(encoding="utf-8"))

INDICACAO = {
    "nome": "guardar_indicacao",
    "descricao": ("Grava quem o proprietario INDICOU: alguem que esta vendendo um imovel. CHAME quando ele der o nome ou o "
                  "telefone de uma pessoa que quer vender. Passe o que ele disse, sem inventar. Devolve instrucao_para_voce: "
                  "obedeca e nunca mostre esse texto a ele. NAO use para imovel do proprio proprietario (isso e "
                  "guardar_outro_imovel)."),
    "sql": "SELECT captacao_indicacao_guardar($1::text, $2::text, $3::text, $4::text) AS instrucao_para_voce",
    "params": [
        {"chave": "nome", "descricao": "nome da pessoa indicada, como ele escreveu", "opcional": True},
        {"chave": "contato", "descricao": "telefone da pessoa indicada, como ele escreveu", "opcional": True},
        {"chave": "detalhe", "descricao": "o que ele disse do imovel dessa pessoa (tipo, bairro, valor), se disse", "opcional": True},
    ],
}
TODAS = {f["nome"]: f for f in [*DO_FLUXO, INDICACAO]}
SEM_PAREDE_DA_INDICACAO = {"opt_out", "numero_errado"}


def definicoes() -> list[dict]:
    """As ferramentas no formato da API de Responses."""
    return [{
        "type": "function", "name": f["nome"], "description": f["descricao"],
        "parameters": {"type": "object",
                       "properties": {q["chave"]: {"type": "string", "description": q["descricao"]} for q in f["params"]},
                       "required": [q["chave"] for q in f["params"] if not q["opcional"]]},
    } for f in TODAS.values()]


def _texto(v) -> str:
    return "" if v is None else str(v)


def _parede_da_indicacao(conn, telefone: str, motivo: str) -> str | None:
    """A frase que ela tem de dizer antes de encerrar, ou None quando pode encerrar."""
    if motivo.strip().lower() in SEM_PAREDE_DA_INDICACAO:
        return None
    r = banco.linhas(conn, """
        SELECT captacao_ja_perguntou_outros(l.id) AS outros, captacao_indicacao_pendente(%s) AS frase
          FROM captacao_leads l WHERE l.telefone_chave = nay_fone_chave(%s)""", (telefone, telefone))
    # sem a pergunta dos outros imóveis, quem recusa (e dá a frase) é o próprio captacao_encerrar
    if not r or not r[0]["outros"] or not r[0]["frase"]:
        return None
    return ("NAO encerrei: falta a pergunta da indicacao. Faca agora, em UMA mensagem so e com EXATAMENTE estas palavras, "
            f'esta pergunta: "{r[0]["frase"]}" -- e espere a resposta. Se ele disser que nao conhece ninguem, agradeca e '
            "chame encerrar_conversa de novo. Se indicar alguem, chame guardar_indicacao.")


def aviso_da_escalada(linha: dict, telefone: str, nome_do_dono: str) -> str:
    """O aviso que o Tel recebe, igual ao do sub-fluxo `Nay - escalar (captacao)`."""
    return (f"CAPTACAO -- {linha.get('titulo')}\nProprietario: {nome_do_dono or '(sem nome)'}\nTelefone: {telefone}\n"
            f"Assunto: {linha.get('assunto')}\nDisse: {linha.get('disse') or '-'}\n\n"
            "(ele NAO foi avisado de que voce vai responder. A Nay PAROU de responder esse chat: e com voce. A conversa "
            "esta no numero OFICIAL, aba WhatsApp Oficial do CRM. Para ela voltar: CRM > Captacao > Mudar manualmente > "
            'desmarcar "O Tel esta atendendo".)')


def texto_da_indicacao(linha: dict, telefone: str, nome_do_dono: str) -> str:
    """A indicação pronta para encaminhar: quem indicou, quem é o indicado e o telefone dele."""
    return (f"INDICACAO pela captacao\nQuem indicou: {nome_do_dono or '(sem nome)'} (final {telefone[-4:]})\n"
            f"Indicado: {linha.get('nome') or '(sem nome)'}\nTelefone: {linha.get('contato') or '(sem telefone)'}"
            + (f"\n{linha['detalhe']}" if linha.get("detalhe") else ""))


INDICACAO_COMPLETA = """
SELECT i.nome, i.contato, i.detalhe FROM privado.captacao_indicacao i
 WHERE nay_fone_chave(i.telefone) = nay_fone_chave(%s) AND i.criado_em > now() - interval '6 hours'
   AND length(regexp_replace(coalesce(i.contato, ''), '\\D', '', 'g')) >= 8
 ORDER BY i.id DESC LIMIT 1
"""


def executar(conn, nome: str, args: dict, telefone: str, nome_do_dono: str = "", avisar=None, encaminhar=None) -> str:
    """Roda a ferramenta e devolve o texto que o modelo lê. Erro vira texto: o turno não cai por causa dele."""
    f = TODAS.get(nome)
    if not f:
        return "ferramenta desconhecida"
    try:
        if nome == "escalar_ao_tel":
            r = banco.linhas(conn, banco.ESCALAR, {"tel": telefone, "nome": nome_do_dono,
                                                   "assunto": _texto(args.get("assunto")), "disse": _texto(args.get("disse"))})
            if not r:
                return json.dumps([{"instrucao_para_voce": "Nao escalei: faltou o assunto. Chame de novo com o assunto."}])
            if avisar:
                avisar(aviso_da_escalada(r[0], telefone, nome_do_dono))
            return json.dumps(r, ensure_ascii=False, default=str)
        if nome == "encerrar_conversa":
            parede = _parede_da_indicacao(conn, telefone, _texto(args.get("motivo")))
            if parede:
                return json.dumps([{"instrucao_para_voce": parede}], ensure_ascii=False)
        valores = [telefone, *[_texto(args.get(q["chave"])) for q in f["params"]]]
        saida = json.dumps(banco.rodar_do_fluxo(conn, f["sql"], valores), ensure_ascii=False, default=str)
        if nome == "guardar_indicacao" and encaminhar and _texto(args.get("contato")).strip():
            # com o telefone do indicado em mãos, a indicação segue na hora para quem cuida (sem esperar relatório)
            completa = banco.linhas(conn, INDICACAO_COMPLETA, (telefone,))
            if completa:
                encaminhar(texto_da_indicacao(completa[0], telefone, nome_do_dono))
        return saida
    except Exception as e:  # noqa: BLE001 -- o modelo precisa saber que não gravou
        return "ERRO: " + str(e).strip().splitlines()[0][:300]
