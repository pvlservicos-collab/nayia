# 31 — Lembrete de retorno: plano de construção

*Levantado em 30/08/2026 por um trabalho paralelo de 10 agentes: quatro
levantando como corretor de Manaus fala de prazo (205 expressões), dois
desenhando a máquina de estados, três atacando o desenho pelos lados do
corretor irritado, do engenheiro e do negócio (45 falhas, 31 graves), e um
consolidando.*

*Os dois agentes de desenho morreram no meio (queda de conexão). O red team e a
síntese rodaram sobre o material das variações, então o plano está completo mas
a máquina de estados nasceu na síntese, não de dois desenhos independentes.*

**Origem:** o Tel pediu, a partir da conversa com a corretora Solange em 29/08,
um mecanismo para a Nay cobrar retorno de cliente no dia e hora que o corretor
prometeu. As 12 decisões dele estão no corpo do plano como especificação.

---

# PLANO DE CONSTRUÇÃO — LEMBRETE DE RETORNO DA NAY

---

## 1. O MAPA DE HORÁRIOS FINAL

Regra geral: **hora-alvo é sempre `America/Manaus` (UTC-4)**, gravada em `timestamptz`. Nada sai antes das 08:00 nem depois das 20:00. Coluna "2ª" = segunda tentativa automática se não vier resposta.

⚠ = a Nay **não agenda direto**, pergunta uma vez antes (decisão 7).

| # | Como o corretor de Manaus escreve de verdade (variações) | Alvo | Dia | 2ª |
|---|---|---|---|---|
| 1 | amanhã cedo · amanha cdo · amn cedo · cedinho · bem cedinho · de manhãzinha · cedão · cedo cedo · logo cedo · primeira hora · 1ª hora · assim que amanhecer · antes de sair pro trabalho · depois que deixar as crianças na escola · quando abrir a imobiliária · começo do expediente | **08:00** | D+1 | 11:00 |
| 2 | quando eu chegar no escritório · chegando na loja te falo · assim que eu chegar | **09:00** | D+1 | 11:30 |
| 3 | assim que eu acordar · acordando te chamo · depois do café ⚠ | **09:00** | D+1 | 19:00 |
| 4 | de manhã · pela manhã · d manha · na parte da manhã · no turno da manhã · amanhã de manhã | **09:00** | D+1 | 11:30 |
| 5 | final da manhã · perto do almoço · antes do almoço · antes do meio-dia · lá pelas 11 | **11:00** | dia citado | 12:40 |
| 6 | depois do almoço · dps do almoço · após almoçar · na hora do rango · logo depois do almoço | **12:40** | dia citado | 17:30 |
| 7 | começo da tarde · início da tarde · primeira hora da tarde | **13:30** | dia citado | 17:30 |
| 8 | à tarde · de tarde · no período da tarde · amanhã à tarde | **14:30** | D+1 | 17:30 |
| 9 | meio da tarde · lá pelas 3 · umas 15h · na hora do café (com "tarde" por perto) | **15:30** | dia citado | 18:00 |
| 10 | final da tarde · até o final da tarde · fim do expediente · antes de fechar · fim do dia útil | **17:30** | dia citado | 19:00 |
| 11 | final do dia · fim do dia · hoje ainda · até hoje | **17:45** | hoje | 19:00 |
| 12 | início da noite · à noite · de noite · depois que eu chegar em casa · depois do jantar | **19:00** | dia citado | D+1 09:00 |
| 13 | mais tarde · daqui a pouco · já já · agorinha · te falo logo · qualquer hora dessas | **+3h** (teto 19:00) | hoje | D+1 09:00 |
| 14 | amanhã · amanhã te falo · amanhã eu respondo · amanhã eu retorno | **08:00** | D+1 | 11:00 |
| 15 | depois de amanhã · daqui a 2 dias | **09:00** | D+2 | 15:30 |
| 16 | segunda · na terça · quinta que vem ⚠ (esta semana ou a próxima?) | **09:00** | dia citado | 15:30 |
| 17 | semana que vem ⚠ · depois do fim de semana · na próxima semana | **segunda 09:00** | — | 15:30 |
| 18 | dia 5 · dia 12 ⚠ (se a data já passou no mês) | **09:00** | data citada | 15:30 |
| 19 | de madrugada eu te falo · só vejo de madruga · te falo de madrugada | **08:00** (nunca de madrugada) | D+1 | 11:00 |
| 20 | depois do feriado · depois do carnaval · passando o feriadão | **09:00 no 1º dia útil** | — | 15:30 |
| 21 | quando sair o FGTS · depois do pagamento · quando o banco responder · quando sair a aprovação ⚠ | **09:00 em D+2**, uma vez só | — | não insiste |
| 22 | assim que ela me responder · quando ele me der retorno · qualquer coisa te falo · deixa comigo · vou ver e te falo ⚠ | **09:00 em D+1**, uma vez só | — | não insiste |
| 23 | uns dias · daqui uns dias · mais pra frente · em breve ⚠ | pergunta 1x; sem resposta → **D+2 09:00** e encerra | — | não insiste |

**Três pivôs que valem mais que a tabela inteira:**

1. **Mensagem escrita entre 00:00 e 05:00 → "amanhã" é HOJE no calendário.** Não somar +1. Errar isso joga a cobrança 32 horas à frente.
2. **"logo" sem "cedo" é hoje** (+2h). "logo cedo" é manhã de D+1. Um dia inteiro de diferença numa palavra.
3. **Sem retorno até meio-dia → cobra 19:00** (mapa acordado), respeitando o teto de contato do item 4.1.

**Rolagem obrigatória (regra de dado, nunca do modelo):** alvo que cair em domingo, feriado, sábado depois de 12:00, ou fora de 08:00–20:00, rola para o próximo horário útil. Domingo 08:00 vira segunda 09:00.

---

## 2. AS TABELAS E O ESTADO

Reusar o que já existe: `pendencias`, `pendencia_rascunho`, `mensagens`, `nay_memoria`, `imoveis`, `corretores`, `config`, `identidade_lid`, `enviar_zapi.py`, o cron de minuto em minuto.

**Três tabelas novas. Só três.**

### `lembrete`
Um por (corretor, imóvel, assunto). Nunca dois abertos para a mesma chave.

```
id
corretor_id          -- resolvido, NUNCA string de telefone
codigo               -- imóvel; NULL impede o envio
assunto              -- 'feedback' | 'visita' | 'prazo' | 'perfil'
referencia           -- "a cliente que viu sábado" (texto curto, vem do dado)
estado               -- agendado|adiado|enviado|aguardando|morto|escalado|congelado
disparar_em          timestamptz   -- SEMPRE timestamptz
tentativa            smallint      -- 1,2,3
mensagem_origem_id   -- a linha de `mensagens` que gerou
quoted_msg_id        -- id do card, para citar na cobrança
expressao_original   -- o texto cru: "ela decide amanhã de manhã"
regra_aplicada       -- "#14 amanhã→08:00"
confianca            -- alta|baixa (baixa = passou por pergunta)
criado_em / atualizado_em / motivo_morte
UNIQUE (corretor_id, codigo, assunto) WHERE estado IN ('agendado','adiado','enviado','aguardando','congelado')
```

### `contato_corretor`
Livro-caixa único de toque. **Todo emissor grava e consulta antes de enviar** — lembrete, oferta proativa, publicador, qualquer coisa nova. Sem isso, os três emissores continuam sem saber um do outro e o corretor leva 5 mensagens num dia.

```
id, corretor_id, telefone, canal ('direto'|'grupo'), quando timestamptz,
motivo ('lembrete'|'oferta'|'resposta'|'grade'), ref_id
```

### `feriado`
`data date PRIMARY KEY, descricao text`. Preenchida à mão, um ano por vez, com nacionais + Amazonas + Manaus. Duas linhas de SQL evitam a mensagem de 8 da manhã no feriado.

**Mais nada de tabela.** O log de evento vai em `lembrete_evento` (append-only: criado, adiado, enviado, resposta_vista, morto, escalado, detalhe) se você quiser auditoria — recomendo, custa pouco e é o que vai explicar "por que ela cobrou".

**A máquina de estado, inteira:**

```
agendado ──(pausa / janela de silêncio / teto de contato)──> adiado ──> agendado
agendado ──(reserva atômica + checagem 1s antes)──> enviado ──> aguardando
qualquer ──(mensagem do corretor casada)──> morto
qualquer ──(VENDEU/ALUGOU/travado/bloqueado)──> morto
qualquer ──(ambiguidade, áudio não transcrito, nome duplicado)──> congelado ──> escalado
aguardando ──(3ª tentativa sem resposta)──> escalado
```

Uma coluna a mais em `imoveis`: nenhuma. `VENDEU`/`ALUGOU` já passa por `nay_comando` — é lá que se mata a cadeia do imóvel (decisão 10).

---

## 3. COMO O LEMBRETE MORRE

**Recomendação única: o lembrete morre pela chegada de mensagem, não pela interpretação dela.**

Na prática, três camadas, nesta ordem:

1. **Suspensão por chegada.** Qualquer linha nova em `mensagens` daquele `corretor_id` — em qualquer canal, texto, áudio, citação, figurinha — posterior a `lembrete.criado_em` coloca o lembrete em `congelado` na hora. O disparo para. Isso não exige entender nada.
2. **Morte por casamento.** Se a mensagem for interpretada e casar com o `codigo`, o lembrete vai para `morto`. Resposta parcial (dois clientes, um respondido) mata **só** o item citado; o outro volta para `agendado` no próximo período, nunca no mesmo dia (decisão 2).
3. **Escalonamento por dúvida.** Congelado que não casou em 6 horas vai para você com o trecho cru. **Nunca volta a cobrar sozinho.**

E, 1 segundo antes do POST na Z-API, o disparador refaz a checagem 1 — porque o corretor pode ter respondido às 07:59.

**Por que essa e não outra:** silêncio de verdade é **ausência de linha em `mensagens`**, não ausência de match do parser. A Liliane que manda áudio às 21:40 e a que cita o card do 2014 respondem de verdade; o que falha é a leitura. Se a morte depender da leitura, o sistema cobra exatamente quem respondeu — e "ela não lê o que eu mando" é a percepção que faz o corretor parar de responder de vez. Melhor congelar 20 lembretes por dúvida do que cobrar 1 pessoa que já respondeu.

**Chave, sem exceção:** `corretor_id` resolvido via `identidade_lid`, casando pelos 8 últimos dígitos (a lógica de `nay_e_da_equipe` — reusar, não reescrever). Os três formatos (12 dígitos, 13 dígitos, `@lid`) precisam de teste passando antes de ligar. **Nome nunca resolve identidade** — uma "Ana" não mata o lembrete de outra "Ana"; nome ambíguo mantém vivo e escala.

**Também matam:** `VENDEU`/`ALUGOU` (decisão 10), imóvel virar `bloqueado`/`travado`/`disponivel=false`, corretor pedir mais prazo (o antigo morre, fica só o novo — decisão 6), e um comando manual seu: `Nay respondeu 5711 do Leonan`.

---

## 4. AS FALHAS GRAVES QUE PRECISAM DA SUA DECISÃO

**4.1 — Teto de contato.** Hoje três emissores independentes (n8n, cron da grade, agendador novo) podem somar 5 mensagens diretas no mesmo corretor no mesmo dia. Com 1.050 corretores, um punhado de "denunciar" queima o número da Z-API inteiro, não só aquele contato.
> **Pergunta: no máximo 1 mensagem direta por corretor por dia — mesmo que três lembretes vençam juntos, os outros esperam o dia seguinte. Fecha?**

**4.2 — Janela de silêncio.** "Ela responde amanhã de manhã" dito num sábado às 16:00 vira cobrança às 08:00 de domingo.
> **Pergunta: nada sai entre 20:00 e 08:00, nada em domingo e feriado, sábado só até 12:00 — e o que cai fora rola para o próximo horário útil. Confirma?**

**4.3 — Quantas cobranças antes de parar.** As decisões 3 e 5 somadas rendem de 4 a 6 toques sobre o mesmo assunto. "Ela vai pensar" em Manaus quase sempre é não — e ele está sendo perseguido por um não.
> **Pergunta: teto de 3 toques por imóvel/cliente (o do horário prometido + 19:00 + um no outro dia) e depois vai para você, ou você quer 2?**

**4.4 — Áudio e citação que o sistema não lê.** Áudio sem transcrição e citação de card jogada fora fazem a Nay achar que houve silêncio quando houve resposta.
> **Pergunta: quando existe mensagem do corretor que a Nay não conseguiu ler, ela adia e te manda o trecho, ou cobra assim mesmo?**

**4.5 — Onde chega o caso escalado.** Tudo que congela vai parar em algum lugar; sem isso definido, escalar vira sumir.
> **Pergunta: caso escalado chega como mensagem direta no seu WhatsApp na hora, ou fica numa lista que você puxa com `Nay PENDENTES` quando quiser?**

**4.6 — Quando quem está negociando somos nós (decisão 8).** A Nay te pergunta antes de avisar o corretor. Se você estiver em visita, no trânsito, ou dormindo, o lembrete fica parado e o corretor fica no escuro.
> **Pergunta: se você não responder em 24h se pode avisar, a Nay fica calada esperando, ou avisa o corretor por conta?**

---

## 5. CENÁRIOS NOVOS

1. **Ele responde no grupo, não no direto.** O corretor comenta "esse a cliente não quis" embaixo do card no grupo. O lembrete do privado continua vivo.
 → A suspensão por chegada olha **qualquer canal**. Menção ao código pelo mesmo `corretor_id` em grupo congela o lembrete do privado.

2. **Ele responde para o seu número pessoal.** Você sabe, a Nay não.
 → Comando manual seu, curto: `Nay respondeu 5711 do Leonan` mata a cadeia. Sem isso, você vira o gargalo silencioso.

3. **Ele corrige o prazo em 10 minutos.** "amanhã cedo"… "na verdade só à tarde". A decisão 6 cobre pedir prazo depois; não cobre a correção imediata.
 → `UNIQUE` na chave (corretor, imóvel, assunto): nova expressão de tempo **substitui**, nunca soma. Sempre a última vence.

4. **O imóvel morreu enquanto o lembrete vivia.** Ficou `bloqueado`, `travado` ou saiu do site, e a Nay cobra feedback de coisa que não pode mais vender.
 → Checagem em `imoveis` antes do disparo. Se saiu, a mensagem muda de cobrança para aviso: "esse saiu do ar — quer que eu mande parecidos?".

5. **Dois disparos do mesmo lembrete.** O cron roda de minuto em minuto e `postar_agora` já provou neste projeto que sem reserva atômica manda duas vezes.
 → `UPDATE lembrete SET estado='enviado' WHERE id=$1 AND estado='agendado' RETURNING id` antes do POST. Sem linha retornada, não envia. Igual ao `postar_easy`.

6. **Backlog depois de queda.** O servidor cai das 08:00 às 14:00 e 40 lembretes vencidos sobem todos juntos às 14:05.
 → Vencido há mais de 3 horas **não cobra retroativo**: rola para o próximo horário do mapa. E limite de envio por minuto no disparador.

7. **Ele responde com pergunta, não com resposta.** "e o valor tá negociável?" — não é feedback, mas também não é silêncio.
 → Congela, responde a pergunta, reagenda o feedback para D+1 no mesmo horário, **uma vez só**. Não reinicia a cadeia.

8. **Número morto.** Corretor trocou de chip; a Z-API devolve erro de número inexistente.
 → Erro de entrega marca o corretor e **mata a cadeia inteira**, não tenta de novo. Vira linha na lista de pendências para você limpar a base.

9. **Passou o cliente pra outro corretor.** "fala com o Júnior que ele tá com ela agora".
 → Fecha o lembrete atual. Só abre outro se o Júnior for identificável por telefone; se for só nome, escala. Nome não abre nem fecha lembrete.

10. **O lembrete nasce da frase errada.** Você ou o Fernando escrevem "ela decide amanhã de manhã" dentro do grupo, e a Nay abre lembrete contra vocês — ou contra a própria mensagem dela.
 → Só abre lembrete quando o autor é **corretor identificado** e a mensagem é dele. Mensagem da Nay nunca gera lembrete (evita o laço).

11. **A pergunta de perfil vira uma segunda cadeia.** Ele diz "não quiseram", a Nay pergunta o perfil (decisão 1) e ele não responde.
 → Pergunta de perfil **não gera lembrete**. Morre em silêncio. Se ele responder, ótimo; se não, acabou.

12. **Cobrar feedback de visita que não aconteceu.** A visita foi desmarcada e a Nay pergunta "o que acharam do imóvel?".
 → Sem confirmação de visita com o Fernando, a primeira pergunta muda de forma: "conseguiram ver o 5711?" em vez de "o que acharam?".

13. **A cobrança sempre com o mesmo texto.** Três toques idênticos parecem robô e a Z-API pode deduplicar.
 → Três variantes fixas por tipo, escolhidas pelo número da tentativa. Texto de dado, não gerado livre pelo modelo.

14. **A cobrança sem dizer do quê.** "teve retorno?" para quem tem quatro imóveis rodando.
 → Toda cobrança cita o card (`quoted_msg_id`). Sem citação, a primeira linha é obrigatória e vem de dado: "sobre o 2014 (Rio Amazonas), a cliente que viu sábado". `codigo` NULL **impede o envio** — não gera mensagem genérica.

---

## ORDEM DE CONSTRUÇÃO SUGERIDA

1. `identidade_lid` resolvendo `corretor_id` nos três formatos, com teste. **Nada funciona antes disso.**
2. Captura da citação no `Filtrar e normalizar` (a pendência aberta da Parte 1 do doc 30) — é pré-requisito, não melhoria.
3. `contato_corretor` + o disparador lendo `config.atendimento_pausado`, janela de silêncio e feriado. Teste provando que nada sai com a pausa em 'sim'.
4. Tabela `lembrete` + interpretador do mapa de horários, com teste dos casos de virada (23:50, 00:10, 01:40, sábado 16:00).
5. Só então o envio, com reserva atômica e a checagem de 1 segundo antes.