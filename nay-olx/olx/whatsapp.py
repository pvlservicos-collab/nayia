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
SABER_POR_IMOVEL = 8         # 01/11: o que o Tel já respondeu de cada imóvel, no turno (os mais recentes)
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
   diga que confirma e já retorna, e marque "perguntar" com o que ficou pendente), e feche com UMA pergunta curta, com as
   suas palavras, que faça a conversa andar (se ela quer conhecer o imóvel ou ver outros parecidos). Não use sempre a
   mesma frase. Se na OLX ela já pediu visita com dia/horário, marque "visita"; se pediu desconto ou proposta, marque
   "perguntar" (a equipe responde e a conversa segue com você).
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
   Respondidas as perguntas que cabem, diga numa frase curta que vai separar as opções e peça a busca: acao "buscar".
   O sistema manda os imóveis, um por vez, logo depois. Não faça mais perguntas depois do fechamento.
   Ela pediu as opções ("tem outras?", "quero ver opções", "manda o que tem") e você já sabe o tipo ou a finalidade, o
   valor e o lugar: busque JÁ ("buscar"). O que faltar (quartos, mobília, crédito) vira tanto faz; não segure as opções
   por mais uma pergunta.
3. DEPOIS DAS OPÇÕES: se ela gostou de algum, ofereça a visita; se quer mais, refaça o roteiro só no que mudou e peça
   "buscar" de novo. Quando não há nada no perfil exato, o sistema pergunta a ela se serve com menos quartos, num bairro
   vizinho ou um pouco acima do valor: se ela aceitou, ponha nos filtros (aceita_menos_quartos = true, o bairro novo em
   bairros, o teto novo) e peça "buscar"; se não aceitou, nada muda e o sistema segue procurando o perfil exato.
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
   Ela quer visitar AGORA ou daqui a menos de 30 min ("posso visitar agora?"): não marque "visita"; diga que precisa de
   um tempinho para confirmar com o corretor e o proprietário e pergunte se pode ser daqui a meia hora ou em outro dia.
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
   curta (sem a palavra "card": para ela são as informações e as fotos). O card já responde e mostra o resto. O que o card
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
   sistema dá a ficha: responda pela ficha e pergunte, com as suas palavras, se ela quer conhecer o imóvel ou ver outros
   parecidos, como na OLX (o tipo, os quartos e a finalidade vêm desse imóvel).
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
- "NAY (resposta da equipe)" é o que você já passou a ela da resposta da equipe: vale como informação confirmada.

=== QUANDO É COM A EQUIPE (acao "equipe") ===
Documentação, contrato, reclamação, pedido para falar com uma pessoa, corretor oferecendo parceria, cliente que decidiu
fechar (quer comprar ou alugar, vai dar entrada) ou que mandou documentos. Diga com
naturalidade que já passa para a equipe e que vão falar com ela por aqui. (Desconto, proposta e menor valor NÃO: é
"perguntar", a equipe responde e a conversa continua com você.) Interesse num imóvel ("tenho interesse", "gostei desse",
"quero ver esse", "tenho um cliente interessado nesse") também NÃO é com a equipe: é a VISITA. Mande o imóvel se ela
ainda não viu (acao "fotos") e pergunte o dia e o horário.

=== UMA CONFIRMAÇÃO SÓ ===
- Cada pedido é confirmado UMA vez. Quando for buscar, é UM balão só, juntando nele o que for perguntar à equipe (o que
  vai confirmar e que já separa as opções, numa frase); os imóveis chegam logo depois, pelo sistema.
- Já disse que vai confirmar algo com a equipe ou que já retorna: não diga de novo. Se ela só agradeceu, disse "ok" ou
  "aguardo", não responda (balões vazios).

=== NUNCA ===
- Pedir o código do imóvel. O código é nosso, não dela: ele vem da conversa (anúncio, cards, nome do condomínio).
- Falar de um imóvel só pelo código (Pedro, 03/11: "sempre que a Nay for responder sobre um imóvel, ter o nome do
  condomínio para ficar claro e não gerar confusão"): diga o condomínio, e o código só junto ("o apartamento do Vila do
  Sol Maior (#9120)"). Sem condomínio, o tipo e o bairro ("a casa no Parque 10 (#5733)").
- Repetir uma pergunta ou uma frase que você já mandou nesta conversa. Perguntou e ela ainda não respondeu: espere a
  resposta dela (balões vazios é melhor que repetir). Já disse que vai confirmar com a equipe: não diga de novo a cada
  mensagem; responda o que ela disse agora.
- Dar negativa ("não consigo", "não dá", "não é possível", "não temos"). Se a busca não achar, o sistema pergunta a ela
  o que pode afrouxar (menos quartos, um bairro vizinho) ou diz que segue procurando.
- Inventar. O que não está na ficha você não sabe: diga que confirma e retorna. Isso vale para CRECI, CNPJ e qualquer
  número de documento: só o que o sistema deu; senão, "vou confirmar com a equipe".
- Endereço exato, número da casa ou do apartamento, bloco, torre, nome do proprietário. Bairro, condomínio e as avenidas
  da linha do imóvel pode.
- Link, telefone, e-mail, emoji.
- Falar de Nay da OLX, de robô, de ficha, de catálogo. Para ela você é só a Nay, da Imob Easy.
- Dizer que um imóvel é "de parceiro", "de parceria" ou "de outra imobiliária". Para ela todo imóvel é da Imob Easy.

=== COMO VOCÊ FALA ===
(Pedro, 04/11: "ela tá falando muito robótica; melhorar sem deixar formal demais, um humano normal que fala de maneira
objetiva".) Português do Brasil, de gente: uma moça de Manaus no WhatsApp do trabalho, objetiva e simpática, não um
assistente traduzido do inglês nem atendimento de call center. Curto: um ou dois balões, poucas linhas.
- Reaja ao que ela disse ANTES de perguntar a próxima coisa: responda a dúvida dela ou comente o que ela contou (uma
  frase), e só então pergunte. Não pule direto para a próxima pergunta como quem preenche formulário.
- NÃO abra toda mensagem com "Perfeito", "Entendi", "Claro", "Certo" ou "Ótimo" + o nome. Varie, ou vá direto ao ponto.
  O nome dela só de vez em quando, não em toda mensagem.
- Sem frase pronta e sem formalidade: nada de "lhe enviar", "meu sistema", "posso estar enviando", "Fico à disposição",
  "Como posso te ajudar hoje?". Diga como uma pessoa diria: "te mando", "vou separar", "já te falo".
Trate pelo tratamento que o sistema dá (Sra./Sr. + primeiro nome; "a senhora", "o senhor"); sem tratamento, pelo
primeiro nome e "você". Valor em reais assim: R$ 700.000 / R$ 2.500.

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
  campos não cobrem ("cozinha e lavanderia completas", "elevador", "andar baixo"), um item curto cada. Suítes e andar
  entram aqui como ela disse ("pelo menos 1 suíte", "2 suítes", "andar alto", "térreo ou primeiro andar"): a busca só
  manda o imóvel que cumpre.
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


# 03/11 (Pedro: "sempre que a Nay for responder sobre um imóvel, ter o nome do condomínio para ficar claro e não gerar
# confusão, e não só o código"): o "#9120" / "código 9120" de um texto ganha o condomínio ao lado (sem condomínio, o tipo
# e o bairro), a não ser que o nome já esteja no texto. O card (📍 ...) já traz o nome.
CODIGO_NO_TEXTO = re.compile(r"(?:#|\bc[óo]d(?:igo)?\.?\s*:?\s*)(\d{3,5})\b", re.I)
SO_TIPO = {"casa", "apartamento", "apto", "ap", "loja", "ponto", "sala", "terreno", "predio", "galpao", "comercial",
           "imovel", "condominio", "residencial", "edificio", "sem", "nao", "na", "outro", "outros", "de", "do", "da"}


def com_condominio(conn, texto: str) -> str:
    if not texto or "📍" in texto:
        return texto
    cods = list(dict.fromkeys(int(m.group(1)) for m in CODIGO_NO_TEXTO.finditer(texto)))
    if not cods:
        return texto
    try:
        linhas = banco.linhas(conn, "SELECT codigo, condominio_nome, bairro, tipo FROM imoveis WHERE codigo = ANY(%s)", (cods,))
    except Exception:  # noqa: BLE001 -- sem o nome, o texto sai como veio
        return texto
    nomes: dict[int, str] = {}
    for l in linhas:
        c = (l.get("condominio_nome") or "").strip()
        palavras = [w for w in _normal(c).split() if w]
        if len(c) < 3 or not palavras or all(w in SO_TIPO for w in palavras):
            c = ""
        tipo = (l.get("tipo") or "").strip()
        nome = c or (f"{tipo.split()[0].lower() if tipo else 'imóvel'} no {l['bairro'].strip()}" if (l.get("bairro") or "").strip() else "")
        if nome:
            nomes[int(l["codigo"])] = nome
    ja = _normal(texto)

    def troca(m: re.Match) -> str:
        nome = nomes.get(int(m.group(1)))
        if not nome or _normal(nome) in ja:
            return m.group(0)
        return f"{m.group(0)} ({nome})"
    return CODIGO_NO_TEXTO.sub(troca, texto)


def mandar_texto(conn, lead: dict, texto: str, tipo: str = "texto") -> str:
    """Um texto dela. O MESMO texto para a mesma pessoa nas últimas 6 h não sai de novo (Pedro, 16/10: "fez a mesma
    pergunta duas vezes para o lead ... precisa checar para ela nunca fazer isso"). Devolve '' quando segurou.
    `tipo` 'resposta_fila' (04/11): a resposta da equipe que ela passa; é a marca que o turno mostra (montar_turno)."""
    texto = com_condominio(conn, texto)
    if any(_normal(texto) == _normal(x) for x in ja_mandou(conn, lead, horas=6)):
        log.info("lead %s: texto repetido segurado: %s", lead.get("id"), texto[:80])
        return ""
    return _mandar(conn, lead, "/send-text", {"message": texto}, tipo, texto_no_crm=texto)


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


# 03/11 (Pedro: "a Nay Leads está enviando 2 vezes o mesmo imóvel"): a Aline (lead 58) recebeu o #9119 duas vezes e o #9120
# três em 12 minutos -- a busca da base, a dos grupos e a revisita mandaram cada uma o seu card, e nenhuma olhava a conversa
CARD_REPETIDO_H = 24


def card_ja_foi(conn, lead: dict, codigo: int, horas: int = CARD_REPETIDO_H) -> bool:
    """O card deste imóvel já foi para esta pessoa (por este número) nas últimas `horas`."""
    tel8 = _so8(lead.get("telefone"))
    if not tel8 or not codigo:
        return False
    return bool(banco.um(conn, """SELECT EXISTS (SELECT 1 FROM captacao_mensagens
                                    WHERE direcao = 'enviada' AND criada_em > now() - make_interval(hours => %s)
                                      AND right(regexp_replace(coalesce(telefone, ''), '\\D', '', 'g'), 8) = %s
                                      AND texto ~ ('C[oó]digo:\\s*' || %s::text || '\\M'))""", (horas, tel8, str(int(codigo)))))


CARD_VISTO_H = 24 * 30


def card_visto(conn, lead: dict, codigo: int) -> bool:
    """04/11 (a Lorena ...9301 pediu "o link" do anúncio e só recebeu as fotos): ela já recebeu o card deste imóvel POR AQUI
    (nos enviados, ou na conversa dos últimos 30 dias). O imóvel do anúncio não conta como visto: o anúncio ela viu na OLX
    ou no portal, o card não."""
    return (_int(codigo) in {_int(x) for x in lead.get("enviados") or []}
            or card_ja_foi(conn, lead, codigo, horas=CARD_VISTO_H))


def mandar_imovel(conn, lead: dict, codigo: int, com_card: bool = True, com_fotos: bool = True, repetir: bool = False) -> int:
    """O card e as fotos de UM imóvel (sem a colagem, que é só dos grupos). Devolve quantas fotos saíram.
    `com_card=False`: só as fotos ("gostaria de ver mais fotos" do imóvel que ela já conhece).
    `com_fotos=False`: só o card (21/10: para ela dizer qual imóvel quer visitar, sem pedir o código).
    `repetir=True`: manda mesmo que o card já tenha ido nas últimas 24 h (ela pediu de novo, ou a equipe mandou à mão)."""
    if com_card and not repetir and card_ja_foi(conn, lead, codigo):
        agentes.passo(lead, "card_repetido", f"o card do #{codigo} já foi nas últimas {CARD_REPETIDO_H} h: não reenvia")
        return 0
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
               EXISTS (SELECT 1 FROM privado.olx_cliente_enviada e WHERE e.message_id = m.message_id) AS nossa,
               -- 04/11: 'resposta_fila' = a resposta da equipe que ela passou (montar_turno a marca para as paredes)
               (SELECT e.tipo FROM privado.olx_cliente_enviada e WHERE e.message_id = m.message_id LIMIT 1) AS tipo_nosso
          FROM captacao_mensagens m
         WHERE right(regexp_replace(coalesce(m.telefone, ''), '\\D', '', 'g'), 8) = %s
           AND m.criada_em > now() - interval '30 days'
           -- 394: o eco das fotos (sem texto) não ocupa o lugar da conversa
           AND (m.direcao = 'recebida' OR coalesce(btrim(m.texto), '') <> '')
         ORDER BY m.id DESC LIMIT 40""", (_so8(lead["telefone"]),))))


def _num(v) -> int | None:
    """04/11: o número de uma coluna do banco (Decimal('700000.00'), 3, '3', None) sem o tropeço do _int, que tira os
    não-dígitos (o Decimal virava 70000000). None = não se sabe."""
    if v is None or isinstance(v, bool) or (isinstance(v, str) and not v.strip()):
        return None
    try:
        return int(round(float(v)))
    except (TypeError, ValueError):
        return _int(v)


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


def chaves(lead: dict) -> bool:
    """554: o lead que o portal Chaves na Mão mandou (cnm_lead_para_a_nay)."""
    return lead.get("origem") == "chavesnamao"


def zap(lead: dict) -> bool:
    """572: o lead que o Grupo ZAP mandou pelo Canal Pro (zap_lead_para_a_nay)."""
    return lead.get("origem") == "zap"


def portal(lead: dict) -> str | None:
    """O nome do portal de onde o lead veio sem conversa antes (Chaves na Mão ou o Grupo ZAP), ou None."""
    if chaves(lead):
        return "Chaves na Mão"
    if zap(lead):
        return lead.get("portal_nome") or "ZAP Imóveis"
    return None


def nome_do_zap(origem: str | None) -> str:
    """O leadOrigin do Grupo ZAP no nome que a pessoa conhece: o site onde ela viu o anúncio."""
    o = (origem or "").lower()
    if "viva" in o:
        return "Viva Real"
    if o.strip() == "olx":
        return "OLX"
    return "ZAP Imóveis"


def quem(lead: dict) -> str:
    """Para os avisos da equipe: 'Fulana (OLX, (92) 9...)' ou '(orgânico, ...)'."""
    # 422: o cliente posto à mão no CRM (Buscar imóvel OLX) aparece como "pelo CRM"
    origem = {"organico": "orgânico", "manual": "pelo CRM",
              "chavesnamao": "Chaves na Mão", "zap": "ZAP"}.get(lead.get("origem") or "", "OLX")
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


def saber_dos_imoveis(conn, lead: dict) -> list[str]:
    """01/11 (Pedro: "atualiza nosso banco ... para que a Nay não pergunte novamente"): o que o Tel e os donos já
    responderam sobre os imóveis desta conversa (imovel_conhecimento, a mesma memória que a Nay da Parceria lê). Até
    01/11 a Nay Leads não lia: o que o Tel respondia a uma cliente voltava como pergunta para a próxima."""
    cods = [c for c in (_int(x) for x in [lead.get("codigo"), *(lead.get("enviados") or []),
                                          *[f.get("codigo") for f in lead.get("fichas_citadas") or []]]) if c]
    if not cods:
        return []
    linhas = banco.linhas(conn, """
        SELECT k.codigo, k.assunto, left(regexp_replace(k.texto, '\\s+', ' ', 'g'), 220) AS texto
          FROM imovel_conhecimento k WHERE k.codigo = ANY(%s::text[])
         ORDER BY k.codigo, k.atualizado_em DESC""", ([str(c) for c in dict.fromkeys(cods)],))
    por: dict[str, list[str]] = {}
    for l in linhas:
        por.setdefault(l["codigo"], [])
        if len(por[l["codigo"]]) < SABER_POR_IMOVEL:
            por[l["codigo"]].append(f"{l['assunto']}: {l['texto']}")
    return [f"#{c}: " + " | ".join(x) for c, x in por.items()]


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


def _contexto(conn, lead: dict) -> dict | None:
    """O que veio antes do WhatsApp: a conversa da OLX (chat) e, do Chaves na Mão (554), a ficha do imóvel do anúncio e o
    que ela deixou no portal (lead['portal'], o mais antigo primeiro)."""
    if portal(lead):
        i = banco.um(conn, "SELECT site_imovel_publico(%s)", (lead["codigo"],)) if lead.get("codigo") else None
        lead["ficha_do_anuncio"] = nay._ficha(i) if isinstance(i, dict) else {}
    if chaves(lead):
        lead["portal"] = banco.linhas(conn, """
            SELECT to_char(coalesce(criado_no_portal, recebido_em) AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI') AS quando,
                   codigo, anuncio_titulo, mensagem, tipo
              FROM privado.cnm_lead WHERE right(telefone, 8) = right(%s, 8)
             ORDER BY coalesce(criado_no_portal, recebido_em) LIMIT 10""", (lead["telefone"],))
    elif zap(lead):
        # 572: o que ela deixou no Grupo ZAP (privado.zap_lead), no mesmo formato do Chaves na Mão
        lead["portal"] = banco.linhas(conn, """
            SELECT to_char(coalesce(criado_em, recebido_em) AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI') AS quando,
                   codigo, NULL AS anuncio_titulo, mensagem, canal AS tipo, origem
              FROM privado.zap_lead WHERE right(telefone, 8) = right(%s, 8)
             ORDER BY coalesce(criado_em, recebido_em) LIMIT 10""", (lead["telefone"],))
        lead["portal_nome"] = nome_do_zap((lead["portal"][-1] if lead["portal"] else {}).get("origem"))
    return banco.um(conn, "SELECT olx_nay_contexto(%s)", (lead["chat"],)) if lead.get("chat") else None


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
    elif portal(lead):
        # 554 (Pedro, 31/10: "põe a mesma Nay da OLX para responder lá com os mesmos objetivos"): o portal não tem chat;
        # ela deixou o contato e quem abre a conversa é você, aqui. O caminho é o da OLX; muda só a abertura.
        # 572 (Pedro, 03/11: "liga a mesma Nay que atende OLX pedindo zap aí"): o Grupo ZAP pelo mesmo caminho.
        nome = portal(lead)
        finalidade = {"locacao": "LOCAÇÃO", "venda": "VENDA"}.get(lead.get("negocio") or "", "finalidade não informada")
        linhas += [
            paredes.DO_CHAVES if chaves(lead) else paredes.DO_ZAP,
            f"Ela viu o nosso anúncio no portal {nome} e deixou o contato (nome, telefone e, às vezes, uma mensagem). "
            "Não houve conversa antes do WhatsApp. "
            + ("Não diga \"falamos antes\"." if nome == "OLX" else "NUNCA fale de OLX nem diga \"falamos antes\"."),
        ]
        # 04/11 (a Paula ...8142: no meio da conversa, uma consulta nova do Chaves na Mão a pôs de volta em 'nova', e a
        # abertura, com a conversa inteira na frente, não saiu três vezes): conversa já começada não tem abertura
        ja_falou = any(m.get("nossa") or m.get("origem") == "resposta" for m in conversa)
        if ja_falou:
            linhas.append("Vocês JÁ estão conversando (abaixo): a abertura já foi. NÃO se apresente de novo nem refaça a "
                          "abertura; siga O CAMINHO de onde a conversa está.")
        if lead.get("meio_da_conversa") and lead.get("codigo"):
            linhas.append(
                f"AGORA, no meio da conversa, ela deixou o contato de novo pelo {nome}, desta vez pelo imóvel cód. "
                f"{lead['codigo']} (a ficha abaixo). Numa frase curta, diga que viu o interesse dela também nesse imóvel "
                "(pelo condomínio ou pelo bairro) e pergunte se quer que você mande as informações; e responda o que ela "
                "escreveu e ainda está sem resposta.")
        if lead.get("ficha_do_anuncio"):
            linhas += [
                *([] if ja_falou else [
                    f"Siga O CAMINHO como na OLX, com uma diferença na ABERTURA: diga que recebeu o contato dela pelo {nome} "
                    "sobre o imóvel (o condomínio ou o bairro), responda pela ficha o que a mensagem dela perguntou e "
                    "feche com uma pergunta curta, com as suas palavras, sobre conhecer o imóvel ou ver outros parecidos. "
                    "Se a mensagem já pede visita com dia e horário, marque \"visita\"."]),
                f"{finalidade} | cód. {lead.get('codigo') or '-'}",
                "Ficha do imóvel do anúncio: " + json.dumps(lead["ficha_do_anuncio"], ensure_ascii=False),
            ]
        elif ja_falou:
            pass                          # sem anúncio e já conversando: a abertura "como o orgânico" já foi
        else:
            # 31/10 (Pedro: a Gleise, posta à mão, sem o anúncio): não se sabe o imóvel; abre como o orgânico
            linhas += [
                f"NÃO se sabe de qual imóvel ela veio. ABERTURA: diga que recebeu o contato dela pelo {nome} e "
                "pergunte se ela procura imóvel para alugar ou para comprar (não cite imóvel nenhum). Depois, o roteiro de "
                "OUTRAS OPÇÕES, uma pergunta por vez, começando pelo tipo (apartamento, casa...).",
                f"Ex.: \"Boa tarde, Sra. Gleise! Aqui é a Nay, da Imob Easy. Recebi seu contato pelo {nome}. A "
                "senhora está procurando imóvel para alugar ou para comprar?\"",
            ]
        tipos = " ".join((p.get("tipo") or "").lower() for p in lead.get("portal") or [])
        if ja_falou:
            pass                          # o que a abertura diria do financiamento e do telefone visto já foi dito
        elif "financ" in tipos:
            # 02/11 (Pedro, os leads de financiamento): quem simulou financiamento é perguntado disso na abertura
            linhas.append(
                "ELA SIMULOU UM FINANCIAMENTO no portal (os valores estão abaixo). A ABERTURA é sobre isso, curta e sem "
                f"citar banco, taxa nem parcela: pergunte se ela estava iniciando um financiamento pelo {nome} e se "
                "quer que você mande mais informações do imóvel. Se simulou mais de um imóvel, fale do mais recente. "
                "Ex.: \"Olá, Sr. Edmilson! Aqui é a Nay, da Imob Easy. O senhor estava iniciando um financiamento pelo "
                f"{nome}? Quer que eu te mande mais informações sobre o imóvel?\" Depois, siga O CAMINHO.")
        elif tipos.strip() and not any((p.get("mensagem") or "").strip() and "visualizei" not in (p.get("mensagem") or "").lower()
                                       for p in lead.get("portal") or []):
            linhas.append(
                "Ela só VIU O TELEFONE ou o WHATSAPP do anúncio (não escreveu nada): não diga que ela perguntou algo. "
                f"Diga que viu o interesse dela no imóvel pelo {nome} e pergunte, com as suas palavras, se ainda procura "
                "e se quer conhecer o imóvel ou ver outros. Seja leve: ela não pediu para ser chamada.")
        linhas.append("O que ela deixou no portal (o mais antigo primeiro):")
        for p in lead.get("portal") or []:
            linhas.append(f"  {p['quando']} · {p.get('tipo') or 'contato'} · {p.get('anuncio_titulo') or 'anúncio'} "
                          f"(cód. {p.get('codigo') or '-'}): {(p.get('mensagem') or '').strip() or '(sem mensagem)'}")
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
        *(["O QUE O TEL E OS DONOS JÁ RESPONDERAM SOBRE ESSES IMÓVEIS (é verdade; responda por aqui e NÃO marque "
           "\"perguntar\" o que já está aqui):"] + [f"  {x}" for x in lead["saber_dos_imoveis"]]
          if lead.get("saber_dos_imoveis") else []),
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
                # 04/11: a resposta da fila sai sem "Sobre a sua pergunta:"; a marca fica só aqui (paredes.RESPOSTA_DA_EQUIPE)
                linhas.append(f"NAY (resposta da equipe): {texto}" if m.get("tipo_nosso") == "resposta_fila" else f"NAY: {texto}")
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
_AVISADOS: set[int] = set()
ESPERA_DEPOIS_DE_3_S = 15 * 60       # 04/11: a abertura que falhou três vezes tenta de novo daqui a 15 min


def _em_espera(lid: int) -> bool:
    return _ESPERA.get(lid, 0.0) > time.monotonic()


def _falhou(conn, lead: dict, ate: int | None, erro: Exception, abertura: bool = False) -> None:
    """394: um cliente com erro (modelo, Z-API, dado estranho) não trava os outros nem chama o modelo de 5 em 5 s:
    espera 2 min; na terceira falha seguida, a Nay larga a mensagem (marca lida) e avisa a equipe no grupo.
    04/11 (a Paula ...8142): na ABERTURA a terceira falha avisa a equipe UMA vez e a Nay tenta de novo a cada 15 min;
    antes ela marcava humano_em ("a Nay não conseguiu abrir") e a conversa ficava parada."""
    lid = lead["id"]
    _FALHAS[lid] = _FALHAS.get(lid, 0) + 1
    _ESPERA[lid] = time.monotonic() + 120
    log.warning("lead %s: falhou (%d): %s", lid, _FALHAS[lid], erro)
    if _FALHAS[lid] >= 3:
        _FALHAS.pop(lid, None)
        if abertura:
            _ESPERA[lid] = time.monotonic() + ESPERA_DEPOIS_DE_3_S
            if lid not in _AVISADOS:
                _AVISADOS.add(lid)
                _ao_crm(f"Cliente {quem(lead)} no WhatsApp de captação: a Nay não conseguiu escrever a primeira mensagem "
                        f"(três tentativas: {str(erro)[:120]}). Ela tenta de novo a cada 15 min; se quiserem, chamem por lá.")
            return
        if ate:
            _marcar(conn, lid, ultima_lida=ate)
        _ao_crm(f"Cliente {quem(lead)} no WhatsApp de captação: a Nay não conseguiu responder a última mensagem "
                f"(três tentativas). Vejam por lá.")


def _deu_certo(lid: int) -> None:
    _FALHAS.pop(lid, None)
    _ESPERA.pop(lid, None)
    _AVISADOS.discard(lid)


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
# 04/11 (Pedro: "é melhor não ter essas frases robóticas, só na nossa memória, e a Nay fala de forma humanizada, isso para
# todas as respostinhas padrões"): o que ainda sai pronto do código (quando o modelo não está no meio, ou não escreveu)
# sai de uma lista curta, variada, e nunca igual ao que ela já mandou (uma_das)
BALOES_SEM_RESPOSTA = {
    "perguntar": ["Vou confirmar isso e já te falo.", "Deixa eu ver isso direitinho e já te respondo.",
                  "Já vejo isso e te falo por aqui."],
    "equipe": ["Vou chamar alguém da equipe pra falar com você por aqui.",
               "Já passo para a equipe, e eles te chamam por aqui."]}
BALAO_SEM_RESPOSTA = {k: v[0] for k, v in BALOES_SEM_RESPOSTA.items()}
MANDO_O_IMOVEL = ["Te mando aqui as informações e as fotos dele.", "Olha as informações e as fotos dele aqui.",
                  "Vou te mandar as informações e as fotos dele."]
MANDO_AS_OPCOES = ["Vou te mandar as opções que tenho nesse perfil.", "Separei umas opções nesse perfil, te mando aqui.",
                   "Te mando agora as que achei com isso."]


def _vez(texto: str) -> int:
    """Um número que muda com o texto (a frase pronta gira sem sortear: o mesmo turno, a mesma frase, nos testes também)."""
    return sum(ord(c) for c in (texto or ""))


def uma_das(opcoes: list[str], ja: list[str] | None = None, vez: int = 0) -> str:
    """Uma das frases, a partir da `vez` (gira), a primeira que não se parece com nada de `ja` (o que já foi para ela).
    Todas parecidas: a da vez."""
    if not opcoes:
        return ""
    for i in range(len(opcoes)):
        o = opcoes[(vez + i) % len(opcoes)]
        if not any(parecida(o, x, 0.8) for x in ja or []):
            return o
    return opcoes[vez % len(opcoes)]


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
            # 04/11 (Pedro: "card" é jargão nosso): era "Vou te mandar o card com as informações e as fotos dele."
            r["baloes"] = [uma_das(MANDO_O_IMOVEL, vez=_vez(texto))]
        mandar(cod, "card_responde", f"o card do #{cod} responde" + ("" if so_o_card else "; o resto vai à equipe"))
        livre = False
    # 4. pediu opções e já se sabe o bastante: busca já (o que falta vira tanto faz)
    if livre and PEDE_OPCOES.search(texto) and "equipe" not in acoes and _filtros_bastam(_filtros(lead.get("filtros"), r.get("filtros"))):
        acoes = [*[a for a in acoes if a != "perguntar"][:1], "buscar"]
        baloes = _baloes_do(r)
        if not baloes or baloes[-1].rstrip().endswith("?"):
            r["baloes"] = [uma_das(MANDO_AS_OPCOES, vez=_vez(texto))]     # 04/11: era uma frase só, sempre a mesma
        passos.append(("pediu_opcoes", "pediu opções e os filtros bastam: busca já"))
    # 4b. 04/11 (Pedro: "o foco da Nay Leads é ser um bom filtro"): buscar sem o valor e sem o lugar não busca (saía o que
    # houvesse, de qualquer valor e lugar); o modelo pergunta o que falta
    if "buscar" in acoes:
        f = _filtros(lead.get("filtros"), r.get("filtros"))
        if not f.get("finalidade"):
            f = {**f, "finalidade": finalidade_sem_dizer(lead, f)}
        if not _filtros_bastam(f):
            acoes = [a for a in acoes if a != "buscar"]
            falta = " e ".join(x for x in ("o valor" if not f.get("teto") else "",
                                            "o lugar" if not (f.get("bairros") or f.get("qualquer_bairro") or f.get("condominio")
                                                              or f.get("perto_de")) else "") if x) or "o tipo"
            r["_falta_para_buscar"] = falta
            passos.append(("buscar_sem_filtro", f"pediu a busca sem {falta}: não busca"))
    # 4c. 04/11 (o lead 60: "Posso visitar agora?" -> visita para 02/11 15:19, a confirmação recusou calada e ela ficou sem
    # resposta): a visita que não vai sair (sem dia/hora, já passou, a menos de 30 min) sai das ações e o turno volta ao
    # modelo com o motivo (turno_mudo)
    if "visita" in acoes:
        v = r.get("visita") if isinstance(r.get("visita"), dict) else {}
        motivo = visita.por_que_nao(_int(v.get("codigo")) or _int(lead.get("codigo")), str(v.get("data") or ""),
                                    str(v.get("hora") or ""), datetime.now(MANAUS))
        if motivo:
            acoes = [a for a in acoes if a != "visita"]
            r["_visita_motivo"] = motivo
            passos.append(("visita_nao_sai", f"a visita não sai ({motivo}): {v.get('data')} {v.get('hora')}"))
    # 5a. 03/11 (Pedro, a Sra. Maria …5999: "pediu visita e ela foi super ignorante"): ela perguntou "como faço pra visitar",
    # o modelo pôs a ação fotos e o balão "vou te enviar as informações e as fotos", e a trava das fotos repetidas mandou
    # "Já te mandei as fotos ... quer que eu mande de novo?". Sem ela pedir foto, foto que já foi não é ação: sai a ação e
    # sai do balão a promessa de mandar fotos/informações
    # 04/11 (a Lorena ...9301: "Me manda o link? Eu esqueci qual é 😅" e só recebeu as fotos): só sai a ação quando as fotos
    # E o card já foram; o card que ela ainda não recebeu por aqui vai (_fazer). E vale também quando ela pediu foto: a
    # frase fixa "Já te mandei as fotos desse aqui em cima na conversa. Quer que eu mande de novo?" saiu de _fazer (às vezes
    # era falsa); quem diz agora é o modelo, com as palavras dele, na segunda chamada (turno_mudo)
    if "fotos" in acoes and not DE_NOVO.search(texto):
        f = r.get("fotos") if isinstance(r.get("fotos"), dict) else {}
        cods = [c for c in dict.fromkeys(_int(x) for x in [*(f.get("codigos") or []), f.get("codigo")]) if c] or [_int(lead.get("codigo"))]
        if all(c and fotos_ja_foram(conn, lead, c) and card_visto(conn, lead, c) for c in cods):
            acoes = [a for a in acoes if a != "fotos"]
            baloes = []
            for b in _baloes_do(r):
                frases = [x for x in re.split(r"(?<=[.!?])\s+", b) if x.strip() and not PROMETE_FOTO.search(x)]
                if frases:
                    baloes.append(" ".join(frases))
            r["baloes"] = baloes
            passos.append(("fotos_sem_pedir", f"as fotos e o card de {', '.join('#' + str(c) for c in cods)} já foram: sem reenviar"))
    # 5. nunca leva a dúvida à equipe sem dizer nada a ela (o lead 60 ficou sem resposta). 04/11: a frase pronta é a rede;
    # _responder_um pede antes ao modelo que escreva (turno_mudo vê a marca _balao_padrao)
    if not _baloes_do(r):
        for a in ("perguntar", "equipe"):
            if a in acoes:
                r["baloes"] = [uma_das(BALOES_SEM_RESPOSTA[a], vez=_vez(texto))]
                r["_balao_padrao"] = True
                passos.append(("balao_sem_resposta", f"ação {a} sem balão: a frase padrão"))
                break
    r["acoes"] = acoes
    return acoes, passos


# 04/11 (Pedro: "ela não pode errar, nem esquecer o lead"; o lead 60 ficou mudo com "Posso visitar agora?", a Lorena com "Só
# tem 1 dormitório?"): a rede de 2c644f6 (só a trava das fotos) vale para QUALQUER turno que ficaria sem balão
FALAM_SOZINHAS = {"fotos", "card", "buscar", "visita"}      # ações que mandam algo a ela mesmo sem balão


def turno_mudo(r: dict, acoes: list[str], passos: list[tuple[str, str]], novas: list[str]) -> str:
    """Por que este turno precisa voltar ao modelo ('' = ele fala): 'visita' (a visita não sai e ela precisa saber),
    'buscar' (pediu a busca sem o valor ou o lugar e prometeu as opções), 'fotos' (as fotos já foram) ou 'mudo' (nenhum
    balão e nenhuma ação que fale, para mensagem que não é só cortesia). A frase padrão da rede 5 também conta como mudo:
    o modelo tem a chance de escrever com as palavras dele."""
    nomes = {n for n, _d in passos}
    baloes = [] if r.get("_balao_padrao") else _baloes_do(r)
    if "visita_nao_sai" in nomes:
        return "visita"
    if "buscar_sem_filtro" in nomes and (not baloes or any(VOU_ENTREGAR.search(b) for b in baloes)):
        return "buscar"
    textos = [t for t in novas or [] if (t or "").strip()]
    if not textos or so_agradeceu(textos) or baloes or (FALAM_SOZINHAS & set(acoes)):
        return ""
    return "fotos" if "fotos_sem_pedir" in nomes else "mudo"


def aviso_do_mudo(motivo: str, r: dict, agora: datetime | None = None) -> str:
    """O aviso da segunda chamada para o turno mudo (turno_mudo)."""
    agora = agora or datetime.now(MANAUS)
    if motivo == "visita":
        v = r.get("visita") if isinstance(r.get("visita"), dict) else {}
        quando = f"{v.get('data') or ''} {v.get('hora') or ''}".strip() or "o horário que ela disse"
        por = {
            "cedo": f"ela quer visitar {quando}, e isso é daqui a menos de 30 min. A visita é confirmada antes com o corretor "
                    "e com o proprietário, e em cima da hora isso não fecha. Diga isso a ela com naturalidade, numa frase, e "
                    f"pergunte se pode ser a partir das {visita.hora(visita.primeiro_horario(agora))} ou em outro dia",
            "passou": f"o horário que ela disse ({quando}) já passou: pergunte o dia e o horário que ela quer",
            "sem_dia_hora": "faltou o dia ou o horário exato da visita: pergunte (\"de manhã\" não é horário)",
            "sem_imovel": "você não sabe qual imóvel ela quer visitar: pergunte pelo nome (condomínio ou bairro), nunca o código",
        }.get(str(r.get("_visita_motivo") or ""), "a visita não pode ser marcada assim: pergunte o dia e o horário")
        return (f"ATENÇÃO: NÃO marque a ação visita agora: {por}. Escreva o balão (sem \"não dá\", \"não consigo\", \"não é "
                "possível\").")
    if motivo == "buscar":
        return (f"ATENÇÃO: ainda falta {r.get('_falta_para_buscar') or 'o valor e o lugar'} para buscar: NÃO marque buscar "
                "e não prometa as opções. Pergunte isso a ela, curto, reagindo antes ao que ela disse.")
    if motivo == "fotos":
        # 2c644f6 (a Lorena ...9301): a trava das fotos repetidas tirou a única ação do turno
        return ("ATENÇÃO: as fotos e as informações desse imóvel JÁ FORAM mandadas a ela (estão ali em cima na conversa) e ela "
                "não pediu de novo. NÃO use a ação fotos. RESPONDA EM TEXTO, no balão, ao que ela escreveu agora (pela ficha; "
                "o que não estiver lá, diga que vai confirmar e marque \"perguntar\"). Se ela pediu fotos, diga com as suas "
                "palavras que as que você tem são as que já mandou e pergunte se quer de novo ou se pede outras à equipe.")
    return ("ATENÇÃO: a sua resposta não tem nenhum balão, e ela escreveu algo que pede resposta. RESPONDA EM TEXTO ao que "
            "ela escreveu agora (pela ficha e pela conversa; o que você não souber, diga que vai confirmar e marque "
            "\"perguntar\") e siga o roteiro. Nunca deixe a mensagem dela sem resposta.")


def ultima_rede(r: dict, motivo: str, novas: list[str], agora: datetime | None = None) -> tuple[list[str], list[str]]:
    """Ainda mudo depois da segunda chamada: (as ações, os balões) da rede. A dúvida vai à equipe ("perguntar") e ela ouve
    que vamos ver; a visita em cima da hora ganha a frase de outro horário. Nunca sem resposta."""
    agora = agora or datetime.now(MANAUS)
    texto = " / ".join(t.strip() for t in novas if (t or "").strip())
    if motivo == "buscar":
        falta = str(r.get("_falta_para_buscar") or "")
        return [], [uma_das(["E até que valor fica bom?", "Qual o valor máximo que fica bom?"] if "valor" in falta else
                            ["E qual região fica melhor?", "Quais bairros ficam bons?"], vez=_vez(texto))]
    if motivo == "visita" and r.get("_visita_motivo") == "cedo":
        h = visita.hora(visita.primeiro_horario(agora))
        return [], [uma_das([f"Pra agora fica em cima da hora para confirmar com o proprietário. Pode ser a partir das {h}, "
                             "ou prefere outro dia?",
                             f"Em cima da hora assim fica difícil confirmar com o proprietário. Que tal a partir das {h}, "
                             "ou outro dia?"], vez=_vez(texto))]
    if motivo == "visita" and r.get("_visita_motivo") in ("passou", "sem_dia_hora"):
        return [], [uma_das(["Que dia e horário ficam bons para a visita?", "Me diz o dia e o horário que fica bom para visitar."],
                            vez=_vez(texto))]
    if not str(r.get("motivo") or "").strip():
        r["motivo"] = f"a Nay ficou sem resposta para: {texto[:300]}"
    return ["perguntar"], [uma_das(BALOES_SEM_RESPOSTA["perguntar"], vez=_vez(texto))]


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
            # 394: o que ela já escreveu (ou o que já conversamos, se veio de outro anúncio) entra na abertura
            conversa = _conversa(conn, lead)
            # 04/11 (a Paula ...8142: no meio da conversa, uma consulta nova do Chaves na Mão -- cnm_lead_para_a_nay -- a
            # pôs de volta em 'nova'; a "abertura" com a conversa inteira na frente não saiu, deu ValueError três vezes e ela
            # foi marcada humano_em "a Nay não conseguiu abrir"): conversa já começada é resposta comum. A etapa volta a
            # ser a de onde a conversa estava (como na reabertura do 'finalizado') e o turno diz que é o meio da conversa.
            meio = any(m.get("nossa") or m.get("origem") == "resposta" for m in conversa)
            etapa = "filtrar"
            if meio:
                etapa = ("visita" if visita.ativa(conn, lead["id"])
                         else "imoveis_enviados" if lead.get("enviados") else "filtrar")
            # a equipe já chamou por este número (nos últimos 3 dias): a conversa é dela
            gente = _gente_escreveu(conn, lead, banco.um(conn, "SELECT now() - interval '3 days'"))
            if gente and meio:
                # 04/11: no meio da conversa a equipe que escreveu não toma a conversa para sempre: a Nay volta ao que era
                # e a resposta comum (com a espera de gap_equipe_min) segue dali
                _marcar(conn, lead["id"], assumido_em_agora=True, etapa=etapa)
                agentes.passo(lead, "abertura_no_meio", "consulta nova no meio da conversa, com a equipe por perto: sem abertura")
                continue
            if gente:
                _marcar(conn, lead["id"], assumido_em_agora=True, humano_em=gente, etapa="filtrar",
                        parada_motivo="a equipe já tinha chamado por este número")
                log.info("lead %s: a equipe já chamou; a Nay não abre", lead["id"])
                continue
            ctx_olx = _contexto(conn, lead)
            lead["visita_aberta"] = visita.para_o_modelo(conn, lead["id"])
            ate = max([m["id"] for m in conversa if m.get("direcao") == "recebida"] or [_ultima_recebida(conn, lead)])
            agentes.novo_turno(lead)
            if meio:
                lead["etapa"], lead["meio_da_conversa"] = etapa, True
                if organico(lead):
                    lead["fichas_citadas"] = _fichas_citadas(conn, conversa, lead)
                lead["imoveis_conhecidos"] = imoveis_da_conversa(conn, lead)
                lead["saber_dos_imoveis"] = saber_dos_imoveis(conn, lead)
                agentes.passo(lead, "abertura_no_meio", f"consulta nova no meio da conversa (#{lead.get('codigo')}): resposta comum")
            else:
                agentes.passo(lead, "abertura", "lead novo: a primeira mensagem da Nay")
            turno = montar_turno(lead, ctx_olx, conversa)
            r = modelo.chamar(PROMPT, turno, no="olx.whatsapp")
            if not _baloes_do(r):
                # 04/11: uma segunda chamada, avisada, antes de dar a volta como falha
                agentes.passo(lead, "chamou_de_novo", "a abertura veio sem balão")
                r = modelo.chamar(PROMPT, turno + "\n\nATENÇÃO: a sua resposta veio sem balão. Escreva a mensagem dela "
                                  "agora (curta, como pessoa), no JSON.", no="olx.whatsapp")
            acoes = acoes_da(r)
            if not _baloes_do(r):
                raise ValueError("o modelo não escreveu a abertura")
            uso = modelo.ultimo_uso()
            agentes.atendimento(lead, {"rotas": [], "geral": True}, r, uso, uso.get("ms"), acoes)
            baloes = _falar(conn, lead, r, acoes)
            agentes.passo(lead, "falou", f"{len(baloes)} balão(ões)" + (f"; ações: {', '.join(acoes)}" if acoes else ""),
                          baloes=baloes)
            filtros = condominio_que_faltou(conn, _filtros(lead.get("filtros"), r.get("filtros")), conversa)
            _marcar(conn, lead["id"], assumido_em_agora=True, etapa=etapa, ultima_lida=ate, filtros=filtros)
            # 16/10: o que ela promete já na abertura (passar o desconto à equipe, confirmar a visita pedida na OLX...) tem
            # de chegar à equipe: as ações da abertura valem como as de qualquer resposta
            for acao in acoes:
                _fazer(conn, _lead(conn, lead["id"]), r, acao, filtros, cfg)
            _deu_certo(lead["id"])
            log.info("lead %s aberto (%d balão/ões)", lead["id"], len(baloes))
            feitos += 1
        except Exception as e:  # noqa: BLE001 -- um cliente não para os outros
            agentes.registrar(lead, "fluxo", "falhou", {"resumo": f"abertura: {type(e).__name__}: {e}"[:200]}, erro=str(e))
            # 04/11 (a Paula ...8142 ficou com a equipe por "a Nay não conseguiu abrir"): falha da Nay nunca marca humano_em;
            # na terceira, a equipe é avisada e ela tenta de novo mais tarde (_falhou)
            _falhou(conn, lead, None, e, abertura=True)
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
    if banco.um(conn, "SELECT count(*) FROM privado.olx_cliente_enviada WHERE lead = %s AND tipo IN ('texto', 'resposta_fila')",
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
    if lead.get("visita_aberta") and visita.desmarcou(novas) and visita.cliente_desmarcou(conn, lead, novas):
        # 31/10 (Pedro, o Eduardo ...2424 desmarcou e a visita seguiu confirmada, sem aviso à corretora e à dona)
        _marcar(conn, lead["id"], ultima_lida=ate)
        agentes.passo(lead, "visita_desmarcada", "o cliente desmarcou: visita cancelada, corretor e dono avisados")
        return True
    ctx_olx = _contexto(conn, lead)
    if organico(lead):
        lead["fichas_citadas"] = _fichas_citadas(conn, conversa, lead)
    lead["imoveis_conhecidos"] = imoveis_da_conversa(conn, lead)
    lead["saber_dos_imoveis"] = saber_dos_imoveis(conn, lead)
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
    mudo = turno_mudo(r, acoes, passos, novas)
    if mudo:
        # 04/11 (Pedro: "na conversa da Lorena ela perguntou e a Nay não respondeu, não pode abandonar um cliente assim";
        # e o lead 60, "Posso visitar agora?", mudo): a rede de 2c644f6 (a trava das fotos) agora vale para qualquer turno
        # mudo -- a visita que não sai, a busca sem filtro, a frase padrão, nenhum balão. Uma segunda chamada, avisada;
        # ainda mudo, a última rede (ultima_rede): nunca sem resposta.
        for nome, detalhe in passos:
            agentes.passo(lead, nome, detalhe)
        agentes.passo(lead, "chamou_de_novo", f"turno mudo ({mudo}): responder em texto")
        r2 = modelo.chamar(prompt, turno + "\n\n" + aviso_do_mudo(mudo, r), no="olx.whatsapp")
        u4 = modelo.ultimo_uso()
        uso = {**u4, **{k: (uso.get(k) or 0) + (u4.get(k) or 0) for k in ("ms", "tokens_entrada", "tokens_saida", "tokens_cache")}}
        sobra, ainda = paredes.cortar(_baloes_do(r2), turno, organico(lead))
        if ainda:
            agentes.passo(lead, "parede_cortou", "; ".join(f"{p}: {x}" for _i, p, x in ainda)[:180], furos=ainda)
        r2["baloes"] = sobra
        acoes2, passos2 = depois_do_modelo(conn, lead, r2, novas, nossas[-1]["texto"] if nossas else "")
        mudo2 = turno_mudo(r2, acoes2, passos2, novas)
        if not mudo2 or (_baloes_do(r2) and not r2.get("_balao_padrao") and mudo2 != "buscar"):
            r, acoes, passos = r2, acoes2, passos2
        else:
            if not r.get("_balao_padrao"):
                extra, r["baloes"] = ultima_rede(r, mudo, novas)
                acoes = list(dict.fromkeys([*[a for a in acoes if a not in ("visita", "buscar")], *extra]))[:2]
                r["acoes"] = acoes
            passos = [("balao_sem_resposta", f"ainda mudo ({mudo2}) depois da segunda chamada: a última rede")]
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
# 03/11: ela pediu foto (ou vídeo/material) nesta mensagem; e o balão que promete mandar fotos/informações
PEDIU_FOTO = re.compile(r"\b(fotos?|imagens?|v[íi]deos?|material|tem foto|manda (as )?fotos?)\b", re.I)
PROMETE_FOTO = re.compile(r"\b(vou|vamos|irei|j[áa] vou)\s+(te\s+|lhe\s+)?(enviar|mandar|passar|encaminhar)\b.{0,60}\b(fotos?|informa[çc][õo]es)\b", re.I)
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
            # um que ela já recebeu POR AQUI: só as fotos (o card ela já viu). 04/11 (a Lorena ...9301: "Me manda o link? Eu
            # esqueci qual é 😅" e só recebeu as fotos): o imóvel do anúncio não conta mais como visto -- ela viu o anúncio,
            # não o card -- e o card vai quando ela ainda não o recebeu aqui (card_visto)
            ja_viu = codigo in enviados or card_visto(conn, lead, codigo)
            de_novo = bool(DE_NOVO.search(" ".join(r.get("_novas") or [])))
            # 25/10 (a marcação do Pedro no treino, …9640: "não reenviar o mesmo card, ela enviou várias vezes"): as fotos
            # que já foram não vão de novo, a não ser que ela peça de novo ("de novo", "não chegaram"). 04/11: saiu a frase
            # fixa "Já te mandei as fotos desse aqui em cima na conversa. Quer que eu mande de novo?" (às vezes falsa): o
            # turno sem nada a mandar volta ao modelo antes (depois_do_modelo 5a e turno_mudo)
            com_fotos = de_novo or not fotos_ja_foram(conn, lead, codigo)
            if ja_viu and not com_fotos:
                agentes.passo(lead, "fotos_ja_foram", f"as fotos e o card do #{codigo} já foram: não reenvia")
                continue
            mandar_imovel(conn, lead, codigo, com_card=not ja_viu, com_fotos=com_fotos, repetir=de_novo)
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
                                  r"verificando com|te aviso (por aqui )?assim que|sigo procurando", b, re.I)
                        for b in (r.get("_baloes_que_sairam") or _baloes_do(r)))
        # 04/11 (Pedro: "o foco da Nay Leads é ser um bom filtro"): sem o valor e o lugar não se busca (a abertura também
        # chega aqui; o turno comum já tirou a ação em depois_do_modelo)
        if not _filtros_bastam({**filtros, "finalidade": filtros.get("finalidade") or finalidade_sem_dizer(lead, filtros)}):
            agentes.passo(lead, "buscar_sem_filtro", f"a busca pedida sem o valor ou o lugar: não busca ({_resumo_dos_filtros(filtros)})")
            return
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
# 04/11 (Pedro: "é melhor não ter essas frases robóticas, só na nossa memória"): saíram as duas frases fixas, "Entendi, por
# enquanto ainda procurando opções." e "E continuo verificando com os nossos corretores parceiros uma com o perfil exato. Te
# aviso por aqui." (esta falava "parceiros" ao cliente). Sem nada no perfil, ela pergunta UMA coisa para afrouxar
# (pergunta_para_afrouxar) ou diz, com uma frase que varia, que segue procurando (sigo_procurando).
MAX_PROXIMOS = 2           # 04/11: o "mais próximo" (bairro vizinho, condomínio próximo) sai no máximo 2 por busca
TETO_FOLGA = 1.10          # 04/11: nada acima de +10% do teto que ela disse, por nenhum caminho (a régua)


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


COMERCIAL = {"galpao", "predio", "sala", "loja", "terreno", "comercial"}


def _comercial(f: dict) -> bool:
    return _normal(str((f or {}).get("tipo") or "")).replace(" ", "_") in COMERCIAL


def _afrouxar(f: dict) -> list[tuple[dict, str]]:
    """O que se pode PERGUNTAR a ela para afrouxar, na ordem: (os filtros afrouxados, 'quartos' | 'bairro' | 'valor').
    394 (Pedro: "e depois já vir com as opções pesquisadas"): era o mais perto, um passo de cada vez, MANDADO sem perguntar
    (um quarto a menos, qualquer bairro, até +20% do valor), e o veto do JEV não rodava nessas.
    04/11 (Pedro: "o foco da Nay Leads é ser um bom filtro mais do que qualquer outra coisa; ela não pode errar ... nem
    mandar imóvel errado"): nada passa de +10% do teto, nem troca de bairro ou baixa quartos sem ela aceitar. Os passos
    agora só servem para saber o que existe e fazer UMA pergunta curta (pergunta_para_afrouxar): "Em Planalto com 4 quartos
    não tenho agora; serve com 3, ou um bairro vizinho?". A mobília continua sem afrouxar (24/10, a Esther).
    O 'bairro' leva a marca _vizinhos: quem busca soma os bairros vizinhos (nai_bairros_ao_redor) aos que ela disse."""
    passos: list[tuple[dict, str]] = []
    # quem já disse que não serve menos quartos (aceita_menos_quartos = false) não é perguntado de novo
    if _int(f.get("quartos")) and _int(f.get("quartos")) > 1 and f.get("aceita_menos_quartos") is None and not _comercial(f):
        passos.append(({**f, "aceita_menos_quartos": True}, "quartos"))
    if f.get("bairros") and not f.get("qualquer_bairro") and not f.get("so_condominio"):
        passos.append(({**f, "_vizinhos": True}, "bairro"))
    if _int(f.get("teto")):
        # 01/11 (lead 119: até R$ 200 mil e recebeu duas de R$ 255 mil): a busca já põe +10%; aqui é só para PERGUNTAR
        # se serve um pouco acima (até +20% no total)
        passos.append(({**f, "teto": int(float(f["teto"]) * 1.2 / 1.1)}, "valor"))
    return passos


# ── 04/11: A RÉGUA ÚNICA "serve ao pedido" ──
# Pedro (04/11): "ela não pode errar, nem esquecer o lead, nem mandar imóvel errado". Tudo o que sai ao cliente sem ela ter
# pedido aquele imóvel (a busca da base, a revisita da base, a oferta do corretor, o cadastro da OLX, o anúncio de
# parceiro) passa por aqui: finalidade, tipo, valor até +10% do teto, quartos, bairro, mobília (o "sem" nunca recebe
# mobiliado), suítes mínimas e faixa de andar. Suítes e andar vinham só como texto nas exigências e não filtravam nada.
SUITES = re.compile(r"(?:(\d+)|\b(uma|um|duas|dois|tres|quatro)\b)?\s*su[ií]tes?\b", re.I)
NUMEROS = {"um": 1, "uma": 1, "dois": 2, "duas": 2, "tres": 3, "quatro": 4}
ANDAR_TEXTO = {"terreo": 0, "baixo": 2, "medio": 5, "mediano": 5, "alto": 10, "cobertura": 99}


def suites_pedidas(f: dict) -> int:
    """O mínimo de suítes que ela pediu ("com suíte", "pelo menos 1 suíte", "2 suítes", "duas suítes"); 0 = não pediu."""
    minimo = 0
    for x in (f or {}).get("exigencias") or []:
        t = _normal(str(x))
        if re.search(r"\b(sem|nao precisa)\b.*\bsuite", t):
            continue
        for m in SUITES.finditer(t):
            n = int(m.group(1)) if m.group(1) else NUMEROS.get(m.group(2) or "", 1)
            minimo = max(minimo, n)
    return minimo


def andar_pedido(f: dict) -> tuple[int | None, int | None]:
    """A faixa de andar que ela pediu, (mínimo, máximo); (None, None) = não pediu. "andar alto" (8, -), "andar mediano ou
    alto" (4, -), "andar baixo" (-, 3), "térreo ou primeiro andar" (-, 1), "térreo" (-, 0), "até o 3º andar" (-, 3),
    "não quero térreo" (1, -). O que fala de escada ("escada se for no segundo andar") é do aceita_escada, não daqui."""
    lo = hi = None
    for x in (f or {}).get("exigencias") or []:
        t = _normal(str(x))
        if "escada" in t or not re.search(r"\bandar|\bterreo\b", t):
            continue
        if re.search(r"\b(nao|sem)\b[^,]*\bterreo\b", t):
            lo = max(lo or 0, 1)
            continue
        m = re.search(r"\bate o?\s*(\d+)", t)
        if m:
            hi = int(m.group(1))
        elif re.search(r"\bterreo\b", t):
            hi = 1 if re.search(r"\b(primeiro|1)\b", t) else 0
        elif re.search(r"\bbaixo\b", t):
            hi = 3
        elif re.search(r"\b(medio|mediano)\b", t):
            lo = 4
            if not re.search(r"\balto\b", t):
                hi = 7
        elif re.search(r"\balto\b", t):
            lo = 8
    return lo, hi


def andar_do_imovel(andar) -> int | None:
    """O andar do cadastro em número: '3', '3º', '02', 'Térreo', 'Alto', 'Andar alto', 'Médio', 'Cobertura'; None = não se sabe."""
    t = _normal(str(andar or ""))
    if not t:
        return None
    m = re.search(r"\d+", t)
    if m:
        return int(m.group(0))
    for k, v in ANDAR_TEXTO.items():
        if k in t:
            return v
    return None


TIPOS_RESIDENCIAIS = {"apartamento", "casa", "casa_condominio", "flat", "cobertura"}


def _tipo_serve(pedido: str, im: dict) -> bool | None:
    """O tipo do imóvel (o da core_imovel_busca) serve ao tipo pedido; None = não se sabe o do imóvel."""
    t = _normal(pedido).replace(" ", "_")
    ti = _normal(str(im.get("tipo") or "")).replace(" ", "_")
    if not ti:
        return None
    original = _normal(str(im.get("tipo_original") or ""))
    if t in ("", "tanto_faz"):
        return ti in TIPOS_RESIDENCIAIS
    if t == "casa":
        return ti in ("casa", "casa_condominio")
    if t == "apartamento":
        return ti in ("apartamento", "cobertura", "flat")
    if t == "comercial":
        return ti in ("sala", "loja") or (ti == "outro" and bool(re.match(r"(galp|predio)", original)))
    if t in ("galpao", "predio"):
        return ti == "outro" and original.startswith(t[:5])
    return ti == t


def serve_ao_pedido(im: dict, f: dict, desconhecido_passa: bool = False) -> str:
    """'' = o imóvel serve ao pedido; senão o motivo curto (vai ao registro dos agentes). `im`: tipo, tipo_original,
    valor_venda, valor_aluguel, quartos, suites, mobilia ('', 'semi', 'mobiliado', 'nao', 'nada'), andar, condominio,
    codigo e bairro_ok (False = fora dos bairros pedidos e dos vizinhos; None = não conferido). O que o imóvel não diz
    (quartos, suítes, andar, mobília) NÃO serve quando ela pediu, a não ser `desconhecido_passa` (o anúncio da OLX)."""
    f = f or {}

    def falta(o_que: str) -> str:
        return "" if desconhecido_passa else f"sem {o_que} no cadastro"

    fin = str(f.get("finalidade") or "")
    venda = fin.startswith("vend")
    locacao = fin.startswith("loca")
    valor = _num(im.get("valor_venda")) if venda else _num(im.get("valor_aluguel")) if locacao else \
        (_num(im.get("valor_aluguel")) or _num(im.get("valor_venda")))
    if (venda or locacao) and not valor and not (desconhecido_passa and im.get("valor_venda") is None
                                                  and im.get("valor_aluguel") is None):
        return "não é de venda" if venda else "não é de locação"
    tipo_ok = _tipo_serve(str(f.get("tipo") or ""), im)
    if tipo_ok is False:
        return f"o tipo ({im.get('tipo')}) não é o pedido ({f.get('tipo') or 'residencial'})"
    teto = _int(f.get("teto"))
    if teto and valor and valor > teto * TETO_FOLGA + 0.5:
        return f"R$ {valor} passa de +10% do teto (R$ {teto})"
    comercial = _comercial(f)
    q = _int(f.get("quartos"))
    if q and not comercial:
        minimo = q - (1 if f.get("aceita_menos_quartos") is True else 0)
        qi = _num(im.get("quartos"))
        if qi is None:
            if falta("quartos"):
                return falta("quartos")
        elif qi < minimo:
            return f"{qi} quarto(s), ela pediu {q}"
    if im.get("bairro_ok") is False:
        return f"o bairro ({im.get('bairro')}) não é o pedido nem vizinho"
    cods_rec, nomes_rec = recusados(f)
    if _num(im.get("codigo")) in cods_rec or (nomes_rec and fora_os_recusados([im], nomes_rec) == []):
        return "ela recusou esse imóvel"
    if f.get("so_condominio") and f.get("condominio") and not so_no_condominio([im], f):
        return f"ela quer só no {f['condominio']}"
    mob = str(f.get("mobilia") or "")
    if locacao and not comercial and mob in ("mobiliado", "semi", "sem"):
        mi = str(im.get("mobilia") or "")
        if mob == "sem":
            if mi == "mobiliado":
                return "mobiliado, e ela não quer mobiliado"
        elif not mi:
            if falta("a mobília"):
                return falta("a mobília")
        elif mob == "mobiliado" and mi != "mobiliado":
            return f"mobília '{mi}', ela quer mobiliado"
        elif mob == "semi" and mi not in ("semi", "mobiliado"):
            return f"mobília '{mi}', ela quer modulados e ar"
    s = suites_pedidas(f)
    if s:
        si = _num(im.get("suites"))
        if si is None:
            if falta("as suítes"):
                return falta("as suítes")
        elif si < s:
            return f"{si} suíte(s), ela pediu {s}"
    lo, hi = andar_pedido(f)
    if (lo is not None or hi is not None) and str(im.get("tipo") or "") in ("apartamento", "cobertura", "flat", ""):
        a = andar_do_imovel(im.get("andar"))
        if a is None:
            if falta("o andar"):
                return falta("o andar")
        elif (lo is not None and a < lo) or (hi is not None and a > hi):
            return f"andar {im.get('andar')}, fora da faixa que ela pediu"
    return ""


def fichas_da_regua(conn, codigos: list[int]) -> dict[int, dict]:
    """O que a régua precisa de cada imóvel: a core_imovel_busca (tipo e mobília já normalizados) e, para o que ainda não
    entrou nela (o cadastro novo, até o REFRESH), o cadastro com o tipo e a mobília lidos do jeito mais simples."""
    cods = [c for c in dict.fromkeys(_int(x) for x in codigos or []) if c]
    if not cods:
        return {}
    return {int(l["codigo"]): l for l in banco.linhas(conn, """
        SELECT i.codigo, coalesce(c.tipo, CASE
                 WHEN lower(unaccent(coalesce(i.tipo, ''))) ~ 'casa.*cond' THEN 'casa_condominio'
                 WHEN lower(unaccent(coalesce(i.tipo, ''))) ~ '^(apart|apto)' THEN 'apartamento'
                 WHEN lower(unaccent(coalesce(i.tipo, ''))) ~ '^casa' THEN 'casa'
                 WHEN lower(unaccent(coalesce(i.tipo, ''))) ~ '^cobert' THEN 'cobertura'
                 WHEN lower(unaccent(coalesce(i.tipo, ''))) ~ '^(flat|kitnet|studio)' THEN 'flat'
                 WHEN lower(unaccent(coalesce(i.tipo, ''))) ~ '^sala' THEN 'sala'
                 WHEN lower(unaccent(coalesce(i.tipo, ''))) ~ '^(loja|ponto)' THEN 'loja'
                 WHEN lower(unaccent(coalesce(i.tipo, ''))) ~ '^(terreno|lote)' THEN 'terreno'
                 WHEN coalesce(i.tipo, '') = '' THEN NULL ELSE 'outro' END) AS tipo,
               coalesce(c.tipo_original, i.tipo) AS tipo_original,
               coalesce(c.valor_venda, i.valor_venda) AS valor_venda, coalesce(c.valor_aluguel, i.valor_aluguel) AS valor_aluguel,
               coalesce(c.quartos, i.quartos) AS quartos, coalesce(c.suites, i.suites) AS suites,
               coalesce(c.mobilia, CASE
                 WHEN lower(unaccent(coalesce(i.mobilia, ''))) ~ '(semi|modulad)' THEN 'semi'
                 WHEN lower(unaccent(coalesce(i.mobilia, ''))) ~ '^mobiliad' THEN 'mobiliado'
                 WHEN lower(unaccent(coalesce(i.mobilia, ''))) ~ '(nao|sem)' THEN 'nao' ELSE '' END) AS mobilia,
               i.andar, i.bairro, coalesce(c.condominio_nome, i.condominio_nome) AS condominio
          FROM imoveis i LEFT JOIN core_imovel_busca c ON c.codigo = i.codigo
         WHERE i.codigo = ANY(%s::int[])""", (cods,))}


def bairros_que_servem(conn, f: dict, bairros: list[str]) -> dict[str, bool] | None:
    """{bairro do imóvel: está nos bairros que ela pediu (o nome do cadastro parecido, o lugar) ou num vizinho deles
    (nai_bairros_ao_redor, a mesma regra da busca)}. Sem bairro pedido (qualquer bairro, só o condomínio): None = não
    confere. O bairro que não volta no dicionário (imóvel sem bairro) não serve."""
    pedidos = [b for b in (f or {}).get("bairros") or [] if str(b).strip()]
    if not pedidos or (f or {}).get("qualquer_bairro"):
        return None
    alvo = sorted({str(b) for b in bairros if b})
    if not alvo:
        return {}
    return {l["bairro"]: bool(l["ok"]) for l in banco.linhas(conn, """
        WITH ped AS (
          SELECT DISTINCT nay_normalizar_lugar(x, true) AS n
            FROM unnest(%(p)s::text[]) b
            CROSS JOIN LATERAL unnest(coalesce(CASE WHEN nay_bairro_parecido(b) IS NOT NULL THEN ARRAY[nay_bairro_parecido(b)] END,
                                               nullif(nai_bairros_do_lugar('no ' || b), '{}'), ARRAY[b])) x
           WHERE btrim(b) <> ''),
        viz AS (SELECT DISTINCT nay_normalizar_lugar(x, true) AS n FROM unnest(nai_bairros_ao_redor(ARRAY(SELECT n FROM ped))) x)
        SELECT b AS bairro, (nay_normalizar_lugar(b, true) IN (SELECT n FROM ped)
                             OR nay_normalizar_lugar(b, true) IN (SELECT n FROM viz)) AS ok
          FROM unnest(%(a)s::text[]) b""", {"p": pedidos, "a": alvo})}


def so_o_que_serve(conn, lead: dict, f: dict, codigos: list[int], bairro_conferido: bool = False,
                   onde: str = "") -> list[int]:
    """Dos `codigos`, os que servem ao pedido `f` (serve_ao_pedido), na mesma ordem. O que não serve fica no registro dos
    agentes com o motivo. `bairro_conferido`: a busca da base (olx_cliente_buscar) já olhou o bairro, com os 2 km da borda."""
    cods = [c for c in dict.fromkeys(_int(x) for x in codigos or []) if c]
    if not cods:
        return []
    fichas = fichas_da_regua(conn, cods)
    ok = None if bairro_conferido else bairros_que_servem(conn, f, [x.get("bairro") for x in fichas.values()])
    saem = []
    for c in cods:
        im = fichas.get(c)
        if not im:
            motivo = "sem cadastro"
        else:
            motivo = serve_ao_pedido({**im, "bairro_ok": None if ok is None else ok.get(im.get("bairro"), False)}, f)
        if motivo:
            agentes.passo(lead, "regua_barrou", f"#{c}: {motivo}" + (f" ({onde})" if onde else ""))
        else:
            saem.append(c)
    return saem


def sem_os_gemeos(conn, achados: list[dict], ja: list[int]) -> list[dict]:
    """01/11 (lead 39: já tinha visitado o Piazza, 3227, e recebeu o 9089 e o 9090, o mesmo apartamento cadastrado de novo):
    tira o que tem o mesmo condomínio, os mesmos quartos e o mesmo preço de um imóvel que ela já recebeu."""
    fora = gemeos(conn, [int(a["codigo"]) for a in achados], ja)
    return [a for a in achados if int(a["codigo"]) not in fora] if fora else achados


def gemeos(conn, codigos: list[int], ja: list[int]) -> set[int]:
    """Dos `codigos`, os que repetem um de `ja` (mesmo condomínio, quartos, aluguel e venda): cadastro em dobro."""
    if not codigos or not ja:
        return set()
    return {int(r["codigo"]) for r in banco.linhas(conn, """
        SELECT a.codigo FROM imoveis a JOIN imoveis b
            ON b.codigo = ANY(%s) AND b.codigo <> a.codigo
           AND similarity(nay_chave_condominio(a.condominio_nome), nay_chave_condominio(b.condominio_nome)) >= 0.7
           AND coalesce(btrim(a.condominio_nome), '') NOT IN ('', 'Casa')
           AND a.quartos IS NOT DISTINCT FROM b.quartos
           AND coalesce(a.valor_aluguel, 0) = coalesce(b.valor_aluguel, 0) AND coalesce(a.valor_venda, 0) = coalesce(b.valor_venda, 0)
         WHERE a.codigo = ANY(%s)""", (list(ja), list(codigos)))}


def tipo_pelas_exigencias(f: dict) -> dict:
    """01/11 (lead 121: "casa ... que seja em condomínio", seis vezes): o modelo guardou o condomínio nas exigências e o tipo
    ficou "casa", e foi uma casa de rua. Casa com "condomínio" nas exigências é casa de condomínio."""
    ex = _normal(" ".join(str(x) for x in (f.get("exigencias") or [])))
    if f.get("tipo") == "casa" and re.search(r"\bcondominio\b", ex) \
            and not re.search(r"\b(sem|fora d[eo]|nao (seja )?(em )?)\s*condominio|\brua\b|via publica", ex):
        return {**f, "tipo": "casa_condominio"}
    return f


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


def _consultar(conn, f: dict, excluir: list[int], nomes_recusados: list[str], limite: int = 10) -> list[dict]:
    """Uma consulta à base (olx_cliente_buscar) com os cortes de sempre: o perto de X, os recusados pelo nome, só o
    condomínio pedido e o cadastro em dobro. 04/11: pede 10 (o máximo da função): a régua e o veto ainda cortam."""
    g = {k: v for k, v in f.items() if not k.startswith("_")}
    achados = banco.linhas(conn, "SELECT * FROM olx_cliente_buscar(%s::jsonb, %s::int[], %s)",
                           (json.dumps(g, ensure_ascii=False), excluir, limite))
    achados = so_no_condominio(fora_os_recusados(so_perto(conn, achados, g), nomes_recusados), g)
    return sem_os_gemeos(conn, achados, excluir)


def buscar_na_base(conn, lead: dict, filtros: dict) -> dict:
    """A busca da base, sem mandar nada (o _buscar_e_mandar e o agentes_erros.buscar_sem_mandar rodam a mesma):
    {f, achados, proximas, excluir, nomes_recusados, antes_do_veto, ms}.
    04/11 (Pedro: "o foco da Nay Leads é ser um bom filtro mais do que qualquer outra coisa; ela não pode errar ... nem
    mandar imóvel errado"): só o perfil que ela disse -- o afrouxar não manda mais nada sozinho --; a régua
    (so_o_que_serve) e o veto do JEV em TUDO o que sai (antes o veto pulava os "mais próximos", que iam até 5, com um
    quarto a menos, de qualquer bairro e até +20%); o mais próximo (perto: o bairro vizinho, o condomínio próximo) sai no
    máximo MAX_PROXIMOS."""
    cods_recusados, nomes_recusados = recusados(filtros)
    excluir = list(lead.get("enviados") or []) + ([lead["codigo"]] if lead.get("codigo") else []) + cods_recusados
    f = tipo_pelas_exigencias(dict(filtros))
    if not f.get("finalidade"):
        f["finalidade"] = finalidade_sem_dizer(lead, f)
    if _aceita_parceiro(conn, lead):
        f["aceita_parceiro"] = "true"           # 400: o cliente final recebe também os de parceiro
    t0 = time.monotonic()
    achados = _consultar(conn, f, excluir, nomes_recusados)
    servem = set(so_o_que_serve(conn, lead, f, [a["codigo"] for a in achados], bairro_conferido=True, onde="busca da base"))
    achados = [a for a in achados if int(a["codigo"]) in servem]
    antes = [int(a["codigo"]) for a in achados]
    if achados:
        achados = agentes.filtrar_imoveis(lead, f, achados)      # 489: o veto do JEV, agora em tudo
    exatos = [a for a in achados if not a.get("perto")][:MAX_IMOVEIS]
    perto = [a for a in achados if a.get("perto")][:max(0, min(MAX_PROXIMOS, MAX_IMOVEIS - len(exatos)))]
    return {"f": f, "achados": exatos + perto, "proximas": bool(perto) and not exatos, "excluir": excluir,
            "nomes_recusados": nomes_recusados, "antes_do_veto": antes, "ms": int((time.monotonic() - t0) * 1000)}


def vizinhos_de(conn, bairros: list[str]) -> list[str]:
    """Os bairros vizinhos dos que ela disse (nai_bairros_ao_redor: divisa ou até 3 km), o mais perto primeiro."""
    if not bairros:
        return []
    return [b for b in (banco.um(conn, "SELECT nai_bairros_ao_redor(%s::text[])", (list(bairros),)) or []) if b]


def o_que_existe_afrouxando(conn, lead: dict, b: dict) -> list[tuple[str, str]]:
    """04/11: o que a base TEM se afrouxar uma coisa (_afrouxar), para a pergunta oferecer só o que existe: até duas de
    ('quartos', '3'), ('bairro', 'Dom Pedro'), ('valor', ''). O valor só entra quando nada mais deu. Nada aqui vai a ela."""
    f, achou = b["f"], []
    for g, o_que in _afrouxar(f):
        if len(achou) >= 2 or (o_que == "valor" and achou):
            break
        if o_que == "bairro":
            viz = vizinhos_de(conn, f.get("bairros") or [])
            if not viz:
                continue
            g = {**g, "bairros": list(f.get("bairros") or []) + viz[:6]}
        try:
            cands = _consultar(conn, g, b["excluir"], b["nomes_recusados"], limite=5)
            cods = so_o_que_serve(conn, lead, g, [a["codigo"] for a in cands], bairro_conferido=True, onde=f"sondagem: {o_que}")
        except Exception:  # noqa: BLE001 -- a sondagem não derruba a resposta
            log.exception("lead %s: a sondagem do afrouxar (%s) falhou", lead.get("id"), o_que)
            continue
        if not cods:
            continue
        bons = [a for a in cands if int(a["codigo"]) in cods]
        if o_que == "quartos":
            achou.append(("quartos", str(min(_num(a.get("quartos")) or 0 for a in bons) or _int(f["quartos"]) - 1)))
        elif o_que == "bairro":
            pedidos = {_normal(str(x)) for x in f.get("bairros") or []}
            fora = [a.get("bairro") for a in bons if a.get("bairro") and _normal(a["bairro"]) not in pedidos]
            achou.append(("bairro", fora[0] if fora else ""))
        else:
            achou.append(("valor", ""))
    return achou


def _dinheiro(v) -> str:
    return f"R$ {int(v):,}".replace(",", ".")


def perfil_curto(f: dict) -> str:
    """"Em Planalto com 4 quartos", "No Vision até R$ 3.000", "Em Flores ou Parque 10" (para as frases da busca)."""
    bairros = [str(b) for b in f.get("bairros") or [] if str(b).strip()]
    lugar = (f"Em {' ou '.join(bairros[:2])}" if bairros and not f.get("so_condominio")
             else f"No {f['condominio']}" if f.get("condominio") else "")
    q = _int(f.get("quartos"))
    detalhe = (f"com {q} {'quarto' if q == 1 else 'quartos'}" if q and not _comercial(f)
               else f"até {_dinheiro(_int(f['teto']))}" if _int(f.get("teto")) else "")
    if lugar:
        return f"{lugar} {detalhe}".strip()
    return f"{detalhe[:1].upper()}{detalhe[1:]}" if detalhe else ""


def pergunta_para_afrouxar(conn, lead: dict, b: dict, ja: list[str] | None = None) -> str:
    """04/11 (Pedro: "Em Planalto com 4 quartos não tenho agora; serve com 3, ou um bairro vizinho?"): sem nada no perfil
    exato, UMA pergunta curta com o que a base tem afrouxando (o_que_existe_afrouxando). '' = nada a oferecer, ou a mesma
    pergunta já foi (pergunta de filtro sai uma vez)."""
    achou = o_que_existe_afrouxando(conn, lead, b)
    if not achou:
        return ""
    f = b["f"]
    ops = []
    for o_que, d in achou:
        if o_que == "quartos":
            ops.append(f"com {d}")
        elif o_que == "bairro":
            ops.append(f"num bairro vizinho, como {d}" if d else "num bairro vizinho")
        else:
            ops.append(f"um pouco acima de {_dinheiro(_int(f['teto']))}")
    inicio = perfil_curto(f) or "Nesse perfil"
    nao = uma_das(["não tenho agora", "não achei agora", "ainda não apareceu"], vez=_vez(inicio + str(lead.get("id"))))
    texto = f"{inicio} {nao}; serve {ops[0]}" + (f", ou {ops[1]}" if len(ops) > 1 else "") + "?"
    if any(parecida(texto, x, 0.8) for x in ja or []):
        agentes.passo(lead, "afrouxar_ja_perguntado", "a mesma pergunta para afrouxar já foi: não repete")
        return ""
    agentes.passo(lead, "afrouxar_pergunta", f"nada no perfil exato: perguntou ({', '.join(o for o, _d in achou)})")
    return texto


def sigo_procurando(lead: dict, f: dict, ja: list[str] | None = None) -> str:
    """04/11: no lugar de "Entendi, por enquanto ainda procurando opções.", uma frase que varia e diz o perfil."""
    p = perfil_curto(f)
    opcoes = ([f"{p} ainda não achei, mas sigo procurando e te aviso por aqui assim que aparecer."] if p else []) + [
        "Com esse perfil ainda não apareceu nada por aqui. Sigo procurando e te aviso assim que surgir.",
        "Ainda não apareceu nada nesse perfil; vou continuar de olho e te aviso por aqui."]
    return uma_das(opcoes, ja, vez=_vez(str(lead.get("id")) + p))


def _buscar_e_mandar(conn, lead: dict, filtros: dict, ja_avisou: bool = False) -> None:
    b = buscar_na_base(conn, lead, filtros)
    f, achados, proximas = b["f"], b["achados"], b["proximas"]
    agentes.passo(lead, "buscou_na_base", f"{len(achados)} imóvel(is)" + (" (só os mais próximos)" if proximas else "")
                  + f" · {_resumo_dos_filtros(f)}", filtros=f, achados=[int(a["codigo"]) for a in achados],
                  barrados_pelo_veto=[c for c in b["antes_do_veto"] if c not in {int(a["codigo"]) for a in achados}],
                  ms=b["ms"])
    # 03/11: o que já foi para ela nas últimas 24 h sai da lista. 04/11: se nada sobra, ela ouve isso e a pergunta para
    # afrouxar (antes calava, e quem tinha prometido as opções no turno ficava sem nada)
    repetidos = False
    if achados:
        novos_achados = [a for a in achados if not card_ja_foi(conn, lead, int(a["codigo"]))]
        if not novos_achados:
            agentes.passo(lead, "card_repetido", "tudo o que a busca achou já foi para ela nas últimas 24 h: não repete")
            repetidos = True
        achados = novos_achados
    if lead.get("etapa") in ETAPAS_DA_BUSCA:
        _marcar(conn, lead["id"], etapa="feito_busca")
    # 475 (Pedro, 22/10): a busca do cliente conta o que a nossa base deu; nada no perfil exato ativa os grupos e a OLX
    # (olx/buscas.py) e ela avisa que vai continuar verificando
    from olx import buscas
    ativou = False if repetidos else buscas.resultado_da_base(conn, lead, f, len(achados), bool(achados) and not proximas)
    buscando = ativou or banco.um(conn, "SELECT estado = 'buscando' FROM privado.busca_cliente WHERE lead = %s", (lead["id"],))
    if not achados:
        if repetidos:
            pass
        elif buscando:
            agentes.passo(lead, "nada_na_base", "a busca de fora continua (grupos, OLX, corretores)" + (" · ativou agora" if ativou else ""))
        elif abrir_busca_na_olx(conn, lead, f):
            # 416 (Pedro, 19/10): o catálogo não tem -> ordem de busca na OLX (olx/parceiro.py)
            agentes.passo(lead, "nada_na_base", "abriu a ordem de busca na OLX")
        else:
            agentes.passo(lead, "nada_na_base", "nada no perfil: o perfil foi à equipe")
            _ao_crm(f"Cliente {quem(lead)} procura {_resumo_dos_filtros(f)} e a busca não achou nada no perfil: separar "
                    "opções para ela.")
        # nunca a negativa seca: UMA pergunta para afrouxar com o que existe; sem ela, que segue procurando (se o turno
        # ainda não disse). 04/11: eram três frases fixas ("Entendi, por enquanto ainda procurando opções.", "Vou verificar
        # as opções que tenho aqui se estão disponíveis e já te retorno.", "Estou separando as opções com a nossa equipe e
        # já te retorno por aqui.")
        ja = ja_mandou(conn, lead)
        texto = pergunta_para_afrouxar(conn, lead, b, ja)
        if repetidos:
            texto = (uma_das(["As que tenho nesse perfil são essas que te mandei.", "Nesse perfil, as que tenho são essas aí de cima."],
                             ja, vez=_vez(str(lead.get("id")))) + (" " + texto[:1].upper() + texto[1:] if texto else ""))
        elif not texto and not ja_avisou:
            texto = sigo_procurando(lead, f, ja)
        if texto:
            mandar_texto(conn, lead, texto)
        if buscando:
            buscas.cliente_avisado(conn, lead, texto or "(o aviso de que continua procurando saiu na resposta do turno)")
        return
    enviados = list(lead.get("enviados") or [])
    for n, a in enumerate(achados):
        if n:
            time.sleep(DEPOIS_DAS_FOTOS_S)       # as fotos do anterior carregam antes do próximo card
        mandar_imovel(conn, lead, int(a["codigo"]))
        agentes.registrar(lead, "imoveis", "enviou", {"codigo": int(a["codigo"]), "proximas": bool(a.get("perto")),
                                                      "resumo": f"#{a['codigo']} {a.get('condominio') or a.get('bairro') or ''}"})
        enviados.append(int(a["codigo"]))
        _marcar(conn, lead["id"], enviados=enviados)
    time.sleep(DEPOIS_DAS_FOTOS_S)
    # 475: mandou só as mais próximas e a busca do perfil exato continua (grupos, OLX): o fecho diz, sem "parceiros"
    texto = fecho(lead, len(achados), proximas=proximas, lugar=perfil_curto(f), sigo=bool(proximas and buscando),
                  evitar=ja_mandou(conn, lead))
    mandar_texto(conn, lead, texto)
    if proximas and buscando:
        buscas.cliente_avisado(conn, lead, texto)
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


# 04/11 (Pedro: "ela tá falando muito robótica ... um humano normal que fala de maneira objetiva" e "é melhor não ter
# essas frases robóticas, só na nossa memória"): o fecho depois dos imóveis era "Essas são as opções que separei. Alguma te
# chamou a atenção? Posso agendar uma visita ou procurar mais opções." sempre igual; agora curto, varia, e nunca repete o
# que já foi (evitar). {voce} = "você" | "a senhora" | "o senhor".
FECHO_UM = ["O que achou dessa? Se gostar, já vejo a visita.", "Gostou dessa? Se quiser conhecer, eu marco a visita.",
            "Essa combina com o que {voce} procura? Se sim, já vejo a visita."]
FECHO_VARIOS = ["Gostou de alguma? Me diz qual que eu vejo a visita.", "Alguma chamou atenção? Se sim, já marco a visita.",
                "Dessas, alguma serve? É só me dizer qual que eu vejo a visita."]
# a oferta que chega depois, sozinha (buscas: a revisita da base, o corretor; parceiro: o cadastro, o anúncio): era
# "Boa notícia! Encontrei uma opção que combina com o que você procura:"
ABRE_UM = ["Apareceu uma opção nova com o que {voce} pediu:", "Achei mais uma no perfil que {voce} procura:",
           "Olha essa que entrou agora, bem no perfil que {voce} pediu:"]
ABRE_VARIOS = ["Apareceram {n} opções novas com o que {voce} pediu:", "Achei mais {n} no perfil que {voce} procura:"]


def _voce(lead: dict) -> str:
    return {"a senhora": "a senhora", "o senhor": "o senhor"}.get(tratamento(lead)[1], "você")


def fecho(lead: dict, quantos: int = 2, de_novo: bool = False, proximas: bool = False, lugar: str = "",
          sigo: bool = False, evitar: list[str] | None = None) -> str:
    """A mensagem depois dos imóveis (o modelo não é chamado no meio do envio). `proximas`: só os mais próximos (o perfil
    exato não tinha): diz isso numa frase, nunca a negativa seca; `sigo`: a busca do perfil exato continua. `de_novo`
    (a segunda busca) e `evitar` (o que já foi para ela): a frase não se repete."""
    v = _voce(lead)
    vez = len(lead.get("enviados") or []) + quantos + (1 if de_novo else 0)
    base = uma_das([x.format(voce=v) for x in (FECHO_UM if quantos == 1 else FECHO_VARIOS)], evitar, vez=vez)
    if not proximas:
        return base
    perto = "essa fica bem pertinho" if quantos == 1 else "essas ficam bem pertinho"
    antes = f"{lugar} mesmo não achei agora; {perto}." if lugar else f"No perfil certinho não achei agora; {perto}."
    return antes + " " + base + (" E sigo procurando no perfil certinho." if sigo else "")


def abre_oferta(lead: dict, quantos: int, evitar: list[str] | None = None) -> str:
    """A frase antes da oferta que chega sozinha (04/11: no lugar de "Boa notícia! Encontrei ...")."""
    v = _voce(lead)
    return uma_das([x.format(voce=v, n=quantos) for x in (ABRE_UM if quantos == 1 else ABRE_VARIOS)], evitar,
                   vez=len(lead.get("enviados") or []))


def e_fecho(texto: str) -> bool:
    """A mensagem é o fecho de uma busca (o de hoje, que varia, ou o de antes de 04/11, FECHO_DA_BUSCA)."""
    t = _normal(texto)
    if not t:
        return False
    if (texto or "").strip().startswith(FECHO_DA_BUSCA):
        return True
    return any(_normal(x.format(voce=v)) in t for x in FECHO_UM + FECHO_VARIOS
               for v in ("você", "a senhora", "o senhor"))


def _grupo(texto: str) -> None:
    """Só o aviso de VISITA vai ao grupo (visita.py); o resto vai às Notificações do CRM (_ao_crm, 508)."""
    try:
        if not grupo.mandar_ao_grupo(texto):
            log.warning("o aviso não chegou ao grupo")
    except Exception:  # noqa: BLE001
        log.exception("o aviso ao grupo falhou")


def nota_nay_foi(conn, lead: dict | None, texto: str) -> None:
    """A NOTINHA AMARELA "Nay foi falar com X" (Pedro, 04/11/2026: "quando a Nay manda para o lead 'vou confirmar' ou 'vou
    buscar', a gente precisa achar onde a Nay vai buscar: ficar lá um aviso tipo uma notinha amarela"). Nota interna no CRM,
    na conversa do CLIENTE (nay_aviso_equipe 'nota', 511): com quem ela foi falar por ele e o que pediu. Só a equipe vê."""
    tel = (lead or {}).get("telefone")
    if not tel or not texto:
        return
    try:
        banco.um(conn, "SELECT nay_aviso_equipe('nay-olx', 'nota', 'Nay foi falar com', %s, %s)", (texto[:1500], tel))
    except Exception:  # noqa: BLE001
        log.exception("nota 'Nay foi falar com' do lead %s", (lead or {}).get("id"))


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


# 04/11 (Pedro: "é melhor não ter essas frases robóticas, só na nossa memória, e a Nay fala de forma humanizada"): saiu
# o SEM_INFORMACAO ("Entendi, por enquanto ainda procurando opções."). Os modelos daqui mandavam respondê-lo EXATAMENTE
# quando a resposta "não trazia a informação", e 12 respostas reais foram jogadas fora assim (a fila disse "o 9127 consta
# no 4º andar" e a cliente recebeu a frase). Agora vai o que a resposta tem; sem nada, ela diz com as palavras dela.
PROMPT_CURTO = """Você é a Nay, da Imob Easy. Chegou a RESPOSTA RECEBIDA (do nosso time) a uma dúvida de um cliente. Escreva o que
vai ao cliente: NO MÁXIMO duas frases curtas (até 220 caracteres), só com o que responde à dúvida dele.
- Entregue TODA informação que a resposta traz sobre a dúvida, mesmo que seja só uma parte.
- Só se a resposta não traz informação nenhuma (não achou, não sabe, depende do proprietário): diga com as suas
  palavras, numa frase curta, que ainda está vendo isso e avisa assim que souber.
- NUNCA cite distância, nem ofereça outros imóveis, bairros ou códigos que ele não pediu, nem diga "mais fora de".
- Português do Brasil, de gente, objetiva e sem formalidade, sem emoji, sem link, sem telefone.
Devolva SÓ JSON: {"texto": "..."}"""


def resposta_curta(resposta: str, chamar=None) -> str:
    """24/10 (Pedro, a Esther recebeu um balão enorme com sugestões e uma distância errada): a resposta do revisor passa por
    aqui. Curta (até 160 caracteres) vai como está; maior, o modelo reescreve em duas frases."""
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


# 31/10 (leitura das conversas, CRM › Guia de atendimento): a resposta do Tel saía crua ao cliente. "Ela passa a
# atender", "Ah sim", "Dele que se faz análise", "Fala que a gente vai ver via WhatsApp, mas manda o WhatsApp dele" e,
# numa delas, a cláusula de honorários ("1.125 ... e 975 para o corretor"). O Tel escreve para a Nay, não para o cliente.
INTERNO = re.compile(
    r"honor[aá]rio|comiss[aã]o|corretagem|cl[aá]usula|pagar? (pra|para) (a )?gente|\d (para|pro|pra) o corretor"
    r"|^\s*(fala|diz|avisa|responde|pergunta|explica)\b|\bmanda(r)? o (whats|zap|contato|n[uú]mero|telefone)"
    r"|passa a atender|\b(ela|ele) nunca responde\b|^\s*(descartar|pular)\b", re.I)
SO_RECADO = re.compile(r"^(ok|okay|ah sim|chegou|excelente|beleza|blz|certo|show|top|valeu|obrigad[oa]|entendi|"
                       r"t[aá] bom|blz obrigado)[.!]*$", re.I)
PROMPT_DA_RESPOSTA = """Você é a Nay, da Imob Easy, no WhatsApp com um CLIENTE final (quem quer alugar ou comprar). O Tel, do
nosso time, respondeu POR DENTRO a uma dúvida dele: a RESPOSTA DO TEL foi escrita para você, não para o cliente.
Decida se ela responde à PERGUNTA DO CLIENTE e escreva o que vai a ele.
- Recado interno, instrução para você ou para a equipe, assunto de outra pessoa, ou algo que não responde à pergunta
  ("ela passa a atender", "chegou", "ah sim", "manda o WhatsApp dele", "dele que se faz análise"): {"manda": false}.
- NUNCA fale de honorários, comissão, divisão de valor, cláusula de contrato entre nós e corretor, nem de outro cliente.
- Ordem para você ("fala que a gente vai ver") vira fala sua, com as suas palavras.
- A resposta traz QUALQUER informação sobre a pergunta (ex.: "o 9127 consta no 4º andar"): entregue essa informação,
  mesmo que seja só parte do que ele perguntou. Nunca troque uma informação por "ainda estou vendo".
- Só quando a resposta não traz informação nenhuma (não achou, não sabe, depende do proprietário): diga com as suas
  palavras, numa frase curta, que ainda está vendo isso e avisa assim que souber.
- Fale como quem conversa, em primeira pessoa: sem "Sobre o #...", sem "Sobre a sua pergunta", sem "o Tel disse", sem
  "a equipe informou". O imóvel pelo nome do condomínio (ou tipo e bairro), sem o código.
- No máximo duas frases curtas (até 220 caracteres), sem emoji, sem link, sem telefone, português do Brasil de gente,
  objetiva e sem formalidade.
Devolva SÓ JSON: {"manda": true, "texto": "..."} ou {"manda": false}"""


def resposta_ao_cliente(pergunta: str, resposta: str, chamar=None, imovel: str = "") -> str | None:
    """A resposta do Tel reescrita para o cliente, ou None quando é recado interno (aí não sai nada ao cliente)."""
    r = re.sub(r"\s+", " ", str(resposta or "")).strip()
    if not r or INTERNO.search(r) or SO_RECADO.match(r):
        return None
    try:
        j = (chamar or (lambda p, u: modelo.chamar(p, u, no="olx.whatsapp")))(
            PROMPT_DA_RESPOSTA, f"PERGUNTA DO CLIENTE: {pergunta or '(não anotada)'}\n"
                                + (f"IMÓVEL: {imovel}\n" if (imovel or "").strip() else "") + f"RESPOSTA DO TEL: {r}")
        if j.get("manda") is False:
            return None
        t = re.sub(r"\s+", " ", str(j.get("texto") or "")).strip()
        if t and not INTERNO.search(t):
            return t[:240]
    except Exception:  # noqa: BLE001 -- sem o modelo: a regra de antes (curta como está, comprida em duas frases)
        log.warning("resposta ao cliente: o modelo falhou; vai a resposta curta")
    return resposta_curta(r, lambda p, u: {})


PREFIXO_DA_FILA = re.compile(r"^\s*sobre (o #\d+[^:]*|a sua pergunta)\s*:\s*", re.I)


def texto_da_resposta(p: dict, chamar=None) -> str | None:
    """A resposta do Tel como ela chega ao cliente, em primeira pessoa e sem prefixo. None = era recado interno e não vai
    ao cliente (quem chama avisa a equipe).
    04/11 (Pedro): era "Sobre o #9026 (Turim Residencial): Fica tudo, sim." -- o prefixo era robótico e, com o
    com_condominio de mandar_texto, o nome saía em dobro ("#9127 (Residencial X) (Residencial X)"). A marca de que é
    resposta da equipe ficou só por dentro: o tipo 'resposta_fila' em privado.olx_cliente_enviada (montar_turno e
    paredes.RESPOSTA_DA_EQUIPE)."""
    r = resposta_ao_cliente(p.get("pergunta") or "", p.get("resposta"), chamar, p.get("imovel") or "")
    if r is None:
        return None
    r = PREFIXO_DA_FILA.sub("", r).strip()
    return r[:1].upper() + r[1:] if r else None


def entregar_respostas(conn) -> int:
    """391: o que o Tel respondeu na fila, para quem está no WhatsApp de captação, sai por aqui (é a Nay falando)."""
    feitas = 0
    for p in banco.linhas(conn, """SELECT id, chave, codigo, imovel, pergunta, resposta FROM pergunta_fila
                                    WHERE linha = 'captacao' AND estado = 'respondida' AND entregue_em IS NULL
                                      AND entrega_erro IS NULL ORDER BY respondida_em LIMIT 5"""):
        achado = banco.linhas(conn, """SELECT id FROM privado.olx_lead_whatsapp WHERE right(telefone, 8) = right(%s, 8)
                                        ORDER BY criado_em DESC LIMIT 1""", (p["chave"],))
        if not achado:
            banco.um(conn, "UPDATE pergunta_fila SET entrega_erro = 'não é cliente da Nay do WhatsApp' WHERE id = %s",
                     (p["id"],))
            continue
        lead = _lead(conn, achado[0]["id"])
        texto = texto_da_resposta(p)
        if texto is None:      # recado do Tel para a Nay, não para o cliente: não sai; a equipe responde pelo CRM
            banco.um(conn, "UPDATE pergunta_fila SET entrega_erro = 'recado interno do Tel: não foi ao cliente' "
                           "WHERE id = %s", (p["id"],))
            _ao_crm(f"Cliente {quem(lead)} no WhatsApp Leads: a resposta do Tel não foi ao cliente porque parece recado "
                    f"interno (\"{str(p.get('resposta') or '')[:120]}\"). A pergunta era: {str(p.get('pergunta') or '')[:160]}. "
                    "Responda pelo CRM.")
            continue
        mandar_texto(conn, lead, texto, tipo="resposta_fila")      # 04/11: a marca da resposta da equipe, por dentro
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
                mandar_imovel(conn, lead, int(codigo), repetir=True)   # a equipe mandou à mão pelo CRM: vai
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
    falou de um imóvel: se quer outras parecidas.
    04/11 (Pedro: "ela tá falando muito robótica"): saiu o gerundismo "posso estar enviando outras opções semelhantes
    para o senhor?" e o "Se quiser, separo outras semelhantes ou já agendo uma visita." do fim."""
    trat, pronome = tratamento(lead)
    para = {"a senhora": "a senhora", "o senhor": "o senhor"}.get(pronome, "você")
    if lead.get("enviados"):
        t = "conseguiu ver as opções que te mandei? Se alguma agradou, já vejo a visita."
    else:
        t = f"quer que eu separe outras opções parecidas para {para}?"
    return f"{trat}, {t}" if trat else t[:1].upper() + t[1:]


FECHO_DA_BUSCA = ("Essas são as opções", "Essa é a opção", "Essas são mais opções", "Essa é mais uma opção")
# "vou separar/pegar/enviar": promessa de ENTREGA, que vale como cumprida quando card ou foto saiu depois
VOU_ENTREGAR = re.compile(r"\b(vou (separar|pegar|enviar|mandar|buscar|procurar)|lhe enviar|te envio|j[aá] envio)\b", re.I)
OFERTA = ("outras opções parecidas", "outras opções semelhantes")     # a de hoje e a de antes de 04/11
# ela prometeu um retorno (a equipe confirma, ela avisa): quem espera é ela, não o cliente
PROMESSA = re.compile(r"\b(retorno|retornar|aviso por aqui|te aviso|assim que|vou (confirmar|verificar|checar|ver com)|"
                      r"estou (verificando|confirmando|separando|aguardando|vendo)|ainda (estou )?aguardando|"
                      r"j[aá] (passei|encaminhei|pedi)|passo para a equipe|reforcei|refor[cç]ar)\b", re.I)


def que_seguimento(lead: dict, conversa: list[dict], entregou_depois: bool = False) -> str | None:
    """392b (Pedro, 16/10: "fez a mesma pergunta duas vezes ... precisa checar para ela nunca fazer isso"). O
    acompanhamento só tem dois casos, e cada um sai UMA vez:
      - depois das opções (a última mensagem dela é o fecho da busca): "conseguiu ver as opções?";
      - ela só falou de um imóvel e nunca ofereceu outras: "quer que eu separe outras opções parecidas?".
    A última mensagem dela é uma PERGUNTA ou uma PROMESSA de retorno: espera (o cliente responde, ou a equipe)."""
    nossas = [m for m in conversa if m.get("direcao") == "enviada" and (m.get("texto") or "").strip()]
    if not nossas:
        return None
    ultima = nossas[-1]["texto"].strip()
    if e_fecho(ultima):                   # 04/11: o fecho varia (fecho); o de antes também conta
        return texto_do_seguimento({**lead, "enviados": lead.get("enviados") or [0]})
    if ultima.endswith("?") or PROMESSA.search(ultima):
        return None
    if VOU_ENTREGAR.search(ultima) and not entregou_depois:
        return None                       # 394: prometeu as opções/fotos e ainda não mandou: quem espera é ela
    if lead.get("enviados") or any(o in (m.get("texto") or "") for m in nossas for o in OFERTA):
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
