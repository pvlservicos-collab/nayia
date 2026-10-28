---
name: aprendizado-youtube
description: Rotina de aprendizado da Imob Easy. Use quando o Pedro pedir para analisar vídeos, transcrições ou "os vídeos de hoje/novos", ou mandar um link do YouTube ou uma transcrição pedindo ideias. Lê a transcrição, cruza com o contexto da empresa no vault do Obsidian e grava as ideias que ajudam de verdade no quadro Ideias refinadas (uma nota por ideia, com sugestão, como é hoje, onde ajuda, prazo e nota 0-100).
---

# Aprendizado do YouTube → Ideias refinadas

Pedro, 28/10/2026: "vai pegar essa transcrição, analisar, analisar a nossa empresa no Obsidian com todo nosso contexto, e
ver quais ideias do vídeo poderiam ajudar de verdade ... minha ideia é fazer isso toda noite com vários vídeos".

## Onde fica cada coisa
- Transcrições: `transcricoes/` (o Agente de Aprendizado salva `AAAA-MM-DD <título> [<id>].txt`; fora do git).
- Vault: `C:\Users\pedro\Documents\Obsidian Vault`. Regras dele em `OBSIDIAN MEMORIA.md` (ler antes).
- Contexto da empresa: `IMOBEASY/` (IMOBEASY.md, Situação atual, Métricas, Funis, Atendimento, Empresa).
- Saída: `IMOBEASY/Estratégia/Vídeos/` (uma nota por vídeo) e `IMOBEASY/Estratégia/Ideias/` (uma nota por ideia).
- Quadro: `IMOBEASY/Estratégia/Ideias refinadas.md` (plugin `imobeasy-ideias` do vault: barrinha vertical e filtro).

## Passo a passo
1. `python scripts/aprendizado.py pendentes`: as transcrições que ainda não viraram nota de vídeo. Se o Pedro mandou link
   sem transcrição salva, peça para mandar ao Agente de Aprendizado (admin › Agentes) ou use a skill `watch`. Se colou
   o texto na conversa, use o texto colado.
2. `python scripts/aprendizado.py texto <id>` e leia o arquivo que ele imprime INTEIRO (o vídeo todo, não o começo).
3. Leia o contexto: `IMOBEASY/IMOBEASY.md`, a nota de situação atual mais recente, `Métricas`, `Funis Imobeasy` e as
   notas da área que o vídeo toca. Use os números de lá; não invente número.
4. `python scripts/aprendizado.py ideias`: as ideias que já existem e o próximo número. Ideia que já existe NÃO vira nota
   nova: acrescente na nota existente uma linha em "## Do vídeo" com o trecho do vídeo novo e, se mudar, ajuste
   `nota_claude` (nunca mexa em `nota` nem em `nota_revisada`, que são do Pedro).
5. Escreva as ideias novas (normalmente de 3 a 10 por vídeo; vídeo fraco pode dar 0 — diga isso).
6. Escreva a nota do vídeo e acrescente a linha na tabela "Vídeos estudados" de `Aprendizados YouTube.md`.
7. Responda em poucas linhas: quantas ideias, as 3 de maior nota, e o que do vídeo foi descartado.

## O que vira ideia
Só o que ajuda a Imob Easy de verdade: uma rede de corretores parceiros em Manaus, com Nays de IA no WhatsApp. Descarte
(e liste no fim da nota do vídeo, em "O que não serve para nós") dica genérica, o que já fazemos igual ou melhor, e o
que não cabe no negócio. Toda ideia precisa citar um fato do vault em "Como é hoje".

## A nota de cada ideia
Arquivo `Ideias/NNN <título curto>.md` (NNN = número com 3 dígitos; sem `:` `/` `?` no nome). Sem `[[links]]` (o
gráfico do vault é uma árvore; ver OBSIDIAN MEMORIA). Modelo:

```markdown
---
tipo: ideia
numero: 11
titulo: "Título claro, com verbo"
video: "Autor · Título do vídeo"
youtube_id: XXXXXXXXXXX
data: AAAA-MM-DD
area: "Marketing"            # Marketing | Funis | Atendimento e dados | Captação | Equipe | Produto
prazo: curto                 # curto | medio | longo
nota: 80                     # começa igual à nota_claude; o Pedro mexe pela barrinha
nota_claude: 80
nota_revisada: false
status: nova
---

```nota-barra
```

## Sugestão
O que fazer, concreto, em até 4 itens.

## Como é hoje
Os fatos do vault (números, o que já existe) que mostram a lacuna.

## Onde nos ajuda
Qual funil, número ou gargalo melhora, e por quê.

## Por que esse prazo
Uma frase.

## Do vídeo
[mm:ss] "trecho literal curto" que originou a ideia.
```

## A régua da nota_claude (0-100)
- Até 40: impacto no gargalo atual (situação do mês: o que está travando venda, captação ou medição).
- Até 20: encaixe no que já existe (Nays, CRM, site, grupos, dados).
- Até 20: esforço baixo (quanto menor o esforço, mais pontos).
- Até 20: força da evidência (dado do vault ou exemplo concreto do vídeo, não opinião solta).
Acima de 90 só para o que é claramente para executar já.

## O prazo
- **curto**: até 2 semanas, com o que já existe.
- **medio**: 1 a 2 meses, precisa construir, produzir conteúdo ou contratar algo pequeno.
- **longo**: 3 meses ou mais, canal novo, verba ou mudança de posicionamento.

## A nota do vídeo
`Vídeos/AAAA-MM-DD <Autor> - <Título>.md` com as propriedades `tipo: video`, `titulo`, `quem`, `youtube_id`, `link`,
`data`, `duracao`, `transcricao` (caminho do .txt) e `ideias` (quantas), e as seções "O que defende" (5 a 8 itens),
"O que não serve para nós" e "Ideias que saíram" (os números). O `youtube_id` é o que marca o vídeo como estudado.
