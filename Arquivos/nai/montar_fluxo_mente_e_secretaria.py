# -*- coding: utf-8 -*-
"""Poe a mente mestra, a Nay secretaria e a leitura de midia robusta no fluxo.

Le o export do `NaiAtendLocacao1`, acrescenta os nos e devolve o JSON pronto
para importar. Nao apaga nada: o caminho de locacao continua o mesmo, e a
mente so desvia quando `nai_config.secretaria_ligada` estiver em 'sim' --
quem decide isso e o banco, dentro de `nai_mente_registrar`.

    python3 montar_fluxo_mente_e_secretaria.py w.json w_novo.json
"""
import io, json, sys, uuid

CRED_PG    = {"postgres": {"id": "iR8sKG7vjnpQSWio", "name": "Banco Nay"}}
CRED_OPENAI = {"openAiApi": {"id": "CzrQhGemsCI4hLUh", "name": "OpenAI account"}}
MODELO_CONVERSA = "gpt-5.6-sol"     # o mesmo da Nay de locacao
MODELO_MENTE    = "gpt-4o-mini"     # a mente so escolhe o caminho

TURNO = "$('Abrir turno').first().json.cab.turno_id"


def nid():
    return str(uuid.uuid4())


def carregar(caminho):
    d = json.load(io.open(caminho, encoding="utf-8"))
    return d[0] if isinstance(d, list) else d


def no(nome, tipo, versao, parametros, **extra):
    n = {"parameters": parametros, "name": nome, "type": tipo,
         "typeVersion": versao, "id": nid(), "position": extra.pop("position", [0, 0])}
    n.update(extra)
    return n


def ferramenta(nome, descricao, sql, args, posicao):
    return no(nome, "n8n-nodes-base.postgresTool", 2.7, {
        "descriptionType": "manual",
        "toolDescription": descricao,
        "operation": "executeQuery",
        "query": sql,
        "options": {"queryReplacement": "={{ [" + ", ".join(args) + "] }}"},
    }, position=posicao, credentials=CRED_PG)


def ligar(w, de, para, tipo="main", saida=0):
    c = w["connections"].setdefault(de, {})
    ramos = c.setdefault(tipo, [])
    while len(ramos) <= saida:
        ramos.append([])
    ramos[saida].append({"node": para, "type": tipo, "index": 0})


def desligar(w, de, para, tipo="main"):
    for ramo in w["connections"].get(de, {}).get(tipo, []):
        for i, x in enumerate(list(ramo or [])):
            if x["node"] == para:
                ramo.pop(i)


def achar(w, nome):
    for n in w["nodes"]:
        if n["name"] == nome:
            return n
    raise SystemExit("no nao encontrado: " + nome)


# =====================================================================
# 1. A MIDIA: baixar o arquivo e mandar o PROPRIO arquivo ao GPT
# =====================================================================
def midia(w):
    # a) cada mensagem guarda a url da sua midia
    f = achar(w, "Filtrar e normalizar")
    js = f["parameters"]["jsCode"]
    if "midia_url" not in js:
        alvo = "let origem = 'texto';"
        assert alvo in js, "nao achei o ponto da origem"
        antes = (
            "// A URL DA MIDIA FICA NA LINHA DA MENSAGEM (22/09). O ramo que le a\n"
            "// imagem so enxerga UMA midia -- a do webhook que ganhou a janela --,\n"
            "// entao de cinco fotos quatro se perdiam. Guardada aqui, o turno inteiro\n"
            "// tem todas: `msg_ids` ja aponta para elas.\n"
            "const midiaUrl = (b.image && (b.image.imageUrl || b.image.url))\n"
            "  || (b.audio && b.audio.audioUrl)\n"
            "  || (b.document && (b.document.documentUrl || b.document.url))\n"
            "  || (b.video && (b.video.videoUrl || b.video.url)) || null;\n")
        js = js.replace(alvo, antes + alvo)
        js = js.replace("  origem: origem,", "  origem: origem,\n  midia_url: midiaUrl,")
        f["parameters"]["jsCode"] = js

    # b) e a fila grava
    g = achar(w, "Gravar na fila")
    q = g["parameters"]["query"]
    if "midia_url" not in q:
        q = q.replace("fluxo, message_id)", "fluxo, message_id, midia_url)")
        q = q.replace("'nai', NULLIF($8, 'null'))", "'nai', NULLIF($8, 'null'), NULLIF($9, 'null'))")
        g["parameters"]["query"] = q
        r = g["parameters"]["options"]["queryReplacement"]
        g["parameters"]["options"]["queryReplacement"] = r.replace(
            "$json.message_id ?? null]", "$json.message_id ?? null, $json.midia_url ?? null]")

    # c) baixar a imagem e mandar o arquivo, em vez da url
    if any(n["name"] == "Baixar imagem" for n in w["nodes"]):
        return
    w["nodes"].append(no("Baixar imagem", "n8n-nodes-base.httpRequest", 4.2, {
        "url": "={{ $json.midia_url }}",
        "options": {"timeout": 25000,
                    "response": {"response": {"responseFormat": "file"}}},
    }, position=[1120, 700], onError="continueRegularOutput"))

    w["nodes"].append(no("Montar leitura da imagem", "n8n-nodes-base.code", 2, {
        "jsCode": (
            "// O GPT LE O ARQUIVO, NAO A URL (22/09).
"
            "// Mandando a url da Z-API, quem precisa alcancar a foto e a OpenAI --
"
            "// e midia de WhatsApp expira e as vezes nem abre de fora. Baixando aqui
"
            "// (como o audio ja fazia) e mandando o arquivo, a leitura nao depende de
"
            "// ninguem alcancar nada.
"
            "//
"
            "// O BINARIO NAO ESTA EM `binary.data.data` (medido em 22/09). Este n8n
"
            "// guarda arquivo em DISCO: aquele campo vem com a etiqueta
"
            "// 'filesystem-v2', e foi exatamente isso que viajou para a OpenAI --
"
            "// 'data:image/png;base64,filesystem-v2' --, que respondeu 'you uploaded
"
            "// an unsupported image'. Quem traz os bytes e o helper abaixo.
"
            "const ent = $('Detectar imagem').first().json;
"
            "const OK = ['image/png', 'image/jpeg', 'image/gif', 'image/webp'];
"
            "let b64 = '', mime = 'image/jpeg';
"
            "try {
"
            "  const bin = $input.first().binary || {};
"
            "  const chave = bin.data ? 'data' : Object.keys(bin)[0];
"
            "  const d = bin[chave] || {};
"
            "  if (OK.indexOf(String(d.mimeType || '')) >= 0) { mime = d.mimeType; }
"
            "  const buf = await this.helpers.getBinaryDataBuffer(0, chave);
"
            "  b64 = buf.toString('base64');
"
            "} catch (e) { b64 = ''; }
"
            "const corpo = JSON.parse(ent.corpo);
"
            "// Sem o arquivo na mao, volta a valer a url: pior ler pela url do que
"
            "// nao ler.
"
            "if (b64) {
"
            "  corpo.messages[0].content[1].image_url.url = 'data:' + mime + ';base64,' + b64;
"
            "}
"
            "return [{ json: Object.assign({}, ent, { corpo: JSON.stringify(corpo),
"
            "                                        veio_arquivo: !!b64,
"
            "                                        bytes_lidos: b64.length }) }];"
        )}, position=[1240, 700]))

    desligar(w, "Detectar imagem", "Ler imagem (GPT)")
    ligar(w, "Detectar imagem", "Baixar imagem")
    ligar(w, "Baixar imagem", "Montar leitura da imagem")
    ligar(w, "Montar leitura da imagem", "Ler imagem (GPT)")
    achar(w, "Ler imagem (GPT)")["position"] = [1380, 700]


# =====================================================================
# 2. A MENTE MESTRA
# =====================================================================
REGRA_DA_MENTE = (
    "Voce e a mente da Nay, a atendente da Imob Easy, uma imobiliaria de Manaus. "
    "Voce NAO responde ninguem: voce so escolhe quem responde.\n\n"
    "LOCACAO -- a atendente de imoveis. Tudo que for sobre imovel NOSSO: pedir "
    "card, foto, codigo, valor, disponibilidade, condominio, bairro, perfil de "
    "cliente, agendar ou remarcar visita, resultado de visita, documentacao da "
    "locacao, parceria, e conversa fiada no meio de um desses assuntos.\n\n"
    "SECRETARIA -- a secretaria. O que sobra: o corretor que OFERECE um imovel "
    "dele (\"tenho um apartamento, se quiser te envio\"), quem quer cadastrar "
    "imovel com a gente, duvida geral sobre a imobiliaria, recado, assunto "
    "pessoal, cobranca, reclamacao, e qualquer coisa que a de locacao nao "
    "saberia atender.\n\n"
    "Na duvida, escolha LOCACAO: e o caminho que esta pronto.\n\n"
    "Responda SO um JSON, sem mais nada:\n"
    "{\"atendente\":\"locacao\",\"motivo\":\"em ate 8 palavras\"}"
)


def mente(w):
    if any(n["name"] == "Mente da Nay" for n in w["nodes"]):
        return

    w["nodes"].append(no("Precisa da mente?", "n8n-nodes-base.if", 2.2, {
        "conditions": {
            "options": {"caseSensitive": True, "leftValue": "", "typeValidation": "strict", "version": 2},
            "conditions": [{
                "id": nid(),
                "leftValue": "={{ $json.rota }}",
                "rightValue": "agente",
                "operator": {"type": "string", "operation": "equals"},
            }],
            "combinator": "and",
        },
        "options": {},
    }, position=[1500, 300]))

    w["nodes"].append(no("Montar pergunta da mente", "n8n-nodes-base.code", 2, {
        "jsCode": (
            "// ELA LE O BLOCO INTEIRO (Tel, 22/09: \"nao toda uma mensagem a cada e\n"
            "// sim espera um minuto para ver se o cliente ja digitou e ela le todo o\n"
            "// bloco\"). Isso ja esta garantido: este no roda depois da janela, com o\n"
            "// texto que o \"Juntar mensagens\" costurou.\n"
            "const base = $json;\n"
            "const j = $('Juntar mensagens').first().json || {};\n"
            "const cab = $('Abrir turno').first().json.cab || {};\n"
            "const texto = String(j.texto || cab.texto || '').slice(0, 1500);\n"
            "const corpo = JSON.stringify({\n"
            "  model: " + json.dumps(MODELO_MENTE) + ",\n"
            "  max_tokens: 80,\n"
            "  messages: [\n"
            "    { role: 'system', content: " + json.dumps(REGRA_DA_MENTE) + " },\n"
            "    { role: 'user', content: texto || '(sem texto: so midia)' }\n"
            "  ]\n"
            "});\n"
            "return [{ json: Object.assign({}, base, { corpo, texto_da_mente: texto }) }];"
        )}, position=[1640, 460]))

    w["nodes"].append(no("Mente da Nay", "n8n-nodes-base.httpRequest", 4.2, {
        "method": "POST",
        "url": "https://api.openai.com/v1/chat/completions",
        "authentication": "predefinedCredentialType",
        "nodeCredentialType": "openAiApi",
        "sendBody": True,
        "specifyBody": "json",
        "jsonBody": "={{ $json.corpo }}",
        "options": {"timeout": 20000},
    }, position=[1800, 460], credentials=CRED_OPENAI, onError="continueRegularOutput"))

    w["nodes"].append(no("Ler decisão da mente", "n8n-nodes-base.code", 2, {
        "jsCode": (
            "// A mente pode falhar (o no tem onError): sem resposta, o caminho e o de\n"
            "// locacao -- o que ja funciona. Nenhuma mensagem fica sem dono.\n"
            "let atendente = 'locacao', motivo = 'sem resposta da mente';\n"
            "try {\n"
            "  const j = $json || {};\n"
            "  const bruto = ((j.choices || [])[0] || {}).message || {};\n"
            "  const txt = String(bruto.content || '').trim();\n"
            "  const m = txt.match(/\\{[\\s\\S]*\\}/);\n"
            "  if (m) {\n"
            "    const d = JSON.parse(m[0]);\n"
            "    if (String(d.atendente || '').toLowerCase() === 'secretaria') atendente = 'secretaria';\n"
            "    motivo = String(d.motivo || '').slice(0, 120) || 'sem motivo';\n"
            "  }\n"
            "} catch (e) { motivo = 'decisao ilegivel'; }\n"
            "return [{ json: { atendente, motivo } }];"
        )}, position=[1960, 460]))

    w["nodes"].append(no("Decidir quem responde", "n8n-nodes-base.postgres", 2.6, {
        "operation": "executeQuery",
        "query": ("-- Quem manda de verdade e o banco: com `secretaria_ligada` = 'nao',\n"
                  "-- `nai_mente_registrar` devolve 'locacao' aconteca o que acontecer.\n"
                  "SELECT nai_mente_registrar($1::bigint, $2, $3, 'mente') AS atendente,\n"
                  "       (SELECT texto FROM nai_prompt WHERE papel = 'secretaria') AS prompt_secretaria;"),
        "options": {"queryReplacement":
                    "={{ [" + TURNO + ", $json.atendente, $json.motivo] }}"},
    }, position=[2120, 460], credentials=CRED_PG))

    w["nodes"].append(no("Rota da mente", "n8n-nodes-base.code", 2, {
        "jsCode": (
            "// Devolve o MESMO item que o roteador montou, so trocando a rota: os nos\n"
            "// de baixo leem campos dele.\n"
            "const base = $('Rotear pelo cabeçalho').first().json;\n"
            "const d = $('Decidir quem responde').first().json || {};\n"
            "const at = d.atendente === 'secretaria' ? 'secretaria' : 'agente';\n"
            "return [{ json: Object.assign({}, base, { rota: at, atendente: d.atendente }) }];"
        )}, position=[2280, 460]))

    # o roteador passa a falar com o IF, e o IF com o switch
    desligar(w, "Rotear pelo cabeçalho", "Qual caminho?")
    ligar(w, "Rotear pelo cabeçalho", "Precisa da mente?")
    ligar(w, "Precisa da mente?", "Montar pergunta da mente", saida=0)   # e 'agente'
    ligar(w, "Precisa da mente?", "Qual caminho?", saida=1)              # o resto passa direto
    ligar(w, "Montar pergunta da mente", "Mente da Nay")
    ligar(w, "Mente da Nay", "Ler decisão da mente")
    ligar(w, "Ler decisão da mente", "Decidir quem responde")
    ligar(w, "Decidir quem responde", "Rota da mente")
    ligar(w, "Rota da mente", "Qual caminho?")

    # o switch ganha a saida da secretaria
    sw = achar(w, "Qual caminho?")
    regras = sw["parameters"]["rules"]["values"]
    if not any(r.get("outputKey") == "secretaria" for r in regras):
        regras.append({
            "conditions": {
                "options": {"caseSensitive": True, "leftValue": "", "typeValidation": "strict", "version": 2},
                "conditions": [{
                    "id": nid(),
                    "leftValue": "={{ $json.rota }}",
                    "rightValue": "secretaria",
                    "operator": {"type": "string", "operation": "equals"},
                }],
                "combinator": "and",
            },
            "renameOutput": True,
            "outputKey": "secretaria",
        })


# =====================================================================
# 3. A NAY SECRETARIA
# =====================================================================
TEXTO_DA_SECRETARIA = (
    "=(informação de sistema, não repita isso a ele) agora em Manaus é "
    "{{ $now.setZone('America/Manaus').setLocale('pt-BR').toFormat('cccc dd/MM/yyyy HH:mm') }}. "
    "{{ $('Abrir turno').first().json.cab.vocativo ? 'trate por: ' + $('Abrir turno').first().json.cab.vocativo + '. ' : '' }}"
    "{{ $('Juntar mensagens').first().json.qtd > 1 ? 'ele mandou ' + $('Juntar mensagens').first().json.qtd + ' mensagens neste intervalo, juntas abaixo: responda TODAS. ' : '' }}"
    "{{ $('Fotos do cadastro').first().json.n > 0 ? 'ele mandou ' + $('Fotos do cadastro').first().json.n + ' foto(s), e elas ja entraram na ficha do imovel dele: nao peca de novo. ' : '' }}"
    "\n\n{{ $('Juntar mensagens').first().json.texto }}"
)


def secretaria(w):
    if any(n["name"] == "NAI (secretária)" for n in w["nodes"]):
        return
    y = 1700

    w["nodes"].append(no("Fotos do cadastro", "n8n-nodes-base.postgres", 2.6, {
        "operation": "executeQuery",
        "query": ("-- As fotos do turno viram fotos da ficha aberta. Sem ficha aberta,\n"
                  "-- devolve 0 e nada acontece.\n"
                  "SELECT nai_sec_guardar_fotos_do_turno($1::bigint) AS n;"),
        "options": {"queryReplacement": "={{ [" + TURNO + "] }}"},
    }, position=[1750, y], credentials=CRED_PG))

    w["nodes"].append(no("NAI (secretária)", "@n8n/n8n-nodes-langchain.agent", 3.1, {
        "promptType": "define",
        "text": TEXTO_DA_SECRETARIA,
        "options": {
            "systemMessage": ("={{ (() => {\n"
                              "  const p = $('Decidir quem responde').first().json?.prompt_secretaria;\n"
                              "  if (typeof p === 'string' && p.trim().length > 300) return p;\n"
                              "  throw new Error('PROMPT_VAZIO: nai_prompt da secretaria nao veio do banco');\n"
                              "})() }}"),
            "returnIntermediateSteps": True,
        },
    }, position=[1950, y]))

    w["nodes"].append(no("GPT (secretária)", "@n8n/n8n-nodes-langchain.lmChatOpenAi", 1.3, {
        "model": {"__rl": True, "value": MODELO_CONVERSA, "mode": "list",
                  "cachedResultName": MODELO_CONVERSA},
        "builtInTools": {}, "options": {},
    }, position=[1850, y + 220], credentials=CRED_OPENAI))

    w["nodes"].append(no("Memória (secretária)", "@n8n/n8n-nodes-langchain.memoryPostgresChat", 1.4, {
        "sessionIdType": "customKey",
        # DOIS CONTEXTOS SEPARADOS (Tel, 22/09). A memoria da secretaria e
        # outra: ela nao ve a conversa de imovel, e a de locacao nao ve a dela.
        "sessionKey": "={{ $('Abrir turno').first().json.cab.memoria }}-sec",
        "tableName": "nai_memoria",
        "contextWindowLength": 20,
    }, position=[2010, y + 220], credentials=CRED_PG))

    ferramentas = [
        ("consultar_o_que_sei",
         "O que o Tel ja me ensinou sobre isso.\n"
         "Use SEMPRE que ele perguntar alguma coisa, antes de qualquer outra coisa.\n"
         "Arg: pergunta (nas palavras dele).",
         "SELECT texto_pronto, instrucao_para_voce FROM nai_sec_consultar($1::bigint, $2);",
         [TURNO, "$fromAI('pergunta', 'o que ele quer saber, nas palavras dele', 'string') ?? null"]),
        ("perguntar_ao_tel",
         "Manda a pergunta dele para o Tel e avisa que voce ja responde.\n"
         "Use quando consultar_o_que_sei nao souber.\n"
         "Arg: pergunta (nas palavras dele).",
         "SELECT texto_pronto, instrucao_para_voce FROM nai_sec_perguntar_ao_tel($1::bigint, $2);",
         [TURNO, "$fromAI('pergunta', 'a pergunta dele, nas palavras dele', 'string') ?? null"]),
        ("abrir_cadastro_de_imovel",
         "Abre a ficha do imovel que ELE esta oferecendo e devolve a proxima pergunta.\n"
         "Use quando ele disser que tem um imovel para mandar.\n"
         "Sem argumento.",
         "SELECT texto_pronto, instrucao_para_voce FROM nai_sec_abrir_cadastro($1::bigint);",
         [TURNO]),
        ("guardar_do_imovel_novo",
         "Guarda o que ele respondeu sobre o imovel dele e devolve a proxima pergunta.\n"
         "Mande so o que ele disse nesta mensagem; o resto deixe vazio.\n"
         "Args: tipo, finalidade, condominio, bairro, quartos, valor, mobilia, descricao.",
         ("SELECT texto_pronto, instrucao_para_voce FROM nai_sec_guardar_do_imovel("
          "$1::bigint, $2, $3, $4, $5, $6, NULL, NULL, NULL, $7, NULL, $8, $9);"),
         [TURNO,
          "$fromAI('tipo', 'apartamento, casa, terreno...', 'string') ?? null",
          "$fromAI('finalidade', 'venda ou locacao', 'string') ?? null",
          "$fromAI('condominio', 'o nome do condominio', 'string') ?? null",
          "$fromAI('bairro', 'o bairro', 'string') ?? null",
          "$fromAI('quartos', 'quantos quartos', 'string') ?? null",
          "$fromAI('valor', 'o valor que ele pediu', 'string') ?? null",
          "$fromAI('mobilia', 'mobiliado, semimobiliado ou vazio', 'string') ?? null",
          "$fromAI('descricao', 'o que ele contou do imovel, nas palavras dele', 'string') ?? null"]),
    ]
    for i, (nome, desc, sql, args) in enumerate(ferramentas):
        w["nodes"].append(ferramenta(nome, desc, sql, args, [2170 + i * 170, y + 220]))
        ligar(w, nome, "NAI (secretária)", tipo="ai_tool")

    w["nodes"].append(no("Resposta da secretária", "n8n-nodes-base.code", 2, {
        "jsCode": (
            "// A caixa de saida e a MESMA da Nay de locacao: quem divide o texto em\n"
            "// mensagens, guarda e libera o envio ja esta pronto ali.\n"
            "const a = $('NAI (secretária)').first().json || {};\n"
            "const j = $('Juntar mensagens').first().json || {};\n"
            "return [{ json: {\n"
            "  texto: String(a.output || '').trim(),\n"
            "  codigos: [],\n"
            "  escreveu: j.texto || '',\n"
            "  fotos_site: []\n"
            "} }];"
        )}, position=[2600, y]))

    ligar(w, "GPT (secretária)", "NAI (secretária)", tipo="ai_languageModel")
    ligar(w, "Memória (secretária)", "NAI (secretária)", tipo="ai_memory")
    ligar(w, "Fotos do cadastro", "NAI (secretária)")
    ligar(w, "NAI (secretária)", "Resposta da secretária")
    ligar(w, "Resposta da secretária", "Enfileirar resposta")

    # a saida nova do switch (a ultima regra) vai para a secretaria
    sw = achar(w, "Qual caminho?")
    saida = len(sw["parameters"]["rules"]["values"]) - 1
    ligar(w, "Qual caminho?", "Fotos do cadastro", saida=saida)


def main():
    entrada, saida = sys.argv[1], sys.argv[2]
    w = carregar(entrada)
    midia(w)
    mente(w)
    secretaria(w)
    # O `id` VAI JUNTO: sem ele o `import:workflow` cria um fluxo NOVO em vez
    # de atualizar o que esta no ar -- e ficariam dois atendendo o mesmo
    # webhook.
    limpo = {k: w[k] for k in ("id", "name", "nodes", "connections", "settings",
                               "staticData", "pinData", "active")
             if k in w}
    io.open(saida, "w", encoding="utf-8", newline="\n").write(
        json.dumps(limpo, ensure_ascii=False, indent=1))
    print("nos: %d | conexoes: %d" % (len(w["nodes"]), len(w["connections"])))


if __name__ == "__main__":
    main()
