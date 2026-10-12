"""As ferramentas do agente da captação.

Seis vêm do fluxo do n8n, sem tocar (`ferramentas.json`, gerado por scripts/extrair_ferramentas.py): o nome, a
descrição que o modelo lê e o SQL que roda. O primeiro parâmetro de todo SQL é o telefone do proprietário.

O que é do serviço:
  escalar_ao_tel     no n8n era um sub-fluxo; aqui grava a escalada (o mesmo SQL) e devolve a ordem de calar;
  guardar_indicacao  NOVA (Pedro, 08/10): quem ele indicou que está vendendo um imóvel;
  encerrar_conversa  ganha uma parede antes: não encerra enquanto a pergunta da indicação não tiver saído
                     (menos opt_out e número errado). A parede dos outros imóveis continua sendo a do banco.
  guardar_honorarios NOVA (Pedro, 09/10): a ÚLTIMA pergunta, depois da indicação -- "no valor de R$ X já estão
                     inclusos os 6% de honorários?" (324). Só existe quando há valor de venda; mesma parede.
  guardar_situacao   é do fluxo, mas ganha aqui dois campos (325): `inicio` e `duracao` do contrato. Quando ele diz
                     QUANDO alugou, a pergunta deixa de ser "até quando vai" e vira "de quanto tempo é o contrato";
                     com os dois, o serviço faz a conta e entrega o fim ao fluxo como `prazo` (captacao/contrato.py).
"""
from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path

from captacao import banco, contrato, venda
from captacao.turno import MANAUS

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
HONORARIOS = {
    "nome": "guardar_honorarios",
    "descricao": ("Grava o que o proprietario respondeu sobre os 6% de honorarios de corretagem no valor de venda "
                  "(incluso no valor, por fora, ou o que ele disse). CHAME logo depois que ele responder essa pergunta. "
                  "Devolve instrucao_para_voce: obedeca e nunca mostre esse texto a ele."),
    "sql": "SELECT captacao_honorarios_guardar($1::text, $2::text) AS instrucao_para_voce",
    "params": [
        {"chave": "resposta", "descricao": "o que ele respondeu sobre os honorarios, como ele escreveu", "opcional": False},
    ],
}
# os dois campos que o serviço acrescenta ao guardar_situacao do fluxo (o SQL do fluxo continua com os três dele)
CONTRATO_EXTRAS = [
    {"chave": "inicio", "opcional": True,
     "descricao": ("QUANDO o contrato de locacao COMECOU (quando ele alugou), nas palavras dele: 'fevereiro', 'marco do ano "
                   "passado', '02/2026'. Vazio se ele nao disse. NAO e ate quando vai: isso e o campo prazo.")},
    {"chave": "duracao", "opcional": True,
     "descricao": ("a DURACAO do contrato de locacao, nas palavras dele: '12 meses', '2 anos', '30 meses'. Vazio se ele nao "
                   "disse.")},
]
CONTRATO_NA_DESCRICAO = (" Se ele disser QUANDO alugou em vez de ate quando vai, passe isso em inicio (e deixe prazo "
                         "vazio); quando disser de quanto tempo e o contrato, passe em duracao. O sistema faz a conta do "
                         "fim do contrato: voce nao calcula.")
TODAS = {f["nome"]: f for f in [*DO_FLUXO, INDICACAO, HONORARIOS]}
TODAS["guardar_situacao"] = {**TODAS["guardar_situacao"], "extras": CONTRATO_EXTRAS,
                             "descricao": TODAS["guardar_situacao"]["descricao"] + CONTRATO_NA_DESCRICAO}
# as duas frases do fluxo que mandam perguntar pelo FIM do contrato; saem quando a pergunta certa é outra
PERGUNTAS_DO_FIM = (". agora pergunte ate quando vai o contrato de locacao.", ". ele deu so o ano: peca o mes.")
SEM_PAREDE_DA_INDICACAO = {"opt_out", "numero_errado"}


def definicoes() -> list[dict]:
    """As ferramentas no formato da API de Responses."""
    return [{
        "type": "function", "name": f["nome"], "description": f["descricao"],
        "parameters": {"type": "object",
                       "properties": {q["chave"]: {"type": "string", "description": q["descricao"]}
                                      for q in [*f["params"], *f.get("extras", [])]},
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


def _parede_dos_honorarios(conn, telefone: str, motivo: str) -> str | None:
    """A última pergunta (324): os 6% no valor de venda. None quando já saiu ou não se aplica (sem valor de venda)."""
    if motivo.strip().lower() in SEM_PAREDE_DA_INDICACAO:
        return None
    r = banco.linhas(conn, "SELECT captacao_honorarios_pendente(%s) AS frase", (telefone,))
    if not r or not r[0]["frase"]:
        return None
    return ("NAO encerrei: falta a ultima pergunta, a dos honorarios. Faca agora, em UMA mensagem so e com EXATAMENTE "
            f'estas palavras: "{r[0]["frase"]}" -- e espere a resposta. Quando ele responder, chame guardar_honorarios '
            "com o que ele disse e depois encerrar_conversa de novo.")


def _guardar_situacao(conn, f: dict, args: dict, telefone: str, hoje=None) -> list[dict]:
    """guardar_situacao com o começo e a duração do contrato (325; Pedro, 09/10: "quando o proprietário disser que foi
    contratado em uma data ela não pergunta até quando vai e sim quanto tempo é a duração do contrato").

    Sem `inicio` nem `duracao`, é a ferramenta do fluxo, igual. Com um deles e sem `prazo`: guarda o que ele disse,
    junta com o que já tinha dito e, com os dois, entrega ao fluxo o fim do contrato já calculado. Faltando um, troca a
    pergunta que o fluxo mandaria fazer ("até quando vai") pela que falta."""
    situacao, prazo, valor = (_texto(args.get(k)).strip() for k in ("situacao", "prazo", "valor"))
    inicio, duracao = _texto(args.get("inicio")).strip(), _texto(args.get("duracao")).strip()
    pedir = None
    if not prazo and (inicio or duracao):
        dito = contrato.lembrar(conn, telefone, inicio, duracao)
        feito, pedir = contrato.prazo_ou_pergunta(dito["inicio"], dito["duracao"], hoje or datetime.now(MANAUS).date())
        prazo = feito or ""
    if not (situacao or prazo or valor):
        # só o começo, ou só a duração: o fluxo ainda não tem o que gravar; a pergunta que falta sai daqui
        return [{"instrucao_para_voce": "anotado. " + (pedir or "")}]
    linhas = banco.rodar_do_fluxo(conn, f["sql"], [telefone, situacao, prazo, valor])
    # imóvel que anunciamos para VENDA: nada de "valor para locação"; confirma o valor do cadastro (12/10, venda.py)
    linhas = venda.no_lugar_da_locacao(linhas, venda.do_cadastro(conn, banco, telefone), venda.sem_imovel(conn, banco, telefone))
    if pedir:
        for linha in linhas:
            texto = linha.get("instrucao_para_voce")
            if isinstance(texto, str):
                for frase in PERGUNTAS_DO_FIM:
                    texto = texto.replace(frase, ".")
                linha["instrucao_para_voce"] = texto + " " + pedir
    return linhas


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
            # primeiro a indicação, por último os honorários (Pedro, 09/10: "mais uma pergunta no final, sempre")
            parede = (_parede_da_indicacao(conn, telefone, _texto(args.get("motivo")))
                      or _parede_dos_honorarios(conn, telefone, _texto(args.get("motivo"))))
            if parede:
                return json.dumps([{"instrucao_para_voce": parede}], ensure_ascii=False)
        if nome == "guardar_situacao":
            return json.dumps(_guardar_situacao(conn, f, args, telefone), ensure_ascii=False, default=str)
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
