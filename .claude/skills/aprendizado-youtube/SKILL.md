---
name: aprendizado-youtube
description: Rotina de aprendizado da Imob Easy. Use quando o Pedro pedir para analisar vídeos, transcrições ou "os vídeos de hoje/novos", ou mandar um link do YouTube ou uma transcrição pedindo ideias. Lê a transcrição, LÊ o contexto da empresa no vault do Obsidian (sem escrever nada lá) e grava as ideias que ajudam de verdade no banco, na aba Ideias refinadas de admin › Aprendizado (sugestão, como é hoje, onde ajuda, prazo e nota 0-100).
---

# Aprendizado do YouTube → admin › Aprendizado › Ideias refinadas

Pedro, 28/10/2026: "vai pegar essa transcrição, analisar, analisar a nossa empresa no Obsidian com todo nosso contexto, e
ver quais ideias do vídeo poderiam ajudar de verdade ... minha ideia é fazer isso toda noite com vários vídeos".
29/10: "eu não pedi para pôr nada no obsidian, tu só vai ler o obsidian para ver as informações da imobeasy, os
aprendizados ficam em aprendizado na nova aba". **O vault é só leitura nesta rotina.**

## Onde fica cada coisa
- Transcrições: `transcricoes/` (o Agente de Aprendizado salva `AAAA-MM-DD <título> [<id>].txt`; fora do git).
- Contexto (SÓ LER): vault `C:\Users\pedro\Documents\Obsidian Vault`, pasta `IMOBEASY/` (IMOBEASY.md, Situação atual,
  Métricas, Funis, Atendimento, Empresa).
- Saída: banco (514) `aprendizado_video` e `aprendizado_ideia`, gravados por `aprendizado_gravar(jsonb)`.
- Tela: `imob-easy/admin/aprendizado.html#ideias` (`assets/js/aprendizado-ideias.js`): barrinha vertical da nota e
  os filtros Acima de 90 / Ainda não avaliadas / prazo / vídeo. Nada a publicar na rotina: a tela lê o banco.

## Passo a passo
1. `python scripts/aprendizado.py pendentes`: as transcrições cujo vídeo ainda não está no banco. Se o Pedro mandou link
   sem transcrição salva, peça para mandar pela tela Aprendizado (aba Transcrições). Se colou o texto na conversa, use
   o texto colado.
2. `python scripts/aprendizado.py texto <id>` e leia o arquivo que ele imprime INTEIRO (o vídeo todo, não o começo).
3. Leia o contexto no vault: `IMOBEASY/IMOBEASY.md`, a nota de situação atual mais recente, `Métricas`, `Funis Imobeasy`
   e as notas da área que o vídeo toca. Use os números de lá; não invente número. Não crie nem edite nota no vault.
4. `python scripts/aprendizado.py ideias`: as ideias que já existem e o próximo número. Ideia que já existe NÃO vira
   ideia nova: ponha no JSON a ideia existente (mesmo `numero`) com o texto acrescido do trecho do vídeo novo em
   `do_video` e, se mudar, a nova `nota_claude` (a nota que o Pedro deu na barrinha não muda).
5. Escreva `transcricoes/_ideias/<youtube_id>.json` (formato abaixo; normalmente de 3 a 10 ideias por vídeo; vídeo
   fraco pode dar 0, e então grave só o vídeo, com `"ideias": []`).
6. `python scripts/aprendizado.py gravar transcricoes/_ideias/<youtube_id>.json` (vai pelo `./scripts/nay aplicar`).
   Vários vídeos na mesma noite: um JSON e um gravar por vídeo.
7. Responda em poucas linhas: quantas ideias, as 3 de maior nota, o que do vídeo foi descartado, e o link
   `https://imobeasy.online/admin/aprendizado.html#ideias`.

## O que vira ideia
Só o que ajuda a Imob Easy de verdade: uma rede de corretores parceiros em Manaus, com Nays de IA no WhatsApp. Descarte
(e escreva em `nao_serve` do vídeo) dica genérica, o que já fazemos igual ou melhor, e o que não cabe no negócio. Toda
ideia precisa citar um fato do vault em `como_hoje`.

## O JSON
Os textos são markdown curto: itens com `- `, `**negrito**`, parágrafos por linha.

```json
{
  "video": {
    "youtube_id": "XXXXXXXXXXX", "titulo": "Título do vídeo", "quem": "Autor, onde foi",
    "link": "https://www.youtube.com/watch?v=XXXXXXXXXXX", "data": "AAAA-MM-DD", "duracao": "1h29",
    "defende": "- 5 a 8 itens do que o vídeo defende",
    "nao_serve": "- o que não serve para nós e por quê"
  },
  "ideias": [{
    "numero": 11, "titulo": "Título claro, com verbo", "area": "Marketing", "prazo": "curto", "nota_claude": 80,
    "sugestao": "O que fazer, concreto, em até 4 itens.",
    "como_hoje": "Os fatos do vault (números, o que já existe) que mostram a lacuna.",
    "onde_ajuda": "Qual funil, número ou gargalo melhora, e por quê.",
    "porque_prazo": "Uma frase.",
    "do_video": "[mm:ss] \"trecho literal curto\" que originou a ideia."
  }]
}
```
`area`: Marketing | Funis | Atendimento e dados | Captação | Equipe | Produto. `prazo`: curto | medio | longo.

## A régua da nota_claude (0-100)
- Até 40: impacto no gargalo atual (situação do mês: o que está travando venda, captação ou medição).
- Até 20: encaixe no que já existe (Nays, CRM, site, grupos, dados).
- Até 20: esforço baixo (quanto menor o esforço, mais pontos).
- Até 20: força da evidência (dado do vault ou exemplo concreto do vídeo, não opinião solta).
90 ou mais só para o que é claramente para executar já (o filtro "Acima de 90" da tela pega 90 em diante).

## O prazo
- **curto**: até 2 semanas, com o que já existe.
- **medio**: 1 a 2 meses, precisa construir, produzir conteúdo ou contratar algo pequeno.
- **longo**: 3 meses ou mais, canal novo, verba ou mudança de posicionamento.
