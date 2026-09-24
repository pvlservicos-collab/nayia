# A Nay — como funciona hoje

> **Para quem avalia:** este documento descreve um sistema em produção, atendendo
> corretores de imóveis reais por WhatsApp em Manaus. Leia e critique sem
> cerimônia: onde a arquitetura está frágil, onde uma regra pode falhar sem que
> ninguém perceba, o que você faria diferente. As perguntas que mais interessam
> estão no fim, em **O que eu quero que você avalie**. Os números são reais,
> medidos em 24/09/2026.

---

## 1. O que é

A Nay é uma atendente automática de WhatsApp de uma imobiliária de Manaus
(Imob Easy). Ela fala com **corretores parceiros** — não com o comprador final
— e faz três coisas:

1. **responde sobre imóveis do catálogo**: manda o card, as fotos, o valor, a
   disponibilidade, procura por perfil (bairro, faixa de preço, quartos,
   mobília), agenda visita;
2. **recebe imóvel que o corretor oferece**: colhe os dados e as fotos e
   cadastra;
3. **escala para o dono da imobiliária** (chamado "o Tel" no código) o que ela
   não sabe.

Para quem fala com ela, é uma pessoa só. Por dentro são duas IAs e uma terceira
que decide qual delas responde.

**Números de hoje:**

| | |
|---|---|
| Imóveis no catálogo | 1.255 |
| Que ela pode oferecer | 259 (37 de locação, 219 de venda) |
| De parceiro (nunca saem por ela) | 908 |
| Corretores cadastrados | 1.493 |
| Turnos de conversa processados | 1.880 |
| Funções de negócio no banco | 305 |
| Migrações aplicadas | 117 |

---

## 2. A arquitetura, do WhatsApp até a resposta

```
WhatsApp (Z-API)
   │
   ▼
[webhook n8n]  ── grava a mensagem ──► tabela `mensagens`
   │
   ├─► ramo do áudio:  baixa → transcreve (gpt-4o-transcribe + vocabulário nosso)
   ├─► ramo da imagem: baixa → descreve (gpt-4o-mini, arquivo em base64)
   │
   ▼
[espera 60s]  junta tudo que a pessoa digitou no intervalo
   │
   ▼
[abrir turno]  ← FILTRO DE PALAVRAS: "bom pedro"→Dom Pedro, "aquarelli"→Acquarelle
   │
   ▼
[A PORTA]  nai_deve_atender — ela atende esta pessoa, nesta mensagem?
   │
   ▼
[A MENTE]  modelo lê o bloco inteiro e escolhe quem responde
   │         ↓ e o banco CONFERE a escolha (redundância)
   ├──────────────────────────┐
   ▼                          ▼
[NAY IMÓVEIS]            [NAY SECRETÁRIA]
 modelo + 13 ferramentas  modelo + 4 ferramentas
   │                          │
   └──────────┬───────────────┘
              ▼
       [O CONFERIDOR]  a resposta obedece o formato e as regras?
              ▼
       [CAIXA DE SAÍDA]  nai_saida — card, fotos, fechamento, com hora marcada
              ▼
       [O PORTÃO]  parceria, pausa, "o Tel assumiu", espelho de treino
              ▼
          WhatsApp
```

**Tecnologia:** PostgreSQL (toda a regra de negócio em PL/pgSQL), n8n (o fluxo,
86 nós), OpenAI (conversa, transcrição, leitura de imagem), Z-API (WhatsApp),
Flask + páginas estáticas (o painel administrativo).

**A decisão de projeto mais importante:** *a regra mora no banco, não no
prompt.* O prompt diz como falar; o banco decide o que pode sair. A razão é
empírica — toda vez que uma regra ficou só no prompt, o modelo a ignorou em
produção mais cedo ou mais tarde.

---

## 3. As camadas, uma a uma

### 3.1 A porta — quem ela atende

Regra do dono: ela atende **corretores** (os dos grupos e os que têm "Xx" no
nome da agenda). Quem já conversava com ele antes do religamento continua com
ele, **exceto se pedir imóvel claramente**.

"Pedir imóvel claramente" inclui: escrever um código nosso, colar um card,
citar um condomínio pelo nome, pedir foto de um código, mandar um link de
produto do catálogo do WhatsApp, ou fazer um pedido de perfil.

> **Nota de cicatriz:** a regra do nome tinha um "desde que NÃO tenha código"
> na frente. Resultado: quem escrevia "o Acquarelle ainda tá valendo?" era
> atendido, e quem **colava o card com o código** — a forma mais clara que
> existe de dizer de qual imóvel fala — era recusado. Um corretor da lista
> ficou sem resposta por isso.

### 3.2 O filtro de palavras — antes de qualquer leitura

Transcrição de áudio erra nome próprio. O texto passa por uma correção antes de
a porta e a IA lerem:

| veio | ela lê |
|---|---|
| "bom pedro" | **Dom Pedro** (bairro) |
| "aquarelli" / "aquareli" | **Acquarelle** (condomínio) |
| "ponta negrra" | **Ponta Negra** |
| "tarumaassu" | **Tarumã-Açu** |

Vocabulário: 188 nomes tirados do próprio catálogo, atualizados de madrugada.
A régua é **distância de letras** (Levenshtein), não trigramas — medido:
"bom pedro" × "Dom Pedro" dá 0,54 de trigrama e 0,89 de letras. Corte em 70%.
Roda em 9 ms. Travas: palavra com menos de 5 letras não é corrigida, palavra
comum do português não é candidata, nome próprio não começa nem termina em
preposição, e comando do dono não passa pelo filtro.

### 3.3 A mente — quem responde

Um modelo barato lê o bloco inteiro e escolhe entre **IMÓVEIS** e
**SECRETÁRIA**. A secretária só fica com três coisas: o corretor oferecendo um
imóvel dele, alguém querendo cadastrar imóvel, e assunto que não é imóvel.

> **Nota de cicatriz:** esse caminho se chamava "LOCAÇÃO" no texto da mente. O
> modelo leu o nome e concluiu que **venda não era dela** — mandou para a
> secretária "tem casa para venda no Itapuranga?" com o motivo literal
> *"VENDA DE IMÓVEL NÃO É LOCAÇÃO"*. Foram 58 de 137 conversas desviadas antes
> de alguém notar. Hoje o caminho se chama IMÓVEIS e o texto diz que venda é
> dele.

**Redundância:** depois que a mente escolhe, o banco confere. Se a mensagem
fala de imóvel e não é oferta nem link de catálogo, vai para IMÓVEIS —
independentemente do que o modelo tenha decidido. E cortesia ("ok",
"obrigado", "bom dia" sozinhos) **não troca de atendente**: segue com quem já
atendia, senão a secretária entra no meio de uma negociação.

### 3.4 A Nay Imóveis

Modelo com prompt de 7.742 caracteres e 13 ferramentas (card por código,
resumo do condomínio, busca por perfil, disponibilidade, o que sei do imóvel,
pedir visita, guardar dados da visita, resultado da visita, escalar ao dono…).

**Quem conduz a conversa é a ferramenta, não o modelo.** A busca por perfil
devolve *a próxima pergunta* — bairro, depois faixa de preço, depois mobília —
uma por mensagem. Deixar a sequência com o modelo fez ele juntar duas
perguntas numa mensagem só.

Regras que valem aqui:

- **casa não vira apartamento.** Se o corretor pede casa e não há casa no
  perfil, ela diz que não tem — não oferece outro tipo.
- **acima de R$ 100 mil é venda**, mesmo sem a palavra. E o leitor de valor
  pega o **maior** número da frase, ignorando telefone, CEP, data e hora.
- **sem preferência de bairro** ela procura na cidade inteira, e o nome da
  cidade nunca vira bairro (ela chegou a dizer "não trabalhamos com imóvel em
  Manaus" — sendo de Manaus).
- **quem pede os valores recebe a lista**, não a pergunta de orçamento.
- **pediu dois imóveis, recebe os dois**, cada um com card e fotos próprias.

### 3.5 A Nay Secretária

Prompt de 2.000 caracteres — curto de propósito. Não tem fluxo de atendimento:
tem tom, a regra de não inventar, e as ferramentas. Ela **começou sem saber
nada** e aprende:

```
corretor pergunta → ela não sabe → abre pendência e avisa o dono
dono responde "RESPOSTA 81 <texto>" no WhatsApp dele
   → o corretor recebe a resposta
   → e a resposta fica guardada em `nai_saber`
   → da próxima vez ela responde sozinha
```

Hoje tem 8 coisas aprendidas. É pouco, e é o esperado: está no ar há dois dias.

**O cadastro de imóvel** é dela. Colhe uma coisa por mensagem (tipo →
finalidade → lugar → quartos → valor → fotos) e o imóvel sobe, com o contato
do corretor removido da descrição.

> **Nota de cicatriz:** no primeiro dia um corretor descreveu **a carteira
> dele** ("vou te anunciar os imóveis que eu tenho") e virou um imóvel
> publicado com tipo "apartamentos, casas e imóveis em prédios", condomínio
> "Living Comfort e Coral Gables" e bairro "Parque Dez e Flores". Hoje: tipo só
> entra se for **um** tipo do catálogo, condomínio e bairro só com **um** nome.
> O que não passa não é gravado, e ela pergunta de novo.

### 3.6 A caixa de saída — ordem e tempo

Tudo que sai passa por uma tabela (`nai_saida`) antes de virar mensagem. Ali
acontecem três coisas que a entrega do WhatsApp sozinha não garante:

**A ordem.** Texto é entregue na hora; foto precisa subir. Numa resposta com
16 fotos, a mensagem de fechamento chegava **no meio das fotos** — e os dois
textos finais trocaram de lugar entre si. Serializar a fila não resolve: a
Z-API responde "ok" quando aceita a foto, não quando o WhatsApp entrega. A
solução foi **hora marcada**: cada mensagem espera (fotos na frente dela) ×
2,5 segundos — medido no eco real, 16 fotos levaram 26 segundos. A espera é
por imóvel: as fotos de um saem juntas, e quem espera é o card do próximo.

**A conferência.** Antes de virar mensagem, todo card e toda foto são
conferidos contra o que a pessoa pediu: tipo errado, finalidade errada,
imóvel de parceiro ou fora do mercado são **retirados da fila**. É a rede
embaixo da busca e do modelo.

**O portão.** Bloqueia: imóvel de parceiro, pausa geral, conversa que o dono
assumiu (ele escreve manualmente e ela cala por 30 minutos), e o contato-espelho
de treino, que nunca sai para o WhatsApp de verdade.

### 3.7 O dono no controle, pelo próprio WhatsApp

Ele comanda por mensagem: `DEVOLVER <telefone>` (ela volta a atender),
`PARAR <telefone>`, `RESPOSTA <n> <texto>` (responde uma pendência e ensina),
`<código> alugado` (tira do mercado), e outros. Mensagem manual dele silencia a
Nay por 30 minutos naquela conversa.

---

## 4. Como as regras são protegidas

O dono foi explícito: *"se eu coloco regra é para seguir"*. Cada regra vale em
**três camadas**:

| camada | quem faz | exemplo (casa ≠ apartamento) |
|---|---|---|
| decide | a mente / o modelo | escolhe o atendente e as ferramentas |
| confere | o banco, na decisão | força IMÓVEIS quando é assunto de imóvel |
| impede | a conferência da saída | tira da fila o apartamento quando ele pediu casa |

E **o que a pessoa quer sai de uma fonte só** (`nai_pedido_do_turno`): tipo,
finalidade, teto, imóveis citados, se é cortesia, se é oferta. Antes cada
função adivinhava do seu jeito, e era por isso que uma sabia e a outra não.

### A bateria de regressão

`SELECT * FROM nai_rodar_casos()` roda **15 casos reais** — os erros que o dono
apontou, um por regra — e diz numa tela se continuam de pé. Hoje: 15 de 15.

Cada erro novo que ele aponta vira uma linha nova na bateria. É o que impede o
próximo conserto de quebrar o anterior — que foi exatamente o que vinha
acontecendo antes.

---

## 5. O que está fraco (sem maquiagem)

1. **O vínculo imóvel ↔ proprietário não existe.** A tabela que deveria ligar
   os dois tem, no campo "código", o mesmo número do proprietário. Hoje o
   sistema casa **por nome**, e 1.163 dos 1.250 imóveis do catálogo não têm
   dono identificado.
2. **151 imóveis sem mobília** — o dado não existe em lugar nenhum, nem no site
   antigo. Enquanto isso, eles ficam de fora de qualquer busca por "mobiliado".
3. **A mente é um custo por mensagem.** Toda mensagem passa por um modelo só
   para escolher o caminho. Funciona, mas é um ponto de falha e de latência que
   uma regra determinística cobriria em boa parte dos casos.
4. **O texto da mente mora dentro de um nó do n8n**, não no banco — é a única
   regra importante que não está no lugar onde as outras estão, e foi
   justamente ela que se desalinhou por dois dias sem ninguém ver.
5. **A secretária sabe 8 coisas.** Até aprender, quase toda pergunta vira uma
   pendência no WhatsApp do dono.
6. **Não há teste automático do fluxo n8n.** A bateria cobre as regras do
   banco; o caminho do n8n é testado à mão, mandando mensagem pelo
   contato-espelho.
7. **Muita regra nasceu de incidente.** São 117 migrações, várias delas
   corrigindo a anterior. A consolidação em "uma fonte + três camadas" é
   recente (hoje).

---

## 6. O que eu quero que você avalie

1. **A arquitetura de três camadas se sustenta?** Ou é redundância que dá falsa
   sensação de segurança e esconde o erro em vez de evitá-lo?
2. **Regra de negócio em PL/pgSQL** — 305 funções — é uma escolha defensável
   para este caso, ou virou uma armadilha de manutenção?
3. **A mente (um modelo decidindo o roteamento)** vale o custo e o risco? O que
   você usaria no lugar?
4. **O que você atacaria primeiro** na lista de fraquezas da seção 5, e por quê?
5. **Que falha você consegue imaginar que as três camadas não pegariam?** É a
   pergunta que mais me interessa: estou procurando o buraco que ainda não
   apareceu em produção.
6. **A bateria de 15 casos é suficiente** como rede de regressão, ou é teatro?
   O que faltaria para ela valer de verdade?
