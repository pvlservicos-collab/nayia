# API de ingestão de leads

Entrada de leads das fontes externas (Agenda Ascensão, Site Evento). Cada fonte
vira uma aba na tela **Leads** do CRM.

Este documento é o que se manda pra quem vai configurar o envio do outro lado.

---

## Webhook ou API?

São a mesma coisa vista de pontas diferentes. **API** é o endereço que fica
esperando; **webhook** é o site chamar esse endereço sozinho quando alguém envia
o formulário. O que está descrito aqui já é o alvo de um webhook — não existe uma
segunda coisa pra construir.

O que muda é a **forma**, porque plugin de formulário de WordPress tem limitação
que um integrador não tem. Por isso existem duas maneiras de chamar:

| | Para quem | Endereço |
| --- | --- | --- |
| **Webhook** | formulário do WordPress (WPForms, Elementor, Fluent Forms, CF7) | `POST /api/ingest/leads/{source}` |
| **API** | sistema que você controla (o app da Agenda, n8n, script) | `POST /api/ingest/leads` |

A diferença é só onde vai o `source` — na URL ou no corpo. Daí pra frente é o
mesmo código, o mesmo log e o mesmo funil.

### Modo webhook (WordPress)

Três coisas que os plugins costumam não conseguir fazer, e que o endpoint aceita
por isso:

1. **Cabeçalho customizado** — muitos não têm campo pra `Authorization`. Então a
   chave também vale na URL: `?key=atl_...`
2. **Corpo em JSON** — muitos postam o formulário cru. `application/x-www-form-urlencoded`
   e `multipart/form-data` são aceitos junto com JSON. O Elementor Pro manda cada
   campo como `form_fields[nome]`; a notação de colchete é achatada automaticamente.
3. **Nome dos campos** — o nome é o que o autor do formulário escolheu. São
   reconhecidos automaticamente:

   | Vira | Nomes aceitos |
   | --- | --- |
   | `nome` | nome, name, nome completo, full name, your-name, seu nome, first_name |
   | `email` | email, e-mail, mail, your-email, seu email |
   | `whatsapp` | whatsapp, whats, telefone, phone, celular, tel, fone, número, your-phone |
   | `instagram` | instagram, insta, ig |
   | `id` | id, lead_id, external_id |

   Maiúscula, acento, espaço, hífen e underscore são ignorados na comparação —
   "Seu Nome", "seu_nome" e "SEU-NOME" caem todos em `nome`.

**É só colar isto no campo "Webhook URL" do plugin:**

```
https://titacrm.vercel.app/api/ingest/leads/site_evento?key=SUA_CHAVE
```

E mapear os campos do formulário para `nome`, `email` e `whatsapp` (ou deixar os
nomes que o plugin já usa, se estiverem na tabela acima).

> Se o plugin **conseguir** mandar cabeçalho, prefira `Authorization: Bearer`.
> Chave em query string aparece em log de servidor e em histórico de navegador.

---

## Endpoint

```
POST https://titacrm.vercel.app/api/ingest/leads            (source no corpo)
POST https://titacrm.vercel.app/api/ingest/leads/{source}   (source na URL)
```

A URL exata aparece pronta pra copiar na tela **Leads → Como enviar leads** (ela
usa o domínio de onde o CRM está aberto, então nunca fica desatualizada).

### Cabeçalhos

```
Authorization: Bearer atl_...
Content-Type: application/json
```

### Testar a credencial

Antes de mandar dado de verdade, um `GET` no mesmo endereço confirma se a chave
está válida:

```bash
curl https://titacrm.vercel.app/api/ingest/leads -H "Authorization: Bearer SUA_CHAVE"
```

```json
{ "data": { "ok": true, "organization_id": "…", "sources": ["agenda_ascensao", "site_evento"] } }
```

---

## Chave de API

Gerada em **Leads → Como enviar leads → Gerar nova chave** (ou em Configurações →
Organização, que é a mesma tabela de tokens).

- Começa com `atl_`.
- O banco guarda só o SHA-256 — **a chave em claro aparece uma única vez**, na
  hora em que é criada. Se perder, gere outra e revogue a antiga.
- Revogar é imediato: a chave revogada passa a responder `401`.
- A organização é deduzida da chave, então o corpo nunca informa organização.

Também dá pra criar por linha de comando (útil antes do primeiro login):

```bash
node scripts/create-api-token.mjs "Agenda Ascensão"
```

---

## Corpo da requisição

Corpo achatado: `source` mais os campos daquela fonte no mesmo nível.
O campo **`source` é obrigatório em toda requisição** e é o que decide em qual
aba o lead cai.

### `source: "site_evento"` — Site Evento

| Campo      | Obrigatório | Formato                                              |
| ---------- | ----------- | ---------------------------------------------------- |
| `nome`     | sim         | texto                                                 |
| `whatsapp` | sim         | telefone; pode mandar com máscara, é normalizado pra só dígitos |
| `email`    | não         | texto                                                 |

```json
{
  "source": "site_evento",
  "nome": "João Souza",
  "email": "joao@exemplo.com",
  "whatsapp": "5511912345678"
}
```

### `source: "agenda_ascensao"` — Agenda Ascensão

**Contato e perfil**

| Campo          | Obrigatório | Formato                                                 |
| -------------- | ----------- | ------------------------------------------------------- |
| `id`           | sim         | id numérico do lead na origem — é a chave de deduplicação |
| `nome`         | sim         | texto                                                    |
| `whatsapp`     | sim         | DDI+DDD+número; máscara é aceita e removida              |
| `email`        | não         | texto (hoje sempre vazio; string vazia vira campo em branco) |
| `instagram`    | não         | `@handle`, `handle` ou URL completa — normalizado pra `@handle` |
| `area`         | não         | `Empresário` · `Profissional Autônomo` · `CLT` · `Outro` |
| `aumento`      | não         | `Mais de R$50.000/mês` · `R$25.000-R$50.000/mês` · `R$10.000-R$25.000/mês` · `R$1.000-R$10.000/mês` · `Menos de R$1.000/mês` |
| `investimento` | não         | `Mais de R$50.000` · `R$31.000 à R$50.000` · `R$16.000 à R$30.000` · `R$5.000 à R$15.000` · `Até R$4.000` · `Não fiz esse tipo de investimento` |
| `criado_em`    | não         | data/hora ISO 8601                                       |

> Os valores de `area`, `aumento` e `investimento` **não são recusados** se
> vierem fora da lista — o formulário pode mudar antes do CRM. A lista existe
> pra tela saber exibir e filtrar.

**`agenda`** — objeto com o quiz e a agenda montada

| Campo          | Formato                                                    |
| -------------- | ---------------------------------------------------------- |
| `agenda.phase` | `"done"` = quiz completo com agenda pronta · `"w1"` = parou no meio |
| `agenda.uid`   | contador interno de próximo id de bloco                     |
| `agenda.a1`    | objeto com as respostas do quiz (tabela abaixo)             |
| `agenda.real`  | lista de blocos da agenda montada                           |

**`agenda.a1`** — respostas do quiz

| Campo | Significado |
| ----- | ----------- |
| `bed` / `wake` | horário que vai dormir / que acorda |
| `ws` / `we` | início / fim do expediente |
| `wdays` | dias que trabalha (0=seg … 6=dom) |
| `commute` | deslocamento até o trabalho, por trecho, em minutos (0 = trabalha em casa) |
| `meetAM` / `meetPM` / `meetEve` | minutos em reunião de manhã / à tarde / à noite |
| `bfT` / `bfD` | café da manhã: horário / duração |
| `lunchT` / `lunchD` | almoço: horário / duração |
| `dinT` / `dinD` | jantar: horário / duração |
| `train` | se treina atualmente (true/false) |
| `trainDays` | dias de treino |
| `trainT` / `trainD` | treino: horário / duração |
| `trainCom` | deslocamento até o treino, por trecho |
| `ppl` | se tem momentos fixos com pessoas importantes (true/false) |
| `pplWkDays` / `pplWkT` / `pplWkD` | dias / horário / duração desses momentos na semana |
| `pplWeDays` / `pplWeT` / `pplWeD` | idem no fim de semana |
| `vazAM` / `vazPM` | minutos de procrastinação de manhã / à tarde |
| `vazAMp` / `vazPMp` | se a procrastinação é no `começo` ou no `fim` do período |

**`agenda.real[]`** — cada bloco da agenda

| Campo | Significado |
| ----- | ----------- |
| `id`  | id do bloco (não confundir com o `id` do lead) |
| `t`   | título do bloco |
| `s`   | início, em minutos desde 00:00 |
| `d`   | duração em minutos |
| `day` | dia da semana (0=seg … 6=dom) |
| `c`   | categoria (abaixo) |

Categorias (`c`):

| Valor    | Significado |
| -------- | ----------- |
| `f1`     | Farol 1 — trabalho / progresso financeiro |
| `f2`     | Farol 2 — compromissos com outras pessoas (reuniões, calls) |
| `f3`     | Farol 3 — rotina saudável (alimentação, treino, lazer, pessoas, espiritual) |
| `sono`   | sono |
| `desvio` | necessário, mas fora dos Faróis (deslocamento, burocracia) |
| `vaz`    | procrastinação |

**Exemplo completo**

```json
{
  "source": "agenda_ascensao",
  "id": 1234,
  "nome": "Maria Silva",
  "whatsapp": "5511987654321",
  "email": "",
  "instagram": "@mariasilva",
  "area": "Empresário",
  "aumento": "R$10.000-R$25.000/mês",
  "investimento": "Até R$4.000",
  "criado_em": "2026-09-07T14:32:00-03:00",
  "agenda": {
    "uid": 87,
    "phase": "done",
    "a1": {
      "bed": "23:30", "wake": "06:30", "ws": "09:00", "we": "18:00",
      "wdays": [0, 1, 2, 3, 4], "commute": 25,
      "meetAM": 60, "meetPM": 90, "meetEve": 0,
      "bfT": "07:00", "bfD": 30,
      "lunchT": "12:30", "lunchD": 60,
      "dinT": "20:00", "dinD": 45,
      "train": true, "trainDays": [0, 2, 4],
      "trainT": "07:30", "trainD": 60, "trainCom": 10,
      "ppl": true,
      "pplWkDays": [3], "pplWkT": "21:00", "pplWkD": 60,
      "pplWeDays": [5, 6], "pplWeT": "15:00", "pplWeD": 180,
      "vazAM": 30, "vazAMp": "começo",
      "vazPM": 45, "vazPMp": "fim"
    },
    "real": [
      { "id": 1, "t": "Dormir",     "s": 0,   "d": 390, "c": "sono", "day": 0 },
      { "id": 2, "t": "Treino",     "s": 450, "d": 60,  "c": "f3",   "day": 0 },
      { "id": 3, "t": "Expediente", "s": 540, "d": 540, "c": "f1",   "day": 0 }
    ]
  }
}
```

---

## Respostas

### `200` — recebido

```json
{
  "data": {
    "id": "9f1c…",
    "source": "agenda_ascensao",
    "external_id": "1234",
    "lead_id": "3ab7…"
  }
}
```

`lead_id` é o lead correspondente no CRM (ver "O que acontece" abaixo). Pode vir
`null` se a criação do lead falhar — o registro no log é gravado do mesmo jeito.

### `400` — corpo inválido

```json
{ "error": "Campos obrigatórios ausentes para a fonte \"agenda_ascensao\": whatsapp." }
```
```json
{ "error": "Fonte desconhecida: \"agenda\". Valores aceitos em \"source\": agenda_ascensao, site_evento." }
```

### `401` — credencial

```json
{ "error": "Token de API inválido ou revogado." }
```

---

## O que acontece com o lead recebido

1. **Vira uma linha no log** (`lead_source_submissions`), que é o que a aba da
   tela Leads mostra. Isso sempre acontece.
2. **Vira/encontra um lead no CRM**, colocado na primeira etapa do pipeline, com
   os campos da fonte em `custom_attributes`. Se já existe um lead com o mesmo
   telefone, ele é reaproveitado em vez de duplicar.

O passo 2 é best-effort: se falhar, a requisição ainda responde `200` e o dado
recebido não se perde.

## Reenvio do mesmo lead

Reenviar **atualiza a linha existente em vez de criar outra**:

- **Agenda Ascensão** — identificado pelo `id`. É o caso real de quem começa o
  quiz (`phase: "w1"`), sai, e depois termina (`phase: "done"`): manda de novo
  com o mesmo `id` e a linha é atualizada com a agenda montada.
- **Site Evento** — identificado pelo `whatsapp`, já que o site não manda id
  próprio. Quem preenche o formulário duas vezes continua sendo um lead só.

`received_at` guarda quando o lead apareceu pela primeira vez; `updated_at`,
quando mudou pela última.

---

## O que o CRM faz sozinho quando o lead entra

Além de gravar o log e criar o lead, a entrada dispara o **funil de atendimento**
da fonte, se ele estiver ativo:

```
lead entra  →  [Contactado por IA]  →  mensagem de abertura
                                              ↓
                                   respondeu em 15 minutos?
                        sim ↙                              ↘ não
          [Atendimento por humano]              [Em follow up] → mensagem de follow-up
```

As colunas entre colchetes são as do Kanban — o lead anda sozinho entre elas.
Os dois funis (`Atendimento Site Ascensão` e `Atendimento Agenda Ascensão`), os
textos das mensagens e os 15 minutos são editáveis em **Funil de Mensagens**.

O funil só dispara para lead **novo**. Reenviar o mesmo lead (o quiz que virou
`done`) atualiza a linha sem remandar a mensagem de boas-vindas.

### Criar essa configuração

Uma vez, depois de aplicar as migrations:

```bash
curl -X POST https://titacrm.vercel.app/api/setup/atendimento -H "Authorization: Bearer SUA_CHAVE"
```

Cria o pipeline `Atendimento`, as quatro colunas e os dois funis. É idempotente:
rodar de novo cria só o que faltar e **não sobrescreve** o que você já editou.

Os funis nascem **desligados** de propósito — ativar dispara mensagem pra cliente
de verdade, então quem liga é uma pessoa, na tela, depois de ler os textos.

---

## Adicionar uma fonte nova

Registrar em [`src/lib/leadSources.ts`](../src/lib/leadSources.ts): a chave, o
rótulo, os campos obrigatórios, as colunas da planilha e como normalizar o corpo.
A aba e a validação saem disso. **Não precisa de migration** — os campos
específicos de cada fonte vão pra coluna `payload` (jsonb).

Um `source` fora da lista é recusado com `400` de propósito: assim um erro de
digitação aparece na primeira requisição, em vez de virar uma aba fantasma.
