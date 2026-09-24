# -*- coding: utf-8 -*-
"""Roda o Jev contra conversas de corretor que JA ACONTECERAM.

    python3 jev_rodada.py ultimas20 20
    python3 jev_rodada.py erros 20 --so-erros

Tel, 24/09/2026: "quero testar o jev das ultimas conversas de corretores que
ela errou no zap, e nas ultimas 20 conversas de corretores".

NADA SAI PARA O WHATSAPP. Le turno gravado, chama o Jev por fora do fluxo e
grava em `nai_jev_rodada`. A Nay continua pausada.

O que a rodada compara:
    jev_disse  -> quem o Jev + os pisos mandariam responder
    aconteceu  -> quem de fato respondeu naquele turno
Divergencia nao e erro do Jev: e o lugar para o Tel olhar.
"""
import json, os, sys, urllib.request

import psycopg2
import psycopg2.extras

# a mesma variavel que o corredor de treino usa (`DATABASE_URL` no ambiente)
BANCO = os.environ.get("DATABASE_URL") or os.environ.get("NAI_DATABASE_URL")
URL = "https://openrouter.ai/api/alpha/decisions"


def chave():
    for linha in open("/root/.openrouter.env"):
        if linha.startswith("OPENROUTER_API_KEY="):
            return linha.split("=", 1)[1].strip()
    raise SystemExit("sem a chave em /root/.openrouter.env")


PERGUNTAS = {
    "atendente": {"type": "choice",
        "instructions": "Quem deve responder esta mensagem de um corretor parceiro?",
        "criteria": {
            "imoveis": ("Qualquer assunto sobre imovel do NOSSO catalogo: pedir card, foto, "
                        "codigo, valor, disponibilidade, condominio, bairro, perfil de cliente, "
                        "agendar ou remarcar visita, resultado de visita, documentacao da "
                        "locacao, parceria. VENDA E LOCACAO, as duas."),
            "secretaria": ("Ele esta OFERECENDO um imovel DELE, quer cadastrar ou anunciar um "
                           "imovel dele com a gente, ou o assunto nao e imovel: recado, duvida "
                           "sobre a imobiliaria, cobranca, reclamacao, assunto pessoal.")}},
    "oferta": {"type": "noul",
        "instructions": "A pessoa esta oferecendo um imovel DELA para a imobiliaria?",
        "criteria": {"true": "Diz que tem um imovel e quer enviar, cadastrar ou anunciar com a gente.",
                     "false": "Esta perguntando sobre imovel nosso, ou falando de outra coisa."}},
    "cortesia": {"type": "noul",
        "instructions": "A mensagem e apenas cortesia, sem assunto novo?",
        "criteria": {"true": "So agradecimento, confirmacao ou saudacao: ok, obrigado, bom dia, blz.",
                     "false": "Tem pergunta, pedido ou informacao nova."}},
    "tipo": {"type": "choice",
        "instructions": "Que tipo de imovel a pessoa procura nesta mensagem?",
        "criteria": {"casa": "Casa ou casa de condominio.",
                     "apartamento": "Apartamento, cobertura ou flat.",
                     "outro": "Terreno, lote, sala, loja, galpao, predio, chacara.",
                     "nao_disse": "Nao da para saber pelo texto."}},
    "finalidade": {"type": "choice",
        "instructions": "A pessoa procura comprar ou alugar?",
        "criteria": {"venda": "Compra, venda, ou valor acima de cem mil reais.",
                     "locacao": "Aluguel, locacao, ou valor mensal.",
                     "nao_disse": "Nao da para saber pelo texto."}},
    "o_que_mandou": {"type": "choice",
        "instructions": "O que a pessoa mandou nas imagens ou arquivos?",
        "criteria": {"anuncio_dele": "Fotos ou print de um imovel DELE, que ele quer oferecer.",
                     "documento": "Documento, contrato, comprovante, ficha, print de conversa.",
                     "duvida_sobre_nosso": "Foto de um imovel NOSSO, perguntando algo sobre ele.",
                     "nao_da_para_saber": "Nao veio imagem, ou nao da para dizer pelo que veio."}},
}


def perguntar(k, texto, leitura, codigo):
    corpo = json.dumps({
        "model": "typesafe/jev-1.13",
        "state": {
            "mensagem": texto or "(sem texto)",
            "quem_fala": "corretor parceiro de uma imobiliaria de Manaus",
            "leitura_das_imagens": leitura or "",
            "imovel_da_conversa": str(codigo or ""),
        },
        "questions": PERGUNTAS,
    }).encode()
    req = urllib.request.Request(URL, data=corpo, headers={
        "Authorization": "Bearer " + k, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def main():
    rodada = sys.argv[1]
    quantos = int(sys.argv[2]) if len(sys.argv) > 2 else 20
    so_erros = "--so-erros" in sys.argv
    k = chave()

    if not BANCO:
        raise SystemExit("faltou DATABASE_URL no ambiente")
    conn = psycopg2.connect(BANCO)
    conn.autocommit = True
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("SELECT * FROM nai_turnos_para_o_jev(%s, %s)", (quantos, so_erros))
    turnos = cur.fetchall()
    print("rodada '%s': %d turnos\n" % (rodada, len(turnos)))

    custo = 0.0
    igual = 0
    for t in turnos:
        d = perguntar(k, t["texto"], "", t["turno_id"])
        a = d.get("answers", {})
        a["modelo"] = d.get("model")
        a["custo"] = (d.get("usage") or {}).get("cost")
        custo += a["custo"] or 0

        cur.execute("SELECT nai_jev_decidiria(%s::jsonb) AS d", (json.dumps(a),))
        jev = cur.fetchone()["d"]
        bateu = jev.startswith(t["atendente"]) or jev.startswith("cortesia")
        igual += bateu

        cur.execute("""INSERT INTO nai_jev_rodada
                       (rodada, turno_id, quem, texto, respostas, jev_disse, aconteceu, bateu, custo)
                       VALUES (%s,%s,%s,%s,%s::jsonb,%s,%s,%s,%s)""",
                    (rodada, t["turno_id"], t["quem"], t["texto"], json.dumps(a),
                     jev, t["atendente"], bateu, a["custo"]))

        print("%s %-20s | jev: %-34s | foi: %-10s | %s" % (
            "  " if bateu else "≠ ", (t["quem"] or "")[:20], jev, t["atendente"],
            (t["texto"] or "").replace("\n", " / ")[:44]))

    print("\n%d de %d bateram com o que aconteceu | custo US$ %.6f" % (igual, len(turnos), custo))
    print("as divergencias (≠) sao o que o Tel precisa olhar")


if __name__ == "__main__":
    main()
