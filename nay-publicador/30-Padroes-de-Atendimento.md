# 30 — Padrões de atendimento: o que as conversas reais ensinam

*Aberto em 28/08/2026, a partir de seis conversas reais entre o Tel
(operando como Nay) e corretoras parceiras, mais uma com proprietária.*

---

## Para que serve este documento, e o que NÃO serve

Este é o lugar onde a gente **pensa** sobre como a Nay deve atender. Ele
não é lido por nenhum programa.

O aprendizado da Nay mora em três lugares diferentes, e confundir os três
já custou caro neste projeto:

| onde | o que vai ali | quem lê |
|---|---|---|
| **este documento** | observação, padrão, decisão e pergunta em aberto | pessoas |
| tabela **`regras`** | a regra de negócio já decidida, em uma frase | a Nay, via `sincronizar_regras.py` |
| **query da ferramenta** | a regra que governa um dado específico, colada nele | a Nay, sempre, sem depender de lembrar |

**O caminho é sempre este:** observa aqui → decide aqui → vira linha na
tabela `regras` (ou vai para dentro da query da ferramenta) → sincroniza.
Escrever direto na tabela sem passar por aqui é como o projeto chegou a
ter cinco regras que ninguém tinha revisado, três delas contradizendo a
prática (ver Parte 4 abaixo).

**Como acrescentar uma regra nova**, hoje:

```sql
INSERT INTO regras (texto, contexto) VALUES ('...', 'endereco');
```
depois, no servidor: `python3 sincronizar_regras.py --escrever` e o
import do fluxo (a sequência das quatro linhas está no `CLAUDE.md`).

---

## Parte 1 — Como o corretor identifica o imóvel

Esta é a descoberta mais importante das seis conversas, e ela quebra uma
suposição do sistema.

**O corretor quase nunca diz o código.** Ele **cita o card** que saiu no
grupo — o WhatsApp marca a mensagem original, e ele escreve embaixo:

> *Alice:* `[card citado: Rio Amazonas Residencial ... Código: 2014]`
> *Alice:* "Esse é só modulados e ar condicionado?"

O código está ali, dentro da citação. Mas o nó `Filtrar e normalizar`
guarda só cinco campos — `telefone, nome, texto, origem, message_id` — e
**joga a citação fora na entrada**. A Nay recebe "Esse é só modulados e ar
condicionado?" sem nenhum imóvel.

As três formas observadas, em ordem de frequência:

1. **Card citado** (Alice/2014, Liliane/5711, Samira/1327) — a mais comum
2. **Nome do condomínio ou apelido** ("o estilo ponta negra", "a casa da
   Nova Cidade", "o Smart Tower") — sem código
3. **Código puro** — quase não aparece nas conversas reais

⚠️ **Pendência técnica:** capturar a mensagem citada no `Filtrar e
normalizar`. Antes de escrever o parser da citação é preciso ver um
payload real da Z-API para saber o nome do campo — não adivinhar. O
padrão do alarme serve aqui: capturar defensivamente e despejar o que
veio, para o próximo caso se explicar sozinho.

---

## Parte 2 — O que os corretores perguntam de verdade

Levantado das seis conversas, sem inventar categoria:

| pergunta | exemplo real | a Nay tem o dado? |
|---|---|---|
| fotos, e principalmente **a fachada** | "tem a frente ela quer ver" | `imovel_privado.fachada_url` existe |
| mobília / o que fica | "esse é só modulados e ar condicionado?" | parcial |
| área de lazer | "me mostra a área de lazer" | **não** — "não tenho fotos de lá" |
| quintal | "tem quintal atrás? a cliente tem 2 crianças" | **não** |
| financiamento | "aceita proposta e financiamento?" | parcial |
| o que paga | "paga luz água e IPTU?" | **não** |
| caução e entrada | "parcela a caução?" / "quanto pra entrar?" | **não** |
| andar e face | "qual o andar do Smart Tower?" | `sol` e `andar` existem |
| localização | "fica próximo de onde?" | sim |
| disponibilidade | "o estilo ponta negra tá disponível?" | sim |

**Fotos são o gargalo mais repetido.** Três das seis conversas travam
nisso: "só tem uma foto lá", "não tenho fotos de lá", "tem a frente ela
quer ver". Não é problema de agente — é dado que falta.

---

## Parte 3 — Textos e regras que se repetem (candidatos a virar dado)

### O bloco de condições da locação

O Tel manda esta estrutura, montada na mão, sempre que a locação avança:

```
✅ VALOR ALUGUEL 2.500
   PAGA ÁGUA E ENERGIA

O QUE PRECISA PARA LOCAÇÃO
- Renda 3X o valor
- Mínimo 2 restrições no nome a avaliar
- para entrar no imóvel é o valor de 4.600 sendo 2 caução
- não pedimos aluguel antecipado, só paga após 30 dias no vencimento
```

Tudo isso é **derivável**: o valor vem de `imoveis`, o "para entrar" é
`2 × aluguel`, e o resto é política fixa. Candidato forte a virar
`texto_pronto` de uma ferramenta, no mesmo padrão do `imovel_por_codigo`
— assim ele sai sempre igual e sempre com o valor certo.

⚠️ **E o valor precisa estar certo.** Nesta mesma conversa a Samira citou
o card do grupo com `R$ 2.300` e o Tel respondeu *"mas é 2.500, tenho que
corrigir"*. O 1327 estava desatualizado no banco até a varredura de
28/08. Card errado no grupo = negociação errada com o cliente final.

### Sábado é de tarde

> *"no sábado o Fernando é mais fácil atender à tarde, então precisa
> gravar isso: no sábado, sugerir a tarde."*

Regra de agenda, dita pelo Tel em 28/08. **Ainda não está na tabela
`regras`** — depende de decidir se vale só para sábado ou também para
outros dias.

### A Nay não atende ligação

> *Nay:* "oi Adalgilsa, manda mensagem que eu não consigo atender por
> aqui"

Corretor liga. Ela não atende, e pede mensagem. Vale virar regra.

### Cancelamento é rotina, e a resposta é curta

Duas das seis conversas terminam em cancelamento. A resposta observada é
sempre leve: *"tudo bem, marca outro horário"*, *"Tudo bem"*. Nada de
insistir, nada de perguntar o motivo.

---

## Parte 4 — Regras que contradiziam a prática (corrigidas em 28/08)

As cinco regras da tabela `regras` foram ligadas em 28/08 e **três
contradiziam o que o Tel faz de rotina**. Elas tinham sido escritas e
nunca usadas, então ninguém tinha comparado com a realidade.

| regra | dizia | a prática mostra | resolução |
|---|---|---|---|
| 1 `endereco` | "NUNCA passa torre, andar" | *"5 andar nascente"* (Adalgisa) | **corrigida**: pode torre, andar e face; nunca a unidade |
| 4 `endereco` | "NÃO passa rua nem número" | *"fica na rua Curação"* (Samira e 9155) | **corrigida duas vezes** — ver abaixo |
| 3 `visita` | não sugerir visita sem acompanhante | Tel ofereceu senha da porta à Adalgisa | **mantida** — quem ofereceu foi o Tel, não ela |

**A regra 4 eu errei, e o Tel corrigiu.** Eu li "ele deu a rua duas
vezes" e concluí que a rua pode ser dada. Não pode: ele deu a rua daquele
imóvel porque **a Imob Easy administra** aquele imóvel. Nos administrados
passa-se tudo; nos demais, não.

Como a marcação de "administrado" **ainda não existe no cadastro**, a
regra voltou ao padrão fechado, com a exceção escrita e inerte:

> *"Existe uma exceção para imóveis que a Imob Easy ADMINISTRA, mas a
> marcação de administrado ainda não existe no cadastro: enquanto ela não
> existir, trate todos como não administrados e não passe a rua."*

⚠️ **Pendência:** identificar no site/cadastro quais imóveis a Imob Easy
administra — o Tel falou em marcá-los com uma **estrela** no site. Sem
isso, a Nay é mais restritiva do que precisa nos administrados, o que é o
lado seguro de errar.

Textos antigos em `regras_arquivo_20260828` e `regras_arquivo_20260828b`.

**A lição de método, agora dobrada:** regra escrita e nunca exercitada não
é regra, é intenção — e observar a prática sem perguntar **por quê** leva
a generalizar a exceção. Duas conversas mostravam a rua sendo dada; a
causa não estava nelas.

---

## Parte 5 — O modo de visita que o prompt não prevê

O prompt diz, na seção VISITA: *"nunca existe visita sem acompanhante
confirmado"* e que quem acompanha é o Fernando.

Mas existe um segundo modo, observado com a Adalgisa:

> *Nay:* "me passa os dados que a gente autoriza vocês"
> *Nay:* "te passo a senha da porta e você entra"
> *Nay:* "me passa as fotos da documentação sua e da cliente"

**Visita autorizada sem acompanhante**, com senha da porta, mediante
documentação do corretor **e** do cliente. Não está em lugar nenhum do
prompt nem da tabela.

✅ **Respondido pelo Tel em 28/08:** foi exceção, e por um motivo
específico — a Adalgisa ia visitar **sozinha**. A senha nunca parte da
Nay. Dois caminhos levam ao Tel, e não à decisão dela:

- ela **não consegue alinhar** corretor, proprietário e Fernando; ou
- o **proprietário oferece** passar a senha para a Nay.

Nos dois casos ela escala e diz ao corretor que vai verificar. Virou a
regra 3, reescrita em 28/08.

---

## Parte 6 — O padrão da abordagem proativa

Já acontece na mão, e é o que se quer automatizar:

> **27/08 17:57** — *Nay:* "oi Simone, boa tarde! você está procurando
> casa para venda" + o card do 5711
> **28/08 17:11** — *Nay:* "oi Simone, boa tarde! seu cliente tem
> interesse em visitar o imóvel esse final de semana?"

Duas etapas, em dias diferentes: **primeiro o imóvel, depois o convite
para visitar**. E o Tel já pediu o refinamento: antes de reoferecer,
perguntar se o cliente daquele corretor já fechou.

O mesmo padrão apareceu com o 9155: *"caso interesse podemos visitar o
imóvel amanhã, podemos visitar amanhã à tarde qualquer coisa."*

---

## Parte 7 — Conversa com proprietário (a próxima frente)

Uma só, e ela confirma o que o prompt já manda:

> *Nay:* "oi Sra. Ellen, boa tarde! tem como agendarmos uma visita amanhã
> as 10:30 ?"
> *Ellen:* "Sim"
> *Nay:* "vou alinhar aqui então Sra. Elen"

Tratamento formal (`Sra.`), pergunta "tem como agendar" e não "está
disponível" — exatamente como o prompt descreve. **Funciona.**

O que falta é mecânica, não redação: a Nay **não tem ferramenta que mande
mensagem para terceiro**. As seis dela são de consulta. Por isso ela
escalou a visita do Leonan (pendência 15) em vez de falar com o
proprietário — era o único canal de saída que ela tinha.

A infraestrutura existe e nunca foi ligada:
- `visitas` com `conf_proprietario`, `conf_fernando`, `conf_corretor` — **0 linhas**
- `proprietarios` com 5.612 registros
- ponte `imovel_privado`: **1.109 dos 1.206 imóveis chegam a um dono com telefone (92%)**

---

## Respondidas pelo Tel em 28/08 — já viraram regra

| pergunta | resposta | virou |
|---|---|---|
| torre e andar? | **pode**; a unidade, JAMAIS | regra 1 |
| senha da porta? | exceção; ela nunca oferece, escala ao Tel | regra 3 |
| a rua? | só nos imóveis **administrados**, e a marcação não existe ainda | regra 4 |
| sábado? | tarde por padrão, **mas sempre confirmar** se dá de manhã | regra 6 (nova) |
| quem tira do grupo? | a **Nay** posta o aviso, no formato abaixo | regra 7 (nova) |

Formato do aviso de saída do grupo, ditado pelo Tel:

```
CONDOMINIO ACQUARELLE ALUGADO
cod: 2943
3.500
```

## Resolvidos em 29/08

1. ~~**Marcar os imóveis administrados.**~~ Coluna `administrado` (boolean,
   default false) adicionada a `imoveis`. Preenchida à mão, não pelo site.
   Confirmados pelo Tel: **1327** (Casa Nova Cidade) e **4098** (Flex
   Parque Dez). CHECK no banco impede que `e_parceiro` e `administrado`
   coexistam — se a varredura tentar marcar um administrado como parceiro,
   o UPDATE falha e precisa de revisão humana. A regra 4 foi atualizada
   para referenciar a coluna: a consulta inclui o logradouro quando
   `administrado = true`, e omite nos demais.

2. ~~**O valor de entrada.**~~ Respondido pelo Tel: **o número de cauções
   varia por imóvel**, não é sempre 2. A Nay NÃO calcula — responde que
   vai verificar e escala ao Tel. Virou regra na tabela `regras`
   (contexto `locacao`).

## Ainda em aberto

1. **Capturar a mensagem citada no Z-API.** O campo existe no payload
   mas o `Filtrar e normalizar` joga fora. Precisa ver um payload real.
2. **Oferta proativa com verificação.** Antes de reoferecer, perguntar
   se o cliente do corretor já fechou. Bloqueado até a varredura rodar
   com regularidade.
3. **ACK de recebimento.** 35-45s de silêncio antes da resposta causa
   reenvio. Implementar um "recebi, já vou ver" imediato.
