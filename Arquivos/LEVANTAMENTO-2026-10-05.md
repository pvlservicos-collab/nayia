# Levantamento antes de mexer — Nay (05/10/2026, 10h–12h de Manaus)

Só leitura. Feito no repositório `nayia` (foto `producao/`), no repositório `nay-core` (commit `07a2f9f`, igual ao da VPS) e no `naydb` pelo papel de leitura. Pessoas aparecem como P01…P33 (ordem em que surgem nos turnos); nenhum telefone.

**Limite que vale para o documento inteiro:** o núcleo novo (`nay-core`) só responde corretor de verdade desde 02/10 14:10. "Últimos 7 dias" do core são, na prática, **145 turnos reais de 02/10 14:10 a 05/10 09:03, de 33 pessoas**. De 28/09 a 02/10 quem respondeu foi a Nay velha (n8n + funções `nai_*`); dela eu dou números agregados, não turno a turno.

---

## A. Quem atende hoje

### A1. Webhook, fluxo e modo

- **Webhook da Z-API (Parceria) → n8n**, não o nay-core.
  Consulta: `GET {instância}/me` da Z-API, lendo só os campos de callback.
  `receivedCallbackUrl: https://n8n.imobeasy.online/webhook/13d4116a-…` (o fluxo `Nay- recebe mensagem`); `receiveCallbackSentByMe: True`.
- **Fluxo "NAI atendimento locação": ATIVO.** Sqlite do n8n em só leitura, `SELECT name, active, updatedAt FROM workflow_entity`:
  ```
  ATIVO | 2026-10-02 03:31 | NAI atendimento locação   (webhook nai-aten…)
  ATIVO | 2026-10-02 03:31 | Nay- recebe mensagem      (webhook 13d4116a…)
  ATIVO | Nay - responder pendencia · Nay - escalar · Nay - alarme de erro
  parado | Nay - captacao proprietarios · ZZ teste de cron
  ```
  Execuções em 24 h: 1.957 (NAI atendimento locação), 565 (Nay- recebe mensagem).
- **nay-core: MODO=real**, pelo `.env` da VPS (`MODO=real`; o `config/limites.yaml` diz `modo: sombra`, mas o ambiente ganha: `nay/config.py:23`). Containers `nay-core`, `nay-core-worker`, `nay-core-enviador` de pé.
- **Canário: vazio** (`canario: []` no yaml; `nai_config.core_atende_so = ''`). Todo corretor da lista vai para o core.
- **Como o core recebe o turno:** não é pelo webhook. A porta velha (`nai_abrir_turno`, migração 269) grava o turno em `nai_core_turno` quando `nai_core_atende()` diz sim, e o worker do core atende. `nai_config`: `core_atende = sim`, `so_corretor_da_lista = sim`, `modo = todos`, `gap_tel_min = 30`.
- **O que `nai_core_atende` deixa com a Nay velha** (`producao/funcoes/nai_core_atende(bigint,text).sql`): a equipe; mensagem com palavra de visita (salvo "tá aberto para visita?", 276); quem tem visita em andamento ou realizada há menos de 3 dias; ficha de cadastro aberta; contatos de teste.

### A2. Últimos 300 turnos reais de corretor

Consulta: `nai_turno` (papel corretor, não teste, 300 mais recentes: 02/10 12:57 → 05/10 09:27), cruzando `nai_saida` enviado, `nai_core_turno` e `core_saida` enviado (`core_turno.exec_id = nai_turno.id`).

| quem respondeu | turnos |
|---|---|
| só a Nay velha (`nai_saida` enviado) | 31 |
| só o core (`core_saida` enviado) | 122 |
| os dois no mesmo turno | **0** |
| ninguém | 147 |

Entregues ao core: 145; desses, 23 sem nenhuma peça enviada (silêncio de cortesia, figurinha etc.).
Os 147 sem resposta, pela porta: `fora da lista de corretores` 58 · `conversa ja liberada` 33 (20 entregues ao core) · `fora da lista: esperando o Tel dizer se e corretor` 20 · `contato novo, assunto que nao e de corretor` 11 · `fora da lista: perguntou de imovel, perguntar ao Tel` 9 · `da equipe` 7 · outros 9.

### A3. O que mudou desde 02/10

**Commits do nay-core** (`git log --since=2026-10-02`, do mais novo para o mais velho):
```
07a2f9f 03/10 19:37 Imóvel que saiu: "no mesmo condomínio eu tenho" só para condomínio de verdade e do mesmo negócio
8eb01ed 03/10 19:34 Catálogo recarregado na hora em que um imóvel muda (era só de 10 em 10 minutos)
c15711a 03/10 15:15 Validador: "R$ 470 mil" é 470.000; e a foto do post do publicador também resolve a citação
f4653dd 03/10 12:20 Teste da busca sem finalidade: linha dentro do limite de estilo
660073a 03/10 12:18 Busca de quem disse "alugar ou comprar": o valor diz o negócio
b11d697 03/10 10:28 Valor sem negócio definido: abaixo de mil é milhar
8087a86 03/10 10:22 Marcou o card do grupo: a Nay responde sobre o imóvel marcado; lista do grupo, "os dois", "o primeiro" e a mobília no banco
01c700e 02/10 19:10 A lógica de atendimento do Tel (02/10): filtros mínimos, lista, e card com fotos para quem pede o imóvel
be2cf11 02/10 18:10 A ficha lê o cadastro: andar, sol, banheiros, financiamento e os outros campos do extras
79795ae 02/10 17:50 A ficha puxa características e descrição do cadastro quando não há anúncio
f898b39 02/10 17:47 A conversa da Maelita: opção da lista pelo nome, lista que não se repete, ao redor em mensagem separada
9f543f0 02/10 15:46 Pedido de foto: 'imagem' no singular também conta
001e927 02/10 15:29 PROGRESSO: primeiro erro em produção e a religada
1084f63 02/10 15:22 Cumprimento nunca é silêncio; resultado de visita sobe ao Tel
89cd9b1 02/10 15:18 Docs: a Nay nova ligada pela porta do sistema velho
a139051 02/10 15:16 Não entendeu: pergunta uma vez; na segunda seguida sobe ao Tel
c8fdfe3 02/10 15:11 Log: o httpx não grava mais a URL
68278d7 02/10 15:08 Citação reconhece o que o próprio core enviou (core_saida.message_id)
f6f42c9 02/10 15:02 Corrige o roteiro de teste
3402102 02/10 15:01 Teste funcional dos cinco erros mais comuns pelo espelho
7ff0de2 02/10 14:58 Modo real: o core atende os turnos que a Nay velha entrega; condomínio escrito ganha do foco; visita com horário avisa o Tel
a9b9825 02/10 14:27 Jev atrás da interface da Luna (provedor: luna | jev)
228438a 02/10 14:11 PROGRESSO: deploy da fusão em sombra e como voltar atrás
04fb663 02/10 14:00 replay: concordância de imóvel com o que o sistema velho enviou
a9ddcd8 02/10 13:55 Fusão com o pacote de 02/10: estrutura e comportamento do pacote
8a2d5d5 02/10 13:34 DECISOES: respostas de 02/10 (fusão aprovada, fotos só quando pedir, faixa 20/10, agradecimento cala)
a48f89d 02/10 13:29 Pacote de 02/10: conciliação VPS x pacote
0f94d80 02/10 12:07 Pacote de 02/10: relatório de infra, decisões assumidas
```
Migrações do core aplicadas desde 02/10 (`core_migracao`): `011_core_envio` (02/10 12:58), `012_core_turno_do_velho` (02/10 14:03), `013_conversa_mobilia_e_ultima_lista` (03/10 09:24).

**Funções do banco** que mudaram (histórico git de `producao/funcoes/`, que é regerada do `pg_get_functiondef`; A = nova, M = alterada). As que tocam o atendimento:
```
02/10 M  nai_abrir_turno · nai_buscar_por_perfil · nai_conferir_resposta · nai_deve_mandar_fotos
         nai_imovel_da_conversa · nai_imovel_pontos · nai_tel_assumiu · nai_chave
02/10 A  nai_core_atende (+2 M) · nai_core_escalou · nai_imoveis_na_frente (+1 M)
         nai_pergunta_se_da_para_visitar · nai_whatsapp_da_fila · nai_whatsapp_reenviado
03/10 M  nai_abrir_turno · nai_quem_atende · nay_imovel_da_citacao · nai_card_do_banco · nai_gravar_fotos_do_site
05/10 A  crm_quem_mandou (só leitura, para o CRM)
```
Migrações numeradas do período: 266 a 290 (`Arquivos/nai/`). As de atendimento: 266 (visitas do bloco), 267 (imóvel na frente / "manda aí"), 269 (porta entrega ao core), 270 (equipe fica com a velha), 276 ("tá aberto para visita?"), 281/287 (lista e foto do grupo guardam o id), 288, 289.
`SELECT * FROM nai_foto_diferenca()` existe e roda, mas compara com uma foto interna antiga (`nai_foto`): lista dezenas de `corpo_mudou` (ex.: `nai_abrir_turno era 12199 chars, agora 23645`). Não serve para "desde 02/10"; a data dessa foto eu **NÃO SEI** (olhar `SELECT max(id), ... FROM nai_foto`).

**Imports no n8n** (`workflow_history` desde 02/10): **12 linhas, todas de 02/10 03:30 (UTC), autor `import`** — um import em lote de madrugada (NAI atendimento locação, Nay- recebe mensagem, escalar, responder pendencia, alarme de erro e os parados). Nenhum depois.

---

## B. O fluxo de identificação

### B1. Onde vive

**Nos dois.** Cada sistema tem o seu, com ordens diferentes:

| | núcleo novo | Nay velha |
|---|---|---|
| onde | `nay/estado/maquina.py` (`pedir_imovel`, `perguntar_proximo_filtro`) + `nay/estado/filtros.py` + `config/filtros.yaml` | `nai_buscar_por_perfil` (190) + `nai_negocio_antes_do_card` + prompt do agente no n8n |
| ordem | `[finalidade, teto, regiao, tipo, mobilia]`; veio do grupo: `[finalidade, regiao, teto, tipo, mobilia]` (mobília só na locação) | locação/venda → casa/apartamento → valor → região; veio do grupo começa pela região |
| quem usa hoje | todo corretor da lista (145 turnos em 3 dias) | o que a porta não entrega ao core (visita, equipe, ficha, teste) |

`docs/FLUXO.md` do core ainda diz "finalidade, tipo, teto, região": está desatualizado em relação ao `config/filtros.yaml` (conferido igual na VPS).

### B2. Como sabe que o filtro foi respondido

- **Core: dado gravado.** Colunas `core_conversa.filtro_finalidade, filtro_tipo, filtro_teto, filtro_teto_tanto_faz, filtro_regiao, filtro_regiao_tanto_faz, filtro_mobilia`. `nay/estado/filtros.py`:
  ```python
  def preenchido(c, filtro):
      return {"finalidade": c.filtro_finalidade is not None,
              "tipo": c.filtro_tipo is not None,
              "teto": c.filtro_teto is not None or c.filtro_teto_tanto_faz,
              "regiao": bool(c.filtro_regiao) or c.filtro_regiao_tanto_faz,
              "mobilia": c.filtro_finalidade != "locacao" or c.filtro_mobilia not in (None, "tanto_faz")}[filtro]
  ```
  O valor entra por dois caminhos: o pré-roteador (`classificador/atalhos.py::_filtro`, regex sobre a resposta curta à pergunta do estado atual) ou o classificador (JSON da Luna).
  **Achado:** `filtros.zerar()` existe e **não é chamado em lugar nenhum do atendimento** (`grep -rn zerar nay/` só acha a definição; `scripts/auditoria_funcional.py` tem um `zerar` próprio, de teste). Os filtros de uma conversa nunca são limpos; pedido novo herda os do anterior.
- **Nay velha: regex sobre o que ELA mandou.** `producao/funcoes/nai_filtro_ja_perguntado(bigint,text).sql`:
  ```sql
  SELECT EXISTS (SELECT 1 FROM nai_saida s
     WHERE s.contato_id = ANY (nai_contato_irmaos(p_contato))
       AND s.tipo = 'texto' AND s.estado <> 'bloqueado'
       AND s.criado_em > now() - interval '24 hours'
       AND s.texto ~* CASE p_qual
             WHEN 'valor'    THEN 'at[ée] que valor'
             WHEN 'regiao'   THEN '(em qual bairro|qual regi[ãa]o|alguma regi[ãa]o|em qual outro)'
             WHEN 'abertura' THEN 'vou fazer um filtro com voc'
             WHEN 'negocio'  THEN 'alugar ou (para )?comprar'
             ELSE '^$' END);
  ```
  Ela sabe que **perguntou** (1x por 24 h), não que ele **respondeu**; na segunda vez a busca segue sem o filtro.

### B3. Turnos em que saiu card ou lista (core, 02–05/10): 38

Fonte: `core_trace` (etapas `imovel_em_jogo`, `atalho`, `classificar`, `transicao`, `buscar`) + `core_saida`. Filtros "conhecidos" = estado gravado no trace da busca, ou estado antes + o que o modelo extraiu no turno. `~` = último estado conhecido (o pré-roteador não grava os filtros no trace).

| turno | hora | quem | mensagem | filtros conhecidos | saiu | faltava | caminho |
|---|---|---|---|---|---|---|---|
| 792 | 02/10 14:10 | P01 | 5717 | NÃO SEI | card 5717 | os 4 | código digitado |
| 807 | 02/10 16:31 | P05 | Vc tem algum apto a venda no parque dez até 450 mil ? | venda, apartamento, 450 mil, parque 10 | lista | — | busca |
| 808–810 | 02/10 16:33–35 | P05 | Manda o Milano… / Milano Parque dez Milano / …código 9005 | idem | lista (3x a mesma) | — | busca |
| 811 | 02/10 16:35 | P05 | 9005 | ~idem | card 9005 | — | código digitado |
| 812 | 02/10 16:37 | P05 | Manda as fotos | ~idem | 11 fotos 9005 | — | foco |
| 818 | 02/10 16:51 | P06 | Apart da morada do sol | locação, apartamento, 7 mil, adrianópolis | lista | — | busca |
| 820 | 02/10 17:32 | P07 | o que voce tem de locação no parque 10… até 5mil preferencia por casa | locação, casa, 5 mil, parque 10 | lista | — | busca |
| 823 | 02/10 18:47 | P08 | Na Ponta Negra Casa até 1 milhão | venda, casa, 1 mi, ponta negra | lista | — | busca |
| 824 | 02/10 18:51 | P08 | Essa do Morada dos Pássaros Tá bom então | ~idem | card + 12 fotos 3210 | — | escolheu da lista |
| 825 | 02/10 20:09 | P09 | Cód 5728 | locação, apartamento, 4 mil, adrianópolis | card + 7 fotos 5728 | — | código digitado |
| 826 | 02/10 20:09 | P09 | Envia pra mim | idem + semi | **lista** | — | busca (ver F3) |
| 833 | 02/10 22:38 | P10 | Tens fotos desse apartamento para me enviar? | tipo | 6 fotos 9007 | finalidade, teto, região | foco |
| 845 | 03/10 07:18 | P13 | Todos apartamento | locação, apartamento, 3 mil, 3 bairros, mobiliado | lista | — | busca |
| 847, 850 | 03/10 07:20–37 | P13 | Se sim manda os dois / …esses dois aí… | idem | lista (a mesma) | — | busca (ver F2) |
| 855 | 03/10 08:59 | P15 | Bom dia me envia fotos do arezzo | locação | card + 12 fotos 5718 | tipo, teto, região | nome de condomínio |
| 861 | 03/10 09:15 | P18 | Todas as opções que tu me passou… | ambos, apartamento, 5 mil, pq laranjeiras | lista | — | busca (modelo falhou: reserva) |
| 869, 871 | 03/10 10:50–52 | P07 | semi mobiliado… / Pode ser em outro bairro | locação, casa, 5 mil, bairros, semi | lista | — | busca |
| 877 | 03/10 14:12 | P23 | Oiiii Me envie por favor | NÃO SEI | card + 12 fotos 3210 | os 4 | citação |
| 881 | 03/10 15:22 | P23 | Tem fotos dos quartos | nenhum | 12 fotos 3210 | os 4 | foco |
| 888 | 03/10 16:41 | P25 | Semi-mobiliado com ar condicionados | locação, casa, 5 mil, alvorada/sta etelvina, semi | lista | — | busca |
| 890 | 03/10 16:47 | P25 | manda cidade nova ou manda o que tiver aí com piscina | locação, casa, 5 mil, cidade nova, semi | card + 12 fotos 5736 | — | busca com 1 resultado |
| 891 | 03/10 16:48 | P25 | tem fotos da piscina? | idem | 12 fotos 5736 | — | foco |
| 892 | 03/10 16:55 | P26 | Apenas com 3 dormitórios | venda, apartamento, 600 mil, cidade nova/ponta negra | lista | — | busca |
| 896 | 03/10 17:24 | P27 | Ponta negra… Morada dos Pássaros, Passaredo… na faixa de seis mil | locação, casa, 6 mil, ponta negra | card + 12 fotos 3210 | — | nome de condomínio |
| 897 | 03/10 17:28 | P27 | Fotos ? Não tem de 6? Máximo 7 mil ? | locação, casa, 7 mil, ponta negra | 12 fotos 3210 | — | foco |
| 899 | 03/10 17:39 | P28 | Oie Pode me enviar esse material | NÃO SEI | card + 10 fotos 5717 | os 4 | citação |
| 903 | 04/10 11:55 | P29 | Manda as fotos e a descrição | locação | 12 fotos 5722 | tipo, teto, região | foco |
| 922 | 04/10 14:08 | P31 | …da Morada dos Pássaros que eu quero… | ambos, casa, 900 mil | card + 12 fotos 3210 | região | nome de condomínio |
| 928 | 04/10 15:18 | P32 | Esse Residencial Conquista Taruma | nenhum | card 5326 (sem fotos) | os 4 | nome de condomínio |
| 934 | 04/10 20:21 | P10 | …você ia enviar fotos de um apartamento no Mosaico | tipo | 6 fotos **9007** | finalidade, teto, região | foco (errado, ver C2) |
| 935 | 04/10 20:48 | P10 | é um apartamento no Mosaico Ponta Negra… uns 250 mil | tipo | card + 5 fotos 5473 | finalidade, teto, região | nome de condomínio |
| 939 | 05/10 08:22 | P33 | você tem alguma casa que aluguel com proposta de compra ? | ambos, casa, 1 mi, flores/parque 10 | lista | — | busca (filtros herdados, ver F4) |
| 941 | 05/10 08:39 | P27 | Envia amiga | ~locação, casa, 7 mil | 12 fotos 3210 | — | foco ("manda aí") |
| 944 | 05/10 08:49 | P27 | Ha mas essa é 9 mil Quero de 7… Já havia te falado isso | ~idem | card + 12 fotos 3210 | — | citação + "quero" |

Nay velha, mesmo recorte: **NÃO SEI** turno a turno (teria que cruzar `nai_turno`, `nai_saida` e `nai_estado_conversa`, que só guarda o estado de agora).

### B4. Perguntou filtro que ele já tinha respondido (core)

22 perguntas de filtro em 145 turnos. Repetição de verdade: **3**.

| turno | o que ele disse antes | o que ela perguntou | por que não enxergou |
|---|---|---|---|
| 843 (P13, 03/10 07:16) | 841: ela pergunta o valor; 843: "Entre 2 e 3" | "Até que valor?" de novo (3ª vez seguida: 841, 842, 843) | **regex e modelo não extraíram**: `_filtro` em FILTRO_TETO usa `valor_em_reais`/`faixa_em_reais`, que não leem "2 e 3" sem "mil"; a Luna devolveu `teto: null`. Só "Entre 2 e 3 mil reais" (844) passou |
| 887 (P25, 03/10 16:40) | 886: ela pergunta a mobília; 887: "pelo menos ar condicionados" | mobília de novo | **regex não casou e modelo não extraiu**: `MOBILIA` só aceita "só (com) ar"; "pelo menos ar condicionados" não entra; `mobilia: null` |
| 921 (P31, 04/10 14:06) | 920: colou o card do Morada dos Pássaros ("Bairro: Ponta Negra", "Venda: R$ 900.000") | 920: "Até que valor?"; 921: "Em qual bairro?" | **o card colado não vira filtro**; além disso em 920 o modelo falhou (`caminho = fallback`, classificador de reserva) |

Perguntas que parecem repetição e não são (o filtro nunca tinha sido respondido): 842 (respondeu a região quando ela perguntou o valor), 902 e 913 (P29, valor perguntado duas vezes sem resposta), 882 (P23 chegou por citação, sem filtro nenhum).
Nay velha: **NÃO SEI** por turno. O desenho dela permite o erro por construção (B2: ela não guarda a resposta; a 267 nasceu de "ela já tinha dito casa e a Nay perguntou casa ou apartamento?").

### B5. Card, lista ou foto antes dos 4 filtros: 11 de 38

| caminho | turnos |
|---|---|
| foco (imóvel de antes) + pedido de foto | 833, 881, 903, 934, 935 (5) — e 855 por nome de condomínio com foco velho |
| citação (marcou o card do grupo) + "me envia" | 877, 899 |
| nome de condomínio que o modelo extraiu | 855, 922, 928 |
| código digitado | 792 |

É o desenho atual: `maquina.py::por_pre` e `pedir_imovel` apresentam o imóvel quando ele é nomeado (código, card, citação, lista, condomínio com 1 oferta) **sem olhar os filtros**. "Busca com 1 resultado" (890) e "escolheu da lista" (824) saíram com os 4 preenchidos. "Manda o que tiver" não é um caminho separado: caiu na busca normal (890).

---

## C. Imóvel errado

### C1. De onde veio o código (core, 21 turnos com card ou foto)

| origem | turnos |
|---|---|
| foco gravado (`core_conversa.foco_codigo`) | 10 |
| código digitado | 3 |
| citação (marcou mensagem) | 3 |
| nome de condomínio (modelo extraiu, 1 oferta) | 3 |
| escolheu da lista pelo nome | 1 |
| busca com 1 resultado | 1 |
| card colado | 0 com envio (1 só com "está disponível") |
| fila de outros imóveis / inferência da conferência | 0 — não existem no core |

Fonte: `core_trace.etapa = 'imovel_em_jogo'` (`saida.origem`) + `core_saida.motivo IN ('card','foto')`.
Nay velha, 7 dias: 88 cards em 65 turnos e 3.166 fotos enviadas; a origem por turno eu **NÃO SEI** sem ler `nai_anotar` turno a turno.

### C2. Os que divergem dos filtros da conversa

"Apontados pelo Tel": **não achei registro** (ver E). Divergências medidas (imóvel enviado x filtros):

1. **P27 e o 3210 (Morada dos Pássaros, locação R$ 9.000) — enviado 4 vezes a quem pediu até 6–7 mil.**
   - 896 "…Morada dos Pássaros, Passaredo… na faixa de seis mil" → o modelo extrai o condomínio; `pedir_imovel`: `len(ev.condominio_codigos) == 1` → `apresentar` **sem comparar com o teto** → card + 12 fotos.
   - 897 "Fotos ? Não tem de 6? Máximo 7 mil ?" → `pergunta_sobre_imovel` + `pede_fotos` → `so_fotos` do foco → 12 fotos de novo.
   - 941 "Envia amiga" (dia seguinte) → pré-roteador: `na_frente and ultima_acao in ("card","fotos") and MANDA` → `fotos` → 12 fotos de novo.
   - 944 "Ha mas essa é 9 mil / Quero de 7 / Já havia te falado isso" marcando o card → `marcou and MANDA.search(t)` ("**quero**" está em `MANDA`) → `so_codigo` com `manda` → card + 12 fotos pela 4ª vez. `_ja_mandei` não barrou: o primeiro envio tinha 39 h (limite de 24 h) e o caminho `fotos` nunca consulta `ja_enviado`.
   - 946: "Amiga do céu Vc virou um robô foi ? Vc já me enviou essas fotos 4x".
2. **P10 e o Mosaico (934):** pediu "fotos de um apartamento no Mosaico" → o modelo não devolveu o condomínio; o contexto ficou no foco velho (9007, Smile Village) → 6 fotos do imóvel errado. No turno seguinte (935) o condomínio foi extraído e saiu o 5473.
3. **P09 (825):** digitou "Cód 5728" (Novo Aleixo) numa conversa com região Adrianópolis. Código digitado ganha de filtro: é o desenho, não erro de escolha.
4. Tipo `casa` x `casa_condominio` (824, 896, 922): o filtro guarda "casa" e o catálogo separa os dois tipos; ele pediu casa e recebeu casa em condomínio que ele mesmo nomeou. Divergência de rótulo.

### C3. Fila de outros imóveis, portão de fotos, prova de pedido

- **`nai_fila_dos_outros_imoveis` ainda adiciona imóvel** na Nay velha (chamada por `nai_enfileirar_resposta`, linha 193). Definição viva: só entra com 2+ imóveis pedidos; corta secretária, oferta, "Jev disse que não pediu", nome de bairro; sem negócio definido só passa código digitado; teto de 3 cards; **foto do segundo imóvel só se `nai_deve_mandar_fotos`** (224). No core essa fila não existe.
- **Portão de fotos:**
  - core: `config/limites.yaml: fotos_junto_do_card: sempre` (conferido na VPS). Quem recebe card recebe fotos; a exceção é `so_status` (só perguntou se está disponível).
  - Nay velha: `nai_deve_mandar_fotos` = "foto só quando pede" (224) + gatilho duplo "manda aí" (267) + "sim" à pergunta das fotos.
- **"Prova de pedido" (card só com código digitado, citação ou card colado): NÃO aplicada.** No core o card sai também por foco, nome de condomínio, opção da lista e busca com 1 resultado (C1: 15 dos 21 envios vieram desses caminhos). Não há função nem teste com esse nome (`grep -rni "prova de pedido" nay tests docs CLAUDE.md` vazio).

### C4. Portão de coerência

**Não existe.** `ls nay/validador/` → `validar.py`, `regras.yaml` (não há `coerencia.py`). `SELECT count(*) FROM core_trace WHERE etapa ILIKE '%coer%' OR setor ILIKE '%coer%'` → **0**. CONFIRMAR / LISTAR / NEGAR: 0 / 0 / 0. O `validar.py` só confere fonte de números, frases proibidas e markdown (1 veto em 145 turnos: `valor_so_de_ferramenta`).

---

## D. Os "status" programados depois de 02/10

### D1. Lista

| nome | onde mora | o que detecta | o que faz | data |
|---|---|---|---|---|
| "manda aí" depois do card (gatilho duplo) | velha: `nai_deve_mandar_fotos` + `nai_imoveis_na_frente` (267). core: `atalhos.py::_do_imovel` + `MANDA` | velha: fala ≤ 40 letras com `manda/envia/encaminha`, sem número, sem tipo, com imóvel na frente (2 h). core: `na_frente and ultima_acao in ("card","fotos") and MANDA` | manda as fotos do imóvel em foco | 02/10 (267 de manhã; core 13:55) |
| só perguntou se está disponível (`so_status`) | core: `maquina.py::apresentar(so_status=True)`, `resolver_imovel.py::pediu_status` | `disponiv\|ainda tem\|ainda (ta\|esta)\|(ta\|esta) valendo\|abert[oa] (para\|pra\|a) visita\|tem como visitar\|da (para\|pra) visitar`, ou card colado/marcado sem pedido | responde "está disponível" e oferece card e fotos; não manda nada | 02/10 19:10 |
| "tá aberto para visita?" vai ao core | banco: `nai_pergunta_se_da_para_visitar` + `nai_core_atende` (276) | palavra de visita sem dia, hora nem pedido de agendar | deixa a porta entregar ao core (senão ficava com a velha) | 02/10 |
| "me envia" / "sim" depois do status | core: `_do_imovel` | `ultima_acao == "status"` e (`MANDA` ou fotos ou `SIM`) | card + fotos | 02/10 19:10 |
| marcou o card e só cumprimentou / "me envia" | core: `atalhos.py::decidir` (`marcou`, `SAUDA`, `MANDA`, `OUTROS`, `PERGUNTA`) | citação resolvida + cumprimento → status; + "manda" sem pergunta e sem "outros" → pedido | status, ou card + fotos | 03/10 10:22 |
| "os dois / as três" da lista | core: `TODOS`, `maquina.py::apresentar_varios`, `acoes/varios.py` | lista de 2 ou 3 na frente + `os dois\|ambos\|os 3…` sem "?" | card + fotos de cada um | 03/10 10:22 |
| opção da lista pelo nome ou pela ordem | core: `resolver_imovel.py::da_lista`, `core_conversa.ultima_lista` | nome do condomínio (palavra ≥ 4 letras, não genérica) ou "o segundo" | trata como o imóvel pedido | 02/10 17:47; lista gravada 03/10 |
| mesma lista não se repete | core: `executar.py::_mesma_lista` | busca daria os mesmos códigos da lista na frente | pergunta "qual deles?"; na 2ª vez escala | 02/10 17:47 |
| não entendi duas vezes | core: `maquina.py::nao_entendi` | `ultima_acao == "esclarecer"` | escala ao Tel | 02/10 15:16 |
| cumprimento nunca é silêncio | core: `saudar`, `texto.cumprimentou` | cortesia com cumprimento | responde a saudação | 02/10 15:22 |
| mobília / "só climatizado" | core: `MOBILIA`, `FILTRO_CLIMATIZADO`, `buscar.py` | locação: pergunta mobília; sem semi e com climatizado, pergunta se interessa | filtro a mais | 02/10 19:10 |
| imóvel saiu do mercado | core: `enviar_imovel.py::fora_do_mercado`; worker recarrega o catálogo na hora | imóvel fora do mercado | avisa e lista o mesmo condomínio e negócio | 03/10 19:34–19:37 |
| visitas do bloco para o Tel | banco: 266 (`nai_agenda_tick`) | visitas marcadas/pendentes do bloco | aviso ao Tel 08:30, 12:00, 18:00 | 02/10 |

### D2. "Manda aí" depois do card = fotos

- **Onde:** core `nay/classificador/atalhos.py::_do_imovel` (última condição); velha `nai_deve_mandar_fotos` (bloco "267: O GATILHO DUPLO").
- **De qual imóvel:** core → `core_conversa.foco_codigo`, **sem prazo** (o foco não vence). Velha → `nai_imoveis_na_frente(contato)`: último card/lista em 2 h.
- **Quantas vezes (core, 02–05/10):** pré-roteador `fotos` disparou 2 vezes; o gatilho duplo de verdade, **1** (941 "Envia amiga"); a outra (812 "Manda as fotos") tem a palavra foto.
- **Imóvel certo?** 812: sim (9005 recém-enviado). 941: **não** — reenviou as fotos do 3210 no dia seguinte a quem tinha escrito "Não tem de 6? Máximo 7 mil?".
- Parente próximo, mesmo regex: `so_codigo` com `manda` por citação (877, 899 certos; 944 errado, por causa de "quero").
- Nay velha: quantas vezes disparou, **NÃO SEI** (o motivo não fica em coluna; teria que ler `nai_anotar` dos turnos).

### D3. Por dentro ou por fora da máquina; teste; conflito

| status | lido pela máquina? | caso de teste | conflito possível |
|---|---|---|---|
| "manda aí" → fotos | por fora e antes: pré-roteador decide; a máquina só executa `so_fotos` | `tests/unit/acoes/test_logica_do_tel.py`, `caso_fotos_so_quando_pede.yaml` | depois de LISTA: não dispara (exige `ultima_acao` card/fotos); mas com foco velho de outro pedido, dispara no imóvel errado (941) |
| `so_status` | dentro (`apresentar`) | `card_colado_sem_pedido_responde_a_situacao.yaml` | com `marcou`: cumprimento em cima do card vira status |
| `marcou` + `MANDA` | por fora (pré-roteador) | `tests/unit/acoes/test_marcou_o_card.py` (o caso "quero de 7" em cima do card não está lá) | "quero de 7" em cima do card = pedido do card (944) |
| `TODOS` | por fora | `tests/unit/acoes/test_marcou_o_card.py`, `test_logica_do_tel.py` | "todos apartamento" é tratado (frase inteira) |
| opção da lista | por fora (`resolver`) | `maelita_escolhe_da_lista_pelo_nome`, `maelita_o_segundo_da_lista` | nome que serve para 2 opções: não resolve |
| mesma lista | depois da máquina (`ferramentas`) | `maelita_mesma_lista_nao_se_repete` | — |
| não entendi 2x | dentro | `nao_entendi_duas_vezes_sobe_ao_tel` | — |
| 276 / 266 / 267 (banco) | fora do core: rodam na porta e na Nay velha | bateria `nai_rodar_casos()` (116/117 em 03/10) | 267 e o `MANDA` do core são duas implementações da mesma regra, com regex e prazo diferentes |

---

## E. Números

**Core, turnos reais, 02/10 14:10 → 05/10 09:03** (`core_turno` com `exec_id` numérico, `core_trace`, `core_saida`):

| | |
|---|---|
| turnos reais | 145 (02/10: 32 · 03/10: 65 · 04/10: 36 · 05/10: 12), 33 pessoas |
| turnos com card | 13 |
| turnos com lista | 17 (+6 com "não encontrei") |
| turnos com fotos | 18 (189 fotos) |
| perguntas de filtro | 22: valor 9 · mobília 4 · finalidade 3 · tipo 3 · região 3 |
| "qual imóvel?" | 11: `qual_deles` 3 · `qual_da_lista` 3 · `pergunta_qual_imovel` 5 |
| confirmação "é este?" | 0 (não existe no core) |
| escalações | 10 pela máquina (assunto geral 5, não entendi 2x 2, visita 2, oferta 1) + 5 por `nao_sei`; 15 avisos ao Tel |
| silêncios | 21 (cortesia 14, mensagem sem texto 5, agradecimento 2) |
| "não entendi" | 10 |
| chamadas de modelo por turno | média 0,92 (0: 26 turnos · 1: 104 · 2: 15) |
| tempo por turno | média 4,2 s; máximo 21,7 s |
| o mesmo imóvel mandado de novo à mesma pessoa | 4 pares 2 vezes, 1 par 4 vezes |

**Nay velha + core, turnos reais de corretor por dia** (`nai_turno`):
```
dia   | turnos | ao core | velha respondeu | fora da lista
28/09 |  221   |    0    |       72        |      89
29/09 |  187   |    0    |       89        |      36
30/09 |  174   |    0    |      116        |      11
01/10 |  125   |    0    |       84        |      12
02/10 |  116   |   31    |       48        |      17
03/10 |  153   |   66    |        9        |      63
04/10 |   53   |   36    |        5        |       4
05/10 |   23   |   12    |        3        |       5   (até 09:30)
```
**Nay velha, 7 dias** (`nai_saida` enviado a corretor): 88 cards em 65 turnos · 3 listas · 3.166 fotos · perguntas: região 20, valor 16, finalidade 9, tipo 7 · confirmações "é esse?" 4 (por regex, aproximado) · 178 avisos ao Tel · 893 peças bloqueadas pela caixa (as maiores: "imovel ja enviado a este corretor nas ultimas 24h" ~454, `tel_assumiu` 125, `repetida` 74, "imovel indisponivel" 73, "tipo errado: ele pediu casa" 47).

**Erros marcados pelo Tel:** **NÃO SEI / não achei registro.** A única tabela parecida é `nai_regra_sugerida` (15 linhas, a última de 27/09, 0 em 7 dias). O que o Tel aponta chega por conversa. Para saber: perguntar a ele, ou criar o registro.

**Custo diário no painel da OpenAI:** **NÃO SEI** (o painel exige login; não entrei). O que o banco guarda: o trace do core só grava custo em `responder_duvida` (US$ 0,0001–0,0005 por dia, 2 a 6 chamadas); o classificador (33 a 97 chamadas por dia desde 02/10) **não grava tokens nem custo**. A Nay velha roda no n8n e `nai_turno.modelo` está nulo nos 1.052 turnos.

---

## F. As 10 situações de erro mais frequentes (core, 02–05/10)

Contagem sobre os 145 turnos. "Previsto" = se o repositório já descreve o conserto (CLAUDE.md, FLUXO.md); `coerencia.py` não existe.

| # | situação | turno real | causa no código | conserto previsto? |
|---|---|---|---|---|
| 1 | **Mesmo imóvel reenviado** (card e fotos 2 a 4 vezes à mesma pessoa; 5 pares) | 896→897→941→944 (3210) | `_ja_mandei` só vale 24 h e só para card; os caminhos `fotos` e `so_fotos` não consultam `ja_enviado`; `core_envio_imovel` guarda só o último envio | FLUXO.md prevê só as 24 h. Não |
| 2 | **Lista repetida** quando ele escolhe pelo nome ou diz "os dois" | 808–810 (Milano), 847/850 | em 02/10 só o código sozinho resolvia; "manda os dois" ia ao modelo como `pedir_imovel` | sim, já commitado (f898b39, 8087a86); não medi depois |
| 3 | **"Envia pra mim" / "manda" depois do card vira busca** | 826 | na versão `a9ddcd8` o gatilho exigia `ultima_acao == "card"`; depois de card + fotos ela vale `"fotos"`, a fala foi ao modelo, que disse `pedir_imovel` → `buscar` | sim: `01c700e` (02/10 19:10) aceita `("card", "fotos")`. A hora em que subiu para a VPS eu NÃO SEI; não medi depois |
| 4 | **Filtros herdados de pedido antigo** | 939 (pediu "casa de aluguel com proposta de compra"; buscou venda até 1 mi em Flores/Parque 10 de outra conversa) | `filtros.zerar()` nunca é chamado; `core_conversa` nunca limpa | FLUXO.md não trata. Não |
| 5 | **Imóvel nomeado ignora o teto/filtro** | 896 (6 mil pedidos, 9 mil enviados), 922 | `pedir_imovel`: condomínio com 1 oferta → `apresentar` direto, sem portão de coerência | não (o portão não existe) |
| 6 | **Foco velho responde pedido novo** | 934 (pediu Mosaico, recebeu fotos do Smile Village), 941 | `resolver()` cai em `foco_codigo`, que não vence; o pedido de foto usa o foco | não |
| 7 | **"Não entendi" para recado, andamento ou escolha** (10 turnos; 2 viraram escalação) | 859 "ainda não deu retorno", 866 "Aguardando um retorno dele", 849 "Os dois", 904 "Tudo é interessante", 947 "Ela achou um" | o modelo devolve `nao_da_para_saber`; não há intenção de "recado/andamento"; `nao_entendi` responde o template | a139051 só limita a 2 vezes. Não |
| 8 | **Pergunta de filtro repetida por resposta não lida** | 843 "Entre 2 e 3", 887 "pelo menos ar condicionados", 921 (card colado) | `_filtro` (regex curta) + modelo não extraem; card colado não preenche filtro | não |
| 9 | **Pergunta simples sobre o imóvel escala** (`nao_sei`, 5 turnos) | 814 "Andar baixo ou médio?", 878 "conseguimos chegar em 850 mil?", 900 "Qual andar?", 942 "Fica na rua…?" | a ficha não tem o dado (andar, endereço) ou é negociação; `responder_duvida` devolve `NAO_SEI` e a máquina escala e cala por 24 h | é o desenho ("se não está, escala") |
| 10 | **Pedido em cima de card marcado mal lido** | 944 ("Quero de 7" = pedido do card), 893 (marcou o 3210 e pediu "casa assim na faixa de 6 mil": perguntou "qual deles?") | `MANDA` contém `quero/queria`; marcar o card + falar de valor diferente não é tratado como "parecido com este" | não |

Fora do core, no mesmo período: 58 dos 300 últimos turnos pararam em "fora da lista de corretores" e 29 em "fora da lista: esperando/perguntar ao Tel" (`so_corretor_da_lista = sim`). Não é erro de código; é a regra ligada, e é o maior motivo de corretor sem resposta.

---

### O que eu não consegui responder

- B3/B4/C1/D2 **da Nay velha, turno a turno** (28/09–02/10): só agregados. Olhar `nai_anotar` + `nai_saida` por turno.
- **Erros apontados pelo Tel**: não há tabela; perguntar a ele.
- **Custo no painel da OpenAI**: precisa de login no painel.
- **Data da foto interna** usada por `nai_foto_diferenca()`.
- Efeito dos commits de 02/10 à noite e 03/10 de manhã **medido depois deles** (situações 2 e 3): a amostra posterior é pequena e eu não separei antes/depois.
