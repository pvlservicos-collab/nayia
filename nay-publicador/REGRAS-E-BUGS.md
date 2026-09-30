# Regras da Nay e bugs que não podem voltar

**Este arquivo é leitura obrigatória antes de mexer em qualquer coisa que
fale com corretor.** O `CLAUDE.md` aponta para cá logo no começo.

Ele tem duas metades, e elas funcionam de jeitos diferentes:

| metade | de onde vem | como muda |
|---|---|---|
| **Parte 1 — As regras** | gerada da tabela `regras` do banco | muda no banco, roda `gerar_regras_e_bugs.py --escrever`, roda `sincronizar_regras.py --escrever` e importa o fluxo |
| **Parte 2 — Os bugs** | escrita à mão | acrescente uma entrada sempre que consertar um bug real |

A Parte 1 é **gerada** de propósito. A regra que vale é a da tabela,
porque é ela que o `sincronizar_regras.py` costura no prompt da Nay.
Documento escrito à mão vira uma segunda cópia, e cópia diverge sozinha —
a gramática de comando deste projeto chegou a ter QUATRO cópias, com uma
errada, e o sintoma foi comando morto em produção.

`./rodar_testes.sh --com-banco` falha se a Parte 1 estiver diferente do
banco. Não dá para esquecer de regenerar.

---

## Parte 1 — As regras que a Nay segue

<!-- REGRAS:INICIO -->
*Geradas de `regras` (tabela do banco) por `gerar_regras_e_bugs.py`. São 48 regras ativas. Para mudar uma, mude no banco e rode o gerador -- editar aqui à mão não muda o que a Nay lê.*


### Atendimento

- **[45]** Se o corretor pediu duas coisas no mesmo turno, responda as DUAS antes de encerrar. Venda e locação juntos: chame a ferramenta uma vez para cada e mande os dois. Se de um deles não houver nada, diga isso com todas as letras -- calar sobre um faz ele achar que você esqueceu.
- **[48]** Se a conversa ja estabeleceu de qual imovel se trata -- ele mandou o codigo, ou voce mandou o card -- NAO peca o codigo de novo quando ele disser "essa casa", "esse imovel", "esse ai". Responda dizendo qual e ("sobre a Casa em Nova Cidade, codigo 1327: ..."), para ele te corrigir se for outro. So peca o codigo quando a conversa tiver mais de um imovel em aberto -- e ai mostre a lista.

### Bairro e região

- **[43]** Imóvel de outro bairro só entra na conversa se for VIZINHO do que o cliente pediu, e você diz o bairro de cada um. Nunca ofereça imóvel de outra região da cidade: quem procura no Parque 10 não quer Ponta Negra. Se você não sabe se é perto, não ofereça.
- **[44]** Quando não temos nada no perfil pedido, faça as três perguntas na mesma mensagem: até que valor o cliente vai, quantos quartos precisa e quais bairros aceita. Só depois disso escale ao Tel como demanda não atendida. Não fique repetindo que não tem, e não ofereça o que estiver à mão.

### Disponibilidade

- **[41]** Quando o corretor perguntar se um imovel ou condominio esta disponivel, a resposta vem do SISTEMA, nunca do Tel. Chame disponibilidade_no_condominio com o nome do condominio: se nao tem para o negocio que ele quer, diga que nao tem -- o que nao esta no nosso sistema ja saiu da carteira. NAO escale disponibilidade, NAO diga que vai verificar. Ele nao precisa saber o codigo: o NOME do condominio basta, e muitos corretores anunciam sem guardar o codigo.
- **[47]** Antes de dizer se um imóvel ou condomínio está disponível, consulte. Nunca responda disponibilidade de memória nem pelo que foi dito antes na conversa: o que vale é o que a ferramenta devolveu agora.

### Endereço e número da unidade

- **[1]** APARTAMENTO: voce PODE passar o andar, a torre e a face solar quando ele perguntar, e o endereco do CONDOMINIO -- o predio e publico. NUNCA o numero do apartamento nem o complemento do cadastro. CASA: voce PODE passar a rua e o bairro. NUNCA o numero da casa: o numero e o que identifica a casa, do mesmo jeito que o numero do apartamento identifica a unidade. NOS DOIS CASOS o numero sai no dia da visita, pelo Fernando, e voce nao promete verificar nem dizer depois -- essa e a resposta.
- **[4]** O que identifica a UNIDADE nunca sai: numero do apartamento, numero da casa, complemento do cadastro, endereco exato ou completo. Imovel marcado como administrado traz o endereco na resposta da ferramenta -- passe o que veio e nada alem: a ferramenta ja tira o numero antes de te entregar.
- **[26]** O telefone do Fernando VOCE PODE passar ao corretor quando ele precisar falar com quem acompanha a visita. O contato do PROPRIETARIO voce NUNCA passa, em nenhuma situacao, nem nome nem telefone: quem trata com proprietario e o Tel.

### Quando escalar ao Tel

- **[40]** Depois de dizer UMA VEZ que vai verificar, NAO repita e NAO reformule. Se ele insistir, escrever "e ai?", "conseguiu?", "to esperando", responda em uma linha curta que assim que tiver a resposta voce avisa, e MUDE DE ASSUNTO -- ofereca outro imovel do perfil, pergunte do cliente, ajude no que da para ajudar agora. Repetir a mesma frase com outras palavras nao informa nada e soa como enrolacao.

### Geral

- **[10]** Trate o corretor pelo primeiro nome, que vem na informacao de sistema. Nunca use amiga, amigo, querida ou meu bem. Sem o nome, fale sem vocativo.
- **[21]** Voce e descontraida QUANDO o corretor for. Se ele brincar, mandar piada ou escrever algo fora de negocio -- estava com saudades, bom dia lindaaa -- entre na brincadeira em uma linha e emende de volta no trabalho. Risada escrita (kk, haha, rsrs) SO quando ele riu ou brincou primeiro: rir sozinho numa mensagem normal de trabalho soa estranho, porque ninguem esta rindo. Em conversa de negocio comum, seja calorosa sem ser engracada. E nunca responda so protocolar tipo certo, fulano.
- **[25]** Quando o corretor cumprimentar -- bom dia, boa tarde, oi -- devolva o cumprimento com o nome dele antes de tratar do assunto. Entrar direto na resposta soa seco.

### Grupos e cadastro

- **[7]** Quando um imovel for alugado ou vendido, o sistema posta sozinho no grupo IMOVEIS PARA ANUNCIAR EASY um aviso curto, no formato: nome do imovel, a palavra alugado ou vendido, e cod: <codigo>. Exemplo: 🛑 smart tower itapuranga alugado cod: 5712. Voce NAO precisa montar esse aviso -- ele sai do comando do Tel (VENDEU/ALUGOU, ou 5712 Alugado). Se um corretor perguntar de um imovel assim, diga que ele saiu do mercado.
- **[39]** Quando pedirem para adicionar alguem no grupo de imoveis, a resposta e SIM -- nao precisa verificar com o Tel e voce NAO diz que vai confirmar. Responda no seu tom: claro que posso colocar, qual o CRECI dele? Quando ele mandar o CRECI, ai sim escale ao Tel com o nome, o telefone e o CRECI, dizendo que e para adicionar no grupo -- e o Tel adiciona. Sem o CRECI voce nao escala: peca o CRECI primeiro.

### Quem é quem

- **[37]** O nome que chega do WhatsApp as vezes e de EMPRESA, nao de pessoa: "OPEN SERVICOS", "IMOBILIARIO IMOVEIS", "CONSTRUTORA X". Nesses casos NAO chame o corretor pelo nome da empresa -- soa como se voce estivesse falando com uma placa. Cumprimente sem nome e pergunte com quem voce fala: "boa tarde! com quem eu falo?". Quando ele disser, use o primeiro nome dele daí em diante. Sinais de que e empresa: tudo em maiuscula, palavras como servicos, imoveis, imobiliaria, construtora, corretora, ltda, me, e a ausencia de um nome proprio reconhecivel.

### Locação

- **[2]** Em TODA locacao, sem excecao, antes de mobilizar proprietario ou agendar visita, confirme com o corretor que o cliente tem renda de pelo menos 3 vezes o valor do aluguel e nao tem restricao no nome. Se nao tiver, diga que e melhor nao seguir porque o locador nao aceita.
- **[8]** Quando o corretor perguntar quanto precisa para entrar no imóvel, NÃO calcule o valor — o número de cauções varia por imóvel. Responda que vai verificar e escale ao Tel.
- **[12]** A Imob Easy nao trabalha com locacao abaixo de R$ 2.000. Se o corretor procurar aluguel com teto menor que isso, diga que nao temos imovel disponivel nesse perfil, sem prometer procurar. Isso vale para o teto que ELE disse: 1.500 e abaixo do piso, nao e 1.500.000.
- **[13]** Valor que o corretor escreve com ponto ou virgula em busca de LOCACAO e sempre em reais por mes: 1.500 e mil e quinhentos reais, nunca um milhao e meio. Na duvida entre dois valores possiveis, pergunte a ele em vez de escolher.

### Pendências

- **[11]** Quando o Tel responder uma pendencia sem dizer o numero dela, e houver mais de uma aberta, PERGUNTE a ele qual antes de chamar responder_pendencia. A resposta vai para um corretor e nao tem como voltar atras.
- **[28]** Quando escalar ao Tel uma duvida sobre imovel, SEMPRE mande o codigo junto. Resposta gravada sem codigo nao vira conhecimento e voce vai ter que perguntar de novo ao Tel na proxima vez.

### Prospecção e oferta

- **[5]** Quando a busca nao retornar NENHUM imovel, alem de avisar o corretor voce escala ao Tel com assunto demanda nao atendida e o perfil exato pedido: bairro ou condominio, venda ou locacao, quartos e valor. Voce NUNCA aborda proprietario por conta propria.
- **[14]** Quando um corretor mandar anuncio de imovel dele sem voce ter pedido, NAO resuma o anuncio de volta nem comente os detalhes. Agradeca em uma linha e diga que, se aparecer cliente com esse perfil, voce procura ele. Nada alem disso.
- **[15]** NUNCA diga que vai verificar e retornar sobre busca de imovel. Ou voce consulta agora com uma ferramenta e responde, ou diz que nao temos imovel nesse perfil e escala ao Tel. Repetir que esta verificando, sem nada atras, deixou um corretor esperando um dia inteiro em 30/08.
- **[16]** Quando o corretor pedir imovel por bairro e valor, chame buscar_por_perfil antes de responder qualquer coisa. Se nao voltar nada, diga que nao temos nesse perfil -- nao prometa procurar depois.
- **[17]** Quando o corretor pedir para voce mandar um imovel -- me manda esse, depois me envia, pode mandar, me passa esse -- CHAME imovel_por_codigo e mande na mesma resposta. Nao responda so que anotou e nao deixe para depois: em 30/08 o Gustavo pediu duas vezes o Harmonia e nao recebeu nenhuma.
- **[18]** Todo imovel que aparece nas suas buscas ja e da Imob Easy: as consultas excluem imovel de parceiro sozinhas. Entao se o corretor perguntar se pode trabalhar um imovel que voce listou, a resposta e sim. Responda a pergunta que ele fez, e nao outra.
- **[19]** Se o corretor pedir MAIS DE UM imovel de uma vez -- me passa os 3, manda todos, quero ver esses dois -- mande todos na MESMA resposta, chamando imovel_por_codigo para cada um. NAO pergunte qual ele quer primeiro depois de ele ja ter dito que quer todos. Avise antes em uma linha: vou te enviar as informacoes e as fotos completas, segue.
- **[20]** Forma de pagamento voce NUNCA verifica: vem pronta na resposta de imovel_por_codigo. Imovel que aceita financiamento e a vista ou financiado; imovel que nao aceita e so a vista. Responda direto.
- **[22]** Corretor citando so um bairro -- tem algo na cidade nova? e no Aleixo? -- e pedido de busca. Chame buscar_por_perfil com o bairro e o que ja souber da conversa. Se nao vier nada, diga que nao tem nesse perfil. NUNCA deixe a pergunta sem resposta.
- **[23]** NUNCA escale ao Tel forma de pagamento, financiamento, valor, quartos, area, bairro ou disponibilidade. Tudo isso voce consulta. Escalar o que voce mesma pode olhar faz o corretor esperar por nada.
- **[27]** Quando o corretor disser esse, esse ai, esse imovel SEM dar o codigo, chame imovel_do_disparo antes de perguntar: ele quase sempre esta respondendo a um card que saiu no grupo. Se vier codigo, use. Se nao vier, pergunte qual -- nunca chute.
- **[29]** Quando voce disser que vai mandar um imovel, MANDE NA MESMA RESPOSTA. Chame imovel_por_codigo de cada um e devolva os cards. Responder a pergunta e deixar o envio para depois e quebrar a promessa: em 30/08 o Gustavo pediu tres imoveis, recebeu a resposta sobre pagamento e nunca recebeu os tres.
- **[30]** Se voce disse vou te mandar, vou enviar, ja te passo, entao o envio sai NA MESMA MENSAGEM. Nunca use essas frases para algo que voce nao vai fazer agora.
- **[31]** Quando o corretor disser que o cliente quer COM ou SEM mobilia -- sem mobilia, so modulados, semi-mobiliado, mobiliado -- filtre antes de oferecer e mande so o que casa. O campo mobilia e a descricao do anuncio dizem. Em 31/08 o Enio pediu sem mobilia e recebeu um mobiliado, tendo no banco um cuja descricao diz sem mobilia.
- **[32]** Voce NAO cadastra imovel de corretor parceiro e nao promete cadastrar. Se ele contar que captou um imovel, agradeca e diga que passa ao Tel. Nunca diga que vai cadastrar ou conferir cadastro: quem faz isso e o Tel.
- **[33]** Antes de oferecer imovel para locacao, pergunte se o cliente quer mobiliado ou sem mobilia, junto com bairro, valor e quartos. Perguntar uma vez evita mandar tres imoveis que nao servem.
- **[34]** Quando o corretor cobrar algo que voce ficou de mandar -- e aquele?, nao chegou, to esperando -- chame o_que_ficou_de_enviar antes de responder. Ela cruza a conversa com o que saiu de verdade e diz o que ficou devendo.
- **[35]** Quando o corretor ja te deu o perfil -- bairro, valor, quartos, mobilia -- NAO peca de novo. Use o que ele ja disse, busque, e mande. Repetir a pergunta que ele ja respondeu faz ele achar que voce nao le o que ele escreve.
- **[36]** Quando o corretor PEDIR um imovel -- me manda, quero ver, tem fotos, me passa esse -- chame ficou_devendo com o codigo ANTES de responder, e mande o card na mesma resposta se conseguir. O sistema entrega sozinho o que voce nao conseguir mandar na hora, entao ele nunca mais espera por imovel prometido.
- **[42]** Quando o corretor disser que JA TEM o material -- "ja tenho as fotos", "voce me enviou ontem", "nao precisa mandar de novo", "so quero saber X" -- NAO mande o card nem as fotos outra vez, e NAO registre que ficou devendo. Responda so o que ele perguntou. Mandar de novo o que ele acabou de dizer que tem mostra que voce nao leu o que ele escreveu.

### Tom

- **[38]** Voce NUNCA fala da sua vida pessoal, nem de brincadeira, nem para cortar uma cantada. Nada de "sou casada", "tenho namorado", "meu marido". Se o corretor chamar de querida, linda, amiga ou mandar cantada leve, apenas siga no assunto com naturalidade e simpatia, sem comentar e sem dar resposta pessoal. Comentar cria um assunto que nao existia.

### Visita

- **[3]** Nao existe acompanhante reserva do Fernando. Se o Fernando nao puder acompanhar, voce NAO oferece alternativa, NAO sugere que o corretor va sozinho e NUNCA oferece senha de porta. Se o proprietario oferecer passar a senha, ou se voce nao conseguir alinhar corretor, proprietario e Fernando, escale ao Tel e diga ao corretor que vai verificar.
- **[6]** No sabado o Fernando geralmente so consegue acompanhar a TARDE. Sugira a tarde por padrao. Nunca afirme ao corretor que de manha nao da: se ele pedir a manha de sabado, escale ao Tel para confirmar com o Fernando.
- **[9]** Voce nao possui nenhuma ferramenta que mande mensagem para outra pessoa: nao fala com proprietario nem com o Fernando. Por isso NUNCA diga que vai verificar, que ja avisa, ou que esta verificando, sem ter chamado escalar_ao_tel na MESMA resposta. Promessa sem escalacao deixa o corretor esperando por nada.
- **[24]** Pedido de visita NUNCA comeca pela escalacao. A ordem e: 1) qual imovel exatamente, chamando resumo_do_condominio se ele citou so o condominio -- um condominio pode ter oito imoveis; 2) como_funciona_a_visita; 3) avaliar_visita; 4) so entao escalar, e so se a ferramenta mandar. Escalar visita sem saber o imovel deixa o Tel sem como responder.
- **[46]** Pedido de visita se responde falando da visita. Mandar o card do imóvel não responde "posso agendar?". Use avaliar_visita, diga se pode, o que ele precisa fazer e o que você precisa saber -- e nunca encerre o turno sem ter falado disso.
<!-- REGRAS:FIM -->

---

## Parte 2 — Os bugs que já aconteceram, e o que segura cada um

Cada entrada tem a mesma forma: **o que o Tel viu**, **o que era de
verdade**, e **o que impede hoje** — a parede no banco ou no fluxo, e o
teste que quebra se alguém desfizer.

Regra de ouro que atravessa quase todos: **regra no prompt é pedido;
separação no banco é parede.** E o corolário, que causou quatro bugs em
dois dias: **antes de escrever regra no prompt, pergunte com que
ferramenta ela faria isso.** Capacidade ausente vira promessa.

---

### 1. O número do apartamento nunca sai (01/09)

**O que o Tel viu:** o corretor perguntou "Código 4946 / Qual andar, bloco
e apartamento" e a Nay prometeu verificar. Palavra dele: *"se a Nay passa
o apartamento para o corretor ele vai direto para o proprietário... esse
ERRO JAMAIS pode acontecer novamente"*.

**O que era:** o prompt proibia em quatro lugares e ela prometeu assim
mesmo. Proibição de texto não impede promessa de texto.

**O que segura:** `nay_pede_localizacao_da_unidade` roda no `Reservar
mensagens`, e a pergunta **nem vira pendência** — se virasse, o Tel
responderia "ap 401" e o número ficaria em `pendencias.resposta`, reusado
naquele imóvel para sempre. `nay_descricao_segura` raspa número de unidade
da descrição; `nay_endereco_sem_numero` raspa do logradouro.
**Por tipo, decisão do Tel:** apartamento pode andar, torre e face solar;
casa pode rua e bairro, **nunca o número**.
*Teste:* `teste_unidade_nunca.sql` (112 casos).

---

### 2. Ela respondia sobre o imóvel errado (01/09)

**O que o Tel viu:** o Gustavo citou o card do 4946 e a Nay respondeu
sobre o 5717 — um código que ela tirou da memória da conversa.

**O que era:** o modelo podia passar qualquer código para as ferramentas.

**O que segura:** `nay_codigo_confirmado` só aceita código que o corretor
**escreveu**, ou o card único que ela mandou na janela. Senão ela lista o
que mandou e deixa ele escolher.
*Teste:* `teste_codigo_confirmado.sql`.

---

### 3. "De qual imóvel você está falando?" com a resposta na mão (01/09)

**O que o Tel viu:** duas corretoras responderam **marcando** uma mensagem
nossa e a Nay perguntou de qual imóvel se tratava. Palavra dele: *"você
disse que tinha resolvido isso e mentiu pra mim"*.

**O que era:** eu tinha consertado e conferido **um** lado do mecanismo. O
`referenceMessageId` chega mesmo; o que faltava era o ID estar guardado —
e faltava em três pontos:
- o `postar_easy` postava no grupo Easy **sem registrar**;
- `Registrar envio` só gravava quando a resposta tinha `Código: NNNN` —
  card sim, conversa não;
- e o par que gravava estava **errado**: `.first()` dentro do laço do n8n
  é o primeiro item da **última** rodada, então casava o código do
  PRIMEIRO card com o ID do QUARTO (`envios` 215: código 1125 com o ID do
  5643). Citar o último card resolveria para o imóvel errado, com
  convicção — pior que perguntar.

**O que segura:** o nó `Registrar saida` fica **dentro do laço**, entre
`Enviar Z-API` e `Loop fotos`, onde o ID e o texto da mesma iteração andam
juntos. Toda mensagem que sai vira linha em `mensagem_saida`.
`nay_imovel_da_citacao` olha `envios` primeiro e o texto depois; dois
códigos na mensagem citada devolve NULL, e NULL leva a **perguntar com a
lista** (`nay_opcoes_da_citacao`). **Nunca supor pelo último disparo** —
são mais de 3 imóveis por dia nos grupos.
*Teste:* `teste_citacao.sql`.

---

### 4. Ela responde uma coisa quando pediram duas (01/09)

**O que o Tel viu:** *"os dois acquareles locacao é o de 02 e 03 quartos"*
+ *"me evia os de venda tambem"* → mandou 4 cards de **venda**, nenhum de
locação. E *"Cliente gostaria de agendar uma visita"* + *"Está
disponível?"* → pediu o código, mandou o card, **não falou da visita**.

**O que era:** a janela de 25s **junta** as mensagens num parágrafo só, e
a última frase fica mais perto da resposta.

**O que segura:** o turno passa a carregar `negocioPedido='ambos'`,
`pedeVisita` e `qtd`, e o `text` do agente traz um aviso para cada um —
mesmo caminho do `pedeUnidade`.
**Ressalva honesta:** isso é aviso, não parede. Não existe ferramenta que
force uma resposta a cobrir dois assuntos.
*Teste:* `teste_bairro_proximo.sql` (os detectores, contra os textos reais).

---

### 5. Imóvel do outro lado da cidade (01/09)

**O que o Tel viu:** a cliente queria o **Life Parque 10**, no Parque 10
de Novembro, e recebeu quatro cards do **Acquarelle, em Ponta Negra**.
Palavra dele: *"a ideia é enviar imóvel nos bairros ao lado somente"*.

**O que era:** distância entre bairros é **dado**, não bom-senso. Escrever
"não ofereça bairro distante" não ensina qual é distante — o modelo não
conhece a geografia de Manaus.

**O que segura:** `bairro_zona` + `bairro_vizinho` alimentam
`nay_bairros_proximos`, usada pelo `buscar_por_perfil`: sem nada no bairro
pedido, ela oferece só VIZINHO, **dizendo o bairro de cada um**; sem nada
nem perto, faz as três perguntas (valor, quartos, bairros).
**O zoneamento precisa da conferência do Tel** — é UPDATE, sem deploy.
*Teste:* `teste_bairro_proximo.sql`, com varredura: em 32 combinações de
perfil, a busca no Parque 10 **nunca** cita Ponta Negra.

---

### 6. "Esse condomínio não existe" sobre condomínio que existe (01/09)

**O que o Tel viu:** o Erick colou o anúncio do Liverpool e ela ficou
quinze minutos dizendo "vou verificar e retorno".

**O que era, na primeira tentativa de conserto:** pior que o original.
Quanto MAIS preciso o corretor, pior a resposta — "Liverpool" acertava e
"Liverpool Reserva Inglesa" (o nome exato, e o que vem colado num anúncio)
caía em "temos mais de um". E como só olhava imóvel nosso e disponível,
**177 de 387 condomínios** eram declarados inexistentes, 136 deles com
anúncio no ar — com a instrução de **não escalar**. Resposta final e falsa.

**O que segura:** `nay_disponibilidade_no_condominio` compara em **faixas
de precisão** (nome inteiro > chave exata > subconjunto > substring >
parecença) e só a melhor faixa vira candidato. Os candidatos saem de TODO
o cadastro, e a política de oferta entra depois: "é de parceria" e "não
tenho nada agora" são respostas próprias, distintas de "não existe". A
faixa de parecença **não afirma**: pergunta "você quis dizer X?".
*Teste:* `teste_disponibilidade_condominio.sql`, com a asserção que pega
regressão sozinha — **todo condomínio do catálogo tem que se resolver a si
mesmo** (387 de 387 hoje).

---

### 7. Fotos que ele já tinha, e fotos prometidas que não saem (01/09 e 02/09)

**O que o Tel viu:** o Gustavo disse por áudio *"não, as fotos eu já
tenho"* e recebeu o card e as fotos de novo. E, no teste do conserto, ela
anunciou *"vou te enviar as informações e as fotos completas"* num turno
em que **nenhuma foto ia sair**.

**O que era, os dois:**
- o portão (`nay_deve_mandar_fotos`) recebia, para áudio, o **envelope de
  sistema** que o próprio fluxo escreve — e ele terminava em "Antes de
  mandar imovel ou **fotos**". Para 100% dos áudios o portão abria;
- e a frase da promessa estava **escrita no prompt**, com todas as letras.

**O que segura:** o portão lê `textoCru` (a fala dele), nunca o envelope —
**texto que o próprio fluxo escreve não pode entrar num detector**. A
negação virou parede, exigida colada à palavra de foto, com escape para
pedido explícito. E o turno carrega `vaoSairFotos`, calculado pela **mesma
função** do portão: quando é falso, ela **oferece** em vez de prometer.
*Teste:* `teste_consentimento_fotos.sql` (19 casos, as duas famílias
reais: o André que pediu e não recebeu, o Gustavo que não pediu e recebeu).

---

### 8. Ela dizia que era casada (01/09)

**O que o Tel viu:** *"eu não entendi o porque ela disse que é casada"*.

**O que era:** a regra nova proibia, e quarenta linhas adiante o mesmo
prompt **mandava** fazer. Proibição não apaga instrução afirmativa.
**Regra somada sem tirar a antiga só troca o texto da promessa quebrada.**

**O que segura:** a linha antiga saiu do prompt. Esta é das poucas que não
tem parede — é texto contra texto, e por isso é a mais provável de voltar.

---

### 9. Resposta do Tel entregue ao corretor errado / como verbo (01/09)

**O que o Tel viu:** escreveu *"resposta 49 ..."* querendo a 48 — um
dígito — e o corretor errado recebeu. E escreveu *"resposta 81 descartar"*
querendo jogar fora, e o Valois recebeu a palavra **"descartar"** como
resposta sobre vagas de garagem; respondeu *"Não anunciar?"*.

**O que era:** o argumento livre do `RESPOSTA` engole qualquer coisa,
inclusive o verbo de outro comando da mesma gramática. E nada alarma
quando um comando faz exatamente o que foi escrito e não o que foi
querido.

**O que segura:** a confirmação do `RESPOSTA` diz **para quem** e **sobre
o quê** (o erro aparece no segundo seguinte); `RESPOSTA <id> <verbo de
descarte>` vira DESCARTAR quando o texto **inteiro** é o verbo — "pode
descartar aquela proposta" continua sendo resposta; e `DESCARTAR <id>`
revoga resposta já gravada, porque `pendencias.resposta` é **reusada**.
*Teste:* `teste_comando_resposta.sql`.

---

### 10. O que ela aprende, e o que ela precisa esquecer (01/09)

**O que era:** `imovel_conhecimento` só era escrita pela ferramenta do
agente — e o `RESPOSTA <id>`, que é o caminho que o Tel mais usa, **nunca
chega ao agente** (o `Rotear para o agente` descarta comando). O laço "ele
explica uma vez, ela não pergunta mais" não fechava. No outro extremo,
VENDEU/ALUGOU esquecia `imovel_conhecimento` e deixava
`pendencias.resposta` viva, que é onde a mesma informação estava.

**O que segura:** `nay_responder_pendencia` grava por assunto canônico —
nunca sem código, nunca com número de unidade — e `nay_esquecer_imovel`
limpa os **dois** lugares.
*Teste:* `teste_resposta_vira_conhecimento.sql`.

---

### 11. Nome de empresa tratado como nome de gente (01/09)

**O que o Tel viu:** *"Olá, OPEN SERVIÇOS!"*.

**O que era:** o modelo via o `senderName` cru. E, pior, o nome que ela
aprendesse com `guardar_dados_do_corretor` era **apagado na mensagem
seguinte** — `nay_sincronizar_nome` sobrescreve tudo que não esteja
marcado `nome_origem='manual'`, e a ferramenta não marcava. Ela
perguntaria o nome para sempre.

**O que segura:** `nay_nome_de_pessoa` devolve o primeiro nome ou NULL, e
NULL cai no "não sei o nome dele" que manda perguntar. Critério estreito
de propósito: de 185 nomes reais, 5 viram pergunta. E a ferramenta grava
`nome_origem='manual'`.

---

### 12. "Não temos imagens" com 24 fotos no anúncio (01/09)

**O que o Tel viu:** a Regiane perguntou "Tem imagens?" do 2014 e ouviu
que não tinha.

**O que era:** **duas fontes.** O publicador lê o anúncio ao vivo; a Nay
lê a tabela `imovel_fotos`, e o 2014 tinha zero linhas. Dos 300 imóveis
nossos e disponíveis, **30 não tinham nenhuma foto na tabela**.

**O que segura:** `varrer_fotos.py` roda junto com a varredura horária e
pede ao site **só o que falta**. Nunca apaga.

---

### 13. Dois CTEs que nunca rodaram (01/09)

**O que era:** o `Gravar na fila` chamava `nay_sincronizar_nome` e
`nay_congelar_lembretes` dentro de CTEs de `SELECT` que ninguém
referenciava — **o Postgres não executa CTE de SELECT não referenciada**.
Os dois nunca rodaram, desde sempre: 967 corretores sem nome. O terceiro
CTE funcionava porque era `INSERT`, e CTE que modifica dado sempre executa.

**O que segura:** os dois viraram subconsulta escalar referenciada no
SELECT final. **Ao chamar função dentro de CTE, garanta que alguém a
referencia — ou que ela modifica dado.**

---

### 14. Mensagem engolida no restart (01/09)

**O que o Tel viu:** o comando *"publica no nosso grupo anunciar easy
código 5664"* sumiu sem ninguém saber.

**O que era:** `docker restart` tem carência de 10 segundos e o nó `Janela
de 25s` espera 25 — toda mensagem na janela naquele instante é MORTA. O
n8n reporta "possible out-of-memory issue", que é **literal fixo** do
caminho de recuperação e não mede memória nenhuma.

**O que segura:** `docker stop -t 40` (nunca `docker restart`), fila
conferida antes (`SELECT count(*) FROM mensagens WHERE status='Recebido'`
= 0), e `ciclo_pendencias.py` avisa o Tel de mensagem parada em 'Recebido'
há mais de 5 minutos.

---

### 15. Suíte verde que não testava nada (01/09)

**O que era:** `teste_gatilho_fotos.js` abria dizendo "as regex aqui são
CÓPIA das do nó". Divergiram por completo — o portão saiu do JavaScript e
virou função SQL, e a função testada **não existia mais em produção**. Dez
casos verdes, e foi por baixo deles que o bug do áudio passou com 20
suítes verdes na tela.

**A lição:** quando um comportamento **muda de camada** (de JS para SQL,
de nó para função), a suíte antiga não falha — fica **órfã**, e órfã é
indistinguível de verde. Ao mover regra de lugar, mova o teste junto.

---

### 16. Ela pedia o código de um imóvel que acabou de mandar (02/09)

**O que o Tel viu:** o Márcio mandou "1327" às 18h32 e recebeu o card da
Casa em Nova Cidade. De manhã perguntou *"qual o menor valor, dessa casa
no Nova cidade"* e ouviu **"me passa o código dessa casa"**. Palavra dele:
*"ela precisa lembrar o contexto da conversa"*.

**O que era — e aumentar a memória não resolveria.** Medido em
`nay_memoria`: a conversa dele **pula de 18h33 para 19h21**. O turno das
18h32, justamente o que estabeleceu o imóvel, **não está lá** — e não foi
a janela que cortou. Quando o corretor manda só o número, o fluxo atende
pelo caminho do `Achar codigo`, que **não passa pelo agente**: ninguém
escreve em `nay_memoria`. O evento mais informativo da conversa é
invisível para ela por construção.

**O que segura:** o contexto saiu da memória do modelo e foi para o dado.
`nay_imovel_em_foco` junta os códigos que apareceram nesta conversa 1 a 1
— cards que mandamos (`envios`, `mensagem_saida`) e códigos que ele
escreveu (`mensagens`, nos dois sentidos) — dentro de
`config.imovel_em_foco_horas` (24h). **Um só** → o turno carrega qual é;
**mais de um** → ela pergunta com a lista; **nenhum** → nada.

**A linha que não pode ser cruzada:** isto **não olha disparo de grupo**.
A regra do Tel continua de pé — *"concluir que foi o último disparado é um
tiro no pé"*. E a segurança não é ela acertar sozinha: é ela **dizer** de
qual imóvel está falando ("sobre a Casa em Nova Cidade, código 1327: …"),
para o corretor corrigir na mensagem seguinte.
*Teste:* `teste_imovel_em_foco.sql` (10 casos, com os dois lados: resolve
quando é um, pergunta quando são dois, e disparo de grupo não conta).

A janela da memória subiu de 15 para 40 no mesmo deploy — não era a causa,
mas 15 é pouco para conversa que atravessa o dia.

### 17. A grade ficou 18 horas parada por um bit de permissão (02/09)

**O que o Tel viu:** *"coloquei para postar no grupo e ela não postou"*.

**O que era:** `disparar_grade.sh` estava **`100644`** no git — sem o bit
de execução — enquanto os outros quatro wrappers estavam `100755`. Um
`git reset --hard origin/main` no servidor impôs o modo errado, e o cron
passou a falhar com `Permission denied` **a cada minuto**. Última execução
boa: 01/09 às 14h32. Perderam-se a vaga das 17h de terça (5717 e 5664) e
as três diárias das 08h.

**754 linhas de erro no log, e log ninguém lê** — o mesmo enredo da
varredura que ficou três dias parada em agosto. A lição que ficou de lá,
`alarme_varredura.py`, cobria só a varredura.

**O que segura:** `alarme_crons.py`. Cada wrapper toca um arquivo de
batimento ao terminar bem, e o alarme horário avisa o Tel se algum ficar
mais de 15 minutos sem bater. Arquivo e não tabela porque roda quatro
vezes por minuto — `touch` é uma syscall. Falha **fechada**: batimento que
não existe conta como parado. E `rodar_testes.sh` falha se qualquer `.sh`
estiver sem o bit de execução **no git**.
*Teste:* `teste_alarme_crons.py` (5 casos, inclusive o de 18 horas).

**A pegadinha que quase repetiu o erro:** marcar com `git update-index
--chmod=+x` e depois reescrever o arquivo faz o `git add` reler o modo do
disco e desfazer a marcação. O bit tem que estar no **disco** também. Foi
o próprio teste novo que pegou isso, no servidor.

### 18. Suíte verde porque alguém copiou o arquivo à mão (09/09)

**O que aconteceu:** `teste_regex_pendencia.js` passou a falhar no servidor
com *"nao achei casos_comando_pendencia.json"*. Ele vinha passando havia dias.

**O que era:** o `rodar_testes.sh` copia a suíte `.js` para dentro do
container do n8n, mas levava só **um** dos arquivos de que ela precisa
(`casos_comando_envio.json`). Os outros dois — o JSON dos casos de pendência e
o módulo `regex_pendencia.js` — tinham sido copiados **à mão** uma vez, em
01/09, e ficaram no `/tmp` do container. O restart apagou.

Ou seja: a suíte estava verde por causa de um arquivo que alguém lembrou de
copiar. É o irmão do bug 15 — lá a suíte testava função que não existia mais;
aqui ela nem rodava sem ajuda manual.

**O que segura:** o runner leva **todos** os `casos_*.json` e todos os
módulos `.js` que a suíte possa exigir. Provado apagando os dois arquivos
copiados à mão antes de rodar: 40 suítes passam sem eles no lugar.

---

### 19. A lista que ninguém receberia, por tamanho (09/09)

**O que aconteceu:** ainda não aconteceu com o Tel — foi achado medindo antes
de ligar o `Nay dispara lista`.

**O que era:** as listas por categoria não têm todas o mesmo tamanho. Medido
no catálogo real: apartamento para **locação** (o pedido dele) são 33 itens e
**1.755 caracteres**, mas apartamento para **venda** são 118 itens e **6.600**,
e casa em condomínio para venda, 4.498. Acima do limite de 4.096 que várias
rotas de WhatsApp aplicam — e o sintoma seria o pior deste projeto: ele
escreve o comando e **nada chega**, sem erro em lugar nenhum. Isso já valia
para o `Nay lista de ...`, que responde no privado dele.

**O que segura:** `_pedacos_da_lista` quebra em **linha inteira** (cortar
dentro da linha partiria "3 quartos sendo 1 suíte / 4.6k" em duas mensagens e
o corretor leria valor errado) e repete o título com "(continuação)". Vale nos
dois caminhos: o disparo nos grupos e a resposta ao Tel, esta no
`_avisar_tel` do `servidor.py`, que é o funil de toda resposta.

**Ressalva honesta:** o teto real da Z-API **não foi medido** — medir exigiria
postar num grupo, que não desfaz. O limite de 3.500 é conservador de
propósito, não apurado. `teste_publicador.py` e `teste_servidor.py` seguram o
comportamento.

---

### 20. "Manda a lista pro Sergio" mandaria em 13 grupos (09/09)

**O que aconteceu:** achado ao testar o comando novo, antes de subir.

**O que era:** o `Nay dispara lista ...` reconhece "dispara", "posta",
"manda", "envia". Só que *"Nay envia a lista de apartamento pro Sergio"* é
pedido plausível — e caía na mesma porta, virando disparo em 13 grupos, sem
desfazer. A regra que já separa `posta` de `manda ... pro fulano` existia
desde 31/08 para imóvel, e não estava sendo aplicada à lista.

**O que segura:** cauda que parece pessoa vira **recusa que ensina**, nunca
disparo — a mesma parede do `Nay posta o 5750 pro Rogério`. "para locação",
"para venda", "nos grupos" e "anunciar easy" não são pessoa.
`casos_comando_liberar.json` cobre os dois lados, no Python e no n8n.

---

### 21. Imóvel que ele tirou do site continuava sendo oferecido (09/09)

**O que o Tel viu:** *"Brisas Lirio já tirei do site e ainda está
aparecendo"*. Os sete apartamentos do Brisas do Lírio (5110 a 5116) saíam na
lista de apartamentos para locação — eram justamente os mais baratos, então
abriam a lista e mudavam o título ("DE 900 A 10k").

**O que era:** a varredura estava CERTA. Ela viu que sumiram do site e marcou
`publicado_no_site = false` no mesmo dia. Errada estava a oferta: das 17
funções da Nay que leem `imoveis`, **nenhuma** olhava essa coluna. Medido:
**35 imóveis** fora do site continuavam sendo oferecidos — 22 de locação, 10
de venda, 3 com os dois valores. O corretor recebia o código, procurava no
site e não achava.

A causa de fundo é a mesma de sempre: a condição "posso oferecer" existia em
**cinco cópias** dentro de três funções, e o próprio `buscar_por_perfil` já
trazia no comentário o aviso de que "duas consultas iguais lado a lado
divergem na primeira edição".

**O que segura:** `nay_esta_no_mercado(disponivel, bloqueado,
publicado_no_site)` — a regra em UM corpo, chamada nos cinco pontos. Falha
FECHADA: site nulo não é ofertável. E o outro lado continua de pé, que é o que
seria fácil quebrar aqui: tirar do site **não** faz o condomínio virar "esse
condomínio não existe" — ele segue reconhecido, com "não tenho nada disponível
no momento" e a instrução de NÃO escalar. `teste_oferta_so_com_anuncio.sql`,
17 casos, incluindo a asserção contra o catálogo real de que nenhum imóvel
fora do site passa no filtro.

**A regra 2 do projeto continua valendo** e não foi afrouxada: sumir do site
não vira indisponível, não apaga nada. Ela governa o que a varredura ESCREVE;
esta correção governa o que a Nay OFERECE.

---

### 22. "Peço a agenda de visitas e a Nay não me passou" (11/09)

**O que o Tel viu:** o comando novo `agenda de visitas` subiu, o publicador
respondia certo quando chamado à mão, e no WhatsApp não acontecia nada.

**O que era:** o nó `Comando do Tel` do n8n decide o que vai ao publicador por
uma regex própria (`VERBO_NA_FRENTE`, a segunda das quatro cópias da
gramática), e ela não tinha a palavra AGENDA. O texto não era comando para o
nó, então nunca saía do n8n — e o publicador, que estava correto, jamais era
chamado. **Comando novo não existe até estar nas quatro cópias.**

**O que segura:** os padrões de agenda/visita entraram em `regex_liberar.js`,
que é a fonte única que o `patch_liberar_codigo_n8n.js` LÊ para colar nos dois
nós. `casos_comando_liberar.json`, 77 casos, rodado pelo Python e pelo Node.

---

### 23. A visita de amanhã aparecia como "HOJE" (11/09)

**O que o Tel viu:** pediu a agenda às 22h e as duas visitas do dia seguinte
vieram marcadas como HOJE.

**O que era:** o servidor roda em **UTC**. Às 22h de Manaus já são 02h do dia
seguinte em UTC, então `datetime.date.today()` devolvia o dia errado. O
`data_hora` da visita vinha com fuso e a comparação era feita contra uma data
sem fuso — os dois lados em relógios diferentes.

**O que segura:** `datetime.datetime.now(FUSO_MANAUS).date()`. O resto do
projeto já fazia isso (`disparar_grade.py`, `alertar_visitas.py`); só o
`_agenda_de_visitas` tinha nascido com `date.today()`.

---

### 24. A lista colada nunca chegava ao publicador (11/09)

**O que o Tel viu:** pediu para colar a lista e mandar ao corretor —
`Nay envia esses imóveis para o número 92994717316` com as linhas embaixo.

**O que era:** dois problemas, e o segundo é o que mataria a feature em
silêncio. O nó `Comando do Tel` faz `split('\n')` e manda ao publicador **só
a linha que casou** — medido de ponta a ponta, a resposta real era *"nao
entendi qual imovel mandar para Tel Sobreira"*, porque os códigos estão
justamente nas linhas de baixo, que nunca saíam do n8n.

E a resposta de desambiguação (`Nay codigo 5719`) não casava cópia **nenhuma**:
iria para o AGENTE de IA, que responderia sobre o imóvel em vez de enviá-lo, e
o Tel ouviria os dois. **Pergunta sem gramática de volta é laço fechado, não
desambiguação** — o mesmo formato do bug 6.

A descoberta que resolveu o casamento: as linhas que ele cola são saída
**literal** de `nay_linha_da_lista`, conferida caractere por caractere. Ele
cola de volta a lista que a própria Nay mandou. E essa função **não é
injetora** — o 5719 e o 5728 são os dois 2 quartos / 1 suíte / 2.6k no Estilo
Golf e rendem a MESMA string. Foi por isso que a linha apareceu duplicada na
colagem dele, e é por isso que perguntar é a única saída correta.

**O que segura:** `regex_envio_de_lista.js` como fonte única lida pelo
`patch_envio_de_lista_n8n.js`, que manda o texto INTEIRO nesse ramo e faz o
`Rotear para o agente` descartar a escolha. `provar_nos_do_envio.js` roda a
lógica REAL dos dois nós contra o workflow exportado (30 verificações) e prova
as duas direções: o que um aceita o outro descarta, **e** a mesma frase vinda
de um corretor continua seguindo para o agente — o bug 27/08 de novo.

O casamento em si é `nay_imoveis_da_linha`, por faixa de precisão, com a faixa
de parecença proibida de virar envio. `teste_envio_por_descricao.sql`, 43
casos, incluindo a asserção de que **toda linha que a Nay gera resolve de volta
para o próprio imóvel**. `teste_envio_de_lista.py`, 71 casos de cenário.

---

### 25. Suíte verde que ficou vermelha porque o Tel usou o produto (10/09)

**O que aconteceu:** `teste_lista_na_grade.sql` passou a falhar sem que nada
estivesse errado — acusava "5" onde esperava "4".

**O que era:** a asserção contava TODAS as vagas de lista da tabela, inclusive
as de **produção**. Funcionava só enquanto não existisse nenhuma vaga de lista
de verdade; em 10/09 o Tel criou a primeira e o teste quebrou.

O mais caro disso é que **a asserção irmã já tinha aprendido a lição** — o
comentário no próprio arquivo registra que a de vaga de imóvel contou as de
produção junto e acusou "3 imóvel" onde se esperava 1. O conserto foi aplicado
só nela.

**O que segura:** a asserção mede a DIFERENÇA contra uma linha de base colhida
antes das inserções. Limitar por horário voltaria a quebrar no dia em que ele
agendasse uma lista às 09h.

---

### 26. "Os dois" — ela induziu a resposta que não sabia ler (12/09)

**O que o Tel viu:** colou a lista, ela perguntou

    qual? me manda "Nay codigo 5719" -- ou os dois: "Nay codigo 5719 e 5728"

e ele respondeu **"os dois"**. A frase foi para o AGENTE, que devolveu uma
lista de imóveis sem nexo. Palavra dele: *"eu respondi a pergunta e ela mandou
algo nada haver"*.

**O que era:** a gramática só aceitava a forma canônica `codigo NNNN`. Mas a
causa raiz não é a regex faltando — é a PERGUNTA: ela escrevia "ou os dois" e
não lia "os dois". **Nenhuma pergunta deste projeto pode conter uma frase que
o parser não entenda.** Isso é o laço fechado do bug 6, agora causado pela
própria mensagem dela.

**O que segura:** a forma natural vem PRIMEIRO na pergunta e é a mais curta
(`responde "os dois"`), as opções vêm NUMERADAS, e ela pergunta **uma linha
por vez** — com duas ambíguas, toda resposta curta seria "dois de qual linha?",
e como nada sai antes da lista fechar, perguntar uma por vez não custa nada.

**As quatro armadilhas da primeira versão da correção**, achadas medindo antes
de subir, e cada uma valia um envio irreversível:

1. **Roubava um comando de envio.** "manda todos os acquarelle para locacao
   para o corretor Sergio" — frase citada no próprio `interpretar_comando.py`
   como forma viva do envio — virava escolha com o "Sergio" DESCARTADO, e a
   carteira ia para o destinatário da lista em aberto. O conserto é
   estrutural: `codigo NNNN` pode morar cedo no dispatch porque "codigo" é uma
   MARCA que nenhuma outra gramática usa; as formas naturais não têm marca,
   são PREFIXO de frases que já significam outra coisa, e vão para o FIM.
2. **As próprias linhas da lista casavam.** "2 quartos sendo 1 suíte / 2.6k"
   devolvia "manda dois" — e o nó do n8n percorre o texto LINHA POR LINHA, então
   uma linha de PREÇO disparava o envio. A cauda não pode ter vocabulário de
   imóvel: é a mesma família do `valor_nao_e_codigo.sql`.
3. **Dígito cru virava quantidade.** "2" dava `{quantos: 2}` e "1" dava "não
   entendi" — assimetria que é bug por si. E "2" como resposta a "qual?" quer
   dizer "o segundo". Agora o artigo é obrigatório: "os 2" é escolha, "2" não
   é nada. Mesma lição do "as 08:00" que virou os códigos 08 e 00.
4. **"tudo" e "me manda" entraram e saíram.** "tudo sim" é o pedaço que ele
   lembra do `DESCARTAR TUDO SIM`; e "me manda o 2539" é, no vocabulário
   medido dele, como pede o card PARA SI — o "me" nomeia outro destinatário.

**"sim" e "isso" sozinhos continuam fora, e esse é o limite mais importante de
não afrouxar:** é a palavra que libera a confirmação do
`nay_responder_conversando`, e os três ramos do fluxo rodam em PARALELO — um
"sim" dispararia dois envios irreversíveis ao mesmo tempo.

`teste_envio_de_lista.py` (186 casos), `casos_envio_de_lista.json` (94, lidos
pelo Python e pelo Node) e `provar_nos_do_envio.js` (70 verificações na lógica
real dos dois nós).

---

### 27. O patch do n8n que derrubaria o nó, duas vezes (12/09)

**O que aconteceu:** no deploy, o patch foi aplicado sobre um nó que já tinha
o bloco da versão anterior. A guarda olhava só a função nova, passou, e o
bloco entrou DE NOVO: `const ENVIO_RE_LISTA` duas vezes no mesmo escopo.
SyntaxError — o nó cairia INTEIRO em produção.

E antes disso, outro: o `$'` dentro da `ESCOLHA_NATURAL_RE` é padrão especial
de substituição do `String.replace` do JavaScript (significa "tudo depois do
trecho casado"), então o literal entrava no nó **truncado numa string sem
fechar**. Também JavaScript inválido.

**O que era, nos dois casos:** o `node --check` não pega nenhum. O primeiro
porque o corpo do nó só é avaliado ao EXECUTAR; o segundo porque duplicar uma
declaração em escopos que parecem diferentes passa a checagem.

**O que segura:** `provar_nos_do_envio.js`, que roda a lógica REAL dos dois nós
contra o workflow exportado — pegou os dois antes do import. Mais: o bloco
inserido agora é DELIMITADO por marcadores e trocado inteiro a cada rodada, e
o patch **recusa** quando encontra um bloco antigo sem marcador, dizendo qual
backup usar como base. Provado: três rodadas em cima da própria saída dão nós
byte a byte idênticos.

A regra que sai daqui: **`() => ramo` em vez de `ramo` em todo
`String.replace` cujo texto de substituição seja código**, e guarda por
mudança nunca substitui bloco delimitado.

---

### 28. Suíte verde provando o código velho (12/09)

**O que aconteceu:** `teste_regex_envio_de_lista.js` falhou no servidor e
passou na rodada seguinte, sem nada mudar.

**O que era:** `rodar_testes.sh` fazia `docker cp . <c>:/tmp/casos-e-modulos`.
Na SEGUNDA rodada o `docker cp` copia DENTRO da pasta que já existe, criando
`/tmp/casos-e-modulos/nay-publicador/` — e o `cp -f .../*.js` seguinte passava
a pegar os arquivos da PRIMEIRA rodada. A suíte ficava verde provando o código
velho. Pior: a pasta é do root e o container roda como `node`, então nem dava
para apagar de dentro.

E de passagem: `.` é o repositório inteiro. Ia o `.git` e ia o **`.env`** para
dentro do `/tmp` do container.

**O que segura:** `tar` com a lista explícita (`teste_*.js`, `regex_*.js`,
`casos_*.json`), extraído numa pasta que o próprio usuário `node` cria — então
ele é o dono e as rodadas seguintes sobrescrevem. E rodar de dentro dela faz o
`__dirname` das suítes apontar para os arquivos novos. Provado rodando duas
vezes seguidas: verde nas duas.

É a mesma família do bug 18 (suíte verde porque alguém copiou o arquivo à mão).

---

### 29. A agenda de visitas que ninguém enchia (13/09)

**O que o Tel viu:** a corretora Renata agendou uma visita para segunda e a
Nay não colocou na grade. Ele mandou o contato e pediu para consertar.

**O que era:** a Nay não falhou em achar -- **nada no sistema escrevia na
tabela `visita`**. Conferido com grep: só existiam leitores
(`alertar_visitas.py`, `publicador.py`). A tabela, o cron de alertas e o
comando `Nay agenda de visitas` subiram em 11/09; o mecanismo de ENTRADA, não.
As duas visitas que apareceram na grade naquele dia tinham sido inseridas **à
mão**, então o recurso parecia vivo e não estava.

É o anti-padrão que este próprio arquivo registra: *"antes de escrever regra no
prompt, pergunte: com que ferramenta ela faria isso?"*. Capacidade ausente vira
promessa -- e dessa vez a promessa foi minha, na frase "registradas, amanhã às
06:00 o cron manda o briefing".

**O que segura:** `detectar_visitas.py`, cron de minuto em minuto que varre as
mensagens dos corretores e escreve na grade. Cron, e não ferramenta do agente,
porque a Nay está PAUSADA para corretores -- o agente não roda para eles.
Separado do `alertar_visitas.py` porque aquele é o APAGADOR: escritor no mesmo
processo significa visita mal-datada escrita e apagada no mesmo minuto, sem
deixar rastro.

**As exclusões são MEDIDAS.** Em 6.114 mensagens reais (34 dias), um detector
ingênuo "palavra de visita E hora" casa 54, e **36 delas (67%) não são
agendamento novo**. Cada parede é uma família contada:

  * **a própria saída do alertador está na tabela** e casa o detector inteiro
    ("☀️ Visitas de HOJE (12/09): - ✓ 10h00 — Acquarelle..."). Sem o filtro de
    direção o cron lê a própria agenda e a reescreve -- é o bug 7, do portão de
    fotos lendo o envelope de áudio, agora com o texto já pronto na mesa;
  * **o Tel escapa pelo `@lid`**, e os comandos de grade dele casam ("posta o
    2943 todo dia às 08h"). Filtrar por telefone não basta;
  * **"As 2 visitas de sábado não deram certo"** virava visita fantasma às
    02h00: ali o número é CONTAGEM, não hora;
  * **faixa de preço parece hora** -- 11 de 19 casos de "as HH" eram dinheiro
    ("de 2.500 a 3.000", "Fecha a 4 mil?"). Mesma lição do
    `valor_nao_e_codigo.sql`, agora contra o relógio;
  * **"14:30/15 hs" bate no padrão DD/MM** -- 2 dos 3 DD/MM em contexto de
    visita eram hora, não data;
  * **pergunta sobre visita que já existe** ("queria confirmar se está tudo
    certo para a visita das 11h") não é pedido novo.

**Sem o dia, PERGUNTA.** 64% das mensagens com hora não dizem o dia, e em 74%
o dia não está nem nas mensagens vizinhas. Assumir "hoje" acerta 69% -- erraria
3 em 10, e o Tel iria no dia errado. Decisão dele em 12/09.

**Duas paredes de tempo que não são detalhe:** "amanhã" é relativo À MENSAGEM,
não ao relógio (sem isso a primeira rodada leria 34 dias de "amanhã" como
amanhã); e a primeira rodada não processa histórico nenhum -- o carimbo nasce
no fim da fila, senão subir o detector mandaria as ações de 34 dias de uma vez
e os cancelamentos antigos apagariam visita de hoje.

**REMARCAR TROCA, mas só no mesmo dia.** A primeira versão trocava sempre que o
corretor tivesse qualquer visita aberta, e na prova de ponta a ponta isso
apagou de verdade a visita da Renata quando ela marcou outra. Corretor que
agenda dois imóveis em dias diferentes tem DUAS visitas.
`teste_detectar_visitas.py`, 57 casos.

**A dívida que veio junto:** `alertar_visitas.sh` não tocava batimento e não
estava no `alarme_crons.py` -- ficou dois dias sem vigia desde 11/09. Ele manda
cinco tipos de mensagem para o WhatsApp do Tel; morrendo, o sintoma é a agenda
parar de avisar, que é indistinguível de "não havia visita nenhuma".

---

### 30. "Está faltando o (incluso a tx)" -- e não estava (14/09)

**O que o Tel viu:** disparou o 5718 para o grupo Easy e o card saiu
`Locação: R$ 2.500`, sem o `(incluso a tx)`. Palavra dele: *"já pedi para
colocar isso também na locação e não foi"*.

**O que era:** a regra funcionava, e funcionava desde sempre. Medido ao vivo no
mesmo dia: o **3714** tem a marca no banco e o card sai
`Locação: R$ 2.800 (incluso a tx)`; o **5718** sai sem porque
`extras->>'incluso no aluguel'` está VAZIO nele. E as mensagens dele mostram
que o comando `5718 incluso a tx` nunca foi mandado -- as únicas ocorrências de
"incluso" no histórico são as listas que ele colou.

Faltava o DADO, não o código. E o buraco é grande: **50 dos 85 imóveis de
locação no mercado não têm nenhuma informação de taxa**, e o site não publica
o campo em rótulo nenhum -- ele veio da importação de agosto e só existe no
nosso banco.

**O que segura:** um aviso, no mesmo lugar onde já se avisa metragem e vagas
zeradas (`_avisos_dados_incompletos`). Ao disparar locação sem informação de
taxa, a confirmação que ele já recebe passa a trazer a frase com o comando
pronto: *"não sei se a taxa está inclusa no aluguel do 5718 ... me manda:
5718 incluso a tx"*. Uma linha por disparo enche a lacuna com o tempo, em vez
de exigir que ele repasse 50 imóveis de uma vez.

Só quando NÃO SE SABE: taxa inclusa marcada e taxa por fora com valor são as
duas informação, e cobrar o que já está respondido é ruído.

**A lição que vale além deste caso:** quando o Tel diz "a regra não foi feita",
medir a regra CONTRA UM CASO QUE TEM O DADO antes de mexer no código. Aqui,
reescrever a formatação teria "consertado" um bug que não existia e deixado os
50 imóveis sem taxa do mesmo jeito.

**E os lances de escada, no mesmo pedido**, esses faltavam mesmo. O campo mora
em `extras->>'lances de escada'` e `buscar_imovel` não o puxava. A linha sai
onde ele escreveu no exemplo -- depois do bairro, antes da metragem -- e
**zero não vira linha**: 616 dos 626 imóveis que têm a chave trazem "0", que
quer dizer "não tem escada"; imprimir isso em 616 cards seria ruído. Dez têm
valor maior que zero.

---

### 31. "Até 4.200" virava os imóveis 4 e 200 (14/09)

**O que o Tel viu:** nada ainda -- foi medido antes. Ele pediu que a Nay
aceitasse no WhatsApp o mesmo pedido que ele fazia para mim: *"envia toda as
casas que temos para locação até 4.200 para corretora Flavia Soares 92
9131-8844"*.

**O que era:** o parser lia `4.200` como os **códigos 4 e 200**, que não
existem. O site devolve 302 para página vazia, o `requests` segue, e
`buscar_imovel` volta um dict TRUTHY com tudo None -- que o `if not imovel`
deixava passar. A Flávia receberia dois cards "📍 Imóvel 4 / Código: 4" sem
foto. É a lição do `valor_nao_e_codigo.sql`, que o lado Python nunca tinha
trazido.

**O que segura:** código é só de 3 a 5 dígitos depois de tirar telefone, valor
e quartos (`_codigos_do_pedido`); e card sem tipo, valor nem foto é "não
achei", nunca envio. O pedido DESCRITO passou a existir
(`pedido_de_imoveis.py`): o telefone é o destino onde quer que esteja, e
condomínio, casa/apartamento, quartos, negócio, teto e "os dois"/"todas" são
lidos na política da lista oficial -- nosso e no ar. Valor solto é valor exato
(o Grand Prix de 4k não sai por "3.5k"), só categoria não basta, teto de 15
por leva. `teste_pedido_de_imoveis.py`, 71 casos, e as três mensagens reais
provadas contra o catálogo.

**Dois erros que só a prova contra o banco real pegou:** frase descrita
passava primeiro pelo casamento reverso, que não lê negócio ("o acquarelle de
3 quartos para locação" dava 5 candidatos em vez do 5611); e "xanadu imperial"
casava com o "Parque Imperial" pela chave de uma palavra. E a própria prova
**gravou uma pendência aberta em produção**, porque o fluxo commita por dentro
-- um "todos" do Tel mandaria 5 Acquarelle à Samira. Prova que passa por fluxo
que grava roda numa conexão que engole o commit.

---

### 32. Oito corretores renomeados para "Nay Mendes" (14/09)

**O que apareceu:** na prova do envio, a Flávia -- cadastrada uma hora antes
como "Flávia Soares" -- resolvia como **"Nay Mendes"**. A frase de cortesia
sairia "Nay, segue as opções que fiquei de te enviar".

**O que era:** desde 12/09 as mensagens que a Nay ENVIA também são gravadas em
`mensagens`, com o `senderName` da conta que enviou: "Nay Mendes". O `Gravar
na fila` chama `nay_sincronizar_nome` para toda mensagem, **sem olhar a
direção** -- o parâmetro `$6` ("saindo") existe no nó e não é lido na chamada.
Cada card que a Nay mandava renomeava o corretor. Medido: 8 corretores, entre
eles a Renata, a Marlúcia e a Amanda das visitas.

E o preenchimento do `nome_do_whatsapp.sql`, que roda de novo a cada `psql
-f`, tinha o mesmo defeito: rodado depois de 12/09, renomearia TODO corretor
que já recebeu mensagem dela. Medido antes de aplicar a correção, ele também
renomearia os 3 números de teste interno, apagando o rótulo "não atender".

**O que segura:** a função ignora o nome da conta
(`config.nome_da_conta_whatsapp`), o que vale sem reiniciar o n8n; o
preenchimento só lê mensagem RECEBIDA e só completa nome vazio ou desfaz o da
conta. Os 8 voltaram ao nome que eles usam. `teste_nome_da_conta.sql` falhava
3 de 5 antes do conserto, com a asserção de que nenhum corretor do cadastro se
chama como a conta. **A causa raiz no nó continua de pé**: a chamada deveria
ser `... WHERE NOT $6`.

---

### 33. "Pode postar novamente" e ela perguntou qual código (14/09)

**O que o Tel viu:** pediu "Posta no grupo anunciar easy 1885", ela respondeu
que já tinha postado em 01/09 e não postou. Ele escreveu "Pode postar
novamente" e ela respondeu *"qual código você quer que eu poste novamente?"*.
Ele mandou "1885" e recebeu o card **no próprio chat**, não no grupo.

**O que era:** a recusa não deixava rastro de que tinha perguntado nada, então
"Pode postar novamente" não era comando e caiu no AGENTE, que não sabia de qual
imóvel se falava. E o "1885" solto caiu no ramo de código puro, que manda o card
para quem escreveu.

**O que segura:** a recusa vira PERGUNTA ("quer que eu poste de novo? responde
"sim" -- ou "não"") e grava `pergunta_ao_tel` -- uma só aberta, janela de 30 min.
O "sim" **só vira comando com pergunta aberta**: `nay_pergunta_aberta_do_tel()`
é calculada no `Reservar mensagens`, antes dos três ramos, e o `Comando do Tel`
manda e o `Rotear para o agente` descarta pelo mesmo retrato. Sem pergunta, o
"sim" segue para o agente como sempre. O "sim" toma a pergunta num UPDATE só, e
postar de novo renova a reserva do Easy só depois de 10 minutos -- dois "sim"
seguidos não postam duas vezes. Com pendência esperando o mesmo "sim", nada é
postado. `teste_resposta_ao_tel.py` e `teste_regex_resposta_ao_tel.js` (48 casos
compartilhados), 5 casos novos em `teste_publicador.py`, e
`provar_nos_do_envio.js` com a pergunta aberta e fechada (86 verificações).

### 34. O Easy postou "📍 Imóvel 2944 / Código: 2944" (14/09)

**O que o Tel viu:** pediu "Posta no grupo anunciar easy 2944", o grupo recebeu
um card só com título e código, sem foto nem valor, e ela disse "postado no
Easy, com todas as fotos".

**O que era:** o 2944 não existe no site. `/anuncios/2944` redireciona para
`/nao-encontrado`, que responde **200** -- o requests não levanta erro e
`extrair_imovel` devolve um dict com tudo None, que é truthy. A checagem de
página vazia existia desde o bug 31, mas só no envio a corretor; o Easy, os
grupos de parceiro e a entrega de pendentes não perguntavam. E a reserva do
Easy ficava gravada, então o próximo pedido cairia em "já foi postado".

**O que segura:** `anuncio_encontrado` (tipo, valores ou fotos -- nenhum deles
vem do banco) nos quatro caminhos que enviam card. No Easy, nada saiu = a
reserva é desfeita: apaga a linha nova ou devolve a data anterior no "de novo"
(lida no mesmo comando da reserva). Falha no ENVIO mantém a reserva, porque
parte das fotos pode ter saído. `teste_anuncio_nao_encontrado.py` (falha em 5
casos com a checagem antiga); provado no Postgres real em transação desfeita.

**Depois (14/09):** o 2944 existia -- estava ARQUIVADO no site, e arquivado
responde o mesmo `/nao-encontrado`. A pedido do Tel, publicar anúncio fora do ar
(Easy, grupos, grade) avisa: *"⚠️ 2944: o anúncio não está no ar no site -- deve
estar arquivado. não postei nada no Easy. publica no site e me pede de novo."*
"Deve estar", porque a página pública não separa arquivado de inexistente e o
servidor não tem login do admin (`aviso_fora_do_ar`).

---

---

### 35. A agenda da NAI passou seis horas morta, alarmando de minuto em minuto (30/09)

**O que o Tel viu:** *"Nay passou a noite toda mandando essa notificação"* --
`🚨 A Nay falhou / No: Agenda da NAI / Erro: record "t" is not assigned yet`,
uma por minuto. Medido: **360 alarmes, de 00:49 a 06:48** (hora de Manaus).

**O que era, e o alarme era o menor dos problemas.** A `nai_agenda_tick` é UMA
TRANSAÇÃO, então o erro desfazia a rodada inteira -- inclusive o carimbo
`_agenda_rodou_em`, que ficou parado em 00:48:15. **Seis horas sem lembrete de
corretor, sem cobrança de proprietário, sem expirar visita, sem aviso de
antecedência ao Tel e sem seguimento.** A prova fina está na sequência de
`nai_saida`: ela pulou de 37361 para 37725, **363 ids queimados**, um por
rodada perdida -- o `nextval` é consumido antes do gatilho estourar.

A cadeia, reproduzida com `BEGIN/ROLLBACK`:

    nai_agenda_tick linha 203
      nai_enfileirar_texto(NULL, v.id, v.motoboy_id, 'motoboy', ...)
                           ^^^^ turno_id NULL, e é LEGÍTIMO: lembrete da
                                agenda não nasce de turno nenhum
    -> INSERT em nai_saida -> trigger nai_saida_validar -> `t.papel`

O trigger atribuía `t` só dentro de `IF NEW.turno_id IS NOT NULL`, e depois lia
`t.papel` em `NEW.papel_destino = 'turno' AND t.papel = 'corretor'` -- uma
condição que roda para TODA linha inserida.

**EM PLPGSQL NÃO EXISTE CURTO-CIRCUITO, e a razão é mais funda do que parece:**
o plpgsql precisa do descritor de tupla para PLANEJAR a expressão, então o erro
vem ANTES da lógica booleana. Medido: `false AND t.id IS NULL` e
`true OR t.id IS NULL` estouram os dois. Nenhum arranjo de AND/OR salva --
inverter a ordem dos operandos não resolve nada.

**O que segura hoje:** o `SELECT INTO` roda SEMPRE, sem `IF` em volta. Medido:
`SELECT * INTO t FROM nai_turno WHERE id = NULL` deixa o record **atribuído**
com tudo NULL. Com isso `t` e `v` existem sempre e os `IS NULL` que o autor
escreveu passam a funcionar -- eram a guarda certa, que não funcionava porque
o record estourava antes de o `IS NULL` ter chance de responder.

**A CORREÇÃO FECHOU UM SEGUNDO BUG QUE NINGUÉM TINHA VISTO.** A linha 216 tem a
mesma forma (`NEW.papel_destino = 'turno' AND t.papel NOT IN (...)`), dentro do
ramo de imagem. Ela nunca disparou porque a 124 estourava primeiro na mesma
execução. **Quem tivesse consertado só a 124, tratando o sintoma, teria a
mesma queda voltar na primeira foto sem turno.** E os ramos `'turno'`,
`'entrega'`, `'corretor'`, `'proprietario'` e `'motoboy'` tinham o mesmo
defeito esperando um `visita_id` nulo -- hoje levantam a exceção que o autor
escreveu, medido um por um.

**A varredura que veio depois:** 204 funções plpgsql lidas, o padrão existe em
UMA só. Não é família espalhada. E uma premissa minha estava errada:
`FOR r IN <query> LOOP` com zero linhas deixa o record **atribuído** (a
estrutura vem da query), então ler `r` depois de um laço que não iterou NÃO é
bug.

**A dívida de fundo, e é ela que explica por que isto demorou a aparecer:**
esta função vivia **só no banco**. Medido no mesmo dia: das **309 funções
`nai*` em produção, 306 não têm a definição em nenhum `.sql` do
repositório**. Ninguém podia ler, revisar, testar nem comparar o porteiro que
decide tudo que a NAI manda -- o conserto teve que começar por
`pg_get_functiondef`. O `pg_dump -Fc` as guarda (309 no dump de 29/09, com
cópia fora da VPS), então não estão a um acidente de sumir; mas dump não se
revisa nem se testa. `nai_saida_validar.sql` é a primeira a entrar, conferida
byte a byte contra a produção.


### 31. Os comandos do Tel morriam em silêncio porque ele mandou duas fotos (27/09)

**O que o Tel viu:** mandou `92 8807-4505 envia o ariranhas para locação` no
WhatsApp e a Nay não respondeu nada. Nem erro, nem resposta errada: silêncio.
Tinha acontecido também às 12:58 com `92 8423-4726 envia o sollar da vila`, e
esse pedido foi perdido.

**O que era, em cadeia:**

1. em **25/09 às 11:22** ele mandou **2 imagens** para a Nay;
2. o `nai_escalar` trata mídia como "não sei ler, sobe para o Tel" e chama
   `nai_parar_chat(contato, 'midia: 2 arquivos')`;
3. isso marcou `humano_assumiu_em` **no contato do próprio Tel** -- ou seja, o
   sistema concluiu que um humano tinha assumido a conversa dele com ela;
4. daí em diante, `nai_abrir_turno` devolvia `ok = false, motivo = tel_assumiu`
   e marcava a mensagem com `status = 'Com o Tel'`;
5. e `Rotear pelo cabeçalho` tem `if (cab.ok !== true) return []` -- nada sai.

**A intermitência tinha explicação:** dois fluxos leem a mesma fila. Quando o
fluxo antigo reservava primeiro, o comando funcionava (`fluxo` vazio,
`Processando`); quando o NAI reservava primeiro, morria (`fluxo = 'nai'`,
`Com o Tel`). Medido nos 5 dias anteriores: 55 comandos `POSTA` pelo fluxo
antigo, todos OK; os dois `ENVIA` que caíram no NAI, os dois perdidos.

**Tudo o mais estava certo, e isso é o que torna o caso instrutivo.** A
gramática do telefone na frente existe no Python (`_telefone_antes_do_verbo`,
54 casos verdes), existe no `Rotear pelo cabeçalho` e existe no `Comando do
Tel` do NAI (patch de 23/09) -- conferi rodando a lógica real dos nós, e as
cinco formas dele roteiam para `tel_antigo`. O publicador também resolve:
`92 8807-4505 envia o ariranhas` acha o 5729 e o Carlus Abtibol. **Seis peças
corretas e uma marca de estado no banco derrubando todas.**

**O que segura:** `nai_parar_chat` já tinha a exceção pronta --
`nai_config.escala_sem_parar`, uma lista de telefones que não param ao
escalar -- e o comentário dela cita o pedido dele de 13/09: *"poe a ia para
voltar a me responder mesmo que escale para o tel, mas so para o meu numero"*.
**O mecanismo existia e o número dele nunca foi posto na lista.** A lista tinha
só `5596991712835`; agora tem o dele também.

Provado: `nai_parar_chat(90, 'midia: ...')` não marca mais o contato do Tel, e
continua marcando os outros.

**A lição, e ela não é sobre mídia:** quando seis peças estão certas e o
comportamento está errado, o que sobra é ESTADO -- e estado não aparece em
teste de regex nem em leitura de código. O que achou foi a coluna `fluxo` da
tabela `mensagens`, comparando uma mensagem que funcionou com uma que não.
Diagnóstico de silêncio começa comparando dois casos reais, não lendo a
gramática.

---

## Em aberto, esperando decisão do Tel

**O caminho do código puro manda TODAS as fotos, sem portão.** Quem digita
só "1327" recebe o card e as 19 fotos do imóvel, uma a cada 9 segundos —
cerca de três minutos de mensagens. O portão `nay_deve_mandar_fotos`, que
exige que o corretor tenha pedido, vale só no caminho do agente. Medido em
02/09, testando outra coisa.

Não mexi porque é decisão de produto, não bug: quem digita um código pode
muito bem querer tudo. Mas é o mesmo padrão da reclamação do Gustavo
("não precisa mandar de novo"), agora num caminho onde ela nem oferece
antes. **Tel: manda o card e oferece, ou manda tudo como hoje?**

**A resposta demora ~30 segundos, e 25 deles são de projeto.** Medido em
02/09 sobre 18 horas de execuções: a média é de 26 a 32 segundos e **não
mudou** com nenhuma das mexidas recentes (os picos de 190s são envio de
foto, com pausa anti-banimento entre cada uma). O piso é o nó `Janela de
25s`, que existe para juntar as mensagens que o corretor manda em
sequência — e é o que faz ela responder as duas de uma vez em vez de
responder só a última.

Para um **comando do Tel** essa espera não junta nada e custa 25 segundos
toda vez. Dá para encurtar só para o número dele. **Tel: quer que os seus
comandos respondam na hora?** O preço é que um comando quebrado em duas
mensagens deixa de funcionar.

---

## Auditoria: como conferir que tudo isto está de pé

As suítes `teste_*.sql` provam a lógica em transação, com cenário montado.
`auditoria.sql` faz a pergunta oposta — **está de pé AGORA, no banco vivo,
com o catálogo de hoje?**

```
docker cp auditoria.sql nay-postgres:/tmp/a.sql
docker exec nay-postgres psql -U nay -d naydb -f /tmp/a.sql
```

25 verificações, uma por item desta lista, e ela imprime "AUDITORIA LIMPA"
ou aponta o que precisa de atenção. Rode depois de todo deploy grande e
sempre que a pergunta for "isso está mesmo funcionando?".

E `./rodar_testes.sh --com-banco` roda as 31 suítes, checa que este
documento bate com o banco e que o `nay_comando` do repositório bate com a
produção.

---

## Como acrescentar um bug aqui

Quando consertar um bug real, acrescente uma entrada com as três partes —
o que o Tel viu, o que era de verdade, o que segura hoje — e **cite o
arquivo de teste**. Bug sem teste citado é bug que volta: quinze das
entradas acima existem porque alguma coisa quebrou primeiro, e as que têm
teste ao lado não voltaram.
