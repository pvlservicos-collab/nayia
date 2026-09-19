# 28 — Publicador de grupos: plano de construção

*Escrito em 22/08/2026, a partir das decisões do Tel nesta sessão. Este
documento descreve o que construir e por quê. Nada aqui foi construído
ainda.*

---

## O que é

O publicador é a peça que envia imóveis para os grupos de WhatsApp de
corretores. Ele **não decide o que postar** — o Tel decide, em linguagem
natural, e o publicador executa no horário certo, nos grupos certos.

Diferença em relação ao desenho anterior (conversa de 21/08): não existe
mais fila fixa com `POSTAR`/`TIRAR`. O modelo mental correto é uma
**grade de horários com vagas**. Uma vaga é um espaço no dia; quando o
imóvel que estava nela sai de circulação, a vaga fica livre e o Tel
preenche com outro.

## De onde vêm os dados

**Do site público**, não do banco local.

Isso resolve o problema que travaria tudo: quando o Tel capta um imóvel
novo, ele cadastra no admin, o imóvel ganha um código novo e fica
público no site. O banco local (`naydb`) é uma cópia sincronizada de
tempos em tempos — um imóvel cadastrado hoje **não está lá**. Buscar do
site direto, pelo código, funciona com captação nova, no mesmo dia.

A leitura é a mesma que o script de varredura já faz hoje (doc 25):
`imobeasy.com/anuncios/<codigo>` entrega condomínio, bairro, área,
quartos, valores e as fotos, sem login.

⚠️ **Consequência a aceitar:** se o imóvel foi cadastrado no admin mas
ainda não foi marcado como publicado no site, o publicador não vai
achar. A mensagem de erro precisa dizer isso com clareza ("o código
5750 não está publicado no site"), e não "código não encontrado", que
mandaria o Tel procurar no lugar errado.

## A regra do grupo de venda — estrutural, não de prompt

**Um dos 10 grupos ("terceiros compra e venda") só aceita imóvel de
venda. Postar locação lá resulta em expulsão.** Confirmado pelo Tel:
é o único grupo com restrição de tipo.

Isso **não pode** ser instrução no prompt. É a mesma lição que custou o
dia 21/08 com o bug do imóvel de parceria: aviso que o modelo pode
ponderar e ignorar não é trava. Ver doc 27, Parte 4.3.

**O desenho correto:** dois campos novos na tabela `grupos` —
`aceita_venda` e `aceita_locacao`, ambos boolean. Antes de montar a
lista de destinos, o publicador olha o imóvel: tem `valor_venda`? tem
`valor_aluguel`? E monta a lista **só com os grupos compatíveis**. O
grupo restrito sai sozinho quando for locação.

O Tel nunca precisa lembrar disso. Não existe caminho em que uma
locação chegue naquele grupo, mesmo que o comando peça.

**Imóvel com venda E locação (22 casos, descobertos na varredura do doc
25) — decidido pelo Tel:** pode ir no grupo de venda, mas o texto muda
conforme o destino.

- **No grupo de venda:** a mensagem sai **só com o valor de venda**. A
  linha de locação é omitida.
- **Nos outros grupos:** a mensagem sai completa, com venda e locação.

Isso significa que o publicador **não monta uma mensagem só e envia
para todos** — ele monta a mensagem **por grupo**, dependendo do que
aquele grupo aceita. É uma consequência importante para o desenho: a
função que monta o texto precisa receber o grupo como parâmetro, não só
o imóvel.

## Comandos

Em linguagem natural, interpretados pela Nay:

| O Tel manda | O que acontece |
|---|---|
| `posta o 5750` | envia agora, em todos os grupos elegíveis |
| `posta o 5750 todo dia às 14h` | cria vaga recorrente diária |
| `posta 5750, 5751 e 5752 terça e quinta às 9h` | uma vaga com até 3 imóveis |
| `VENDEU 5750` / `ALUGOU 5750` | tira de circulação, libera a vaga |
| `VAGAS` | mostra a grade atual |

**Até 3 imóveis por vaga.** O limite de vagas por dia é folgado (o Tel
citou "uns 50 se eu quiser", sinalizando que não é o número real, só que
não deve haver trava baixa).

**Sem limite de cadência de envio.** Decisão explícita do Tel: dispara em
todos os grupos, sem espaçamento artificial. Isso é uma decisão de risco
consciente, coerente com a decisão anterior sobre fotos sem limite
(doc 27, Parte 2).

## Vaga livre

Quando um imóvel sai de circulação — porque o Tel mandou `VENDEU` ou
`ALUGOU` —, a vaga que ele ocupava fica vazia. **A Nay avisa o Tel** que
sobrou espaço naquele horário, e **espera**. Ela não escolhe o próximo
imóvel sozinha.

Confirmado pelo Tel: *"Eu passo para ela qual colocar quando desocupar."*

Isso é coerente com o princípio que atravessa o projeto inteiro: a Nay
executa, o Tel decide.

## Rede de segurança

O comando `VENDEU`/`ALUGOU` depende do Tel lembrar de avisar. Como rede
de segurança, a varredura do catálogo (doc 25) pode detectar que um
imóvel agendado sumiu do site público e avisar — cobrindo o que escapar.

Isso é complementar, não substituto: o comando é imediato, a varredura
só pega na frequência em que rodar.

---

# O que construir, em ordem

**1. Tabela de grade.** Vagas: dia, horário, recorrência, e quais
códigos ocupam cada uma.

**2. Campos na tabela `grupos`.** `aceita_venda` e `aceita_locacao`,
preenchidos para os 10 grupos existentes. Só o "terceiros compra e
venda" fica com `aceita_locacao = false`.

**3. Busca do imóvel no site.** Reaproveita a lógica de extração que já
existe e está testada (doc 25), mudando só de listagem para anúncio
individual.

**4. Montagem da lista de destinos.** A função que, dado um imóvel,
devolve em quais grupos ele pode entrar. É aqui que a trava do grupo de
venda vive.

**5. Montagem da mensagem, por grupo.** A função recebe **imóvel +
grupo** e devolve o texto. No grupo que só aceita venda, omite a linha
de locação; nos outros, texto completo. Uma função só, chamada uma vez
por grupo de destino.

**6. Envio.** Fotos e texto via Z-API, reaproveitando o que já funciona
no atendimento a corretor.

**7. Agendador.** O que dispara nos horários da grade.

**8. Comandos.** Interpretação da linguagem natural, no mesmo padrão do
`Comando do Tel` que já existe e está testado.

**9. Aviso de vaga livre.**

---

## Onde construir

**Recomendação: Claude Code, não n8n.**

O motivo é o doc 27, Parte 4.3 — a lógica de "em quais grupos este
imóvel pode entrar" **não pode** acabar duplicada em dois lugares, como
aconteceu com a formatação da mensagem de imóvel. Em código, é uma
função só, chamada de onde precisar. No n8n, seria uma query ou um Code
node que alguém pode reescrever em outro caminho sem perceber.

E aqui o custo de duplicar não é uma mensagem feia: é expulsão de grupo.

O agendador também é mais simples em código (cron) do que em n8n.

## O que fica para depois

**Negociação e checklist de documentação.** O Tel descreveu, na mesma
conversa, uma frente diferente: quando chega proposta, ele hoje
direciona a Nay sobre o que responder, e quer que ela peça permissão
antes de mandar o checklist de documentação, aprendendo com as
correções até ficar boa.

Isso é **outra peça**, com risco próprio — errar na divulgação é
constrangedor, errar na negociação custa negócio. Deve ser desenhada
separadamente, depois do publicador estar rodando.

⚠️ **Uma correção necessária sobre "ela vai aprendendo":** a Nay não
ajusta o próprio comportamento sozinha. Isso já foi tratado como
expectativa desmontada no doc 27, Parte 3. O que funciona — e já
funciona hoje no comando `RESPOSTA` — é: o Tel corrige, a correção fica
gravada, e a Nay passa a usar aquela resposta. É aprendizado real, mas
mediado, não autônomo. O desenho da negociação precisa nascer com esse
mecanismo em mente.
