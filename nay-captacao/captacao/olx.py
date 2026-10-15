"""A NAY PROPRIETÁRIOS DA OLX: o dono que anunciou na OLX, pelo número oficial, com o roteiro do Pedro.

Pedro, 14/10/2026, com o "SCRIPT APÓS OLX": "monta uma nay cópia da nay captação que atende na api oficial, mas essa
vai funcionar captando os proprietários da OLX, a gente já vai ter o nome e número deles, e algumas informações do
imóvel, então o que essa deve fazer é checar o resto conforme aí no roteiro ... quero as mesmas regras gerais da que
fala com os proprietários hoje, como parar quando um humano assume e tudo mais".

ELA MORA DENTRO DESTE SERVIÇO. O lead é um lead comum da captação; ser "da OLX" é ter linha em `captacao_olx`
(migração 370), com o anúncio e as respostas. O atender.py pergunta `dados()`: se o lead é da OLX, o prompt, o
cabeçalho do turno e as ferramentas são os daqui. Todo o resto é o da captação, sem cópia: a fila e o silêncio de
20 s, a reserva, "gente escreveu pelo CRM = ela cala" (captacao_ainda_e_da_ia), o SILENCIO depois da despedida, o
portão de saída (sem emoji, sem prometer retorno do Tel), a escalada ao Tel e o envio pelo número oficial.

QUEM ESCOLHE A PERGUNTA É O BANCO (`captacao_olx_proxima`), por perfil (venda/locação x apartamento de escada ou de
elevador, casa de condomínio, casa de via pública), pulando o que o anúncio já diz. Ela só pergunta, anota com
`guardar_resposta` e faz a próxima que a ferramenta devolve.

A PRIMEIRA MENSAGEM é um modelo da Meta (fora da janela de 24 h só modelo abre conversa):
captacao_config.olx_abertura_modelos, o primeiro aprovado. `abrir()` manda; o serviço chama `abridor()` de tempos em
tempos para quem está em captacao_config.olx_telefones e ainda não recebeu (hoje, só o telefone do Pedro).

    python -m captacao.olx abrir 835        manda a abertura agora (se algum modelo estiver aprovado)
    python -m captacao.olx ver 835          o anúncio, o perfil, o que já respondeu e a próxima pergunta
    python -m captacao.olx novo 9038 [telefone nome]   põe o dono de um imóvel da OLX na captação
"""
from __future__ import annotations

import json
import logging
import sys
from datetime import datetime

from captacao import banco, envio, ferramentas
from captacao.turno import Turno, _agora_em_manaus

log = logging.getLogger("captacao.olx")

DADOS = """
SELECT o.lead_id, o.codigo, o.anuncio, o.respostas, o.aberto_em, l.status = 'concluido' AS encerrada,
       EXISTS (SELECT 1 FROM captacao_mensagens m WHERE m.lead_id = o.lead_id AND m.direcao = 'enviada'
                  AND m.criada_em > o.criado_em) AS ja_falou,
       captacao_olx_perfil(o.lead_id) AS perfil,
       captacao_olx_proxima(%(tel)s) AS proxima
  FROM captacao_olx o JOIN captacao_leads l ON l.id = o.lead_id
 WHERE l.telefone_chave = nay_fone_chave(%(tel)s)
"""

PROMPT = """Você é a Nay, da Imob Easy, imobiliária de Manaus. Internamente o seu nome é "Nay proprietários da OLX".
Neste número você fala com PROPRIETÁRIOS que anunciaram o próprio imóvel na OLX. A Imob Easy já conversou com ele pela
OLX sobre esse anúncio, e a primeira mensagem desta conversa (o modelo oficial) já disse quem você é.
O seu trabalho é UM só: completar as informações do imóvel dele, uma pergunta por vez, seguindo o roteiro que o sistema
te entrega pronto. O dono da imobiliária é o Tel. Ele decide o que você não decide.

=== TRATAMENTO (Sr. / Sra.) ===
O tratamento vem pronto do sistema. Se vier "Sr." você escreve Sr., se vier "Sra." você escreve Sra. Se vier dizendo que
é desconhecido, você chama a pessoa SÓ pelo primeiro nome, sem Sr. e sem Sra. Você NUNCA deduz o tratamento pelo nome.
O tratamento vale na frase inteira: com Sra. é "a Sra.", com Sr. é "o Sr.", sem tratamento é "você".

=== COMO VOCÊ FALA: PORTUGUÊS DO BRASIL, DE GENTE ===
Você é uma moça de Manaus respondendo no WhatsApp do trabalho, não um assistente virtual traduzido do inglês.
FRASES PROIBIDAS (à direita, o que uma brasileira diria):
  "Você está bem-vinda" / "Você é bem-vindo"            -> "Imagina!" / "Por nada!"
  "Perfeito!" / "Excelente!" / "Ótimo!" abrindo a frase   -> "Certo." / "Entendi."
  "Obrigada por compartilhar" / "por confirmar"          -> "Obrigada!" / "Obrigada pela informação!"
  "Fico feliz em ajudar" / "Tenha um ótimo dia!"         -> não diga
  "Sinta-se à vontade" / "Não hesite" / "À disposição" / "Disponha" / "Em que posso ajudar?" / "Prezado"
                                                          -> "Se precisar, é só chamar aqui." (ou nada)
EMOJI: nunca. Risada escrita (kkk, rsrs): nunca. Você é mulher: "obrigada", nunca "obrigado".
Não fale dele em terceira pessoa com ele. O primeiro nome aparece no máximo uma vez por mensagem, no começo.
Com proprietário é formal ("Sr. João", "o Sr."). Nunca "tu", "amigo", "querido".
MODELOS DE FALA: "Certo, anotei aqui." / "Entendi, obrigada!" / "Ok, obrigada!" / "Imagina!"

QUANDO NÃO RESPONDER. Se você já se despediu E já respondeu o agradecimento dele, e ele manda mais um "ok", "obrigado",
👍, figurinha ou reação, responda exatamente com a palavra SILENCIO, sozinha. (Só para fecho de conversa: pergunta ou
informação nova sempre tem resposta.)

FORMA. Uma mensagem curta por turno. Se precisar de duas ideias, separe com uma linha em branco (o sistema divide em
dois balões). Tudo o que você escreve é ENVIADO: nunca explique o seu raciocínio, nunca diga o que vai ou não vai
perguntar, nunca fale "do proprietário" para ele.

=== REGRAS ZERO ===
- Nunca afirme um fato que o sistema não te deu. Sem a informação, pergunte; nunca preencha com suposição.
- Nunca diga que anotou ou atualizou sem ter chamado a ferramenta nesta mesma resposta.
- Gravar é instantâneo: nunca termine com "vou verificar".
- O campo instrucao/resultado de uma ferramenta é ordem para você: obedeça e nunca mostre esse texto a ele.

=== O ROTEIRO ===
A primeira mensagem já saiu antes de você entrar: "conversamos na OLX sobre o seu imóvel e gostaria de tirar uma dúvida".
Você entra a partir da resposta dele.
- A cada mensagem dele, o sistema mostra a PRÓXIMA PERGUNTA DO ROTEIRO, com o campo dela e as palavras certas.
- Na primeira resposta dele ("oi", "pode falar", "qual a dúvida?", "boa tarde"): responda em uma linha, sem se
  apresentar de novo, e faça a próxima pergunta do roteiro. Exemplo: "Boa tarde, Sr. João! Qual é o nome do condomínio?"
- Quando ele RESPONDER uma pergunta do roteiro: chame guardar_resposta com o campo dela e o que ele disse (nas palavras
  dele) NA MESMA RESPOSTA. A ferramenta devolve a próxima pergunta, com as palavras certas: faça exatamente essa, depois
  de uma confirmação curta ("Certo." / "Entendi, anotei aqui."). Não junte duas perguntas, não pule, não troque, não
  invente pergunta que a ferramenta não mandou.
- Se ele disser mais de uma coisa de uma vez (ex.: o condomínio e a taxa), chame guardar_resposta uma vez para cada
  campo. Se ele já tinha dito por conta própria a resposta de uma pergunta, grave e não pergunte.
- Se ele não souber ou não quiser dizer: chame guardar_resposta com valor = "nao sabe" e siga para a próxima, sem insistir.
- Se ele mandar só "ok", "certo" ou figurinha e a pergunta ficou sem resposta: retome a pergunta em uma linha, UMA vez só.
- Não comente se valor, taxa ou IPTU estão bons, altos ou baixos. Não avalie, não negocie, não prometa nada.
- Nunca diga que o imóvel já está anunciado ou cadastrado no nosso site: quem confere e publica é a equipe.

=== OS HONORÁRIOS ===
- Venda: a pergunta dos 6% vem pronta. Se ele disser que NÃO estão inclusos ("tem que acrescentar", "quero líquido"),
  a ferramenta manda você dizer "Tudo bem, podemos trabalhar com uma margem de 10% a mais." -- diga exatamente isso e siga.
- Aceitamos até 5% de honorários. Se ele propuser MENOS de 5%, não negocie: a ferramenta manda escalar.
- Locação: se ele disser que quer pagar só METADE dos honorários de corretagem da locação, responda, com estas palavras:
  "Eu entendo, mas imagine que 15 dias com o imóvel parado, pagando IPTU e taxa de condomínio, já é um custo de uma
  receita que poderia estar entrando. A gente está aqui justamente para acelerar a locação do seu imóvel. Como dividimos
  os honorários com os corretores, fica ruim para nós pelo custo das visitas, da vistoria que terceirizamos e da divisão
  com o corretor que traz o cliente. Podemos trabalhar com o valor integral dos honorários para acelerar a locação do
  seu imóvel?"
  (com o tratamento certo no começo, se couber). Se ele insistir na metade depois disso, chame escalar_ao_tel com
  assunto "honorarios de locacao pela metade" e responda SILENCIO.

=== OUTROS IMÓVEIS E INDICAÇÃO ===
- Se ele disser que tem outro imóvel, a próxima pergunta é qual é e onde fica (vem da ferramenta). TUDO o que ele
  disser do OUTRO imóvel vai num guardar_resposta só, campo outros_detalhe: nunca em metragem_terreno, numero_casa,
  sol ou outro campo, que são do imóvel do anúncio.
- Na pergunta da indicação: se ele disser que não conhece ninguém, grave com guardar_resposta (campo indicacao). Se
  indicar alguém, peça o nome e o telefone que ainda faltarem e chame guardar_indicacao. Mensagem no formato
  "👤 Contato: NOME — TELEFONE" é um cartão de contato: ali estão o nome e o telefone.
- Quando a ferramenta disser que o roteiro acabou: agradeça em uma linha e chame encerrar_conversa (motivo concluido).
  encerrar_conversa não encerra antes da hora: se faltar pergunta, ela devolve a pergunta para você fazer.

=== ONDE CONSEGUIMOS O CONTATO (resposta pronta: NUNCA escale isso) ===
"Onde conseguiu meu contato?", "quem te passou meu número?", "como vocês me acharam?": responda você mesma, sem chamar
escalar_ao_tel: "Conversamos com o Sr. pela OLX, sobre o anúncio do seu imóvel." (no tratamento certo) e, na mesma
mensagem, depois de uma linha em branco, retome a pergunta do roteiro que ficou aberta.
Se perguntarem quem você é: "Sou a Nay, da Imob Easy, imobiliária aqui de Manaus."

=== QUANDO ESCALAR (escalar_ao_tel) ===
Só quando ele PERGUNTAR ou PEDIR algo fora do roteiro que você não pode responder: proposta, avaliação, quanto vale,
comissão (fora a regra dos honorários acima), visita, contrato, documentação, reclamação, falar com alguém, "isso é
golpe?", "quem é o Tel?", como a imobiliária funciona. Você não explica nada disso: chama escalar_ao_tel e NÃO diz
nada sobre isso (nada de "vou passar para o Tel", "vou verificar", "já te retorno"). Se o assunto escalado era tudo o
que ele disse, responda SILENCIO; se ele falou também de algo do roteiro, responda só essa parte e pare de perguntar.
NÃO escale: saudação, "ok", "depois te falo", afirmação, mensagem automática, ele dar um dado do roteiro, ele não
lembrar um número, ele perguntar de onde veio o contato (resposta pronta acima). Na dúvida: se é DADO do roteiro,
siga o roteiro.

=== IA ===
Nunca diga que é IA, robô ou automação. Nunca afirme ser humana. Não levante o assunto.

=== SE ELE PEDIR PARA PARAR ===
Não quer receber mensagem, número errado, não é o dono: peça desculpa em uma linha, diga que vai remover e chame
encerrar_conversa com motivo = opt_out (ou numero_errado / nao_e_o_dono). Não pergunte mais nada.
"""

GUARDAR = {
    "type": "function", "name": "guardar_resposta",
    "description": ("Grava a resposta do proprietario a UMA pergunta do roteiro e devolve a proxima pergunta, com as palavras "
                    "certas (ou a ordem de encerrar). CHAME sempre que ele responder uma pergunta do roteiro, ou disser por "
                    "conta propria um dado de outra pergunta do roteiro. O resultado e ordem para voce: obedeca e nunca mostre."),
    "parameters": {"type": "object", "required": ["campo", "valor"], "properties": {
        "campo": {"type": "string", "description": (
            "o campo da pergunta: condominio_nome, elevador, taxa_condominio, iptu, lances_escada, bloco, andar, torre, "
            "metragem_terreno, numero_casa, endereco, sol, honorarios, condominio_incluso, outros, outros_detalhe, indicacao")},
        "valor": {"type": "string", "description": "o que ele disse, nas palavras dele; 'nao sabe' se ele nao souber ou nao quiser dizer"},
    }},
}
ENCERRAR = {
    "type": "function", "name": "encerrar_conversa",
    "description": ("Encerra a conversa com este proprietario. Motivo concluido so depois de a ferramenta guardar_resposta "
                    "dizer que o roteiro acabou (se faltar pergunta, ela devolve a pergunta). opt_out, numero_errado ou "
                    "nao_e_o_dono encerram na hora."),
    "parameters": {"type": "object", "required": ["motivo"], "properties": {
        "motivo": {"type": "string", "description": "concluido, opt_out, numero_errado ou nao_e_o_dono"},
    }},
}


def _da_captacao(nome: str) -> dict:
    """A ferramenta da captação no formato da API (a mesma definição; só o executor muda)."""
    return next(d for d in ferramentas.definicoes() if d["name"] == nome)


def definicoes() -> list[dict]:
    return [GUARDAR, _da_captacao("guardar_indicacao"), _da_captacao("escalar_ao_tel"), ENCERRAR]


def dados(conn, telefone: str) -> dict | None:
    r = banco.linhas(conn, DADOS, {"tel": telefone})
    return r[0] if r else None


def _reais(v) -> str:
    try:
        return "R$ " + f"{round(float(v)):,}".replace(",", ".")
    except (TypeError, ValueError):
        return str(v)


ROTULOS = {"condominio_nome": "condomínio", "elevador": "elevador", "taxa_condominio": "taxa de condomínio", "iptu": "IPTU",
           "lances_escada": "lances de escada", "bloco": "bloco", "andar": "andar", "torre": "torre",
           "metragem_terreno": "metragem do terreno", "numero_casa": "número da casa", "endereco": "endereço",
           "sol": "sol da sala", "honorarios": "honorários (6%)", "condominio_incluso": "condomínio incluso no aluguel",
           "outros": "outros imóveis", "outros_detalhe": "o outro imóvel", "indicacao": "indicação"}


def resumo_do_anuncio(d: dict) -> str:
    a, p = d.get("anuncio") or {}, d.get("perfil") or {}
    negocio = "VENDA" if p.get("negocio") != "locacao" else "LOCAÇÃO"
    valor = a.get("valor_venda") if negocio == "VENDA" else a.get("valor_aluguel")
    partes = [f"{a.get('tipo') or 'imóvel'} para {negocio}" + (f" por {_reais(valor)}" if valor else "")]
    if p.get("condominio"):
        partes.append(f"no condomínio {p['condominio']}")
    if a.get("bairro"):
        partes.append(f"bairro {a['bairro']}")
    for k, rot in (("quartos", "quartos"), ("andar", "andar"), ("sol", "sol"), ("area_util", "m² de área"),
                   ("area_total", "m² de terreno")):
        if a.get(k):
            partes.append(f"{rot}: {a[k]}")
    if a.get("taxa_condominio"):
        partes.append(f"taxa de condomínio {_reais(a['taxa_condominio'])}")
    if a.get("iptu"):
        partes.append(f"IPTU {_reais(a['iptu'])}")
    if a.get("logradouro"):
        partes.append(f"endereço {a['logradouro']}" + (f", {a['numero']}" if a.get("numero") else ""))
    return "; ".join(partes)


def cabecalho(t: Turno, d: dict, agora: datetime) -> str:
    """O texto do turno: quem é ele, o anúncio que já temos, o que ele já respondeu e a PRÓXIMA PERGUNTA."""
    resp = d.get("respostas") or {}
    prox = d.get("proxima") or {}
    partes = [
        "(informação de sistema, não repita isso ao proprietário) agora em Manaus é " + _agora_em_manaus(agora) + ".",
        "o proprietário é " + (t.tratamento or "(tratamento desconhecido -- NAO escreva Sr. nem Sra., chame so pelo primeiro nome)")
        + " " + (t.nome or "(nome não cadastrado -- fale sem vocativo, não invente)") + ".",
        "o anúncio dele na OLX, que já temos: " + resumo_do_anuncio(d) + ".",
    ]
    if not d.get("aberto_em") and not d.get("ja_falou"):
        partes.append("ATENÇÃO: a primeira mensagem (o modelo oficial) NÃO saiu: foi ele quem escreveu primeiro. Nesta resposta, "
                      "apresente-se com a abertura do roteiro -- \"Olá, " + (t.tratamento + " " if t.tratamento else "")
                      + (t.nome or "") + ", aqui é a Nay, da Imob Easy. Conversamos na OLX sobre o seu imóvel e gostaria de "
                      "tirar uma dúvida.\" -- e, depois de uma linha em branco, faça a próxima pergunta do roteiro.")
    if resp:
        partes.append("o que ele já respondeu: " + "; ".join(f"{ROTULOS.get(k, k)} = {v}" for k, v in resp.items()) + ". não pergunte de novo.")
    if d.get("encerrada"):
        partes.append("A CONVERSA JÁ FOI ENCERRADA (o roteiro terminou e já está tudo gravado): NÃO chame nenhuma ferramenta. "
                      "Se ele só agradeceu ou mandou ok, responda curto (\"Imagina!\") uma vez; se você já respondeu o "
                      "agradecimento, responda SILENCIO. Se ele trouxer assunto novo, siga as regras de escalada.")
    elif prox.get("fim"):
        partes.append("O ROTEIRO JÁ ACABOU: se ele só agradeceu, responda curto (ou SILENCIO, se você já se despediu); "
                      "se ainda não encerrou, chame encerrar_conversa com motivo concluido.")
    elif prox.get("pergunta"):
        partes.append(f'PRÓXIMA PERGUNTA DO ROTEIRO (campo {prox.get("campo")}): "{prox.get("pergunta")}"')
    if t.qtd > 1:
        partes.append(f"ATENÇÃO: ele mandou {t.qtd} mensagens neste intervalo, juntas abaixo, uma por linha. Responda o conjunto.")
    if t.veio_audio:
        partes.append("ele respondeu por ÁUDIO e o texto abaixo é a transcrição. Antes de gravar um número, repita em uma "
                      "linha o que entendeu e peça a confirmação dele.")
    if t.pediu_parar:
        partes.append("ATENÇÃO: o texto dele tem sinal de que ele NÃO QUER receber mensagem, ou de que o número está errado. "
                      "Peça desculpa em uma linha, diga que vai remover, chame encerrar_conversa com motivo opt_out e NÃO "
                      "faça mais nenhuma pergunta.")
    partes.append("mensagem do proprietário: " + t.texto)
    return " ".join(partes)


def _um(conn, sql: str, params) -> str:
    """Uma linha, uma coluna. No ensaio (uma transação só) o erro de uma ferramenta não derruba a transação inteira."""
    if conn.autocommit:
        return banco.linhas(conn, sql, params)[0]["r"]
    banco.linhas(conn, "SAVEPOINT olx")
    try:
        r = banco.linhas(conn, sql, params)[0]["r"]
        banco.linhas(conn, "RELEASE SAVEPOINT olx")
        return r
    except Exception:
        banco.linhas(conn, "ROLLBACK TO SAVEPOINT olx")
        raise


# os campos do imóvel do anúncio: depois da pergunta dos outros imóveis, o que ele diz é do OUTRO imóvel
DO_ANUNCIO = {"condominio_nome", "elevador", "taxa_condominio", "iptu", "lances_escada", "bloco", "andar", "torre",
              "metragem_terreno", "numero_casa", "endereco", "sol", "honorarios", "condominio_incluso"}


def executar(conn, nome: str, args: dict, telefone: str, nome_do_dono: str = "", avisar=None, encaminhar=None) -> str:
    """Roda a ferramenta da Nay da OLX. Erro vira texto: o turno não cai por causa dele."""
    try:
        if nome == "guardar_resposta":
            campo = str(args.get("campo") or "")
            resp = (banco.linhas(conn, "SELECT o.respostas FROM captacao_olx o JOIN captacao_leads l ON l.id = o.lead_id "
                                       "WHERE l.telefone_chave = nay_fone_chave(%s)", (telefone,)) or [{}])[0].get("respostas") or {}
            if campo in DO_ANUNCIO and campo not in resp and "outros_detalhe" in resp:
                return ("NAO gravei: isso e do OUTRO imovel dele, que ja esta em outros_detalhe. Nao grave em outro campo; "
                        "siga com a pergunta que a ferramenta mandou antes.")
            r = _um(conn, "SELECT captacao_olx_guardar(%s, %s, %s) AS r",
                    (telefone, str(args.get("campo") or ""), str(args.get("valor") or "")))
            if "margem de 10%" in r:
                # a frase da margem já é a confirmação: sem "Certo." depois dela (ensaio de 15/10)
                r = r.replace('depois de uma confirmacao curta ("Certo." / "Entendi, anotei aqui."), ',
                              'logo depois dessa frase (sem "Certo." nem outra confirmacao), ')
            return r
        if nome == "encerrar_conversa":
            return _um(conn, "SELECT captacao_olx_encerrar(%s, %s) AS r", (telefone, str(args.get("motivo") or "concluido")))
        if nome == "guardar_indicacao":
            if "indicacao" in (banco.linhas(conn, "SELECT o.respostas FROM captacao_olx o JOIN captacao_leads l ON l.id = o.lead_id "
                                                  "WHERE l.telefone_chave = nay_fone_chave(%s)", (telefone,)) or [{}])[0].get("respostas", {}):
                return "A indicacao ja estava gravada: nao grave de novo. Nao chame mais ferramentas; responda curto ou SILENCIO."
            r = ferramentas.executar(conn, nome, args, telefone, nome_do_dono, avisar=avisar, encaminhar=encaminhar)
            if "gravada" in r.lower():
                # indicação completa: é a resposta da última pergunta do roteiro
                resumo = " ".join(str(args.get(k) or "") for k in ("nome", "contato", "detalhe")).strip()
                seguinte = _um(conn, "SELECT captacao_olx_guardar(%s, 'indicacao', %s) AS r", (telefone, resumo or "indicou"))
                return r + " " + seguinte
            return r
        if nome == "escalar_ao_tel":
            r = banco.linhas(conn, banco.ESCALAR, {"tel": telefone, "nome": nome_do_dono,
                                                   "assunto": str(args.get("assunto") or ""), "disse": str(args.get("disse") or "")})
            if not r:
                return json.dumps([{"instrucao_para_voce": "Nao escalei: faltou o assunto. Chame de novo com o assunto."}])
            if avisar:
                avisar(ferramentas.aviso_da_escalada(r[0], telefone, nome_do_dono).replace("CAPTACAO --", "CAPTACAO OLX --", 1))
            return json.dumps(r, ensure_ascii=False, default=str)
        return "ferramenta desconhecida"
    except Exception as e:  # noqa: BLE001 -- o modelo precisa saber que não gravou
        return "ERRO: " + str(e).strip().splitlines()[0][:300]


# ── a primeira mensagem (o modelo da Meta) ───────────────────────────────────────────────────────────────────────

LEAD = """
SELECT l.id, l.telefone, l.nome, l.tratamento, l.opt_out, l.humano_assumiu_em IS NOT NULL AS com_gente, o.aberto_em
  FROM captacao_leads l JOIN captacao_olx o ON o.lead_id = l.id WHERE l.id = %s
"""
MODELOS = "SELECT coalesce((SELECT valor FROM captacao_config WHERE chave = 'olx_abertura_modelos'), '') AS v"
ABERTOS = """
UPDATE captacao_olx SET aberto_em = now(), atualizado_em = now() WHERE lead_id = %(lead)s;
UPDATE captacao_leads SET status = 'enviado', canal = 'oficial', tentativas = tentativas + 1, ultimo_envio_em = now(),
       pergunta_pendente = NULL, atualizado_em = now()
 WHERE id = %(lead)s;
INSERT INTO captacao_motor (lead_id) VALUES (%(lead)s) ON CONFLICT (lead_id) DO NOTHING;
INSERT INTO captacao_mensagens (lead_id, telefone, direcao, origem, texto, status, message_id)
VALUES (%(lead)s, %(tel)s, 'enviada', 'disparo', %(texto)s, 'Enviado', %(mid)s);
"""
# quem pode receber a abertura agora: da lista de telefones liberados (hoje, só o do Pedro) e ainda sem abertura
A_ABRIR = """
SELECT o.lead_id FROM captacao_olx o JOIN captacao_leads l ON l.id = o.lead_id
 WHERE o.aberto_em IS NULL AND NOT l.opt_out AND l.humano_assumiu_em IS NULL
   AND captacao_no_horario()   -- a mesma janela do disparo da captação (nada de madrugada)
   AND (o.abertura_tentada_em IS NULL OR o.abertura_tentada_em < now() - interval '15 minutes')
   -- ele escreveu antes do modelo sair (e ela já se apresentou): o modelo não vai mais
   AND NOT EXISTS (SELECT 1 FROM captacao_mensagens m WHERE m.lead_id = o.lead_id AND m.direcao = 'recebida' AND m.criada_em > o.criado_em)
   AND l.telefone_chave IN (SELECT nay_fone_chave(btrim(x)) FROM captacao_config c, regexp_split_to_table(c.valor, '[,;\\s]+') x
                             WHERE c.chave = 'olx_telefones' AND btrim(x) <> '')
 ORDER BY o.lead_id LIMIT 5
"""


def abrir(conn, lead_id: int) -> str:
    """Manda o primeiro modelo aprovado de captacao_config.olx_abertura_modelos. Não aprovado ainda = tenta de novo depois."""
    from captacao.disparo import vocativo   # aqui para não criar laço de importação
    r = banco.linhas(conn, LEAD, (lead_id,))
    if not r:
        return f"o lead {lead_id} não é da OLX"
    lead = r[0]
    if lead["aberto_em"]:
        return "a abertura já saiu para este lead"
    if lead["opt_out"] or lead["com_gente"]:
        return "RECUSADO: pediu para não receber, ou alguém da equipe assumiu"
    quem = vocativo(lead["tratamento"], lead["nome"])
    if not quem:
        return "RECUSADO: sem nome para o modelo"
    erros = []
    for modelo in [m.strip() for m in banco.linhas(conn, MODELOS)[0]["v"].split(",") if m.strip()]:
        mid, texto, erro = envio.modelo(lead["telefone"], modelo, "pt_BR", [quem])
        if mid:
            banco.linhas(conn, ABERTOS, {"lead": lead_id, "tel": lead["telefone"], "texto": texto or f"[modelo {modelo}]", "mid": mid})
            return f"abertura ({modelo}) enviada para …{lead['telefone'][-4:]}: {texto}"
        erros.append(f"{modelo}: {erro}")
        if (erro or "").startswith(envio.INCERTO):
            break   # pode ter saído: não manda o segundo modelo por cima
    banco.linhas(conn, "UPDATE captacao_olx SET abertura_tentada_em = now() WHERE lead_id = %s", (lead_id,))
    return "NÃO SAIU: " + " | ".join(erros)


def abridor(conn) -> list[str]:
    """Uma passada: manda a abertura para quem está liberado e ainda não recebeu. Chamado pelo serviço."""
    return [f"lead {l['lead_id']}: {abrir(conn, l['lead_id'])}" for l in banco.linhas(conn, A_ABRIR)]


def main(argv: list[str]) -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s")
    conn = banco.conectar()
    try:
        if argv[:1] == ["abrir"]:
            print(abrir(conn, int(argv[1])))
        elif argv[:1] == ["ver"]:
            tel = banco.linhas(conn, "SELECT telefone FROM captacao_leads WHERE id = %s", (int(argv[1]),))[0]["telefone"]
            d = dados(conn, tel)
            print(json.dumps(d, ensure_ascii=False, indent=2, default=str) if d else "não é da OLX")
        elif argv[:1] == ["novo"]:
            tel = argv[2] if len(argv) > 2 else None
            nome = argv[3] if len(argv) > 3 else None
            print("lead", banco.linhas(conn, "SELECT captacao_olx_novo(%s, %s, %s) AS l", (int(argv[1]), tel, nome))[0]["l"])
        else:
            print(__doc__)
            return 2
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
