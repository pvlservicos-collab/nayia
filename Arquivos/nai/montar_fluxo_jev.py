# -*- coding: utf-8 -*-
"""Poe o Jev no lugar da mente. Uso: montar_fluxo_jev.py atual.json novo.json

Tel, 24/09/2026: "quero implementar o jev como processador de mensagem para
interpretar melhor a imagem, ele e como a nay mestre, ele vai substituir ela na
selecao de agentes que ele chama e compreensao de mensagem".

O QUE SAI: "Montar pergunta da mente" -> "Mente da Nay" -> "Ler decisao da
mente" -- um modelo de texto escrevendo um JSON. Foi assim que a mente passou
dois dias mandando venda para a secretaria.

O QUE ENTRA: "Montar pergunta ao Jev" -> "Jev decide" -> "Ler o Jev" -- o
mesmo caminho, mas a resposta vem TIPADA, com probabilidade por pergunta. O
"Decidir quem responde" passa a chamar `nai_decidir_com_jev`, que compara com
os pisos guardados em `nai_config`.

A CHAVE NAO ENTRA AQUI. O no usa a credencial "OpenRouter (Jev)", que ja esta
guardada (e cifrada) dentro do n8n. Este arquivo pode ir para o repositorio.

SE O JEV CAIR, o fluxo nao para: o no tem onError, e o "Ler o Jev" devolve uma
decisao de reserva a partir do proprio texto -- e a conferencia do banco (117)
ainda corrige por cima.
"""
import io, json, sys

CRED_JEV = {"httpHeaderAuth": {"id": "openrouterJev01", "name": "OpenRouter (Jev)"}}

PERGUNTAS = {
    "atendente": {
        "type": "choice",
        "instructions": "Quem deve responder esta mensagem de um corretor parceiro?",
        "criteria": {
            "imoveis": ("Qualquer assunto sobre imovel do NOSSO catalogo: pedir card, foto, "
                        "codigo, valor, disponibilidade, condominio, bairro, perfil de cliente, "
                        "agendar ou remarcar visita, resultado de visita, documentacao da "
                        "locacao, parceria. VENDA E LOCACAO, as duas."),
            "secretaria": ("Ele esta OFERECENDO um imovel DELE, quer cadastrar ou anunciar um "
                           "imovel dele com a gente, ou o assunto nao e imovel: recado, duvida "
                           "sobre a imobiliaria, cobranca, reclamacao, assunto pessoal."),
        },
    },
    "oferta": {
        "type": "noul",
        "instructions": "A pessoa esta oferecendo um imovel DELA para a imobiliaria?",
        "criteria": {
            "true": "Diz que tem um imovel e quer enviar, cadastrar ou anunciar com a gente.",
            "false": "Esta perguntando sobre imovel nosso, ou falando de outra coisa.",
        },
    },
    "cortesia": {
        "type": "noul",
        "instructions": "A mensagem e apenas cortesia, sem assunto novo?",
        "criteria": {
            "true": "So agradecimento, confirmacao ou saudacao: ok, obrigado, bom dia, blz.",
            "false": "Tem pergunta, pedido ou informacao nova.",
        },
    },
    "tipo": {
        "type": "choice",
        "instructions": "Que tipo de imovel a pessoa procura nesta mensagem?",
        "criteria": {
            "casa": "Casa ou casa de condominio.",
            "apartamento": "Apartamento, cobertura ou flat.",
            "outro": "Terreno, lote, sala, loja, galpao, predio, chacara.",
            "nao_disse": "Nao da para saber pelo texto.",
        },
    },
    "finalidade": {
        "type": "choice",
        "instructions": "A pessoa procura comprar ou alugar?",
        "criteria": {
            "venda": "Compra, venda, ou valor acima de cem mil reais.",
            "locacao": "Aluguel, locacao, ou valor mensal.",
            "nao_disse": "Nao da para saber pelo texto.",
        },
    },
    "o_que_mandou": {
        "type": "choice",
        "instructions": "O que a pessoa mandou nas imagens ou arquivos?",
        "criteria": {
            "anuncio_dele": "Fotos ou print de um imovel DELE, que ele quer oferecer.",
            "documento": "Documento, contrato, comprovante, ficha, print de conversa.",
            "duvida_sobre_nosso": "Foto de um imovel NOSSO, perguntando algo sobre ele.",
            "nao_da_para_saber": "Nao veio imagem, ou nao da para dizer pelo que veio.",
        },
    },
}


def main():
    d = json.load(io.open(sys.argv[1], encoding="utf-8"))
    w = d[0] if isinstance(d, list) else d
    nos = {n["name"]: n for n in w["nodes"]}

    # ---- 1. o estado que vai ao Jev -------------------------------------
    nos["Montar pergunta da mente"].update({
        "name": "Montar pergunta ao Jev",
        "parameters": {"jsCode": (
            "// O ESTADO E O QUE O JEV LE (24/09). Ele nao le imagem: le isto.\n"
            "// Por isso a descricao que o GPT fez da foto e a transcricao do audio\n"
            "// entram aqui -- medido: sem a descricao ele responde 'nao da para\n"
            "// saber' com 100% de certeza, que e o certo; com ela, reconhece\n"
            "// 'anuncio dele' e 'documento'.\n"
            "const base = $json;\n"
            "const j = $('Juntar mensagens').first().json || {};\n"
            "const cab = $('Abrir turno').first().json.cab || {};\n"
            "const texto = String(j.texto || cab.texto || '').slice(0, 1500);\n"
            "\n"
            "let leitura = '';\n"
            "try {\n"
            "  const im = $('Ler imagem (GPT)').all();\n"
            "  if (im && im.length) {\n"
            "    const c = ((im[0].json || {}).choices || [])[0];\n"
            "    leitura = String(((c || {}).message || {}).content || '').trim();\n"
            "  }\n"
            "} catch (e) { leitura = ''; }\n"
            "\n"
            "const estado = {\n"
            "  mensagem: texto || '(sem texto)',\n"
            "  quem_fala: 'corretor parceiro de uma imobiliaria de Manaus',\n"
            "  leitura_das_imagens: leitura || '',\n"
            "  imovel_da_conversa: cab.codigo ? String(cab.codigo) : '',\n"
            "};\n"
            "\n"
            "const corpo = JSON.stringify({\n"
            "  model: 'typesafe/jev-1.13',\n"
            "  state: estado,\n"
            "  questions: " + json.dumps(PERGUNTAS, ensure_ascii=False) + "\n"
            "});\n"
            "return [{ json: Object.assign({}, base, { corpo, texto_lido: texto }) }];"
        )},
    })

    # ---- 2. a chamada ----------------------------------------------------
    nos["Mente da Nay"].update({
        "name": "Jev decide",
        "parameters": {
            "method": "POST",
            "url": "https://openrouter.ai/api/alpha/decisions",
            "authentication": "genericCredentialType",
            "genericAuthType": "httpHeaderAuth",
            "sendBody": True,
            "specifyBody": "json",
            "jsonBody": "={{ $json.corpo }}",
            "options": {"timeout": 25000},
        },
        "credentials": CRED_JEV,
        "onError": "continueRegularOutput",
    })

    # ---- 3. a leitura ----------------------------------------------------
    nos["Ler decisão da mente"].update({
        "name": "Ler o Jev",
        "parameters": {"jsCode": (
            "// O JEV DEVOLVE NUMERO, nao prosa: uma probabilidade por pergunta.\n"
            "// Aqui so se empacota; quem compara com os pisos e o banco, em\n"
            "// `nai_decidir_com_jev` -- para o Tel poder mexer sem deploy.\n"
            "//\n"
            "// SE O JEV CAIR (o no tem onError), nao para nada: vale a reserva\n"
            "// pelo proprio texto, e a conferencia do banco corrige por cima.\n"
            "const j = $json || {};\n"
            "const a = j.answers || {};\n"
            "const tem = Object.keys(a).length > 0;\n"
            "\n"
            "if (!tem) {\n"
            "  const t = String(($('Montar pergunta ao Jev').first().json || {}).texto_lido || '')\n"
            "    .toLowerCase();\n"
            "  const deImovel = /(imovel|imóvel|apartamento|casa|aluguel|loca|venda|visita|foto|dispon|c[oó]digo|condom)/.test(t);\n"
            "  return [{ json: { jev: {}, reserva: true,\n"
            "                    atendente: deImovel ? 'imoveis' : 'secretaria' } }];\n"
            "}\n"
            "\n"
            "return [{ json: { jev: Object.assign({}, a, {\n"
            "  modelo: j.model || null,\n"
            "  custo: (j.usage && j.usage.cost) || null,\n"
            "}), reserva: false } }];"
        )},
    })

    # ---- 4. a decisao no banco -------------------------------------------
    nos["Decidir quem responde"]["parameters"] = {
        "operation": "executeQuery",
        "query": ("-- Quem manda de verdade continua sendo o banco: os pisos estao em\n"
                  "-- `nai_config`, e a conferencia da 117 ainda corrige por cima.\n"
                  "SELECT nai_decidir_com_jev($1::bigint, $2::jsonb) AS atendente,\n"
                  "       (SELECT texto FROM nai_prompt WHERE papel = 'secretaria') AS prompt_secretaria;"),
        "options": {"queryReplacement":
                    "={{ [$('Abrir turno').first().json.cab.turno_id, JSON.stringify($json.jev || {})] }}"},
    }

    # ---- 5. as ligacoes seguem os nomes novos ----------------------------
    c = w["connections"]
    for velho, novo in (("Montar pergunta da mente", "Montar pergunta ao Jev"),
                        ("Mente da Nay", "Jev decide"),
                        ("Ler decisão da mente", "Ler o Jev")):
        if velho in c:
            c[novo] = c.pop(velho)
    for origem in c.values():
        for tipo in origem.values():
            for ramo in tipo:
                for lig in (ramo or []):
                    lig["node"] = {"Montar pergunta da mente": "Montar pergunta ao Jev",
                                   "Mente da Nay": "Jev decide",
                                   "Ler decisão da mente": "Ler o Jev"}.get(lig["node"], lig["node"])

    limpo = {k: w[k] for k in ("id", "name", "nodes", "connections", "settings",
                               "staticData", "pinData", "active") if k in w}
    io.open(sys.argv[2], "w", encoding="utf-8", newline="\n").write(
        json.dumps(limpo, ensure_ascii=False, indent=1))
    print("Jev no lugar da mente | %d nos" % len(w["nodes"]))


if __name__ == "__main__":
    main()
