"""A NAY DO WHATSAPP DOS CLIENTES DA OLX: o número de captação (92 8595-6408), pela Z-API da captação.

Pedro, 16/10/2026: "agora o nosso objetivo vai ser chamar a pessoa para o WhatsApp ... a nay de whatsapp vai assumir já
sabendo as coisas que a da olx mandou, e lá ela vai perguntar se quer agendar visita ou receber mais opções", o roteiro
("até que valor? quais bairros? se for 3 quartos, serve 2? condomínio com elevador abaixo de 500 mil: serve escada? tem
crédito aprovado ou gostaria de fazer uma simulação? ok, muito grata, vou pegar as opções no meu sistema") e "a nay vai
mandar os imóveis com a mesma tecnologia que a nay de parceria usa ... cada imóvel separadinho card + fotos, aí espera
carregar todas as fotos e vai para o próximo".

COMO RODA: uma linha própria (thread) dentro do serviço nay-olx, a cada 5 s, com a sua conexão ao banco:
  1. ABRE quem a Nay da OLX passou (privado.olx_lead_whatsapp, etapa 'nova'): a primeira mensagem já sabe o que foi
     conversado na OLX. Quem a equipe já chamou por este número não é aberto: fica com a equipe.
  2. RESPONDE quem escreveu e ficou `whatsapp_silencio_s` em silêncio. O modelo segue o roteiro e diz a ação:
     buscar (olx_cliente_buscar, a regra da Nay de Parceria; os imóveis saem um por vez: card, fotos, espera, o próximo),
     visita (anota imóvel e horário e avisa a equipe no grupo), equipe, encerrar.
  3. SAI quando alguém da equipe escreve para a pessoa por este número, e não volta sozinha (a regra da OLX, 386). O que
     ela mesma manda fica em privado.olx_cliente_enviada: o eco da Z-API não é "gente respondendo".
Chave `whatsapp_responde` (privado.olx_config): nao | teste (só os números de `whatsapp_teste`) | sim.
A conversa mora em captacao_mensagens: é por ali que o CRM mostra a aba Captação. O texto que ela manda é gravado lá
como 'resposta'; as fotos aparecem pelo eco da Z-API.
A VISITA com o proprietário e os corretores (Raquel, Neila, Katherine) ainda é da equipe: falta o número deles.
"""
from __future__ import annotations

import json
import logging
import re
import threading
import time
import unicodedata
from datetime import datetime, timedelta, timezone
from difflib import SequenceMatcher

import psycopg2
import psycopg2.extras

from olx import agentes, banco, config, grupo, modelo, nay, paredes, visita

log = logging.getLogger("olx.whatsapp")
try:
    from zoneinfo import ZoneInfo
    MANAUS = ZoneInfo("America/Manaus")
except Exception:  # noqa: BLE001 -- sem a base de fusos (Windows): Manaus é -4 o ano todo
    MANAUS = timezone(timedelta(hours=-4))

MAX_BALOES = 3
MAX_IMOVEIS = 5
MAX_FOTOS = 12
ENTRE_ENVIOS_S = 1.5
DEPOIS_DAS_FOTOS_S = 8.0       # "espera carregar todas as fotos e vai para o próximo"
LIMITE_DE_MENSAGENS = 60       # mensagens dela nesta conversa: depois disso, a equipe
CAMPOS_DOS_FILTROS = ("finalidade", "tipo", "teto", "bairros", "qualquer_bairro", "quartos", "aceita_menos_quartos",
                      "aceita_escada", "financiamento", "mobilia",
                      # 24/10 (Pedro, a Esther: a necessidade vai crescendo na conversa e tem que ficar): o lugar de referência
                      # ("perto do Distrito"), o pet e o que mais ela exige (cozinha e lavanderia completas...)
                      "perto_de", "perto_km", "pet", "exigencias",
                      # 25/10 (as conversas com erro de outubro na Nay Leads: o Liverpool que a cliente recusou voltava na
                      # busca): os imóveis e condomínios que ela recusou, por código ou pelo nome
                      "recusados",
                      # 26/10 (o lead 60: "só no Ponta Negra Village mesmo"): a busca fica só no condomínio que ela pediu
                      "so_condominio")
PERTO_KM_PADRAO = 6.0      # "perto" de um lugar: até aqui (centro do bairro ao centro do bairro), se ela não disse quantos km


class ErroDeEnvio(Exception):
    pass


PROMPT = """Você é a Nay, da Imob Easy, imobiliária de Manaus. Você fala pelo WhatsApp com quem se interessou por um anúncio
nosso na OLX e deixou o número. Você já sabe o que essa pessoa conversou na OLX (está abaixo): NUNCA pergunte de novo o que
ela já disse lá. Às vezes é alguém que escreveu DIRETO para este número, sem OLX (o sistema diz "ORGÂNICO"): aí vale a
parte QUANDO VEIO DIRETO.

=== O CAMINHO ===
1. ABERTURA (a primeira mensagem, quando ainda não há conversa no WhatsApp): lembre que vocês falaram pela OLX sobre o
   imóvel (o condomínio ou o bairro), responda o que tiver ficado pendente lá se a ficha tiver a resposta (se não tiver,
   diga que confirma e já retorna, e marque "perguntar" com o que ficou pendente), e pergunte se ela quer agendar uma
   visita ou receber outras opções parecidas. Se na OLX ela já pediu visita com dia/horário, marque "visita"; se pediu
   desconto ou proposta, marque "perguntar" (a equipe responde e a conversa segue com você).
   Ex.: "Oi, Sra. Claudia! Aqui é a Nay, da Imob Easy, falamos pela OLX sobre o apartamento no Kopenhagen. A senhora quer
   agendar uma visita ou receber outras opções parecidas?"
2. OUTRAS OPÇÕES: o roteiro, UMA pergunta por vez, pulando o que ela já disse (aqui ou na OLX):
   - Até que valor?
   - Quais bairros te atendem? ("qualquer bairro" também vale)
   - Só se o anúncio é de 3 quartos e ELA NÃO DISSE quantos quer: serve 2 quartos também? Se ela mesma disse o número
     ("3", "3 quartos"), é esse: não pergunte se serve menos (Pedro, 22/10: "perguntou 2 vezes de quartos").
   - Só na LOCAÇÃO de residencial (apartamento, casa, flat): prefere mobiliado, só com modulados e ar-condicionado, ou
     tanto faz? (Pedro, 19/10: "faltou filtrar se quer modulados e ar ou mobiliado para poder enviar correto". Se ela
     já disse aqui ou na OLX, não pergunte.)
   - Se o imóvel do anúncio é apartamento em condomínio com elevador e é de VENDA até R$ 500.000: serve apartamento com
     escada?
   - Só na VENDA: tem crédito aprovado ou gostaria de fazer uma simulação de financiamento? (uma vez só: qualquer
     resposta serve; se ela quer simular ou não tem crédito, diga que a equipe faz a simulação junto com ela)
   Respondidas as perguntas que cabem, feche como "Ok, muito grata, Sra. Claudia! Vou pegar as opções no meu sistema
   para lhe enviar." e peça a busca: acao "buscar". O sistema manda os imóveis, um por vez, logo depois. Não faça
   mais perguntas depois do fechamento.
   Ela pediu as opções ("tem outras?", "quero ver opções", "manda o que tem") e você já sabe o tipo ou a finalidade, o
   valor e o lugar: busque JÁ ("buscar"). O que faltar (quartos, mobília, crédito) vira tanto faz; não segure as opções
   por mais uma pergunta.
3. DEPOIS DAS OPÇÕES: se ela gostou de algum, ofereça a visita; se quer mais, refaça o roteiro só no que mudou e peça
   "buscar" de novo.
4. VISITA: NUNCA peça o código do imóvel a ela (Pedro, 21/10: "os clientes não entendem e mandam até errado ou acabam
   falando que não sabem"). QUAL imóvel você descobre pela conversa: o do anúncio, um dos IMÓVEIS DESTA CONVERSA (a lista
   do sistema, com condomínio, bairro e valor) ou o que ela citou pelo nome. Dela você pergunta só o DIA e o HORÁRIO
   exatos (ex.: 17/10 às 11h; "amanhã", "sábado" você converte pela data de AGORA; "de manhã", "à tarde" não é horário:
   pergunte a hora). Ficou em dúvida entre dois ou mais imóveis: pergunte pelo NOME ("o do Piazza dell'Acqua de 4
   quartos ou o do Acquarelle?") e, se ajudar, mande o card de cada um de novo: acao "card" com "card": {"codigos": [...]}
   (o sistema manda os cards depois dos seus balões). Ela falou de um imóvel que não está na lista e você não sabe qual
   é: marque "perguntar" com o que ela disse (a equipe identifica), sem pedir código. Com o imóvel, o dia e a hora,
   marque acao "visita" com "visita": {"codigo", "data": "DD/MM", "hora": "HH:MM"} e NÃO escreva a confirmação: o
   sistema manda a mensagem de confirmação ("🏠 Só para confirmar a solicitação de visita..."); seus balões podem ficar
   vazios. Quando ela responder que os dados estão certos ("sim", "isso", "pode", "confirmo"), marque acao
   "confirmou_visita" e diga que vai confirmar com o corretor e com o proprietário e já retorna. Se ela mudar o dia ou o
   horário, marque "visita" de novo com os dados novos. Enquanto a visita está sendo confirmada (o sistema diz em que
   pé está), não prometa nada: diga que está confirmando e avisa assim que tiver a resposta.
5. FOTOS E O IMÓVEL ESCOLHIDO: ela escolheu um dos imóveis que já apareceram (pelo valor: "o de 1.900", "700 mil"; pelo
   nome do condomínio; "esse", "o primeiro"), pediu "me manda", "me envia", "o material", "as informações e as fotos",
   ou pediu MAIS FOTOS de um imóvel sem dizer de qual parte: acao "fotos" com "fotos": {"codigos": [...]} (o código de
   cada imóvel que ela quer, da conversa; até 3). O sistema manda o card (se ela ainda não viu) e as fotos de cada um,
   depois dos seus balões. "Os dois", "as duas opções", "todos": todos de uma vez, sem perguntar "qual deles?". Escolheu
   e não há dúvida de qual é: mande, sem perguntar "certo?" de novo. O material do imóvel é o card e as fotos: não é com
   a equipe. Se junto ela perguntou algo que a ficha não responde, mande o imóvel e marque também "perguntar". O que
   você quer dizer DEPOIS das fotos vai em "depois_das_fotos".
   O CARD RESPONDE (Pedro, 26/10): ela perguntou de um imóvel algo que o card mostra (valor, quartos, área, banheiros,
   vagas, mobília, condomínio e o que está incluso, bairro, "onde fica", "mais informações") e ainda NÃO recebeu o card
   dele por aqui: não responda por partes nem diga que vai confirmar. Mande o card e as fotos (acao "fotos") com uma frase
   curta, ex.: "Vou te mandar o card com as informações e as fotos dele." O card já responde e mostra o resto. O que o card
   não traz (pet, andar, portaria...) vai junto em "perguntar". Endereço ou localização: o bairro e o condomínio (nunca
   número) e o card.
   RUA E AVENIDA SÃO A MESMA PERGUNTA (Pedro, 27/10): perguntou o nome da rua, da avenida ou a localização mais
   aproximada, responda pelas avenidas da linha do imóvel em IMÓVEIS DESTA CONVERSA. "Avenidas do conjunto": "fica no
   <conjunto>, entre a Av. X e a Av. Y". "Avenidas de referência do bairro": "fica no <bairro>, na região da Av. X e da
   Av. Y". Perguntou rua e é avenida, responda a avenida (e o contrário). Sem avenida na linha: o bairro e o condomínio, e
   "perguntar" para a equipe. Nunca o número nem uma rua que não esteja na linha.
6. FOTO DE UMA PARTE (dos quartos, do roupeiro, do banheiro, da cozinha, da varanda, da vista, da fachada, da área de
   lazer...): você NÃO sabe qual foto é de qual cômodo. Não mande fotos e não prometa que manda: diga que vai separar
   essas fotos e já retorna, e marque acao "perguntar" com o pedido em "motivo" (ex.: "fotos dos quartos com roupeiros
   dos imóveis 9026, 9037 e 5724"). A equipe recebe a pergunta e manda as fotos por aqui.
Seja flexível: se ela pula etapas, acompanhe; se faz uma pergunta sobre um imóvel, responda pela ficha. Se numa mensagem
só ela pede as fotos E já diz o que procura (valor, região), faça as duas coisas: "acoes": ["fotos", "buscar"].
BAIRROS: escreva bairros de Manaus. Avenida ou região vira os bairros por onde ela passa (ex.: "da Constantino Nery até
a Ponta Negra" = Chapada, São Jorge, Dom Pedro, Planalto, Alvorada, Ponta Negra). Os bairros vizinhos o sistema já soma.
MOBÍLIA (locação): "mobiliado" = com móveis; "semi" = modulados e/ou ar-condicionado; "sem" = NÃO quer mobiliado ("sem
mobília", "vazio", "já tem os móveis dele"; modulados e ar servem); "tanto_faz" = ela disse que tanto faz; "" = ainda
não perguntou. Quem quer "semi" também recebe mobiliado; quem quer "sem" nunca recebe mobiliado.
COMERCIAL (galpão, prédio, sala, loja, ponto, terreno): NUNCA pergunte de mobília (mobiliado ou semi) nem de quartos, e
não pergunte de escada. Pergunte só o valor e a região (e o crédito, na venda).
DA NAY PARCERIA (Pedro, 25/10: o que ela já faz e vale aqui também):
- "Manda o que você tem", "pode mandar", "me manda as opções", "qualquer um serve": PARE as perguntas. O que falta vira
  tanto faz e você pede a busca ("buscar") já nesta resposta.
- Pergunta de filtro sai UMA vez. Se ela respondeu outra coisa e deixou a sua pergunta de lado, não pergunte de novo:
  trate como tanto faz e siga o roteiro.
- "Tá valendo?", "compensa?", "vale a pena?" de um imóvel disponível na ficha: "Está valendo, sim! Está disponível por
  R$ X." (o valor da ficha). Não é dúvida para a equipe.
- Energia (conta de luz) é do locatário: quem aluga paga o consumo. Só a energia solar do imóvel não entra nessa regra.
- Andar: com escada, diga os lances; com elevador, o andar; prédio com mais de 10 andares, só andar baixo, médio ou
  alto. "Andar alto" na ficha é a resposta: não diga que não sabe.
- O nome do condomínio pode vir escrito de ouvido ou pela metade ("o do laranjeiras", "piazza dell acqua"): é o mais
  parecido entre os IMÓVEIS DESTA CONVERSA. Se servir a dois, pergunte qual pelo nome dos dois.
DO TEL (28/10):
- Financiamento: imóvel que aceita financiamento aceita QUALQUER banco que faz financiamento habitacional (Caixa, Banco
  do Brasil, Itaú, Bradesco, Santander...). "Pode ser pela Caixa?" tem resposta: sim. Não é dúvida para a equipe. A
  entrada e a parcela saem da simulação: não invente números; ofereça fazer a simulação com ela.
- Disponibilidade: só diga "está disponível" de imóvel com ficha do nosso site. Ficha com "disponibilidade: NÃO
  CONFIRMADA" (imóvel de parceiro, ou que ela trouxe do site antigo) você não confirma: diga que vai verificar e marque
  "perguntar".

=== QUANDO VEIO DIRETO (ORGÂNICO) ===
Não houve OLX nem anúncio: a pessoa escreveu para este número por conta própria. NUNCA fale de anúncio, de OLX, de "falamos
antes". Se uma mensagem sua nesta conversa já falou de anúncio, foi engano: não repita (se ela estranhar, peça desculpas
pela confusão e siga).
1. ABERTURA (você ainda não falou com ela): responda o cumprimento pela hora de AGORA, apresente-se e pergunte se ela
   procura imóvel e se é para alugar ou comprar. Se ela já disse o que quer, não pergunte de novo: siga o roteiro.
   Ex.: "Boa tarde! Aqui é a Nay, da Imob Easy. Você está procurando imóvel? Seria para alugar ou para comprar?"
   Se ela citou um imóvel (pelo código ou pelo nome, ex.: "Quero saber mais sobre o imóvel Cobertura - Life Flores"), o
   sistema dá a ficha: responda pela ficha e pergunte se ela quer agendar uma visita ou receber outras opções parecidas,
   como na OLX (o tipo, os quartos e a finalidade vêm desse imóvel).
2. Se o assunto não é procurar imóvel (quer vender ou alugar o imóvel dela, é corretor, cobrança, outro assunto): diga com
   naturalidade que já passa para a equipe e marque "equipe" com o motivo.
3. Procura imóvel: o mesmo roteiro de OUTRAS OPÇÕES, uma pergunta por vez, começando pelo que o anúncio daria: o TIPO
   (apartamento, casa, casa em condomínio ou comercial; "tanto faz" vale) e, se residencial, quantos quartos (UMA
   pergunta: o número que ela disser é o que vale, sem "serve 2?" depois); depois até que valor,
   quais bairros, a mobília (só na LOCAÇÃO residencial: mobiliado, modulados e ar, ou tanto faz), a escada (só na VENDA
   até R$ 500.000, se ela quer apartamento) e o crédito (só na VENDA). Fechamento
   e acao "buscar" como lá.

=== VENDA OU LOCAÇÃO ===
O anúncio diz qual é (no orgânico, ela diz). O VALOR também diz (Pedro, 22/10: "o cliente disse que quer até 1 milhão
e ela não precisa perguntar se é para venda ou locação"): acima de R$ 100.000 é COMPRA; até R$ 30.000 é ALUGUEL. Com
um valor desses, não pergunte se é para alugar ou comprar: siga o roteiro da compra ou da locação. Só entre R$ 30.000 e
R$ 100.000 (ou sem valor) é que se pergunta.
Na locação o campo "incluso" da ficha é o que está INCLUSO NO ALUGUEL (ex.: água, gás, condomínio).
Na locação não fale de financiamento; na venda não fale de caução nem fiador.

=== A EQUIPE NA CONVERSA (as falas EQUIPE) ===
(Pedro, 21/10: "toda vez que eu mandar mensagem para o lead ... ela tem que entender o contexto da conversa para poder
voltar a atender".) EQUIPE é a nossa equipe (o Tel) escrevendo por este mesmo número: para ela, foi a Imob Easy. O que a
equipe disse VALE, e você continua de onde ela parou:
- A equipe confirmou a visita ("confirmado", "confirmada a visita amanhã às 11h"): a visita ESTÁ confirmada. Não mande
  confirmação, não diga que vai confirmar com corretor ou proprietário, não marque "visita" nem "confirmou_visita".
- A equipe fez uma pergunta e ela respondeu: a resposta é para ESSA pergunta (ex.: a equipe perguntou "até que valor?" e
  ela disse "1.000.000": é o teto da busca, não a escolha de um imóvel). Siga o roteiro a partir daí.
- Não repita o que a equipe já disse ou perguntou, e não se apresente de novo.

=== QUANDO É COM A EQUIPE (acao "equipe") ===
Documentação, contrato, reclamação, pedido para falar com uma pessoa, corretor oferecendo parceria, cliente que decidiu
fechar (quer comprar ou alugar, vai dar entrada) ou que mandou documentos. Diga com
naturalidade que já passa para a equipe e que vão falar com ela por aqui. (Desconto, proposta e menor valor NÃO: é
"perguntar", a equipe responde e a conversa continua com você.) Interesse num imóvel ("tenho interesse", "gostei desse",
"quero ver esse", "tenho um cliente interessado nesse") também NÃO é com a equipe: é a VISITA. Mande o imóvel se ela
ainda não viu (acao "fotos") e pergunte o dia e o horário.

=== UMA CONFIRMAÇÃO SÓ ===
- Cada pedido é confirmado UMA vez. Quando for buscar, é UM balão só, juntando nele o que for perguntar à equipe (ex.:
  "Perfeito, Sr. Felipe! Vou confirmar com a equipe a entrada com o apartamento e já pego as opções no meu sistema para
  lhe enviar."); os imóveis chegam logo depois, pelo sistema.
- Já disse que vai confirmar algo com a equipe ou que já retorna: não diga de novo. Se ela só agradeceu, disse "ok" ou
  "aguardo", não responda (balões vazios).

=== NUNCA ===
- Pedir o código do imóvel. O código é nosso, não dela: ele vem da conversa (anúncio, cards, nome do condomínio).
- Repetir uma pergunta ou uma frase que você já mandou nesta conversa. Perguntou e ela ainda não respondeu: espere a
  resposta dela (balões vazios é melhor que repetir). Já disse que vai confirmar com a equipe: não diga de novo a cada
  mensagem; responda o que ela disse agora.
- Dar negativa ("não consigo", "não dá", "não é possível", "não temos"). Se a busca não achar, o sistema avisa a equipe
  e diz a ela que você está separando as opções.
- Inventar. O que não está na ficha você não sabe: diga que confirma e retorna. Isso vale para CRECI, CNPJ e qualquer
  número de documento: só o que o sistema deu; senão, "vou confirmar com a equipe".
- Endereço exato, número da casa ou do apartamento, bloco, torre, nome do proprietário. Bairro, condomínio e as avenidas
  da linha do imóvel pode.
- Link, telefone, e-mail, emoji.
- Falar de Nay da OLX, de robô, de ficha, de catálogo. Para ela você é só a Nay, da Imob Easy.
- Dizer que um imóvel é "de parceiro", "de parceria" ou "de outra imobiliária". Para ela todo imóvel é da Imob Easy.

=== COMO VOCÊ FALA ===
Português do Brasil, de gente: uma moça de Manaus no WhatsApp do trabalho, não um assistente traduzido do inglês. Curto:
um ou dois balões, poucas linhas. Trate pelo tratamento que o sistema dá (Sra./Sr. + primeiro nome; "a senhora", "o
senhor"); sem tratamento, pelo primeiro nome e "você". Nada de "Como posso te ajudar hoje?", "Fico à disposição".
Valor em reais assim: R$ 700.000 / R$ 2.500.

=== A SUA RESPOSTA: SÓ ESTE JSON, NADA MAIS ===
{"baloes": ["..."], "acoes": [],
 "filtros": {"finalidade": "", "tipo": "", "teto": 0, "bairros": [], "qualquer_bairro": false, "quartos": 0,
             "aceita_menos_quartos": null, "aceita_escada": null, "financiamento": "", "mobilia": "", "condominio": "",
             "perto_de": "", "perto_km": 0, "pet": "", "exigencias": [], "recusados": [], "so_condominio": false},
 "fotos": {"codigos": []}, "depois_das_fotos": [], "card": {"codigos": []}, "visita": {"codigo": 0, "data": "", "hora": ""},
 "motivo": ""}
- acoes: [] ou, na ordem, até duas de: "fotos" (o card, se ela ainda não viu, e as fotos dos imóveis em fotos.codigos) |
  "card" (só o card de novo dos imóveis em card.codigos, para ela apontar qual) | "buscar" |
  "visita" | "confirmou_visita" | "perguntar" (você precisa
  que a equipe responda ou mande algo, e a conversa continua com você) | "equipe" (a conversa passa para a equipe) |
  "encerrar" (ela agradeceu e não quer mais nada).
- filtros: TUDO o que ela já disse até agora (aqui e na OLX); vazio/0/null o que não disse. finalidade: "locacao" ou
  "venda" (sem ela dizer, é a do anúncio). tipo: "apartamento", "casa", "casa_condominio", "tanto_faz" ou, no
  comercial, "galpao", "predio", "sala", "loja", "terreno" ("comercial" quando ela não disser qual). teto: só o
  número em reais. quartos: o número que ela quer. financiamento: "aprovado", "simular", "a vista" ou "".
  mobilia: "mobiliado", "semi" (modulados e/ou ar), "sem" (não quer mobiliado), "tanto_faz" ou "" (ainda não disse).
  condominio: o nome do condomínio que ela pediu ou disse que quer ("no Parque das Laranjeiras", "algo no Vision"),
  como ela escreveu; "" se não disse nenhum. A busca traz esse e os condomínios próximos dele primeiro.
  No orgânico, finalidade quando ela disser ou pelo valor (acima de R$ 100.000 "venda", até R$ 30.000 "locacao").
  A NECESSIDADE CRESCE na conversa (Pedro, 24/10, a Esther): cada coisa nova que ela revelar entra nos filtros e fica;
  nunca apague o que ela já disse. perto_de: o lugar de referência quando ela quer perto de algum ("acesso fácil ao
  Distrito" = "Distrito Industrial"; um bairro ou lugar de Manaus); o SISTEMA calcula a distância de verdade e só traz o
  que fica perto: NUNCA diga distância, "fica longe" ou "fica perto" por conta própria. perto_km: só se ela disse
  quantos km. pet: o que ela disse do bicho ("2 gatas", "cachorro pequeno"). exigencias: o que ela quer e os outros
  campos não cobrem ("cozinha e lavanderia completas", "elevador", "andar baixo"), um item curto cada.
  so_condominio: true quando ela quer SÓ no condomínio que disse ("só no Ponta Negra Village", "somente no Flex Parque
  Dez"): a busca não traz outro lugar.
  recusados: o que ela recusou ou descartou, para NUNCA voltar na busca: o código do imóvel ("esse não serve" de um
  card que você mandou) ou o nome do condomínio que ela não quer ("já mora no Liverpool", "na Reserva Inglesa não").
  Mobiliado é MOBILIADO: nunca ofereça nem aceite "modulados e ar" para quem pediu mobiliado.
- visita: o código do imóvel (da lista do sistema, NUNCA perguntado a ela), a data (DD/MM) e a hora (HH:MM) que ela disse.
- motivo: em poucas palavras, para a equipe (com "perguntar" ou "equipe"): o que ela pediu, com os códigos.
"""


# ── a Z-API da captação: a mesma do config do vigia (só root lê); nada de segredo aqui ──
def _instancia() -> dict:
    conf = grupo._conf_do_vigia()
    inst = (conf or {}).get("instancias", {}).get("captacao")
    if not inst:
        raise ErroDeEnvio("não achei a Z-API da captação no config do vigia")
    return inst


_CONEXAO = [0.0, False]


def conectada() -> bool:
    """Desconectada, a Z-API aceita e não entrega (02/10): sem conexão, a Nay não fala. A resposta vale 30 s (a volta é
    de 5 em 5 s e várias partes perguntam)."""
    if time.monotonic() - _CONEXAO[0] < 30:
        return bool(_CONEXAO[1])
    try:
        st = grupo._zapi(_instancia(), "GET", "/status")
        ok = isinstance(st, dict) and bool(st.get("connected"))
    except ErroDeEnvio:
        ok = False
    _CONEXAO[0], _CONEXAO[1] = time.monotonic(), ok
    return ok


def _mandar(conn, lead: dict, caminho: str, corpo: dict, tipo: str, codigo: int | None = None,
            texto_no_crm: str | None = None) -> str:
    r = grupo._zapi(_instancia(), "POST", caminho, {"phone": "55" + lead["telefone"], **corpo}, timeout=40)
    mid = str((r or {}).get("messageId") or (r or {}).get("id") or "") if isinstance(r, dict) else ""
    if not mid:
        raise ErroDeEnvio((r or {}).get("_erro") if isinstance(r, dict) else "sem resposta da Z-API")
    banco.um(conn, """INSERT INTO privado.olx_cliente_enviada (message_id, lead, tipo, codigo) VALUES (%s, %s, %s, %s)
                      ON CONFLICT (message_id) DO NOTHING""", (mid, lead["id"], tipo, codigo))
    if texto_no_crm:
        # a conversa do CRM (aba Captação) é captacao_mensagens: se o eco da Z-API chegou antes, só vira 'resposta'
        banco.um(conn, """
            WITH ja AS (UPDATE captacao_mensagens SET origem = 'resposta' WHERE message_id = %(mid)s AND direcao = 'enviada'
                        RETURNING 1)
            INSERT INTO captacao_mensagens (telefone, direcao, origem, texto, status, message_id)
            SELECT %(tel)s, 'enviada', 'resposta', %(texto)s, 'Enviado', %(mid)s WHERE NOT EXISTS (SELECT 1 FROM ja)""",
                 {"mid": mid, "tel": "55" + lead["telefone"], "texto": texto_no_crm})
    return mid


def mandar_texto(conn, lead: dict, texto: str) -> str:
    """Um texto dela. O MESMO texto para a mesma pessoa nas últimas 6 h não sai de novo (Pedro, 16/10: "fez a mesma
    pergunta duas vezes para o lead ... precisa checar para ela nunca fazer isso"). Devolve '' quando segurou."""
    if any(_normal(texto) == _normal(x) for x in ja_mandou(conn, lead, horas=6)):
        log.info("lead %s: texto repetido segurado: %s", lead.get("id"), texto[:80])
        return ""
    return _mandar(conn, lead, "/send-text", {"message": texto}, "texto", texto_no_crm=texto)


# ── nunca repetir (392b) ──
def _normal(t: str | None) -> str:
    t = unicodedata.normalize("NFKD", (t or "").lower())
    t = "".join(c for c in t if not unicodedata.combining(c))
    return " ".join(re.sub(r"[^a-z0-9]+", " ", t).split())


def parecida(a: str | None, b: str | None, limite: float = 0.85) -> bool:
    na, nb = _normal(a), _normal(b)
    if not na or not nb:
        return False
    return na == nb or SequenceMatcher(None, na, nb).ratio() >= limite


def ja_mandou(conn, lead: dict, horas: int = 24) -> list[str]:
    """Os textos que foram para esta pessoa por este número (dela ou da equipe), os mais novos primeiro."""
    return [l["texto"] for l in banco.linhas(conn, """
        SELECT texto FROM captacao_mensagens
         WHERE direcao = 'enviada' AND coalesce(btrim(texto), '') <> '' AND criada_em > now() - make_interval(hours => %s)
           AND right(regexp_replace(coalesce(telefone, ''), '\\D', '', 'g'), 8) = %s
         ORDER BY id DESC LIMIT 80""", (horas, _so8(lead["telefone"])))]


def _frases(t: str) -> list[str]:
    return [f.strip() for f in re.split(r"(?<=[.!?])\s+", t or "") if f.strip()]


def sem_repetir(baloes: list[str], ja: list[str]) -> list[str]:
    """Tira o balão igual (ou quase) a um que já foi, e a PERGUNTA já feita de dentro de um balão novo ("Até que valor
    o senhor procura?" duas vezes): o resto do balão fica. Balão que ficou vazio sai."""
    frases_ja = [f for x in ja for f in _frases(x)]
    saida: list[str] = []
    for b in baloes:
        if any(parecida(b, x) for x in ja + saida):
            continue
        # a pergunta já feita sai (0,8); a frase de 4+ palavras já dita também ("Assim que tiver um retorno, aviso por aqui.")
        frases = [f for f in _frases(b)
                  if not any(parecida(f, p, 0.8 if f.endswith("?") else 0.85) for p in frases_ja
                             if f.endswith("?") or len(f.split()) >= 4)]
        novo = " ".join(frases).strip()
        if len(novo.split()) <= 3 and len(frases) < len(_frases(b)):
            continue                      # sobrou só o "Certo, Sr. Carlos!" de uma pergunta repetida: não vale um balão
        if novo and not any(parecida(novo, x) for x in ja + saida):
            saida.append(novo)
    return saida


def mandar_imovel(conn, lead: dict, codigo: int, com_card: bool = True, com_fotos: bool = True) -> int:
    """O card e as fotos de UM imóvel (sem a colagem, que é só dos grupos). Devolve quantas fotos saíram.
    `com_card=False`: só as fotos ("gostaria de ver mais fotos" do imóvel que ela já conhece).
    `com_fotos=False`: só o card (21/10: para ela dizer qual imóvel quer visitar, sem pedir o código)."""
    # 400: o card de CLIENTE (o de parceiro sai completo); só chega aqui o que _ofertavel deixou
    card = banco.um(conn, "SELECT texto_pronto FROM nai_card_do_imovel(%s, true)", (codigo,)) if com_card else None
    if card:
        _mandar(conn, lead, "/send-text", {"message": card}, "card", codigo, texto_no_crm=card)
    if not com_fotos:
        return 0
    fotos = [l["url"] for l in banco.linhas(conn, "SELECT url FROM nai_imagens_do_envio(%s) WHERE NOT e_colagem", (codigo,))
             if l.get("url")][:MAX_FOTOS]
    for url in fotos:
        time.sleep(ENTRE_ENVIOS_S)
        _mandar(conn, lead, "/send-image", {"image": url}, "foto", codigo)
    return len(fotos)


# ── o banco ──
def _so8(t: str | None) -> str:
    return re.sub(r"\D", "", t or "")[-8:]


def _lista(v: str | None) -> set[str]:
    return {_so8(x) for x in re.split(r"[,;\s]+", v or "") if len(re.sub(r"\D", "", x)) >= 8}


def _pode(cfg: dict, telefone: str) -> bool:
    if _so8(telefone) in _lista(cfg.get("whatsapp_nunca")):
        return False
    modo = (cfg.get("whatsapp_responde") or "nao").strip().lower()
    return modo == "sim" or (modo == "teste" and _so8(telefone) in _lista(cfg.get("whatsapp_teste")))


def _lead(conn, lid: int) -> dict:
    l = banco.linhas(conn, """SELECT l.*, nay_tratamento_por_nome(l.nome) AS trat FROM privado.olx_lead_whatsapp l
                               WHERE l.id = %s""", (lid,))
    return l[0] if l else {}


def _gente_escreveu(conn, lead: dict, desde) -> object:
    """A última mensagem de GENTE para esta pessoa por este número (texto que não foi a Nay), depois de `desde`: a do
    celular (captacao_mensagens) ou, desde 21/10, a do CRM (crmdb)."""
    daqui = _gente_escreveu_daqui(conn, lead, desde or banco.um(conn, "SELECT now() - interval '30 days'"))
    crm = [e["criada_em"] for e in da_equipe_no_crm(_so8(lead.get("telefone")), 1)
           if desde is None or e["criada_em"] > desde]
    return max([x for x in [daqui, *crm] if x is not None], default=None)


def _gente_escreveu_daqui(conn, lead: dict, desde) -> object:
    return banco.um(conn, """
        SELECT max(m.criada_em) FROM captacao_mensagens m
         WHERE m.direcao = 'enviada' AND m.criada_em > %s AND coalesce(btrim(m.texto), '') <> ''
           AND coalesce(m.origem, '') NOT IN ('resposta', 'disparo')
           AND right(regexp_replace(coalesce(m.telefone, ''), '\\D', '', 'g'), 8) = %s
           AND NOT EXISTS (SELECT 1 FROM privado.olx_cliente_enviada e WHERE e.message_id = m.message_id)""",
                    (desde, _so8(lead["telefone"])))


def _marcar(conn, lid: int, **campos) -> None:
    if not campos:
        return
    sets, vals = [], []
    for k, v in campos.items():
        if k == "etapa":
            sets.append("etapa = %s, etapa_em = now()")
        elif k in ("filtros", "visita"):
            sets.append(f"{k} = %s::jsonb")
            v = json.dumps(v, ensure_ascii=False)
        elif k == "assumido_em_agora":
            sets.append("assumido_em = now()")
            continue
        else:
            sets.append(f"{k} = %s")
        vals.append(v)
    banco.um(conn, f"UPDATE privado.olx_lead_whatsapp SET {', '.join(sets)}, atualizado_em = now() WHERE id = %s",
             (*vals, lid))


_CRM = [None]


def da_equipe_no_crm(tel8: str, limite: int = 20) -> list[dict]:
    """21/10: o que a equipe mandou pelo CRM (WhatsApp Leads, a linha Z-API da captação) para este número. Fica só no crmdb
    (lead_activities), não em captacao_mensagens: sem isto a Nay não via o Tel ("confirmado a nossa visita amanhã") e
    respondia por cima. Só leitura; falhou = [] e a Nay segue como antes."""
    if not tel8 or not config.CRM_DATABASE_URL:
        return []
    try:
        if _CRM[0] is None or _CRM[0].closed:
            _CRM[0] = psycopg2.connect(config.CRM_DATABASE_URL, connect_timeout=5, application_name="nay-olx-crm",
                                       options="-c statement_timeout=15000 -c default_transaction_read_only=on")
            _CRM[0].autocommit = True
        with _CRM[0].cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute("""
                SELECT a.created_at AS criada_em, btrim(a.content) AS texto, p.full_name AS quem
                  FROM lead_activities a
                  JOIN leads l ON l.id = a.lead_id
                  JOIN integrations i ON i.id = l.integration_id
                  LEFT JOIN organization_members m ON m.id = a.actor_member_id
                  LEFT JOIN profiles p ON p.id = m.user_id
                 WHERE i.type = 'whatsapp_zapi_captacao' AND a.type = 'whatsapp'
                   AND right(regexp_replace(coalesce(l.phone, ''), '[^0-9]', '', 'g'), 8) = %s
                   AND a.metadata->>'direction' = 'outbound'
                   AND (a.metadata->>'source' = 'human' OR a.metadata->>'do_celular' = 'true')   -- 25/10: o celular
                   AND coalesce(btrim(a.content), '') <> '' AND a.created_at > now() - interval '30 days'
                 ORDER BY a.created_at DESC LIMIT %s""", (tel8, limite))
            return [dict(r) for r in cur.fetchall()]
    except Exception:  # noqa: BLE001
        log.exception("não li a equipe no crmdb")
        try:
            if _CRM[0] is not None:
                _CRM[0].close()
        except Exception:  # noqa: BLE001
            pass
        _CRM[0] = None
        return []


def _conversa(conn, lead: dict) -> list[dict]:
    """As mensagens daqui (captacao_mensagens) e, junto, as da equipe pelo CRM (21/10), na ordem do relógio."""
    daqui = _conversa_daqui(conn, lead)
    textos = {_normal(m.get("texto") or "") for m in daqui if m.get("direcao") == "enviada"}
    equipe = [{"id": 0, "direcao": "enviada", "origem": "equipe_crm", "texto": e["texto"], "criada_em": e["criada_em"],
               "nossa": False, "quem": e.get("quem")}
              for e in da_equipe_no_crm(_so8(lead.get("telefone")))
              if _normal(e["texto"]) not in textos]
    juntas = sorted(daqui + equipe, key=lambda m: m["criada_em"])
    return juntas[-40:]


def novas_depois_da_equipe(conversa: list[dict], ultima_lida: int, equipe_em) -> list[dict]:
    """As mensagens dela ainda não lidas que chegaram DEPOIS da última fala da equipe (22/10): as de antes, a equipe já
    respondeu."""
    return [m for m in conversa if m.get("direcao") == "recebida" and (m.get("id") or 0) > ultima_lida
            and (equipe_em is None or m.get("criada_em") is None or m["criada_em"] > equipe_em)]


def _conversa_daqui(conn, lead: dict) -> list[dict]:
    return list(reversed(banco.linhas(conn, """
        SELECT m.id, m.direcao, m.origem, m.texto, m.criada_em,
               EXISTS (SELECT 1 FROM privado.olx_cliente_enviada e WHERE e.message_id = m.message_id) AS nossa
          FROM captacao_mensagens m
         WHERE right(regexp_replace(coalesce(m.telefone, ''), '\\D', '', 'g'), 8) = %s
           AND m.criada_em > now() - interval '30 days'
           -- 394: o eco das fotos (sem texto) não ocupa o lugar da conversa
           AND (m.direcao = 'recebida' OR coalesce(btrim(m.texto), '') <> '')
         ORDER BY m.id DESC LIMIT 40""", (_so8(lead["telefone"]),))))


def _int(v) -> int | None:
    """O número que o modelo mandou ("#9026", "9026", 9026.0, "R$ 2.500") ou None."""
    if isinstance(v, bool) or v is None:
        return None
    if isinstance(v, (int, float)):
        return int(v) or None
    d = re.sub(r"\D", "", str(v))
    return int(d) if d else None


def _ultimas_do_cliente(conn, lead: dict, n: int = 3) -> str:
    """O que o cliente mandou por último (até n mensagens, da mais antiga à mais nova), para o aviso da equipe."""
    textos = [l["texto"] for l in banco.linhas(conn, """
        SELECT texto FROM captacao_mensagens
         WHERE direcao = 'recebida' AND coalesce(btrim(texto), '') <> ''
           AND right(regexp_replace(coalesce(telefone, ''), '\\D', '', 'g'), 8) = %s
         ORDER BY id DESC LIMIT %s""", (_so8(lead["telefone"]), n))]
    return " / ".join(t.strip().replace("\n", " ")[:240] for t in reversed(textos))


def _ultima_recebida(conn, lead: dict) -> int:
    return int(banco.um(conn, """SELECT coalesce(max(id), 0) FROM captacao_mensagens WHERE direcao = 'recebida'
                                  AND right(regexp_replace(coalesce(telefone, ''), '\\D', '', 'g'), 8) = %s""",
                        (_so8(lead["telefone"]),)) or 0)


# ── o turno que vai ao modelo ──
def tratamento(lead: dict) -> tuple[str, str]:
    """('Sra. Claudia', 'a senhora') | ('Sr. Felipe', 'o senhor') | ('Ana', 'você')."""
    primeiro = ((lead.get("nome") or "").strip().split() or [""])[0].capitalize()
    t = lead.get("trat")
    if t == "Sra." and primeiro:
        return f"Sra. {primeiro}", "a senhora"
    if t == "Sr." and primeiro:
        return f"Sr. {primeiro}", "o senhor"
    return primeiro or "", "você"


def organico(lead: dict) -> bool:
    return lead.get("origem") == "organico"


def quem(lead: dict) -> str:
    """Para os avisos da equipe: 'Fulana (OLX, (92) 9...)' ou '(orgânico, ...)'."""
    # 422: o cliente posto à mão no CRM (Buscar imóvel OLX) aparece como "pelo CRM"
    origem = {"organico": "orgânico", "manual": "pelo CRM"}.get(lead.get("origem") or "", "OLX")
    return (f"{lead.get('nome') or 'sem nome'} ({origem}, "
            f"{nay.telefone_bonito(lead['telefone'])})")


CODIGO_CITADO = re.compile(r"(?<![\d.,$])#?(\d{4})(?![\d.,]|\s*(?:mil|reais|k\b))", re.I)


# 394: "até 2500", "uns 3000", "aluguel de 2800" são valor, não código de imóvel
VALOR_EM_REAIS = re.compile(r"(R\$|\bat[eé]\b|\b(?:uns|umas|uma|um)\b|\bpor\b|\bvalor\b|\baluguel( de)?\b|\bor[cç]amento\b|\bpag(ar|o)\b|"
                            r"\bteto\b|\bm[aá]ximo\b|\bde\b)\s*[0-9.,]+", re.I)


def codigos_citados(conversa: list[dict], ate: int = 2) -> list[int]:
    """Os códigos de imóvel que a pessoa escreveu (os últimos primeiro): "5758", "#5758", "o 5758"; "2500 reais" não."""
    vistos: list[int] = []
    for m in reversed(conversa):
        if m.get("direcao") != "recebida":
            continue
        # 26/10: o número de dentro de um link ("...?gallery_id=1020") não é código; o link é lido por codigos_dos_links
        sem_link = re.sub(r"https?://\S+|\S+\.com(\.br)?/\S*", " ", m.get("texto") or "")
        for c in reversed(CODIGO_CITADO.findall(VALOR_EM_REAIS.sub(" ", sem_link))):
            if int(c) not in vistos:
                vistos.append(int(c))
    return vistos[:ate]


LINK_OLX = re.compile(r"olx\.com\.br/\S*?-(\d{9,11})(?=[?#/\s]|$)", re.I)


def codigos_dos_links(conn, conversa: list[dict], ate: int = 2) -> list[int]:
    """26/10 (o lead 25 colou o link do Kopenhagen e havia dois Kopenhagen disponíveis, 5360 e 5758): o link da OLX que ela
    colou é um anúncio NOSSO (privado.olx_anuncio.list_id); o código dele vale mais que o nome do condomínio."""
    ids: list[str] = []
    for m in reversed(conversa):
        if m.get("direcao") == "recebida":
            ids += [i for i in reversed(LINK_OLX.findall(m.get("texto") or "")) if i not in ids]
    if not ids:
        return []
    achados = {r["list_id"]: int(r["codigo"]) for r in banco.linhas(conn, """
        SELECT DISTINCT ON (list_id) list_id, codigo FROM privado.olx_anuncio WHERE list_id = ANY(%s) ORDER BY list_id, id DESC""",
                                                                    (ids,))}
    return list(dict.fromkeys(achados[i] for i in ids if i in achados))[:ate]


def _pelo_nome(conn, conversa: list[dict]) -> list[int]:
    """Sem código: o condomínio que ela escreveu ("Quero saber mais sobre o imóvel Cobertura - Life Flores", a mensagem
    pronta dos portais), disponível, o tipo que ela disse primeiro."""
    texto = " ".join((m.get("texto") or "") for m in conversa if m.get("direcao") == "recebida")[-1500:]
    if not texto.strip():
        return []
    return [int(l["codigo"]) for l in banco.linhas(conn, """
        WITH n AS (
          -- 21/10 ("Esse apartamento Piazza dell'acqua" não achava o "Residencial Piazza Dell'Acqua"): o nome sem
          -- "Residencial/Condomínio/Edifício..." na frente e sem pontuação, comparado com o texto dela do mesmo jeito
          SELECT codigo, tipo, condominio_nome,
                 btrim(regexp_replace(regexp_replace(lower(unaccent(btrim(condominio_nome))),
                       '^(residencial|condominio|cond|edificio|ed|conjunto|conj|residence|resort)[ .]+', ''),
                       '[^a-z0-9]+', ' ', 'g')) AS nome
            FROM imoveis
           WHERE status = 'Disponível' AND length(btrim(coalesce(condominio_nome, ''))) >= 6
             -- o "condomínio" que é só o tipo (Apartamento, Prédio, Loja/Ponto...) não é nome
             AND lower(unaccent(btrim(condominio_nome))) <> lower(unaccent(coalesce(tipo, '')))
             AND lower(unaccent(btrim(condominio_nome)))
                 !~ '^(apartamento|predio|casa|cobertura|kitnet|terreno|sala|loja|galpao)([/ ].*)?$'
             -- "Residencial"/"Condomínio" sozinho (ou "não identificado") não é nome; "Residencial Piazza..." é
             AND lower(unaccent(btrim(condominio_nome))) !~ '^(condominio|residencial)( nao identificado)?$')
        SELECT codigo FROM n
         WHERE length(nome) >= 5
           AND position(' ' || nome || ' ' IN ' ' || btrim(regexp_replace(lower(unaccent(%(t)s)), '[^a-z0-9]+', ' ', 'g')) || ' ') > 0
         ORDER BY position(lower(unaccent(coalesce(tipo, '-'))) IN lower(unaccent(%(t)s))) > 0 DESC, codigo DESC
         LIMIT 3""", {"t": texto})]


def imoveis_da_conversa(conn, lead: dict) -> list[str]:
    """21/10: os imóveis que já apareceram (o do anúncio, os enviados, os que ela citou), um por linha, com o nome:
    "#3227 · Apartamento · Residencial Piazza Dell'Acqua, Ponta Negra · venda R$ 950.000 · 4 quartos"."""
    cods: list[int] = []
    for c in [lead.get("codigo"), *(lead.get("enviados") or []), *[f.get("codigo") for f in lead.get("fichas_citadas") or []]]:
        c = _int(c)
        if c and c not in cods:
            cods.append(c)
    if not cods:
        return []
    # 27/10 (Pedro: "temos uma planilha com os nomes das ruas de cada condomínio ... ela deve tratar rua e avenida como
    # iguais"): a lista (condominioporruaseav.txt) é a nai_lugar_conjunto (206). As avenidas do conjunto do imóvel; sem
    # conjunto reconhecido, as dos conjuntos do bairro dele.
    linhas = banco.linhas(conn, """
        SELECT i.codigo, i.tipo, nay_condominio_de_verdade(i.tipo, i.condominio_nome) AS condo, i.bairro, i.quartos,
               i.valor_venda, i.valor_aluguel,
               (SELECT string_agg(DISTINCT btrim(a), ', ') FROM nai_lugar_conjunto c, unnest(string_to_array(c.avenidas, '/')) a
                 WHERE nai_lugar_normal(coalesce(i.condominio_nome, '') || ' ' || coalesce(i.logradouro, '')) ~ c.expressao) AS av_conjunto,
               (SELECT string_agg(DISTINCT btrim(a), ', ') FROM nai_lugar_conjunto c, unnest(string_to_array(c.avenidas, '/')) a
                 WHERE lower(unaccent(c.bairro)) = lower(unaccent(i.bairro))) AS av_bairro
          FROM imoveis i WHERE i.codigo = ANY(%s::int[])""", (cods,))
    por = {int(l["codigo"]): l for l in linhas}
    saida = []
    for c in cods:
        l = por.get(c)
        if not l:
            continue
        valores = " e ".join(x for x in (
            f"venda R$ {int(l['valor_venda']):,}".replace(",", ".") if l.get("valor_venda") else "",
            f"aluguel R$ {int(l['valor_aluguel']):,}".replace(",", ".") if l.get("valor_aluguel") else "") if x)
        onde = ", ".join(x for x in (l.get("condo"), l.get("bairro")) if x)
        avenidas = (f"avenidas do conjunto: {l['av_conjunto']}" if l.get("av_conjunto")
                    else f"avenidas de referência do bairro: {l['av_bairro']}" if l.get("av_bairro") else "")
        saida.append(" · ".join(x for x in (f"#{c}", l.get("tipo") or "", onde, valores,
                                            f"{l['quartos']} quartos" if l.get("quartos") else "", avenidas,
                                            "o do anúncio" if c == lead.get("codigo") else "") if x))
    return saida


DISPONIBILIDADE_DE_PARCEIRO = ("NÃO CONFIRMADA: não está no nosso site atual. Nunca diga que está disponível por esta "
                               "ficha; diga que vai confirmar e marque \"perguntar\".")


def _fichas_citadas(conn, conversa: list[dict], lead: dict | None = None) -> list[dict]:
    fichas = []
    for c in codigos_citados(conversa) or codigos_dos_links(conn, conversa) or _pelo_nome(conn, conversa):
        i = banco.um(conn, "SELECT site_imovel_publico(%s)", (c,))
        if isinstance(i, dict) and i:
            fichas.append({"codigo": c, **nay._ficha(i)})
        elif lead and _ofertavel(conn, c, lead):
            # 400: o de parceiro não tem página pública; ela lê o card de cliente dele
            card = banco.um(conn, "SELECT texto_pronto FROM nai_card_do_imovel(%s, true)", (c,))
            if card:
                # 28/10 (Tel, o Gilson e o 4434): o status do cadastro é cópia do site antigo; de parceiro, só o
                # parceiro confirma
                fichas.append({"codigo": c, "card": card, "disponibilidade": DISPONIBILIDADE_DE_PARCEIRO})
    return fichas


def montar_turno(lead: dict, ctx_olx: dict | None, conversa: list[dict]) -> str:
    ctx_olx = ctx_olx or {}
    anuncio = ctx_olx.get("anuncio") or {}
    negocio = "LOCAÇÃO" if (lead.get("negocio") or anuncio.get("negocio") or "").startswith("loca") else "VENDA"
    trat, pronome = tratamento(lead)
    agora = datetime.now(MANAUS)
    periodo = "manhã: Bom dia" if agora.hour < 12 else "tarde: Boa tarde" if agora.hour < 18 else "noite: Boa noite"
    linhas = [
        f"=== AGORA === {visita.DIAS[agora.weekday()]}, {agora:%d/%m/%Y %H:%M} em Manaus ({periodo}). Cumprimente pela hora "
        f"de AGORA, não pela da OLX.",
        "",
        "=== QUEM É ===",
        f"Nome: {lead.get('nome') or 'não informado'} | trate como: {trat or 'pelo primeiro nome'} ({pronome})",
        "",
    ]
    if organico(lead):
        linhas += [
            "=== DE ONDE VEIO: ORGÂNICO ===",
            "Escreveu direto para este número: não houve OLX nem anúncio. Siga QUANDO VEIO DIRETO.",
        ]
        if not any(m.get("nossa") or m.get("origem") == "resposta" for m in conversa):
            linhas.append("Você ainda não falou com ela: esta é a sua primeira mensagem (a abertura do orgânico).")
        for f in lead.get("fichas_citadas") or []:
            linhas.append(f"Ficha do imóvel {f['codigo']} (o que ela citou): " + json.dumps(f, ensure_ascii=False))
    else:
        linhas += [
            "=== DE ONDE VEIO: O ANÚNCIO NA OLX ===",
            f"{negocio} | {anuncio.get('titulo') or '-'} | cód. {lead.get('codigo') or anuncio.get('codigo') or '-'}",
            "Ficha do imóvel do anúncio: " + json.dumps(nay._ficha(ctx_olx.get("imovel")), ensure_ascii=False),
            "O que a Nay da OLX leu dela: " + json.dumps(lead.get("perfil") or {}, ensure_ascii=False),
            f"Na OLX ela disse que quer visitar: {'sim' if lead.get('quer_visita') else 'não'}",
            "A conversa na OLX (a mais antiga primeiro):",
        ]
        for m in ctx_olx.get("mensagens") or []:
            linhas.append(f"  {nay._quem(m)}: {(m.get('texto') or '').strip()}")
    linhas += [
        "",
        "=== ONDE ESTÁ ===",
        f"Etapa: {lead.get('etapa')}",
        "Filtros já ditos: " + json.dumps(lead.get("filtros") or {}, ensure_ascii=False),
        "Imóveis já enviados (códigos): " + (", ".join(str(c) for c in lead.get("enviados") or []) or "nenhum"),
        "IMÓVEIS DESTA CONVERSA (é daqui que sai o código da visita; NUNCA peça o código a ela):",
        *[f"  {x}" for x in (lead.get("imoveis_conhecidos") or ["nenhum"])],
        _linha_da_visita(lead.get("visita_aberta")),
        "",
        "=== A CONVERSA NO WHATSAPP (a mais antiga primeiro) ===",
    ]
    if not conversa:
        linhas.append("Ainda não há conversa: escreva a PRIMEIRA mensagem (a abertura).")
    for m in conversa:
        texto = (m.get("texto") or "").strip()
        if m.get("direcao") == "recebida":
            linhas.append(f"CLIENTE: {texto or '[mandou ' + (m.get('origem') or 'uma mídia') + ']'}")
        elif m.get("nossa") or m.get("origem") == "resposta":
            if texto:
                linhas.append(f"NAY: {texto}")
        elif texto:
            linhas.append(f"EQUIPE{' (' + m['quem'] + ')' if m.get('quem') else ''}: {texto}")
    linhas += ["", "Responda agora, só com o JSON."]
    return "\n".join(linhas)


PE_DA_VISITA = {
    "confirmar_cliente": "a confirmação foi para ela; espere o sim (acao confirmou_visita) ou a correção (acao visita)",
    "buscando_corretor": "ela confirmou; você está confirmando com o corretor",
    "pedindo_proprietario": "o corretor confirmou; você está confirmando com o proprietário",
    "confirmada": "CONFIRMADA: ela já recebeu a confirmação com o corretor",
    "sem_corretor": "a equipe está combinando quem acompanha; se ela perguntar, diga que está confirmando",
    "sem_proprietario": "a equipe está falando com o proprietário; se ela perguntar, diga que está confirmando",
    "proprietario_nao": "o proprietário não pode nesse horário; ela precisa escolher outro dia e horário",
}


def _linha_da_visita(v: dict | None) -> str:
    if not v:
        return "Visita em andamento: nenhuma"
    q = v["quando"].astimezone(MANAUS)
    return (f"Visita em andamento: imóvel #{v['codigo']}, {visita.dia(q)} às {visita.hora(q)} — "
            f"{PE_DA_VISITA.get(v['estado'], v['estado'])}")


def _filtros(antes: dict, novos) -> dict:
    """Junta o que ela disse agora ao que já sabíamos. Vazio, 0 e null não apagam o que já estava."""
    f = dict(antes or {})
    for k in CAMPOS_DOS_FILTROS:
        v = (novos or {}).get(k) if isinstance(novos, dict) else None
        if k in ("exigencias", "recusados"):
            # só acumula: o que ela já exigiu (ou recusou) não some quando o modelo esquece de repetir
            novas = [str(x).strip()[:120] for x in (v if isinstance(v, list) else []) if str(x).strip()]
            f[k] = list(dict.fromkeys([*(f.get(k) or []), *novas]))[:12 if k == "exigencias" else 20]
            if not f[k]:
                f.pop(k)
            continue
        if k == "perto_km":
            try:
                v = float(v or 0)
            except (TypeError, ValueError):
                v = 0
            if v > 0:
                f[k] = v
            continue
        if v in (None, "", 0, [], False) and k not in ("aceita_menos_quartos", "aceita_escada"):
            continue
        if v is None:
            continue
        if k == "teto":
            v = _int(v)
            if not v:
                continue
        f[k] = v
    if f.get("qualquer_bairro") is True and (novos or {}).get("qualquer_bairro") is True:
        f["bairros"] = []                     # 394: "pode ser qualquer bairro" apaga os bairros ditos antes
    return f


def mudou_o_pedido(antes: dict | None, depois: dict | None) -> str:
    """520 (Pedro, 29/10: "depois se ele mudar de solicitação ela volta a barrinha dele sozinha"): o pedido mudou de
    verdade -- outra finalidade, outro tipo, outro condomínio, outro número de quartos, nenhum bairro em comum ou o teto
    30% para cima ou para baixo. Só compara o que estava dito dos dois lados (dizer mais não é mudar). '' = não mudou."""
    a, d = antes or {}, depois or {}
    for k, nome in (("finalidade", "a finalidade"), ("tipo", "o tipo"), ("condominio", "o condomínio"), ("quartos", "os quartos")):
        if a.get(k) and d.get(k) and _normal(str(a[k])) != _normal(str(d[k])):
            return f"{nome}: {a[k]} -> {d[k]}"
    ba = {_normal(str(x)) for x in a.get("bairros") or []}
    bd = {_normal(str(x)) for x in d.get("bairros") or []}
    if ba and bd and not ba & bd:
        return f"os bairros: {', '.join(a['bairros'])} -> {', '.join(d['bairros'])}"
    ta, td = _int(a.get("teto")), _int(d.get("teto"))
    if ta and td and abs(td - ta) / ta > 0.3:
        return f"o valor: {ta} -> {td}"
    return ""


def condominio_que_faltou(conn, f: dict, conversa: list[dict]) -> dict:
    """27/10 (Pedro: "ela foi procurar opções para a 92 9 8181-9145 e não achou"): o Sr. Karis disse "só no Ponta Negra
    Village"; o modelo marcou so_condominio sem o nome e a busca saiu como "Ponta Negra" inteiro. Sem o nome, ele vem do
    que a pessoa escreveu (o reconhecedor de condomínios da Nay), da mensagem mais nova para a mais velha."""
    if not f.get("so_condominio") or f.get("condominio"):
        return f
    for m in reversed([m for m in conversa if m.get("direcao") == "recebida" and (m.get("texto") or "").strip()][-10:]):
        nome = banco.um(conn, "SELECT c.nome FROM condominios c WHERE c.id = nai_condominio_da_pergunta(%s)", (m["texto"],))
        if nome:
            return {**f, "condominio": nome}
    return f


def _resumo_dos_filtros(f: dict) -> str:
    partes = [f.get("finalidade") or "", f.get("tipo") or "",
              f"até R$ {int(float(f['teto'])):,}".replace(",", ".") if f.get("teto") else "",
              ", ".join(f.get("bairros") or []) or ("qualquer bairro" if f.get("qualquer_bairro") else ""),
              f"{f['quartos']} quartos" if f.get("quartos") else "",
              # 19/10: a mobília entra no resumo, senão a Nay pergunta de novo
              {"mobiliado": "mobiliado", "semi": "modulados e ar", "sem": "sem mobília", "tanto_faz": "mobília tanto faz"}.get(f.get("mobilia") or "", ""),
              f.get("financiamento") or "",
              # 20/10: o condomínio pedido (a busca traz ele e os próximos dele primeiro, olx_cliente_buscar 434)
              f"no {f['condominio']}" if f.get("condominio") else ""]
    return " · ".join(p for p in partes if p)


# ── as três tarefas ──
_FALHAS: dict[int, int] = {}
_ESPERA: dict[int, float] = {}


def _em_espera(lid: int) -> bool:
    return _ESPERA.get(lid, 0.0) > time.monotonic()


def _falhou(conn, lead: dict, ate: int | None, erro: Exception) -> None:
    """394: um cliente com erro (modelo, Z-API, dado estranho) não trava os outros nem chama o modelo de 5 em 5 s:
    espera 2 min; na terceira falha seguida, a Nay larga a mensagem (marca lida) e avisa a equipe no grupo."""
    lid = lead["id"]
    _FALHAS[lid] = _FALHAS.get(lid, 0) + 1
    _ESPERA[lid] = time.monotonic() + 120
    log.warning("lead %s: falhou (%d): %s", lid, _FALHAS[lid], erro)
    if _FALHAS[lid] >= 3:
        _FALHAS.pop(lid, None)
        if ate:
            _marcar(conn, lid, ultima_lida=ate)
        _ao_crm(f"Cliente {quem(lead)} no WhatsApp de captação: a Nay não conseguiu responder a última mensagem "
                f"(três tentativas). Vejam por lá.")


def _deu_certo(lid: int) -> None:
    _FALHAS.pop(lid, None)
    _ESPERA.pop(lid, None)


def _baloes_do(r: dict) -> list[str]:
    """Os balões do modelo, limpos. Texto solto (não lista) vira um balão só, não um balão por letra."""
    brutos = r.get("baloes")
    if isinstance(brutos, str):
        brutos = [brutos]
    if not isinstance(brutos, list):
        return []
    return [b for b in (nay.limpar_balao(str(x)) for x in brutos[:MAX_BALOES]) if b]


PERGUNTA_DA_FINALIDADE = re.compile(
    r"\b(alugar ou (para |pra )?comprar|comprar ou (para |pra )?alugar|venda ou (para |pra )?loca[cç][aã]o|"
    r"loca[cç][aã]o ou (para |pra )?venda|compra ou (para |pra )?loca[cç][aã]o|loca[cç][aã]o ou (para |pra )?compra)\b",
    re.I)


def finalidade_pelo_valor(r: dict) -> str | None:
    """22/10 (…6380: "apartamento em Adrianópolis até R$ 1.000.000" e ela perguntou "comprar ou alugar?"): o modelo
    perguntou a finalidade com um valor que já a diz. Devolve "venda" (acima de R$ 100.000) ou "locacao" (até
    R$ 30.000) quando a pergunta está nos balões; None quando a pergunta não está ou o valor não decide."""
    f = r.get("filtros") if isinstance(r.get("filtros"), dict) else {}
    try:
        teto = float(f.get("teto") or 0)
    except (TypeError, ValueError):
        teto = 0
    if not any(PERGUNTA_DA_FINALIDADE.search(b) for b in _baloes_do(r)):
        return None
    return "venda" if teto > 100000 else "locacao" if 0 < teto <= 30000 else None


PERGUNTA_DE_MENOS_QUARTOS = re.compile(
    r"\b(\d|um|dois|tr[eê]s|quatro)\s*quartos?\b[^?]*\b(serve|servem|tamb[eé]m|aceita|atende)\b|"
    r"\b(serve|servem|aceita|atende)\b[^?]*\b(\d|um|dois|tr[eê]s|quatro)\s*quartos?\b", re.I)


def quartos_que_ela_disse(r: dict, conversa: list[dict]) -> int | None:
    """22/10 (…6380: "Quantos quartos?" -> "3" -> "Se aparecer um de 2 quartos, também serve?"): ela mesma disse o número
    de quartos e o modelo perguntou se serve menos. Devolve o número quando a pergunta está nos balões; senão None."""
    f = r.get("filtros") if isinstance(r.get("filtros"), dict) else {}
    try:
        q = int(f.get("quartos") or 0)
    except (TypeError, ValueError):
        q = 0
    if not q or not any(PERGUNTA_DE_MENOS_QUARTOS.search(b) for b in _baloes_do(r)):
        return None
    dela = [str(m.get("texto") or "") for m in conversa if m.get("direcao") == "recebida"]
    return q if any(re.search(rf"(?<!\d){q}(?!\d)", t) for t in dela) else None


INTERESSE = re.compile(r"\b(tenho interesse|tem interesse|interessad[oa]s?|gostei d|gostou d|quero (esse|essa|ver|visitar|conhecer)|"
                       r"me interessei|curti (esse|essa))", re.I)
COISA_DE_EQUIPE = re.compile(r"\b(document|contrato|fechar|fechad|dar entrada|proposta|desconto|reclama|falar com (algu|uma pessoa|o corretor|gente)|"
                             r"atendente|humano|cpf|rg\b|comprovante|parceria|sou corretor)", re.I)


def equipe_a_toa(r: dict, novas: list[str]) -> str:
    """25/10 (a marcação do Pedro no treino, …8345: "quando ele disser claramente que tem um cliente interessado ... mandar o
    card e perguntar da visita"): o modelo passou para a equipe só porque ela mostrou interesse num imóvel. O aviso da
    segunda chamada (vazio = está certo: há motivo de equipe, ou não foi interesse)."""
    texto = " ".join(novas or [])
    if "equipe" not in acoes_da(r) or not INTERESSE.search(texto) or COISA_DE_EQUIPE.search(texto):
        return ""
    return ("ATENÇÃO: ela mostrou INTERESSE num imóvel (não é documento, contrato, proposta nem pedido de falar com alguém): "
            "NÃO passe para a equipe. Mande o imóvel se ela ainda não viu (acao \"fotos\") e pergunte o dia e o horário da visita.")


VALOR_ESCOLHIDO = re.compile(r"^\s*(?:(?:quero|prefiro|manda|me manda|pode ser)\s+)?(?:o|a|esse|essa)?\s*(?:de|do|da)?\s*"
                             r"(?:r\$\s*)?(\d{1,3}(?:[.,]\d{3})*|\d+)(?:[.,](\d{1,2}))?\s*(mil|k)?\s*(?:reais)?[\s.!?]*$", re.I)


def escolha_pelo_valor(novas: list[str], ultima_da_nay: str, conhecidos: list[str]) -> int | None:
    """25/10 ("700mil", "o de 1.900", "1,900" depois da lista): a mensagem é só um valor e ele bate com UM dos imóveis da
    conversa (até 2% de diferença) -> o código desse imóvel. Não vale quando a última pergunta dela foi um número (aí é o
    teto) nem quando o valor serve a dois imóveis."""
    if PERGUNTA_DE_NUMERO.search(ultima_da_nay or ""):
        return None
    precos = []
    for linha in conhecidos or []:
        m = re.match(r"#(\d+)", linha)
        if m:
            precos += [(int(m.group(1)), int(v.replace(".", ""))) for v in re.findall(r"R\$ ([\d.]+)", linha)]
    for t in reversed(novas or []):
        m = VALOR_ESCOLHIDO.match(t or "")
        if not m:
            continue
        base = int(re.sub(r"[.,]", "", m.group(1)))
        candidatos = {base * 1000} if m.group(3) else {base, base * 1000}
        if m.group(2) and not m.group(3):          # "1,9" ou "2.5" sem milhar: 1,9 mil
            candidatos = {int(float(f"{base}.{m.group(2)}") * 1000)}
        acha = {c for c, p in precos for v in candidatos if p and abs(p - v) <= 0.02 * p}
        return acha.pop() if len(acha) == 1 else None
    return None


# 26/10 (Pedro: "às vezes o cliente vai pedir informações que poderíamos nem responder, e sim mandar o card do imóvel e as
# fotos ... isso iria até acelerar, ele já ia ver as várias informações do card"): o que o card mostra
CARD_RESPONDE = re.compile(r"\b(valor|pre[çc]o|quanto (custa|[ée]|fica|sai)|quartos?|su[ií]tes?|banheiros?|[áa]rea|metros|m2|m²|"
                           r"vagas?|garagem|mobiliad\w*|modulad\w*|ar.?condicionado|climatizad\w*|condom[ií]nio|taxas?|inclus\w*|iptu|"
                           r"onde fica|bairro|endere[çc]o|localiza\w*|fotos?|imagens?|dispon[ií]vel|ainda (tem|est[áa])|valendo|"
                           r"informa[çc][õo]es|detalhes|material)\b", re.I)
# o que o card não traz: isso continua indo à equipe ("perguntar"), junto do card
FORA_DO_CARD = re.compile(r"\b(pets?|animal|animais|cachorr\w*|gat[oa]s?|andar|torre|portaria|porteiro|elevador|vizinh\w*|barulho|"
                          r"piscina|academia|lazer|aceita (proposta|permuta)|desconto|cau[çc][ãa]o|fiador|contrato|documentos?|"
                          r"vista|sol da|reforma)\b", re.I)
PEDE_OPCOES = re.compile(r"\b(mais op[çc]\w*|outras op[çc]\w*|tem outr[ao]s?|outros im[óo]veis|op[çc][õo]es parecidas|"
                         r"quero ver (as )?op[çc]\w*|me (manda|mostra|envia) (as )?op[çc]\w*|manda (o que|as op[çc]\w*)|pode mandar|"
                         r"quero op[çc]\w*|quais (voc[êe]s )?t[êe]m)", re.I)
# o card só responde PERGUNTA ("4 mil com condomínio incluso" é filtro, não pergunta: o lead 52)
PERGUNTA = re.compile(r"\?|^\s*(qual|quais|quanto|quantos|quantas|onde|como|tem |aceita|inclui|ainda|me (manda|envia|passa)|"
                      r"pode(ria)? (me )?(mandar|enviar|passar))", re.I | re.M)
BALAO_SEM_RESPOSTA = {"perguntar": "Vou confirmar isso e já te retorno por aqui.",
                      "equipe": "Já vou passar para a equipe, e eles falam com você por aqui."}


def _imovel_da_pergunta(lead: dict) -> int | None:
    """O imóvel de que ela fala, quando só há um na conversa (o do anúncio ou o único citado)."""
    cods = list(dict.fromkeys(c for c in [_int(lead.get("codigo")), *[_int(f.get("codigo")) for f in lead.get("fichas_citadas") or []]] if c))
    return cods[0] if len(cods) == 1 else None


def _filtros_bastam(f: dict) -> bool:
    """Dá para buscar: o tipo ou a finalidade, o valor e um lugar (bairros, qualquer bairro, condomínio ou perto de)."""
    return bool((f.get("tipo") or f.get("finalidade")) and f.get("teto")
                and (f.get("bairros") or f.get("qualquer_bairro") or f.get("condominio") or f.get("perto_de")))


def depois_do_modelo(conn, lead: dict, r: dict, novas: list[str], ultima_da_nay: str) -> tuple[list[str], list[tuple[str, str]]]:
    """As camadas SEM modelo depois da resposta (o jeito da Parceria: o óbvio não depende do modelo acertar). Mexe em `r`
    (fotos, ações, balões) e devolve (as ações, os passos para o registro de fluxos). Usada pelo _responder_um e pelos testes
    (olx/agentes_erros.py, olx/agentes_semana.py), para os três rodarem o mesmo caminho."""
    acoes, passos = acoes_da(r), []
    texto = " ".join(novas or [])

    def mandar(cod: int, nome: str, detalhe: str) -> None:
        nonlocal acoes
        r["fotos"] = {"codigos": [cod]}
        acoes = ["fotos", *[a for a in acoes if a != "fotos"]][:2]
        passos.append((nome, detalhe))

    livre = not ({"fotos", "card", "visita", "buscar"} & set(acoes))
    # 1. só o código (a marcação do Pedro no treino, …1715: "quando ele manda código é para enviar a foto")
    cod = codigo_sozinho(novas, ultima_da_nay) if livre else None
    if cod and _ofertavel(conn, cod, lead):
        mandar(cod, "atalho_codigo", f"mandou só o código {cod}: o imóvel vai inteiro")
        livre = False
    # 2. a escolha pelo valor ("700mil", "o de 1.900") de um imóvel que ela já viu
    cod = escolha_pelo_valor(novas, ultima_da_nay, lead.get("imoveis_conhecidos") or []) if livre else None
    if cod and _ofertavel(conn, cod, lead):
        mandar(cod, "atalho_valor", f"escolheu pelo valor: o #{cod} vai inteiro")
        livre = False
    # 3. O CARD RESPONDE: perguntou o que o card mostra e ainda não recebeu o card dele -> card e fotos, não "vou confirmar"
    cod = _imovel_da_pergunta(lead)
    # "perguntar" (ou "equipe" sem motivo de equipe: o corretor do lead 32 pediu "fotos e informações para enviar a ela")
    leva = [a for a in ("perguntar", "equipe") if a in acoes and (a == "perguntar" or not COISA_DE_EQUIPE.search(texto))]
    if (cod and leva and livre and PERGUNTA.search(texto) and CARD_RESPONDE.search(texto)
            and cod not in (lead.get("enviados") or []) and _ofertavel(conn, cod, lead)):
        so_o_card = not FORA_DO_CARD.search(texto)
        if so_o_card:
            acoes = [a for a in acoes if a not in leva]
            r["baloes"] = ["Vou te mandar o card com as informações e as fotos dele."]
        mandar(cod, "card_responde", f"o card do #{cod} responde" + ("" if so_o_card else "; o resto vai à equipe"))
        livre = False
    # 4. pediu opções e já se sabe o bastante: busca já (o que falta vira tanto faz)
    if livre and PEDE_OPCOES.search(texto) and "equipe" not in acoes and _filtros_bastam(_filtros(lead.get("filtros"), r.get("filtros"))):
        acoes = [*[a for a in acoes if a != "perguntar"][:1], "buscar"]
        baloes = _baloes_do(r)
        if not baloes or baloes[-1].rstrip().endswith("?"):
            r["baloes"] = ["Vou te mandar as opções que tenho com esse perfil."]
        passos.append(("pediu_opcoes", "pediu opções e os filtros bastam: busca já"))
    # 5. nunca leva a dúvida à equipe sem dizer nada a ela (o lead 60 ficou sem resposta)
    if not _baloes_do(r):
        for a in ("perguntar", "equipe"):
            if a in acoes:
                r["baloes"] = [BALAO_SEM_RESPOSTA[a]]
                passos.append(("balao_sem_resposta", f"ação {a} sem balão: a frase padrão"))
                break
    r["acoes"] = acoes
    return acoes, passos


def so_no_condominio(achados: list[dict], f: dict) -> list[dict]:
    """26/10 (o lead 60: "só no Ponta Negra Village mesmo", e a busca trazia o Tarumã e a Chapada): com
    filtros.so_condominio, só o condomínio que ela pediu."""
    if not (f.get("so_condominio") and f.get("condominio")):
        return achados
    alvo = _normal(str(f["condominio"]))
    return [a for a in achados if alvo and (alvo in _normal(str(a.get("condominio") or "")) or
                                            _normal(str(a.get("condominio") or "")) in alvo and a.get("condominio"))]


def pergunta_a_toa(r: dict, conversa: list[dict]) -> str:
    """O aviso para a segunda chamada quando o modelo perguntou o que já se sabe (vazio = nada a corrigir)."""
    avisos = []
    pelo_valor = finalidade_pelo_valor(r)
    if pelo_valor:
        avisos.append("pelo valor que ela disse, é " + ("COMPRA (acima de R$ 100.000)" if pelo_valor == "venda" else
                      "ALUGUEL (até R$ 30.000)") + ". NÃO pergunte se é para alugar ou comprar: filtros.finalidade = \""
                      + pelo_valor + "\"")
    q = quartos_que_ela_disse(r, conversa)
    if q:
        avisos.append(f"ela mesma disse {q} quartos. NÃO pergunte se serve menos quartos: filtros.quartos = {q} e "
                      "aceita_menos_quartos = false")
    return ("ATENÇÃO: " + "; ".join(avisos) + ". Siga o roteiro com a próxima pergunta que falta.") if avisos else ""


def _falar(conn, lead: dict, r: dict, acoes: list[str], desde=None) -> list[str]:
    """Manda os balões do turno. 394 (Pedro: "ela só deve confirmar que vai mandar as solicitações uma vez ... e depois
    já vir com as opções pesquisadas"): com "buscar", é UM balão só (o resto vem nos cards); nada repetido sai.
    22/10 (Eudes, 10:33: o Tel disse "a Raquel que vai" e ela, no mesmo segundo, "ainda estou confirmando quem vai"):
    com `desde`, a equipe que escreveu depois disso (enquanto o modelo pensava) cala o resto do turno."""
    baloes = _baloes_do(r)
    if "buscar" in acoes and len(baloes) > 1:
        baloes = [" ".join(baloes)]
    antes = len(baloes)
    baloes = sem_repetir(baloes, ja_mandou(conn, lead))
    if antes != len(baloes):
        log.info("lead %s: %d balão(ões) repetido(s) não saiu(íram)", lead["id"], antes - len(baloes))
    for n, b in enumerate(baloes):
        if n:
            time.sleep(ENTRE_ENVIOS_S)
        if desde is not None and _gente_escreveu(conn, lead, desde):
            log.info("lead %s: a equipe escreveu durante o turno; %d balão(ões) não saiu(íram)", lead["id"], len(baloes) - n)
            baloes = baloes[:n]
            r["_equipe_no_meio"] = True
            break
        mandar_texto(conn, lead, b)
    r["_baloes_que_sairam"] = baloes
    return baloes


def abrir(conn, cfg: dict) -> int:
    feitos = 0
    for l in banco.linhas(conn, """SELECT id FROM privado.olx_lead_whatsapp
                                    WHERE etapa = 'nova' AND assumido_em IS NULL AND humano_em IS NULL
                                      AND criado_em > now() - interval '7 days' ORDER BY criado_em LIMIT 3"""):
        if _em_espera(l["id"]):
            continue
        lead = _lead(conn, l["id"])
        if not lead or not _pode(cfg, lead["telefone"]):
            continue
        try:
            # a equipe já chamou por este número (nos últimos 3 dias): a conversa é dela
            gente = _gente_escreveu(conn, lead, banco.um(conn, "SELECT now() - interval '3 days'"))
            if gente:
                _marcar(conn, lead["id"], assumido_em_agora=True, humano_em=gente, etapa="filtrar",
                        parada_motivo="a equipe já tinha chamado por este número")
                log.info("lead %s: a equipe já chamou; a Nay não abre", lead["id"])
                continue
            ctx_olx = banco.um(conn, "SELECT olx_nay_contexto(%s)", (lead["chat"],)) if lead.get("chat") else None
            lead["visita_aberta"] = visita.para_o_modelo(conn, lead["id"])
            # 394: o que ela já escreveu (ou o que já conversamos, se veio de outro anúncio) entra na abertura
            conversa = _conversa(conn, lead)
            ate = max([m["id"] for m in conversa if m.get("direcao") == "recebida"] or [_ultima_recebida(conn, lead)])
            agentes.novo_turno(lead)
            agentes.passo(lead, "abertura", "lead novo: a primeira mensagem da Nay")
            r = modelo.chamar(PROMPT, montar_turno(lead, ctx_olx, conversa), no="olx.whatsapp")
            acoes = acoes_da(r)
            if not _baloes_do(r):
                raise ValueError("o modelo não escreveu a abertura")
            uso = modelo.ultimo_uso()
            agentes.atendimento(lead, {"rotas": [], "geral": True}, r, uso, uso.get("ms"), acoes)
            baloes = _falar(conn, lead, r, acoes)
            agentes.passo(lead, "falou", f"{len(baloes)} balão(ões)" + (f"; ações: {', '.join(acoes)}" if acoes else ""),
                          baloes=baloes)
            filtros = condominio_que_faltou(conn, _filtros(lead.get("filtros"), r.get("filtros")), conversa)
            _marcar(conn, lead["id"], assumido_em_agora=True, etapa="filtrar", ultima_lida=ate, filtros=filtros)
            # 16/10: o que ela promete já na abertura (passar o desconto à equipe, confirmar a visita pedida na OLX...) tem
            # de chegar à equipe: as ações da abertura valem como as de qualquer resposta
            for acao in acoes:
                _fazer(conn, _lead(conn, lead["id"]), r, acao, filtros, cfg)
            _deu_certo(lead["id"])
            log.info("lead %s aberto (%d balão/ões)", lead["id"], len(baloes))
            feitos += 1
        except Exception as e:  # noqa: BLE001 -- um cliente não para os outros
            agentes.registrar(lead, "fluxo", "falhou", {"resumo": f"abertura: {type(e).__name__}: {e}"[:200]}, erro=str(e))
            _falhou(conn, lead, None, e)
            if _FALHAS.get(lead["id"]) is None:       # terceira falha: não abre mais sozinha
                _marcar(conn, lead["id"], assumido_em_agora=True, humano_em=banco.um(conn, "SELECT now()"),
                        etapa="filtrar", parada_motivo="a Nay não conseguiu abrir")
    return feitos


_ULTIMA_DESCOBERTA = [0.0]


def descobrir_organicos(conn, cfg: dict, a_cada_s: float = 20.0) -> int:
    """390 (Pedro, 16/10): "quando chega lead novo a Nay deve atender normal, e perguntar se ele quer imóvel, esse vem com a
    tag orgânico". Quem escreveu pela primeira vez neste número e não é dono, corretor, equipe nem cliente da OLX
    (olx_organicos_novos) vira lead da Nay; a resposta sai pela fila de sempre, depois do silêncio."""
    if (cfg.get("organico_atende") or "nao").strip().lower() != "sim":
        return 0
    if time.monotonic() - _ULTIMA_DESCOBERTA[0] < a_cada_s:
        return 0
    _ULTIMA_DESCOBERTA[0] = time.monotonic()
    novos = 0
    for o in banco.linhas(conn, "SELECT telefone, primeira FROM olx_organicos_novos(60)"):
        if not _pode(cfg, o["telefone"]):
            continue
        # 488 (Pedro, 24/10: "faz parceria no Kopenhagen?"): quem pede parceria ou diz que é corretor não é cliente: a Nay
        # Corretores (olx/buscas.py) atende, cadastra o imóvel dele e avisa as buscas
        from olx import buscas
        falas = " ".join((x["texto"] or "") for x in banco.linhas(conn, """
            SELECT texto FROM captacao_mensagens WHERE id >= %s AND direcao = 'recebida'
               AND right(regexp_replace(coalesce(telefone, ''), '[^0-9]', '', 'g'), 8) = right(%s, 8) ORDER BY id LIMIT 3""",
                                                                  (int(o["primeira"]), o["telefone"])))
        if buscas.parece_corretor(falas):
            if banco.um(conn, """INSERT INTO privado.busca_corretor (telefone8, telefone, origem, classificado_em, ultima_lida)
                                 VALUES (right(%s, 8), %s, 'parceria', now(), %s - 1) ON CONFLICT (telefone8) DO NOTHING RETURNING 1""",
                        (o["telefone"], o["telefone"], int(o["primeira"]))):
                log.info("corretor classificado (pediu parceria): %s", nay.telefone_bonito(o["telefone"]))
            continue
        lid = banco.um(conn, """
            INSERT INTO privado.olx_lead_whatsapp (chat, telefone, origem, etapa, etapa_em, assumido_em, ultima_lida, perfil)
            SELECT NULL, %s, 'organico', 'filtrar', now(), now(), %s - 1, '{"procura": "escreveu direto no WhatsApp"}'::jsonb
             WHERE NOT EXISTS (SELECT 1 FROM privado.olx_lead_whatsapp WHERE right(telefone, 8) = right(%s, 8))
            ON CONFLICT DO NOTHING RETURNING id""", (o["telefone"], int(o["primeira"]), o["telefone"]))
        if lid:
            log.info("lead %s: orgânico (%s)", lid, nay.telefone_bonito(o["telefone"]))
            novos += 1
    return novos


def _fila(conn, cfg: dict) -> list[dict]:
    """Quem escreveu e ficou `whatsapp_silencio_s` quieto. Um lead por telefone (o mais novo); o encerrado também (394:
    quem volta a escrever é atendido de novo)."""
    silencio = max(0, int(cfg.get("whatsapp_silencio_s") or 20))
    return banco.linhas(conn, """
        SELECT x.id, x.ate FROM (
          SELECT DISTINCT ON (right(l.telefone, 8)) l.id, max(m.id) AS ate, max(m.criada_em) AS ultima
            FROM privado.olx_lead_whatsapp l
            JOIN captacao_mensagens m ON m.direcao = 'recebida' AND m.id > l.ultima_lida
                                     AND right(regexp_replace(coalesce(m.telefone, ''), '\\D', '', 'g'), 8) = right(l.telefone, 8)
           WHERE l.assumido_em IS NOT NULL
           GROUP BY l.id, l.telefone, l.criado_em
           ORDER BY right(l.telefone, 8), l.criado_em DESC) x
         WHERE x.ultima < now() - make_interval(secs => %s)
         ORDER BY x.ultima LIMIT 5""", (silencio,))


# 394: "ok", "obrigada", "aguardo" depois de uma resposta dela não pedem outra resposta (a Michelle, 16:34: "Obrigada" e a
# Nay confirmou de novo que ia pedir à equipe)
SO_AGRADECEU = re.compile(
    r"^(ok+|okay|ok ok|blz|beleza|obrigad[oa]s?|muito obrigad[oa]|obg|brigad[oa]|valeu|vlw|aguardo|fico no aguardo|"
    r"fico aguardando|aguardando|t[aá] bom|ta|certo|combinado|perfeito|show|top|joia|ok obrigad[oa]|obrigad[oa] aguardo|"
    r"ok aguardo|tudo bem|de nada|por nada|amem|am[eé]m|grat[oa]|gratid[aã]o)$", re.I)


def so_agradeceu(textos: list[str]) -> bool:
    if not textos:
        return False
    for t in textos:
        sem_emoji = re.sub(r"[\U0001F300-\U0001FAFF☀-➿]", " ", t or "")
        n = _normal(sem_emoji)
        if not n and sem_emoji.strip() == "" and (t or "").strip():
            continue                      # só emoji (👍🙏): agradecimento
        if not n or not SO_AGRADECEU.match(n):
            return False                  # mídia sem texto, ou um pedido de verdade
    return True


def responder(conn, cfg: dict) -> int:
    feitos = 0
    for item in _fila(conn, cfg):
        if _em_espera(item["id"]):
            continue
        lead = _lead(conn, item["id"])
        if not lead or not _pode(cfg, lead["telefone"]):
            continue
        ate = int(item["ate"])
        try:
            if _responder_um(conn, cfg, lead, ate):
                feitos += 1
            _deu_certo(lead["id"])
        except Exception as e:  # noqa: BLE001 -- um cliente não para os outros
            agentes.registrar(lead, "fluxo", "falhou", {"resumo": f"{type(e).__name__}: {e}"[:200]}, erro=str(e))
            _falhou(conn, lead, ate, e)
    return feitos


def _responder_um(conn, cfg: dict, lead: dict, ate: int) -> bool:
    # 21/10 (Pedro: "toda vez que eu mandar mensagem para o lead ... ela tem que entender o contexto da conversa para poder
    # voltar a atender"): a equipe escreveu por este número (celular ou CRM) -> a Nay espera `gap_equipe_min` (30) desde a
    # ÚLTIMA mensagem da equipe, sem marcar como lida, e depois responde lendo o que a equipe disse (as falas EQUIPE).
    # Antes ela calava para sempre ("a equipe respondeu"); essa marca antiga deixa de valer.
    if lead.get("humano_em") and lead.get("parada_motivo") == "a equipe respondeu":
        _marcar(conn, lead["id"], humano_em=None, parada_motivo=None)
        lead["humano_em"] = None
    inicio = banco.um(conn, "SELECT clock_timestamp()")
    gente = _gente_escreveu(conn, lead, None)
    try:
        gap = max(0, int(cfg.get("gap_equipe_min") or 30))
    except (TypeError, ValueError):
        gap = 30
    if gente and gente > banco.um(conn, "SELECT now() - make_interval(mins => %s)", (gap,)):
        agentes.novo_turno(lead)
        agentes.humano(lead, gente)       # 489: o Humano na linha do tempo dos agentes
        return False                      # a equipe está na conversa: espera, e a mensagem dela continua não lida
    agentes.novo_turno(lead)              # 490: daqui em diante cada porta e ferramenta é um passo deste turno
    if lead.get("humano_em"):
        # a equipe assumiu (Pedro, 16/10, na OLX: "a nay não deve mais responder"): ela não volta sozinha
        _marcar(conn, lead["id"], ultima_lida=ate)
        agentes.passo(lead, "equipe_assumiu", "a equipe assumiu a conversa: a Nay não responde")
        return False
    conversa = _conversa(conn, lead)
    if gente and not novas_depois_da_equipe(conversa, lead.get("ultima_lida") or 0, gente):
        # 22/10 (Eudes: "Qual andar?" às 09:31, o Tel respondeu às 09:32, e às 10:02 ela respondeu de novo): o que a
        # pessoa escreveu ANTES da última fala da equipe a equipe já respondeu. Só o que veio depois é com ela.
        _marcar(conn, lead["id"], ultima_lida=ate)
        log.info("lead %s: a equipe já respondeu o que ela escreveu; a Nay não responde", lead["id"])
        agentes.passo(lead, "equipe_ja_respondeu", "a equipe já respondeu o que ela escreveu: a Nay não responde")
        return False
    if banco.um(conn, "SELECT count(*) FROM privado.olx_cliente_enviada WHERE lead = %s AND tipo = 'texto'",
                (lead["id"],)) >= LIMITE_DE_MENSAGENS:
        _marcar(conn, lead["id"], humano_em=banco.um(conn, "SELECT now()"), ultima_lida=ate,
                parada_motivo="a conversa foi longe demais para a Nay")
        _ao_crm(f"Cliente {quem(lead)}: a conversa no WhatsApp de captação foi longe; precisa de alguém.")
        agentes.passo(lead, "limite_de_mensagens", f"passou de {LIMITE_DE_MENSAGENS} mensagens: vai para a equipe")
        return False
    if lead.get("etapa") == "finalizado":
        # 394: ela tinha encerrado e a pessoa voltou a escrever: a conversa reabre
        etapa = "visita" if visita.ativa(conn, lead["id"]) else ("imoveis_enviados" if lead.get("enviados") else "filtrar")
        _marcar(conn, lead["id"], etapa=etapa)
        lead["etapa"] = etapa
    lead["visita_aberta"] = visita.para_o_modelo(conn, lead["id"])
    novas = [m.get("texto") or "" for m in conversa if m.get("direcao") == "recebida" and m.get("id", 0) > (lead.get("ultima_lida") or 0)]
    nossas = [m for m in conversa if m.get("direcao") == "enviada" and (m.get("texto") or "").strip()]
    esperando_sim = (lead.get("visita_aberta") or {}).get("estado") == "confirmar_cliente"
    agentes.passo(lead, "chegou", f"{len(novas)} mensagem(ns): " + " / ".join(n.strip() for n in novas if n.strip())[:160],
                  etapa=lead.get("etapa"), visita=(lead.get("visita_aberta") or {}).get("estado"))
    if (so_agradeceu(novas) and nossas and not nossas[-1]["texto"].strip().endswith("?") and not esperando_sim):
        _marcar(conn, lead["id"], ultima_lida=ate)          # "obrigada": não é pedido; ela não repete a confirmação
        log.info("lead %s: só agradeceu; a Nay não responde", lead["id"])
        agentes.passo(lead, "so_agradeceu", "só agradeceu, sem pergunta pendente: a Nay não responde")
        return False
    ctx_olx = banco.um(conn, "SELECT olx_nay_contexto(%s)", (lead["chat"],)) if lead.get("chat") else None
    if organico(lead):
        lead["fichas_citadas"] = _fichas_citadas(conn, conversa, lead)
    lead["imoveis_conhecidos"] = imoveis_da_conversa(conn, lead)
    turno = montar_turno(lead, ctx_olx, conversa)
    # 489 (Pedro, 24/10: os agentes da Nay Leads, olx/agentes.py): o MESTRE (JEV) lê as mensagens novas e escolhe o
    # caminho; o ATENDIMENTO (a Luna) recebe só as regras dele. Chave `agentes`: nao = como era; sombra = decide e grava.
    plano = agentes.planejar(PROMPT, lead, conversa, novas, organico(lead),
                             pode_calar=bool(nossas) and not nossas[-1]["texto"].strip().endswith("?") and not esperando_sim)
    if plano["calar"]:
        _marcar(conn, lead["id"], ultima_lida=ate)            # o mestre leu só cortesia, com as mesmas travas de hoje
        agentes.registrar(lead, "atendimento", "calou", {"resumo": "o mestre leu só cortesia: não responde"})
        log.info("lead %s: o mestre leu só cortesia; a Nay não responde", lead["id"])
        return False
    prompt = plano["prompt"]
    r = modelo.chamar(prompt, turno, no="olx.whatsapp")
    uso = modelo.ultimo_uso()
    aviso = " ".join(x for x in (pergunta_a_toa(r, conversa), equipe_a_toa(r, novas)) if x)
    if aviso:
        # 22/10: perguntou o que já se sabe (a finalidade pelo valor, os quartos que ela disse): uma segunda chamada, avisada
        log.info("lead %s: perguntou o que já se sabe; de novo (%s)", lead["id"], aviso[:120])
        agentes.passo(lead, "chamou_de_novo", "perguntou o que já se sabe: " + aviso[10:130])
        r = modelo.chamar(prompt, turno + "\n\n" + aviso, no="olx.whatsapp")
        u2 = modelo.ultimo_uso()
        uso = {**u2, **{k: (uso.get(k) or 0) + (u2.get(k) or 0) for k in ("ms", "tokens_entrada", "tokens_saida", "tokens_cache")}}
    # 25/10 (as paredes do validador da Parceria, olx/paredes.py): valor e código só do que o turno trouxe, nunca
    # "parceria", negativa, bastidor nem OLX para o orgânico. Furou: volta UMA vez com o aviso; o que ainda furar sai cortado.
    furos = paredes.conferir(_baloes_do(r), turno, organico(lead))
    if furos:
        agentes.passo(lead, "parede", "; ".join(f"{p}: {x}" for _i, p, x in furos)[:180], furos=furos)
        r = modelo.chamar(prompt, turno + "\n\n" + paredes.aviso(furos), no="olx.whatsapp")
        u3 = modelo.ultimo_uso()
        uso = {**u3, **{k: (uso.get(k) or 0) + (u3.get(k) or 0) for k in ("ms", "tokens_entrada", "tokens_saida", "tokens_cache")}}
        sobra, ainda = paredes.cortar(_baloes_do(r), turno, organico(lead))
        if ainda:
            agentes.passo(lead, "parede_cortou", "; ".join(f"{p}: {x}" for _i, p, x in ainda)[:180], furos=ainda)
            r["baloes"] = sobra
    # 25-26/10: as camadas sem modelo (o código sozinho, a escolha pelo valor, o card que responde, pediu opções, nunca
    # sem balão): depois_do_modelo, a mesma que os testes rodam
    acoes, passos = depois_do_modelo(conn, lead, r, novas, nossas[-1]["texto"] if nossas else "")
    for nome, detalhe in passos:
        agentes.passo(lead, nome, detalhe)
    r["_novas"] = novas
    agentes.atendimento(lead, plano, r, uso, uso.get("ms"), acoes)
    saiu = _falar(conn, lead, r, acoes, desde=inicio)
    agentes.passo(lead, "falou", f"{len(saiu)} balão(ões)" + (" (a equipe entrou no meio: parou)" if r.get("_equipe_no_meio") else "")
                  + (f"; ações: {', '.join(acoes)}" if acoes else ""), baloes=saiu)
    if r.get("_equipe_no_meio"):
        return False                      # a equipe entrou no meio: sem ações, e o que ela escreveu fica não lido
    filtros = condominio_que_faltou(conn, _filtros(lead.get("filtros"), r.get("filtros")), conversa)
    _marcar(conn, lead["id"], ultima_lida=ate, filtros=filtros)
    # 520: o pedido mudou -> a etapa (a barrinha do CRM) volta ao começo; a busca e o envio a levam de novo para a frente
    mudou = mudou_o_pedido(lead.get("filtros"), filtros)
    if mudou and lead.get("etapa") in ("feito_busca", "imoveis_enviados", "visita", "proprietarios") \
            and not visita.ativa(conn, lead["id"]):
        _marcar(conn, lead["id"], etapa="filtrar")
        agentes.passo(lead, "pedido_mudou", f"o pedido mudou ({mudou}): a etapa voltou a Filtrar")
    for acao in acoes:
        _fazer(conn, _lead(conn, lead["id"]), r, acao, filtros, cfg)
    return True


CODIGO_SOZINHO = re.compile(r"^\s*(?:c[óo]d(?:igo)?\.?\s*:?\s*|#)?(\d{3,5})\s*[.!?]?\s*$", re.I)
PERGUNTA_DE_NUMERO = re.compile(r"\b(valor|quanto|r\$|or[çc]amento|quartos?|metros|m2|m²|andar|vagas?)\b", re.I)
DE_NOVO = re.compile(r"\b(de novo|novamente|outra vez|n[ãa]o (chegou|chegaram|veio|vieram|abriu|abriram)|reenvi\w*|manda[r]? (as )?fotos? de novo)\b", re.I)


def fotos_ja_foram(conn, lead: dict, codigo: int) -> bool:
    """As fotos deste imóvel já saíram para esta pessoa (olx_cliente_enviada, tipo 'foto')."""
    return bool(banco.um(conn, """SELECT EXISTS (SELECT 1 FROM privado.olx_cliente_enviada
                                     WHERE lead = %s AND codigo = %s AND tipo = 'foto')""", (lead["id"], codigo)))


def codigo_sozinho(novas: list[str], ultima_da_nay: str = "") -> int | None:
    """A mensagem é só o código de um imóvel ("3078", "cód. 3078", "#3078"): é o pedido do imóvel. Não vale quando a
    última pergunta dela foi um número (valor, quartos, andar): aí "3000" é a resposta, não um imóvel."""
    if PERGUNTA_DE_NUMERO.search(ultima_da_nay or ""):
        return None
    for t in reversed(novas or []):
        m = CODIGO_SOZINHO.match(t or "")
        if m:
            return int(m.group(1))
    return None


def acoes_da(r: dict) -> list[str]:
    """As ações da resposta, na ordem, sem repetir (até duas). Aceita o formato antigo ("acao": "buscar").
    394: "visita" e "confirmou_visita" no mesmo turno não: o sim é do turno seguinte, depois da confirmação."""
    brutas = r.get("acoes") if isinstance(r.get("acoes"), list) else [r.get("acao")]
    saida: list[str] = []
    for a in brutas:
        a = str(a or "").strip().lower()
        if a in ("fotos", "card", "buscar", "visita", "confirmou_visita", "perguntar", "equipe", "encerrar") and a not in saida:
            saida.append(a)
    if "visita" in saida and "confirmou_visita" in saida:
        saida.remove("confirmou_visita")
    return saida[:2]


def _ofertavel(conn, codigo: int, lead: dict | None = None) -> bool:
    """O imóvel pode ir a esta pessoa: anunciável; o de PARCEIRO Disponível só a quem não é corretor (400, Pedro 17/10:
    "não enviamos para os corretores, só para os clientes finais que vêm da OLX"). Sem telefone: parceiro não sai."""
    return bool(banco.um(conn, "SELECT olx_imovel_vai_ao_cliente(%s, %s)", (codigo, (lead or {}).get("telefone"))))


def _aceita_parceiro(conn, lead: dict) -> bool:
    """400: cliente final (não é corretor dos grupos nem parceiro do site antigo) recebe imóvel de parceiro."""
    return bool(lead.get("telefone")) and bool(banco.um(conn, "SELECT olx_pode_receber_parceiro(%s)", (lead["telefone"],)))


def codigo_da_pergunta(lead: dict, motivo: str) -> int | None:
    """394: o código que está NA pergunta vence o do anúncio ("o 9026 aceita pet?" não é sobre o #3883); vários códigos,
    nenhum (a resposta não vira memória de um imóvel só)."""
    cods = list(dict.fromkeys(re.findall(r"(?<!\d)(\d{4})(?!\d)", motivo or "")))
    if len(cods) == 1:
        return int(cods[0])
    if len(cods) > 1:
        return None
    if lead.get("codigo"):
        return lead.get("codigo")
    # 28/10 (o Gilson colou imobeasy.com/imoveis/4434 e a pergunta foi à fila sem código: quem respondeu não sabia que
    # o 4434 é de parceiro): o orgânico que citou UM imóvel pergunta sobre ele
    citados = list(dict.fromkeys(_int(f.get("codigo")) for f in lead.get("fichas_citadas") or [] if _int(f.get("codigo"))))
    return citados[0] if len(citados) == 1 else None


def oferta_sozinha_espera(conn, lead: dict, filtros: dict | None = None) -> str:
    """Por que a oferta que ela manda SOZINHA (sem a pessoa ter escrito agora) espera; '' = pode ir. Tel, 28/10 (Susi): "a
    Nay ficou de passar uma informação, e não retornou com essa dúvida da cliente, e logo após mandou uma opção, porém
    ela não fez o filtro antes". Espera enquanto há pergunta dela na fila (a promessa vem antes da opção nova) e
    enquanto o filtro não tem o valor e o lugar (o "tanto faz" do bairro vale)."""
    f = filtros if filtros is not None else (lead.get("filtros") or {})
    if not f.get("teto"):
        return "o filtro ainda não tem o valor"
    if not (f.get("bairros") or f.get("qualquer_bairro") or f.get("condominio") or f.get("perto_de")):
        return "o filtro ainda não tem a região"
    if lead.get("telefone") and banco.um(conn, """SELECT EXISTS (SELECT 1 FROM pergunta_fila WHERE linha = 'captacao'
                                                     AND estado IN ('agente', 'fila', 'perguntada') AND right(chave, 8) = %s)""",
                                         (_so8(lead["telefone"]),)):
        return "há pergunta dela esperando resposta da equipe"
    # 30/10 (revisão, o Eudes ...8856: o Tel mandou o #9089 às 08:55, escreveu às 09:07 e às 09:30 ela mandou sozinha
    # outra opção): a espera de `gap_equipe_min` depois da equipe vale também para o que ela manda sozinha
    if lead.get("telefone"):
        try:
            gap = max(0, int(banco.chaves(conn).get("gap_equipe_min") or 30))
        except (TypeError, ValueError):
            gap = 30
        gente = _gente_escreveu(conn, lead, None)
        if gente and gente > banco.um(conn, "SELECT now() - make_interval(mins => %s)", (gap,)):
            return f"a equipe escreveu há menos de {gap} min"
    return ""


def _fazer(conn, lead: dict, r: dict, acao: str, filtros: dict, cfg: dict | None = None) -> None:
    agentes.acao(lead, acao, r)                # 489: a ação vira evento do agente dono (busca, imóveis, visita...)
    if acao == "fotos":
        f = r.get("fotos") if isinstance(r.get("fotos"), dict) else {}
        # 25/10 (as conversas com erro da semana: "1,900", "manda o de 630", "me manda as 2 opções", "material do
        # imóvel"): o que ela escolheu ou pediu vai inteiro, até 3 imóveis, cada um com o card (se ainda não viu) e as fotos
        codigos = [c for c in dict.fromkeys(_int(x) for x in [*(f.get("codigos") or []), f.get("codigo")]) if c][:3]
        enviados = list(lead.get("enviados") or [])
        for n, codigo in enumerate(codigos or [_int(lead.get("codigo"))]):
            if not codigo:
                continue
            if not _ofertavel(conn, codigo, lead):
                _para_a_fila(conn, lead, codigo, f"Pediu fotos do #{codigo}, que é de parceria ou não está disponível: o que dizer?")
                continue
            if n:
                time.sleep(DEPOIS_DAS_FOTOS_S)   # as fotos do anterior carregam antes do próximo card
            # o imóvel do anúncio ou um que ela já recebeu: só as fotos (o card ela já viu)
            ja_viu = codigo == lead.get("codigo") or codigo in enviados
            # 25/10 (a marcação do Pedro no treino, …9640: "não reenviar o mesmo card, ela enviou várias vezes"): as fotos
            # que já foram não vão de novo, a não ser que ela peça de novo ("de novo", "não chegaram")
            if ja_viu and fotos_ja_foram(conn, lead, codigo) and not DE_NOVO.search(" ".join(r.get("_novas") or [])):
                agentes.passo(lead, "fotos_ja_foram", f"as fotos do #{codigo} já foram: não reenvia")
                if not any(_normal("Já te mandei as fotos") in _normal(x) for x in ja_mandou(conn, lead)):
                    mandar_texto(conn, lead, "Já te mandei as fotos desse aqui em cima na conversa. Quer que eu mande de novo?")
                continue
            mandar_imovel(conn, lead, codigo, com_card=not ja_viu)
            if not ja_viu:
                enviados.append(codigo)
                _marcar(conn, lead["id"], enviados=enviados)
            time.sleep(DEPOIS_DAS_FOTOS_S)
        depois = sem_repetir([b for b in (nay.limpar_balao(str(x)) for x in (r.get("depois_das_fotos") or [])[:MAX_BALOES]) if b],
                             ja_mandou(conn, lead))
        for b in depois:
            mandar_texto(conn, lead, b)
            time.sleep(ENTRE_ENVIOS_S)
    elif acao == "card":
        # 21/10: o card de novo (até 3), para ela apontar o imóvel da visita pelo nome; nunca se pede o código
        cods = (r.get("card") or {}).get("codigos") if isinstance(r.get("card"), dict) else []
        enviados = list(lead.get("enviados") or [])
        for n, c in enumerate([x for x in (_int(c) for c in (cods or [])) if x][:3]):
            if not _ofertavel(conn, c, lead):
                continue
            if n:
                time.sleep(ENTRE_ENVIOS_S)
            mandar_imovel(conn, lead, c, com_card=True, com_fotos=False)
            if c not in enviados and c != lead.get("codigo"):
                enviados.append(c)
        _marcar(conn, lead["id"], enviados=enviados)
    elif acao == "buscar":
        # ela já disse neste turno que CONTINUA procurando: a busca vazia não diz de novo. 30/10 (revisão das conversas,
        # a Karoline ...0222): "Vou pegar as opções no meu sistema para lhe enviar" é promessa de MANDAR, não aviso de que
        # ainda está procurando -- contava como aviso, a busca deu vazio e ela ficou 5 h sem ouvir nada
        ja_avisou = any(re.search(r"continu\w* (procurando|verificando|buscando)|ainda (estou )?(procurando|verificando)|"
                                  r"verificando com|te aviso (por aqui )?assim que", b, re.I)
                        for b in (r.get("_baloes_que_sairam") or _baloes_do(r)))
        _buscar_e_mandar(conn, lead, filtros, ja_avisou=ja_avisou)
    elif acao == "visita":
        # 389 (Pedro, 16/10): a confirmação no modelo da Parceria; os contatos só depois do sim dela
        v = r.get("visita") if isinstance(r.get("visita"), dict) else {}
        codigo = _int(v.get("codigo")) or lead.get("codigo")
        if codigo and not _ofertavel(conn, codigo, lead):
            _para_a_fila(conn, lead, codigo, f"Quer visitar o #{codigo}, que é de parceria ou não está disponível: o que dizer?")
        elif visita.pedir_confirmacao(conn, lead, codigo, str(v.get("data") or ""), str(v.get("hora") or "")):
            pass                                            # a etapa vira 'visita' lá dentro
    elif acao == "confirmou_visita":
        visita.cliente_confirmou(conn, lead, cfg or {})
    elif acao == "perguntar":
        # Pedro, 16/10 (a Michelle pediu os quartos com roupeiros): "ela deve nos perguntar porque a Nay não sabe que foto
        # é de qual lugar". 391: a pergunta vai à FILA do PV do Tel (uma por vez, cobrada); a resposta dele volta por
        # entregar_respostas e a conversa continua com ela. Sem a fila, ao grupo como antes.
        motivo = str(r.get("motivo") or "algo que a Nay não sabe")[:600]
        if not _para_a_fila(conn, lead, codigo_da_pergunta(lead, motivo), motivo):
            _ao_crm(f"Cliente {quem(lead)} no WhatsApp de captação "
                    f"pediu: {motivo[:240]}. A Nay disse que já retorna: mandem por lá.")
    elif acao == "equipe":
        contato = _contato_do_corretor_da_visita(conn, lead)
        if contato:
            # 31/10 (Pedro, sobre o Eduardo ...2424: "só pedir pra ela me chamar ou enviar contato dela" ficou 3 h sem
            # resposta e ele desmarcou): com visita confirmada, o contato de quem acompanha vai na hora
            mandar_texto(conn, lead, contato)
            return
        _marcar(conn, lead["id"], humano_em=banco.um(conn, "SELECT now()"), parada_motivo=str(r.get("motivo") or "")[:200])
        # 24/10 (Pedro): compra, negociação, documentos: o grupo recebe o que o lead mandou e o número, e alguém assume
        mandou = _ultimas_do_cliente(conn, lead)
        _ao_crm(f"Cliente {quem(lead)} no WhatsApp de captação: {str(r.get('motivo') or 'precisa da equipe')[:200]}."
                + (f" Ele mandou: \"{mandou}\"." if mandou else "")
                + " Alguém da equipe assume a conversa por lá, por favor.")
    elif acao == "encerrar":
        # 394: com visita andando ou marcada, não encerra (a Josy disse "obrigada" e foi para Finalizados com a visita do
        # dia seguinte)
        if not visita.ativa(conn, lead["id"]):
            _marcar(conn, lead["id"], etapa="finalizado")


PEDIU_CONTATO = re.compile(r"\bcontato\b|\bn[uú]mero\b|\btelefone\b|\bwhats|\bzap\b|me (chamar|chama|ligar|liga)\b", re.I)


def _contato_do_corretor_da_visita(conn, lead: dict) -> str | None:
    """O lead pediu o contato (ou que o corretor o chame) e tem visita confirmada com corretor: a frase com o nome e o
    número de quem acompanha. None quando não se aplica (aí a equipe assume, como antes)."""
    if not PEDIU_CONTATO.search(_ultimas_do_cliente(conn, lead) or ""):
        return None
    v = banco.linhas(conn, """SELECT corretor_nome, corretor_telefone FROM privado.olx_visita
                               WHERE lead = %s AND estado = 'confirmada' AND quando > now() - interval '3 hours'
                                 AND coalesce(corretor_telefone, '') <> '' ORDER BY quando LIMIT 1""", (lead["id"],))
    if not v:
        return None
    nome = (v[0]["corretor_nome"] or "").strip().split(" ")[0]
    fone = grupo.telefone_bonito(v[0]["corretor_telefone"])
    return (f"Claro! Quem vai te acompanhar na visita é {nome}, no {fone}. Pode chamar por lá também." if nome
            else f"Claro! O contato de quem vai te acompanhar na visita é {fone}. Pode chamar por lá também.")


ETAPAS_DA_BUSCA = ("nova", "filtrar", "feito_busca", "imoveis_enviados", "finalizado")
# 475 (Pedro, 22/10: "se não tivermos avisamos a ele que vamos continuar verificando")
# 24/10 (Pedro): "se ela não encontrou a busca ela responde 'Entendi, por enquanto ainda procurando opções'"
CONTINUO_VERIFICANDO = "Entendi, por enquanto ainda procurando opções."
CONTINUO_EXATO = "E continuo verificando com os nossos corretores parceiros uma com o perfil exato. Te aviso por aqui."


def distancias_km(conn, bairros: list[str], lugar: str) -> dict[str, float]:
    """24/10 (Pedro, a Esther: "é bem mais de 2 km do distrito, ela deve ser revisada nesse aspecto"): a distância é a do banco
    (o centro de cada bairro, geo_bairro), nunca uma conta da Nay. Devolve {bairro: km até o lugar mais próximo que se chama
    assim}; vazio quando o lugar não é um bairro conhecido."""
    if not (lugar or "").strip() or not bairros:
        return {}
    r = banco.linhas(conn, """
        WITH ref AS (SELECT lat, lon FROM geo_bairro WHERE lower(unaccent(bairro)) LIKE '%%' || lower(unaccent(%s)) || '%%'),
             b AS (SELECT x AS nome, g.lat, g.lon FROM unnest(%s::text[]) x
                     LEFT JOIN geo_bairro_nome n ON n.nome_cadastro = x
                     JOIN geo_bairro g ON g.bairro = coalesce(n.bairro, x))
        SELECT b.nome, min(6371 * 2 * asin(sqrt(power(sin(radians(r.lat - b.lat) / 2), 2)
                          + cos(radians(b.lat)) * cos(radians(r.lat)) * power(sin(radians(r.lon - b.lon) / 2), 2)))) AS km
          FROM b CROSS JOIN ref r GROUP BY b.nome""", (lugar.strip(), list(bairros)))
    return {x["nome"]: float(x["km"]) for x in r}


def so_perto(conn, achados: list[dict], f: dict) -> list[dict]:
    """Com `perto_de` nos filtros, só o que fica até `perto_km` (padrão 6) do lugar. Lugar que não é bairro conhecido: não filtra."""
    lugar = str((f or {}).get("perto_de") or "").strip()
    if not lugar or not achados:
        return achados
    try:
        km_max = float(f.get("perto_km") or PERTO_KM_PADRAO)
    except (TypeError, ValueError):
        km_max = PERTO_KM_PADRAO
    d = distancias_km(conn, sorted({a["bairro"] for a in achados if a.get("bairro")}), lugar)
    if not d:
        return achados
    return [a for a in achados if a.get("bairro") in d and d[a["bairro"]] <= km_max]


def _afrouxar(f: dict) -> list[tuple[dict, bool]]:
    """394 (Pedro: "e depois já vir com as opções pesquisadas"): nada no perfil exato -> o mais perto, um passo de cada vez
    (sem mobília, com um quarto a menos, nos bairros vizinhos e em qualquer bairro, até 20% acima do valor)."""
    passos: list[tuple[dict, bool]] = [(f, False)]
    g = dict(f)
    # 24/10 (Pedro, a Esther pediu mobiliado e recebeu "com modulados e ar"): a mobília NÃO afrouxa mais. Mobiliado é
    # mobiliado (a mobília rígida de 20/10), e o "perto de X" também fica como ela pediu.
    if g.get("quartos") and not g.get("aceita_menos_quartos"):
        g = {**g, "aceita_menos_quartos": True}
        passos.append((g, True))
    if g.get("bairros") and not g.get("qualquer_bairro"):
        g = {**g, "bairros": [], "qualquer_bairro": True}
        passos.append((g, True))
    if g.get("teto"):
        g = {**g, "teto": int(float(g["teto"]) * 1.2)}
        passos.append((g, True))
    return passos


def recusados(f: dict) -> tuple[list[int], list[str]]:
    """Os imóveis que ela recusou (filtros.recusados): os códigos e os nomes (do condomínio ou do lugar), normalizados."""
    cods, nomes = [], []
    for x in (f or {}).get("recusados") or []:
        c = _int(re.sub(r"\D", "", str(x))) if re.fullmatch(r"\s*#?\d{3,5}\s*", str(x)) else None
        if c:
            cods.append(c)
        elif len(_normal(str(x))) >= 4:
            nomes.append(_normal(str(x)))
    return cods, nomes


def fora_os_recusados(achados: list[dict], nomes: list[str]) -> list[dict]:
    """Tira da busca o condomínio que ela recusou pelo nome ("já mora no Liverpool", "Reserva Inglesa não")."""
    if not nomes:
        return achados
    return [a for a in achados if not any(n in _normal(str(a.get("condominio") or "")) for n in nomes)]


def _buscar_e_mandar(conn, lead: dict, filtros: dict, ja_avisou: bool = False) -> None:
    cods_recusados, nomes_recusados = recusados(filtros)
    excluir = list(lead.get("enviados") or []) + ([lead["codigo"]] if lead.get("codigo") else []) + cods_recusados
    f = dict(filtros)
    if not f.get("finalidade"):
        f["finalidade"] = finalidade_sem_dizer(lead, f)
    if _aceita_parceiro(conn, lead):
        f["aceita_parceiro"] = "true"           # 400: o cliente final recebe também os de parceiro
    achados, proximas, tentativas, t0 = [], False, 0, time.monotonic()
    for tentativa, afrouxou in _afrouxar(f):
        tentativas += 1
        achados = banco.linhas(conn, "SELECT * FROM olx_cliente_buscar(%s::jsonb, %s::int[], %s)",
                               (json.dumps(tentativa, ensure_ascii=False), excluir,
                                MAX_IMOVEIS * 4 if (f.get("perto_de") or nomes_recusados or f.get("so_condominio")) else MAX_IMOVEIS))
        achados = so_no_condominio(fora_os_recusados(so_perto(conn, achados, tentativa), nomes_recusados), f)[:MAX_IMOVEIS]
        if achados:
            proximas = afrouxou
            break
    agentes.passo(lead, "buscou_na_base", f"{len(achados)} imóvel(is)" + (" (os mais próximos: afrouxou)" if proximas else "")
                  + f" · {_resumo_dos_filtros(f)}", filtros=f, tentativas=tentativas,
                  achados=[int(a["codigo"]) for a in achados], ms=int((time.monotonic() - t0) * 1000))
    if achados and not proximas:
        # 489: o veto do JEV antes dos cards (só no perfil exato: os "mais próximos" já vão avisados como próximos)
        achados = agentes.filtrar_imoveis(lead, f, achados)
    if lead.get("etapa") in ETAPAS_DA_BUSCA:
        _marcar(conn, lead["id"], etapa="feito_busca")
    # 475 (Pedro, 22/10): a busca do cliente conta o que a nossa base deu; nada no perfil exato ativa os grupos e a OLX
    # (olx/buscas.py) e ela avisa que vai continuar verificando
    from olx import buscas
    ativou = buscas.resultado_da_base(conn, lead, f, len(achados), bool(achados) and not proximas)
    buscando = ativou or banco.um(conn, "SELECT estado = 'buscando' FROM privado.busca_cliente WHERE lead = %s", (lead["id"],))
    if not achados and buscando:
        agentes.passo(lead, "nada_na_base", "a busca de fora continua (grupos, OLX, corretores)" + (" · ativou agora" if ativou else ""))
        texto = CONTINUO_VERIFICANDO
        if any(parecida(texto, x) for x in ja_mandou(conn, lead)):
            texto = "Continuo procurando e te aviso por aqui assim que aparecer."
        if not ja_avisou:
            mandar_texto(conn, lead, texto)
            buscas.cliente_avisado(conn, lead, texto)
        else:
            buscas.cliente_avisado(conn, lead, "(o aviso de que continua procurando saiu na resposta do turno)")
        return
    if not achados:
        # 416 (Pedro, 19/10): o catálogo não tem -> ordem de busca na OLX (olx/parceiro.py); ela "vai verificar"
        if abrir_busca_na_olx(conn, lead, f):
            agentes.passo(lead, "nada_na_base", "abriu a ordem de busca na OLX")
            if not ja_avisou:
                mandar_texto(conn, lead, "Vou verificar as opções que tenho aqui se estão disponíveis e já te retorno.")
            return
        agentes.passo(lead, "nada_na_base", "nada nem perto: o perfil foi ao grupo da equipe")
        # nunca a negativa: ela diz que está separando e a equipe recebe o perfil (se já disse neste turno, não repete)
        if not ja_avisou:
            mandar_texto(conn, lead, "Estou separando as opções com a nossa equipe e já te retorno por aqui.")
        _ao_crm(f"Cliente {quem(lead)} procura "
                f"{_resumo_dos_filtros(f)} e a busca não achou nada nem perto: separar opções para ela.")
        return
    enviados = list(lead.get("enviados") or [])
    for n, a in enumerate(achados):
        if n:
            time.sleep(DEPOIS_DAS_FOTOS_S)       # as fotos do anterior carregam antes do próximo card
        mandar_imovel(conn, lead, int(a["codigo"]))
        agentes.registrar(lead, "imoveis", "enviou", {"codigo": int(a["codigo"]), "proximas": proximas,
                                                      "resumo": f"#{a['codigo']} {a.get('condominio') or a.get('bairro') or ''}"})
        enviados.append(int(a["codigo"]))
        _marcar(conn, lead["id"], enviados=enviados)
    time.sleep(DEPOIS_DAS_FOTOS_S)
    texto = fecho(lead, len(achados), proximas=proximas)
    if any(_normal(texto) == _normal(x) for x in ja_mandou(conn, lead)):
        texto = fecho(lead, len(achados), de_novo=True)        # a segunda busca não fecha com a mesma frase
    mandar_texto(conn, lead, texto)
    if ativou and proximas:
        # 475: mandou as mais próximas e a busca do perfil exato continua nos grupos e na OLX
        time.sleep(ENTRE_ENVIOS_S)
        mandar_texto(conn, lead, CONTINUO_EXATO)
        buscas.cliente_avisado(conn, lead, CONTINUO_EXATO)
    if lead.get("etapa") in ETAPAS_DA_BUSCA:
        _marcar(conn, lead["id"], etapa="imoveis_enviados")
    log.info("lead %s: %d imóvel(is) enviado(s)%s", lead["id"], len(achados), " (os mais próximos)" if proximas else "")


def busca_na_olx_vale(cfg: dict, telefone: str) -> tuple[bool, bool]:
    """(abre, teste): a chave `busca_parceiro` (nao | teste | sim); em teste só para o PRIMEIRO número de `whatsapp_teste`
    (o do Pedro: o segundo da lista é a Michelle, cliente de verdade)."""
    modo = (cfg.get("busca_parceiro") or "nao").strip().lower()
    if modo == "sim":
        return True, False
    primeiro = [x for x in re.split(r"[,;\s]+", cfg.get("whatsapp_teste") or "") if x.strip()][:1]
    if modo == "teste" and primeiro and _so8(telefone) == _so8(primeiro[0]):
        return True, True
    return False, False


def abrir_busca_na_olx(conn, lead: dict, filtros: dict) -> bool:
    """Abre (ou reconhece a que já está aberta) a ordem de busca de imóvel de parceiro na OLX deste cliente."""
    abre, teste = busca_na_olx_vale(banco.chaves(conn), lead["telefone"])
    if not abre:
        return False
    # o mesmo pedido já procurado nas últimas 6 h e encerrado: a busca daria o mesmo; fica o caminho de antes (equipe)
    if banco.um(conn, """SELECT EXISTS (SELECT 1 FROM privado.olx_busca_parceiro WHERE lead = %s AND filtros = %s::jsonb
                           AND estado NOT IN ('pendente', 'buscando', 'sem_navegador', 'perguntado', 'aguardando_cadastro')
                           AND criado_em > now() - interval '6 hours')""", (lead["id"], json.dumps(filtros, ensure_ascii=False))):
        return False
    try:
        nova = banco.um(conn, """INSERT INTO privado.olx_busca_parceiro (lead, filtros, teste) VALUES (%s, %s::jsonb, %s)
                                 ON CONFLICT DO NOTHING RETURNING id""", (lead["id"], json.dumps(filtros, ensure_ascii=False), teste))
    except Exception:  # noqa: BLE001
        log.exception("lead %s: a ordem de busca na OLX não abriu", lead["id"])
        return False
    log.info("lead %s: busca na OLX %s", lead["id"], f"aberta ({nova})" if nova else "já aberta")
    return True


def finalidade_sem_dizer(lead: dict, f: dict) -> str:
    """Ela não disse: na OLX é a do anúncio; no orgânico, o valor diz (até R$ 30.000 é aluguel)."""
    if lead.get("negocio"):
        return "locacao" if lead["negocio"].startswith("loca") else "venda"
    try:
        teto = float(f.get("teto") or 0)
    except (TypeError, ValueError):
        teto = 0
    return "locacao" if 0 < teto <= 30000 else "venda"


def fecho(lead: dict, quantos: int = 2, de_novo: bool = False, proximas: bool = False) -> str:
    """A mensagem depois dos imóveis (fixa: o modelo não é chamado no meio do envio). `proximas`: a busca foi afrouxada
    (o perfil exato não tinha): "as mais próximas do que procura", nunca a negativa."""
    _, pronome = tratamento(lead)
    if proximas and not de_novo:
        procura = {"a senhora": "a senhora procura", "o senhor": "o senhor procura"}.get(pronome, "você procura")
        quem = {"a senhora": "chamou a atenção da senhora", "o senhor": "chamou a atenção do senhor"}.get(pronome, "te chamou a atenção")
        if quantos == 1:
            return f"Essa é a opção mais próxima do que {procura}. Ela {quem}? Posso agendar uma visita ou procurar mais opções."
        return (f"Essas são as opções mais próximas do que {procura}. Alguma {quem}? Posso agendar uma visita ou procurar "
                f"mais opções.")
    if de_novo:
        quem = {"a senhora": "a senhora gostou", "o senhor": "o senhor gostou"}.get(pronome, "você gostou")
        return (f"{'Essa é mais uma opção' if quantos == 1 else 'Essas são mais opções'} que encontrei. Se {quem} de "
                f"alguma, já vejo a visita.")
    if quantos == 1:
        quem = {"a senhora": "agradou a senhora", "o senhor": "agradou o senhor"}.get(pronome, "te agradou")
        return f"Essa é a opção que separei. Ela {quem}? Posso agendar uma visita ou procurar mais opções."
    quem = {"a senhora": "chamou a atenção da senhora", "o senhor": "chamou a atenção do senhor"}.get(pronome, "te chamou a atenção")
    return f"Essas são as opções que separei. Alguma {quem}? Posso agendar uma visita ou procurar mais opções."


def _grupo(texto: str) -> None:
    """Só o aviso de VISITA vai ao grupo (visita.py); o resto vai às Notificações do CRM (_ao_crm, 508)."""
    try:
        if not grupo.mandar_ao_grupo(texto):
            log.warning("o aviso não chegou ao grupo")
    except Exception:  # noqa: BLE001
        log.exception("o aviso ao grupo falhou")


def _ao_crm(texto: str) -> None:
    """508 (Pedro, 28/10/2026): a escalada e a dúvida do cliente vão às Notificações do CRM, não ao grupo."""
    grupo.ao_crm("lead", texto)


def _ha_trabalho(conn, cfg: dict) -> bool:
    silencio = max(0, int(cfg.get("whatsapp_silencio_s") or 20))
    return bool(banco.um(conn, """
        SELECT EXISTS (SELECT 1 FROM privado.olx_lead_whatsapp WHERE etapa = 'nova' AND assumido_em IS NULL
                        AND humano_em IS NULL AND criado_em > now() - interval '7 days')
            OR EXISTS (SELECT 1 FROM privado.olx_lead_whatsapp l JOIN captacao_mensagens m
                         ON m.direcao = 'recebida' AND m.id > l.ultima_lida
                        AND right(regexp_replace(coalesce(m.telefone, ''), '\\D', '', 'g'), 8) = right(l.telefone, 8)
                        AND m.criada_em < now() - make_interval(secs => %s)
                        WHERE l.assumido_em IS NOT NULL)""", (silencio,)))


def _para_a_fila(conn, lead: dict, codigo: int | None, pergunta: str) -> bool:
    """391: a pergunta entra na fila do PV do Tel. False = a fila está desligada (ou falhou): vai ao grupo."""
    try:
        if banco.um(conn, "SELECT pergunta_fila_ligada()") is not True:
            return False
        # 392b: a mesma pessoa já tem pergunta aberta na fila: a parecida não entra; a nova vai junto daquela
        abertas = banco.linhas(conn, """SELECT id, pergunta, estado, linha FROM pergunta_fila WHERE estado IN ('fila', 'perguntada')
                                         AND right(chave, 8) = %s ORDER BY id""", (_so8(lead["telefone"]),))
        if any(parecida(pergunta, a["pergunta"], 0.55) or _mesmo_assunto(pergunta, a["pergunta"]) for a in abertas):
            log.info("lead %s: a pergunta já está na fila", lead.get("id"))
            return True
        na_fila = [a for a in abertas if a.get("estado") == "fila" and a.get("linha") == "captacao"]
        if na_fila:
            banco.um(conn, "UPDATE pergunta_fila SET pergunta = pergunta || %s WHERE id = %s",
                     ("\nE também: " + pergunta.strip(), na_fila[-1]["id"]))
            return True
        return bool(banco.um(conn, "SELECT pergunta_fila_entrar('captacao', %s, %s, %s, NULL, %s, 'olx_whatsapp', NULL)",
                             (lead["telefone"], lead.get("nome"), codigo, pergunta)))
    except Exception:  # noqa: BLE001
        log.exception("lead %s: a pergunta não entrou na fila", lead.get("id"))
        return False


PALAVRAS_VAZIAS = set("a o as os e de da do das dos em no na nos nas um uma para por com que se ela ele sobre confirmar "
                      "imovel imoveis apartamento casa equipe pediu quer saber".split())


def _mesmo_assunto(a: str, b: str) -> bool:
    """As palavras que importam são quase as mesmas ("menor valor ... televisão, geladeira" x "Confirmar o menor valor
    do aluguel e se televisão, geladeira ficam")."""
    pa = {p for p in _normal(a).split() if len(p) > 2 and p not in PALAVRAS_VAZIAS and not p.isdigit()}
    pb = {p for p in _normal(b).split() if len(p) > 2 and p not in PALAVRAS_VAZIAS and not p.isdigit()}
    if not pa or not pb:
        return False
    return len(pa & pb) / min(len(pa), len(pb)) >= 0.6


SEM_INFORMACAO = "Entendi, por enquanto ainda procurando opções."
PROMPT_CURTO = """Você é a Nay, da Imob Easy. Chegou a RESPOSTA RECEBIDA (do nosso time) a uma dúvida de um cliente. Escreva o que
vai ao cliente: NO MÁXIMO duas frases curtas (até 220 caracteres), só com o que responde à dúvida dele.
- Se a resposta NÃO traz a informação pedida (não achou, não sabe, depende de confirmar com o proprietário) ou só traz
  sugestões que ele não pediu: responda EXATAMENTE "Entendi, por enquanto ainda procurando opções."
- NUNCA cite distância, nem ofereça outros imóveis, bairros ou códigos que ele não pediu, nem diga "mais fora de".
- Português do Brasil, de gente, sem emoji, sem link, sem telefone.
Devolva SÓ JSON: {"texto": "..."}"""


def resposta_curta(resposta: str, chamar=None) -> str:
    """24/10 (Pedro, a Esther recebeu um balão enorme com sugestões e uma distância errada): a resposta do revisor passa por
    aqui. Curta (até 160 caracteres) vai como está; maior, o modelo reescreve em duas frases ou diz "ainda procurando"."""
    r = re.sub(r"\s+", " ", str(resposta or "")).strip()
    if len(r) <= 160:
        return r
    try:
        t = str((chamar or (lambda p, u: modelo.chamar(p, u, no="olx.whatsapp")))(PROMPT_CURTO, f"RESPOSTA RECEBIDA: {r}").get("texto") or "").strip()
    except Exception:  # noqa: BLE001 -- sem o modelo, as duas primeiras frases, no máximo 220 letras
        t = ""
    if not t:
        t = " ".join(re.split(r"(?<=[.!?])\s+", r)[:2])[:220].rstrip()
    return t[:240]


def texto_da_resposta(p: dict) -> str:
    """A resposta do Tel como ela chega ao cliente: "Sobre o #9026 (Turim Residencial): Fica tudo, sim."."""
    r = resposta_curta(p.get("resposta"))
    if r.rstrip(".").lower() == SEM_INFORMACAO.rstrip(".").lower():
        return SEM_INFORMACAO
    r = r[:1].upper() + r[1:]
    if p.get("codigo"):
        sobre = f"o #{p['codigo']}" + (f" ({p['imovel']})" if (p.get("imovel") or "").strip() else "")
    else:
        sobre = "a sua pergunta"
    return f"Sobre {sobre}: {r}"


def entregar_respostas(conn) -> int:
    """391: o que o Tel respondeu na fila, para quem está no WhatsApp de captação, sai por aqui (é a Nay falando)."""
    feitas = 0
    for p in banco.linhas(conn, """SELECT id, chave, codigo, imovel, resposta FROM pergunta_fila
                                    WHERE linha = 'captacao' AND estado = 'respondida' AND entregue_em IS NULL
                                      AND entrega_erro IS NULL ORDER BY respondida_em LIMIT 5"""):
        achado = banco.linhas(conn, """SELECT id FROM privado.olx_lead_whatsapp WHERE right(telefone, 8) = right(%s, 8)
                                        ORDER BY criado_em DESC LIMIT 1""", (p["chave"],))
        if not achado:
            banco.um(conn, "UPDATE pergunta_fila SET entrega_erro = 'não é cliente da Nay do WhatsApp' WHERE id = %s",
                     (p["id"],))
            continue
        lead = _lead(conn, achado[0]["id"])
        mandar_texto(conn, lead, texto_da_resposta(p))
        banco.um(conn, "UPDATE pergunta_fila SET entregue_em = now() WHERE id = %s", (p["id"],))
        log.info("lead %s: a resposta do Tel (pergunta %s) entregue", lead["id"], p["id"])
        feitas += 1
    return feitas


def _ha_resposta(conn) -> bool:
    try:
        return bool(banco.um(conn, """SELECT EXISTS (SELECT 1 FROM pergunta_fila WHERE linha = 'captacao'
                                        AND estado = 'respondida' AND entregue_em IS NULL AND entrega_erro IS NULL)"""))
    except Exception:  # noqa: BLE001 -- sem a 391 no banco
        return False


def enviar_pedidos(conn) -> int:
    """396 (Pedro, 16/10: "coloca esse campo [Enviar imóvel] nos cards dos leads também do de captação"): o que a equipe
    escolheu no card do CRM sai por este número (8595-6408), card + fotos, um imóvel por vez. Parceria e fora do ar não
    saem. Com a Nay na conversa, os imóveis entram nos "já enviados" dela (a busca não repete)."""
    feitos = 0
    for p in banco.linhas(conn, """UPDATE privado.captacao_envio_pedido SET estado = 'enviando'
                                    WHERE id = (SELECT id FROM privado.captacao_envio_pedido WHERE estado = 'pendente'
                                                 ORDER BY id LIMIT 1 FOR UPDATE SKIP LOCKED)
                                  RETURNING *"""):
        fone = re.sub(r"\D", "", p["telefone"])
        if fone.startswith("55") and len(fone) in (12, 13):
            fone = fone[2:]
        achado = banco.linhas(conn, """SELECT id FROM privado.olx_lead_whatsapp WHERE right(telefone, 8) = right(%s, 8)
                                        ORDER BY criado_em DESC LIMIT 1""", (fone,))
        lead = _lead(conn, achado[0]["id"]) if achado else {"id": 0, "telefone": fone, "enviados": []}
        enviados, fora = [], []
        try:
            for n, codigo in enumerate(p["codigos"]):
                if not _ofertavel(conn, codigo, lead):
                    fora.append(str(codigo))
                    continue
                if enviados:
                    time.sleep(DEPOIS_DAS_FOTOS_S)       # as fotos do anterior carregam antes do próximo card
                mandar_imovel(conn, lead, int(codigo))
                enviados.append(int(codigo))
                banco.um(conn, "UPDATE privado.captacao_envio_pedido SET enviados = %s WHERE id = %s", (enviados, p["id"]))
            if lead.get("id") and enviados:
                _marcar(conn, lead["id"], enviados=list(dict.fromkeys(list(lead.get("enviados") or []) + enviados)))
            resultado = (f"{len(enviados)} imóvel(is) enviado(s)" +
                         (f"; não saíram (parceria ou fora do ar): {', '.join(fora)}" if fora else ""))
            banco.um(conn, """UPDATE privado.captacao_envio_pedido SET estado = %s, resultado = %s, feito_em = now()
                               WHERE id = %s""", ("enviado" if enviados else "falhou", resultado, p["id"]))
            log.info("envio %s pela captação: %s", p["id"], resultado)
            feitos += 1
        except Exception as e:  # noqa: BLE001
            banco.um(conn, """UPDATE privado.captacao_envio_pedido SET estado = 'falhou', resultado = %s, feito_em = now()
                               WHERE id = %s""", (f"parou no meio ({len(enviados)} saíram): {e}"[:500], p["id"]))
            log.warning("envio %s pela captação falhou: %s", p["id"], e)
    return feitos


def _ha_envio(conn) -> bool:
    try:
        return bool(banco.um(conn, "SELECT EXISTS (SELECT 1 FROM privado.captacao_envio_pedido WHERE estado = 'pendente')"))
    except Exception:  # noqa: BLE001 -- sem a 396 no banco
        return False


def texto_do_seguimento(lead: dict) -> str:
    """392 (Pedro, 16/10): ~10 min de silêncio depois da última mensagem dela. Já mandou opções: se alguma agradou; só
    falou de um imóvel: "Sr. Carlos, posso estar enviando outras opções semelhantes para o Sr.?"."""
    trat, pronome = tratamento(lead)
    para = {"a senhora": "a senhora", "o senhor": "o senhor"}.get(pronome, "você")
    if lead.get("enviados"):
        t = "conseguiu ver as opções que eu mandei? Se quiser, separo outras semelhantes ou já agendo uma visita."
    else:
        t = f"posso estar enviando outras opções semelhantes para {para}?"
    return f"{trat}, {t}" if trat else t[:1].upper() + t[1:]


FECHO_DA_BUSCA = ("Essas são as opções", "Essa é a opção", "Essas são mais opções", "Essa é mais uma opção")
# "vou separar/pegar/enviar": promessa de ENTREGA, que vale como cumprida quando card ou foto saiu depois
VOU_ENTREGAR = re.compile(r"\b(vou (separar|pegar|enviar|mandar|buscar|procurar)|lhe enviar|te envio|j[aá] envio)\b", re.I)
OFERTA = "outras opções semelhantes"
# ela prometeu um retorno (a equipe confirma, ela avisa): quem espera é ela, não o cliente
PROMESSA = re.compile(r"\b(retorno|retornar|aviso por aqui|te aviso|assim que|vou (confirmar|verificar|checar|ver com)|"
                      r"estou (verificando|confirmando|separando|aguardando|vendo)|ainda (estou )?aguardando|"
                      r"j[aá] (passei|encaminhei|pedi)|passo para a equipe|reforcei|refor[cç]ar)\b", re.I)


def que_seguimento(lead: dict, conversa: list[dict], entregou_depois: bool = False) -> str | None:
    """392b (Pedro, 16/10: "fez a mesma pergunta duas vezes ... precisa checar para ela nunca fazer isso"). O
    acompanhamento só tem dois casos, e cada um sai UMA vez:
      - depois das opções (a última mensagem dela é o fecho da busca): "conseguiu ver as opções?";
      - ela só falou de um imóvel e nunca ofereceu outras: "posso estar enviando outras opções semelhantes?".
    A última mensagem dela é uma PERGUNTA ou uma PROMESSA de retorno: espera (o cliente responde, ou a equipe)."""
    nossas = [m for m in conversa if m.get("direcao") == "enviada" and (m.get("texto") or "").strip()]
    if not nossas:
        return None
    ultima = nossas[-1]["texto"].strip()
    if ultima.startswith(FECHO_DA_BUSCA):
        return texto_do_seguimento({**lead, "enviados": lead.get("enviados") or [0]})
    if ultima.endswith("?") or PROMESSA.search(ultima):
        return None
    if VOU_ENTREGAR.search(ultima) and not entregou_depois:
        return None                       # 394: prometeu as opções/fotos e ainda não mandou: quem espera é ela
    if lead.get("enviados") or any(OFERTA in (m.get("texto") or "") for m in nossas):
        return None
    return texto_do_seguimento({**lead, "enviados": []})


_ULTIMO_SEGUIMENTO = [0.0]


def seguir(conn, cfg: dict, a_cada_s: float = 60.0) -> int:
    """392: o acompanhamento (que_seguimento). Os relógios: `seguimento_min` (10) depois da última mensagem DELA e da
    última do CLIENTE ("vamos aguardar, tem 1 minuto só que ele respondeu"); 60 min entre dois acompanhamentos; das 8h às
    20h; só para conversa das últimas 6 h. Visita andando, equipe na conversa e atendimento encerrado ficam de fora."""
    if time.monotonic() - _ULTIMO_SEGUIMENTO[0] < a_cada_s:
        return 0
    _ULTIMO_SEGUIMENTO[0] = time.monotonic()
    if not (8 <= datetime.now(MANAUS).hour < 20):
        return 0
    minutos = max(1, int(cfg.get("seguimento_min") or 10))
    candidatos = banco.linhas(conn, """
        SELECT l.id FROM privado.olx_lead_whatsapp l
         CROSS JOIN LATERAL (
               SELECT max(m.criada_em) FILTER (WHERE m.direcao = 'recebida') AS ela,
                      max(m.criada_em) FILTER (WHERE m.direcao = 'enviada') AS nos
                 FROM captacao_mensagens m
                WHERE right(regexp_replace(coalesce(m.telefone, ''), '\\D', '', 'g'), 8) = right(l.telefone, 8)
                  AND m.criada_em > now() - interval '3 days') x
         WHERE l.assumido_em IS NOT NULL AND l.humano_em IS NULL
           AND l.etapa IN ('filtrar', 'feito_busca', 'imoveis_enviados')
           AND x.ela IS NOT NULL AND x.nos > x.ela
           AND x.nos < now() - make_interval(mins => %(m)s) AND x.ela < now() - make_interval(mins => %(m)s)
           AND x.nos > now() - interval '6 hours'
           AND (l.seguimento_em IS NULL OR l.seguimento_em < now() - interval '60 minutes')
           AND NOT EXISTS (SELECT 1 FROM privado.olx_visita v WHERE v.lead = l.id
                              AND v.estado IN ('confirmar_cliente', 'buscando_corretor', 'pedindo_proprietario'))
         ORDER BY x.nos""", {"m": minutos})
    if not candidatos or not conectada():
        return 0
    feitos = 0
    for c in candidatos:
        lead = _lead(conn, c["id"])
        if not lead or not _pode(cfg, lead["telefone"]):
            continue
        if _gente_escreveu(conn, lead, lead.get("humano_em") or lead.get("assumido_em")):
            continue                                  # a equipe está na conversa: a vez é dela
        conversa = _conversa(conn, lead)
        nossas = [m for m in conversa if m.get("direcao") == "enviada" and (m.get("texto") or "").strip()]
        entregou = bool(nossas) and bool(banco.um(conn, """SELECT EXISTS (SELECT 1 FROM privado.olx_cliente_enviada
                                  WHERE lead = %s AND tipo IN ('card', 'foto') AND enviado_em > %s)""",
                                  (lead["id"], nossas[-1]["criada_em"])))
        texto = que_seguimento(lead, conversa, entregou)
        if not texto:
            continue
        if mandar_texto(conn, lead, texto):
            _marcar(conn, lead["id"], seguimento_em=banco.um(conn, "SELECT now()"))
            log.info("lead %s: acompanhamento mandado", lead["id"])
            feitos += 1
    return feitos


def atender(conn, cfg: dict) -> int:
    if (cfg.get("whatsapp_responde") or "nao").strip().lower() not in ("teste", "sim"):
        return 0
    # 394: cada parte com o seu tropeço (uma não derruba as outras); o que manda mensagem só com a Z-API conectada
    def parte(nome, f, *a):
        try:
            return f(*a) or 0
        except Exception as e:  # noqa: BLE001
            log.warning("%s não andou: %s", nome, e)
            return 0
    if visita.ha_trabalho(conn) and conectada():
        parte("a visita", visita.atender, conn, cfg)                 # 389/393: consultas, lembrete, o depois
    parte("a descoberta dos orgânicos", descobrir_organicos, conn, cfg)
    if _ha_resposta(conn) and conectada():
        parte("a resposta do Tel", entregar_respostas, conn)
    if _ha_envio(conn) and conectada():
        parte("o envio pedido no CRM", enviar_pedidos, conn)          # 396
    parte("o acompanhamento", seguir, conn, cfg)
    # a Z-API só é consultada quando há o que fazer (a volta é de 5 em 5 s)
    if not _ha_trabalho(conn, cfg) or not conectada():
        return 0
    return parte("a abertura", abrir, conn, cfg) + parte("a resposta", responder, conn, cfg)


def laco(a_cada_s: float = 5.0) -> None:
    """A linha da Nay do WhatsApp: a sua própria conexão, e um erro aqui não para o chat da OLX nem os anúncios."""
    conn = None
    while True:
        try:
            if conn is None or conn.closed:
                conn = banco.conectar()
            atender(conn, banco.chaves(conn))
        except Exception:  # noqa: BLE001
            log.exception("a volta da Nay do WhatsApp falhou; reconecto em 30 s")
            try:
                if conn is not None:
                    conn.close()
            except Exception:  # noqa: BLE001
                pass
            conn = None
            time.sleep(30)
        time.sleep(a_cada_s)


def iniciar() -> threading.Thread:
    t = threading.Thread(target=laco, name="nay-whatsapp", daemon=True)
    t.start()
    return t
