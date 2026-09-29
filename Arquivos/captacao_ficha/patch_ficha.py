# A FICHA DO IMÓVEL NA CONVERSA DA CAPTAÇÃO (Pedro, 28/09/2026: "precisa pedir
# as informações certinhas do imóvel para recadastrar qualquer coisa, ou se ele
# mandar um imóvel novo, cadastrar o imóvel novo dele").
#
# Parte do fluxo VIVO exportado agora (vivo_antes_ficha.json) e confere cada
# trecho antes de trocar -- se o fluxo mudou, o assert para tudo.
#   1. guardar_situacao: disponível + valor abre a ficha (captacao_ficha, 165)
#   2. guardar_outro_imovel: não encerra mais; abre a ficha do imóvel novo
#   3. guardar_ficha: a ferramenta nova (a resposta dele -> a próxima pergunta)
#   4. Reservar mensagens + Juntar mensagens + AI Agent: o aviso de ficha
#      aberta entra em TODO turno (captacao_ficha_aviso)
#   5. Foto do dono? -> Guardar foto na ficha: a foto que ele manda vai para o
#      nosso servidor (a URL da Z-API é temporária) e para a ficha
import copy
import json
import uuid

SRC = "/root/n8n-captacao/fluxos/CjsUJefRYcQIIi1F.vivo_antes_ficha.json"
DST = "/root/n8n-captacao/fluxos/CjsUJefRYcQIIi1F.ficha.json"
CRED_FOTO = {"id": "CaptFotoSite0001", "name": "Captacao fotos (site)"}

d = json.load(open(SRC))
wf = d[0] if isinstance(d, list) else d
N = {n["name"]: n for n in wf["nodes"]}
assert "guardar_ficha" not in N and "Foto do dono?" not in N, "o patch já foi aplicado"


def trocar(texto, velho, novo):
    assert texto.count(velho) == 1, "não achei (ou achei mais de um): " + velho[:80]
    return texto.replace(velho, novo)


# ---------------------------------------------------------------- 1. situação
p = N["guardar_situacao"]["parameters"]
p["query"] = trocar(
    p["query"],
    "            WHEN 'aguardando_outros' THEN '. agora pergunte se ele tem outro imovel para vender ou alugar.'",
    "            -- DISPONIVEL com o valor (28/09, 165): abre a FICHA do imovel, e a\n"
    "            -- primeira pergunta dela vem pronta do banco (captacao_ficha)\n"
    "            WHEN 'aguardando_outros' THEN CASE WHEN situacao = 'disponivel'\n"
    "                 THEN '. ' || captacao_ficha((SELECT telefone FROM e), 'este', jsonb_build_object('valor', valor_locacao_pedido), false)\n"
    "                 ELSE '. agora pergunte se ele tem outro imovel para vender ou alugar.' END")
p["toolDescription"] = trocar(
    p["toolDescription"],
    " Devolve instrucao_para_voce:",
    " Quando o imovel esta DISPONIVEL e ele deu o valor, a resposta traz a primeira pergunta da FICHA DO IMOVEL,"
    " pronta: faca essa pergunta. Devolve instrucao_para_voce:")

# ---------------------------------------------------------------- 2. outro imóvel
p = N["guardar_outro_imovel"]["parameters"]
p["query"] = trocar(
    p["query"],
    "SELECT CASE WHEN EXISTS (SELECT 1 FROM g)\n"
    "  THEN 'gravado. agradeça e encerre a conversa chamando encerrar_conversa.'",
    "-- (28/09, 165) NAO ENCERRA MAIS: abre a FICHA do imovel novo, que devolve a\n"
    "-- proxima pergunta pronta (tipo e local, alugar ou vender, comodos, area,\n"
    "-- valor, taxas, mobilia, fotos -- so o que ele ainda nao disse).\n"
    "SELECT CASE WHEN EXISTS (SELECT 1 FROM g)\n"
    "  THEN 'gravado. ' || captacao_ficha($1::text, 'outro', jsonb_build_object('detalhes', $2::text, 'negocio', $3::text,\n"
    "         'tipo', $4::text, 'bairro', $5::text, 'condominio', $6::text), false)")
p["options"]["queryReplacement"] = (
    "={{ [ $('Juntar mensagens').first().json.telefone, "
    "$fromAI('descricao', 'o outro imovel, nas palavras dele: tipo, condominio ou bairro, quartos, o que ele tiver dito.', 'string'), "
    "$fromAI('negocio', 'venda, locacao ou ambos', 'string') ?? '', "
    "$fromAI('tipo', 'casa, apartamento, sala, terreno... o tipo do imovel, se ele disse. vazio se nao disse.', 'string', '') ?? '', "
    "$fromAI('bairro', 'o bairro do imovel, se ele disse. vazio se nao disse.', 'string', '') ?? '', "
    "$fromAI('condominio', 'o nome do condominio ou do predio, se ele disse. vazio se nao disse.', 'string', '') ?? '' ] }}")
p["toolDescription"] = (
    "Grava um OUTRO imovel que o proprietario disse ter, alem do que estava no cadastro, e ABRE A FICHA desse imovel. "
    "CHAME NA MESMA RESPOSTA em que ele contar. Passe a descricao nas palavras dele, o negocio (venda, locacao ou ambos) e, "
    "se ele disse, o tipo, o bairro e o condominio. A resposta traz a proxima pergunta da ficha, pronta: faca essa pergunta. "
    "Nao chame se ele disse que nao tem outro imovel. Devolve instrucao_para_voce: obedeca e nunca mostre esse texto a ele.")

# ---------------------------------------------------------------- 3. guardar_ficha
f = copy.deepcopy(N["guardar_venda"])
f["id"] = str(uuid.uuid4())
f["name"] = "guardar_ficha"
f["position"] = [2256, 1520]
f["parameters"]["toolDescription"] = (
    "Grava na FICHA DO IMOVEL o que ele respondeu e devolve a proxima pergunta, pronta. CHAME NA MESMA RESPOSTA em que ele "
    "responder uma pergunta da ficha (a ficha abre sozinha: pelo guardar_situacao, quando o imovel esta disponivel, e pelo "
    "guardar_outro_imovel). Passe so o que ele disse, cada coisa no seu campo, nas palavras dele; se ele disse mais do que "
    "voce perguntou, passe tudo. O que ele nao souber ou nao quiser dizer: passe nao sabe no campo perguntado. Fotos: quando "
    "ele mandar, passe fotos = recebidas; se disser que manda depois ou que nao tem, passe o que ele disse. Se ele disser que "
    "nao pode ou nao quer responder mais agora, passe parar = sim. Devolve instrucao_para_voce: obedeca e nunca mostre esse "
    "texto a ele.")
f["parameters"]["query"] = (
    "-- A FICHA DO IMOVEL (28/09, migracoes 164 e 165). Quem escolhe a proxima\n"
    "-- pergunta e o banco, uma por vez, na ordem do roteiro e no tratamento dele:\n"
    "-- nao repete o que ele ja respondeu, e \"nao sei\" conta como resposta. A\n"
    "-- ficha pronta aparece no painel (Captacao WhatsApp) para um humano aplicar.\n"
    "SELECT captacao_ficha($1::text, $2::text, jsonb_build_object(\n"
    "         'tipo', $3::text, 'bairro', $4::text, 'condominio', $5::text, 'negocio', $6::text,\n"
    "         'quartos', $7::text, 'suites', $8::text, 'banheiros', $9::text, 'vagas', $10::text,\n"
    "         'area', $11::text, 'valor', $12::text, 'condominio_valor', $13::text, 'iptu', $14::text,\n"
    "         'incluso', $15::text, 'mobilia', $16::text, 'fotos', $17::text, 'detalhes', $18::text,\n"
    "         'parar', $19::text), true) AS instrucao_para_voce;")
CAMPOS = [
    ("qual", "este = o imovel da campanha, que ficou disponivel; outro = o outro imovel que ele ofereceu; vazio = a ficha que esta aberta"),
    ("tipo", "casa, apartamento, sala, terreno... o tipo do imovel"),
    ("bairro", "o bairro do imovel"),
    ("condominio", "o nome do condominio ou do predio"),
    ("negocio", "alugar, vender ou os dois"),
    ("quartos", "quantos quartos"),
    ("suites", "quantas suites"),
    ("banheiros", "quantos banheiros"),
    ("vagas", "quantas vagas de garagem"),
    ("area", "a area, como ele disse (ex: 80 m2, uns 70 metros)"),
    ("valor", "o valor que ele pede, como ele disse (ex: 2.500, 650 mil)"),
    ("condominio_valor", "a taxa de condominio, como ele disse; incluso se esta dentro do aluguel"),
    ("iptu", "o IPTU, como ele disse; incluso se esta dentro do aluguel"),
    ("incluso", "o que o aluguel ja inclui (agua, internet, condominio, IPTU...); nada se nao inclui nada"),
    ("mobilia", "mobiliado, semimobiliado ou sem mobilia"),
    ("fotos", "recebidas quando ele mandou as fotos; senao o que ele disse (vou mandar depois, nao tenho)"),
    ("detalhes", "outra informacao do imovel que ele contou e nao cabe nos outros campos"),
    ("parar", "sim se ele disse que nao quer ou nao pode responder mais sobre o imovel agora; vazio no resto"),
]
for chave, desc in CAMPOS:
    assert "'" not in desc
f["parameters"]["options"] = {"queryReplacement": "={{ [ $('Juntar mensagens').first().json.telefone, " + ", ".join(
    "$fromAI('%s', '%s', 'string', '') ?? ''" % (chave, desc) for chave, desc in CAMPOS) + " ] }}"}
wf["nodes"].append(f)
wf["connections"]["guardar_ficha"] = {"ai_tool": [[{"node": "AI Agent", "type": "ai_tool", "index": 0}]]}

# ---------------------------------------------------------------- 4. o aviso de todo turno
p = N["Reservar mensagens"]["parameters"]
p["query"] = trocar(
    p["query"],
    "       nai_prompt_de('captacao') AS prompt",
    "       -- A FICHA ABERTA (28/09, 165): o aviso de todo turno, pronto do banco.\n"
    "       -- NULL quando nao ha ficha aberta.\n"
    "       captacao_ficha_aviso(l.id) AS ficha,\n"
    "       nai_prompt_de('captacao') AS prompt")

p = N["Juntar mensagens"]["parameters"]
js = p["jsCode"]
js = trocar(
    js,
    "const NOMES_MIDIA = { imagem: 'uma imagem', documento: 'um arquivo', video: 'um video', audio: 'um audio' };\n",
    "const NOMES_MIDIA = { imagem: 'uma imagem', documento: 'um arquivo', video: 'um video', audio: 'um audio' };\n"
    "// A FICHA DO IMOVEL (28/09, 165): o aviso vem pronto do 'Reservar mensagens'\n"
    "// (captacao_ficha_aviso). Com a ficha aberta, a foto que ele manda ja foi\n"
    "// guardada nela pelo ramo 'Foto do dono?' -- aqui ela so avanca a ficha.\n"
    "const fichaAberta = (itens.find(m => m.ficha) || {}).ficha || null;\n"
    "const fotoComLegenda = !!fichaAberta && itens.some(m => m.origem === 'imagem' && val(m));\n")
js = trocar(
    js,
    "        + ' -- \"Recebi, obrigada!\" -- e siga o roteiro de onde parou.'\n",
    "        + ' -- \"Recebi, obrigada!\" -- e '\n"
    "        + (fichaAberta && naoTexto.includes('imagem')\n"
    "           ? 'chame guardar_ficha com fotos = \"recebidas\" (a ficha do imovel esta aberta) e siga a instrucao que ela devolver.'\n"
    "           : 'siga o roteiro de onde parou.')\n")
js = trocar(
    js,
    "if (!texto) return [];\n",
    "if (fotoComLegenda) {\n"
    "  texto += '\\n(junto veio foto do imovel, ja guardada na ficha: chame guardar_ficha com fotos = \"recebidas\" junto com o resto.)';\n"
    "}\n"
    "if (!texto) return [];\n")
js = trocar(
    js,
    "  pergunta_pendente: p.pergunta_pendente || null,\n",
    "  pergunta_pendente: p.pergunta_pendente || null,\n"
    "  ficha: fichaAberta,\n")
p["jsCode"] = js

p = N["AI Agent"]["parameters"]
p["text"] = trocar(
    p["text"],
    "mensagem do proprietário: {{ $json.texto }}",
    "{{ $json.ficha ? $json.ficha + ' ' : '' }}mensagem do proprietário: {{ $json.texto }}")

# ---------------------------------------------------------------- 5. a foto do dono
se = copy.deepcopy(N["Tem audio?"])
se["id"] = str(uuid.uuid4())
se["name"] = "Foto do dono?"
se["position"] = [448, 1400]
se["parameters"]["conditions"]["conditions"] = [{
    "id": "fotodono1",
    "leftValue": "={{ $json.origem === 'imagem' && $json.saindo === false && !!$json.midia_url && $json.canal === 'zapi' }}",
    "rightValue": "",
    "operator": {"type": "boolean", "operation": "true", "singleValue": True},
}]
se["notes"] = ("28/09 (165): so a foto que o PROPRIETARIO manda pela Z-API. O que o Tel manda pelo celular (saindo) "
               "e o eco da API nao entram.")
wf["nodes"].append(se)

h = copy.deepcopy(N["Espelhar no CRM"])
h["id"] = str(uuid.uuid4())
h["name"] = "Guardar foto na ficha"
h["position"] = [672, 1400]
h["parameters"] = {
    "method": "POST",
    "url": "https://api.imobeasy.online/api/fotos-captacao/whatsapp",
    "authentication": "genericCredentialType",
    "genericAuthType": "httpHeaderAuth",
    "sendBody": True,
    "specifyBody": "json",
    "jsonBody": "={{ JSON.stringify({ telefone: $json.telefone, midia_url: $json.midia_url, message_id: $json.message_id }) }}",
    "options": {"timeout": 60000},
}
h["credentials"] = {"httpHeaderAuth": dict(CRED_FOTO)}
h["onError"] = "continueRegularOutput"
h["notes"] = ("28/09 (165): baixa a foto para o nosso servidor (a URL da Z-API expira) e poe na ficha do imovel. "
              "Senha de maquina na credencial; a API so aceita dono da campanha.")
wf["nodes"].append(h)

saida = wf["connections"]["Filtrar e normalizar"]["main"][0]
saida.append({"node": "Foto do dono?", "type": "main", "index": 0})
wf["connections"]["Foto do dono?"] = {"main": [[{"node": "Guardar foto na ficha", "type": "main", "index": 0}], []]}

json.dump(d, open(DST, "w"), ensure_ascii=False, indent=1)
print("ok:", len(wf["nodes"]), "nos")
