# Chat da OLX dentro do CRM

Pedro, 08/10/2026: "quero implementar o chat da olx, serão 2 contas, esse chat olx
vai ser 2 abas, aba Conta proprietários e aba Conta corretores ... basicamente
quero responder o chat da olx pelo meu crm, enviar e receber mensagens pelo crm".

Este arquivo guarda (1) a documentação da OLX que o Pedro colou, (2) o que ela não
trazia e foi conferido em developers.olx.com.br em 08/10/2026, e (3) como o nosso
lado está montado.

## 1. O que a OLX oferece

### 1.1 Registro do aplicativo (uma vez)

Pede-se por e-mail a `suporteintegrador@olxbr.com`: nome do cliente, nome e descrição
da aplicação, website, telefone, e-mail e as **URIs de redirecionamento** (de 1 a 3).
A OLX devolve `client_id` e `client_secret`.

A nossa URI de redirecionamento é **`https://crm.imobeasy.online/api/olx/oauth`**.

### 1.2 Autorização da conta (OAuth)

O dono da conta abre no navegador, logado na OLX **com a conta que vai ser ligada**:

```
https://auth.olx.com.br/oauth?client_id=<client_id>&redirect_uri=<uri cadastrada>&response_type=code&scope=<escopos>&state=<livre>
```

| parâmetro | valor | obrigatório |
|---|---|---|
| `response_type` | `code` | sim |
| `client_id` | o do registro | sim |
| `redirect_uri` | uma das URIs cadastradas | sim, se houver mais de uma |
| `scope` | `basic_user_info`, `autoupload`, `chat` (separados por espaço) | sim |
| `state` | qualquer texto; volta igual | não |

Para o chat, o token precisa do escopo **`chat`**.

A resposta chega na `redirect_uri`: `?code=<código>&state=<o mesmo>`. O código vale
10 minutos e uma vez só.

### 1.3 Trocar o código pelo token

```
POST https://auth.olx.com.br/oauth/token
Content-Type: application/x-www-form-urlencoded

code=<código>&client_id=<client_id>&client_secret=<client_secret>&redirect_uri=<a mesma>&grant_type=authorization_code
```

Resposta (200): `{ "access_token": "...", "token_type": "Bearer" }`. A documentação
não fala em validade do token nem em `refresh_token`.

Dados da conta (escopo `basic_user_info`): `POST https://apps.olx.com.br/oauth_api/basic_user_info`
com `{ "access_token": "..." }`.

### 1.4 Ligar e desligar o webhook do chat

```
POST   https://apps.olx.com.br/autoservice/v1/chat      Authorization: Bearer <token>
Body:  { "webhook": "<a nossa url>" }
  201 ativado (primeira vez) · 200 atualizado · 401 token inválido · 500 erro interno

DELETE https://apps.olx.com.br/autoservice/v1/chat      Authorization: Bearer <token>
  200 desativado · 401 token inválido · 400 conta não existe · 500 erro interno
```

A OLX chama o nosso endereço a partir do IP **54.162.151.93**.

### 1.5 Mensagem que chega (a OLX chama o nosso webhook)

"Quando um comprador submeter uma mensagem no chat em um anúncio cuja conta do
vendedor possuir um webhook configurado":

```json
{
  "chatId": "{msg.publicId}",
  "message": "{msg.message}",
  "senderType": "buyer",
  "email": "{get_email(msg.senderAccountId)}",
  "name": "{get_name(msg.senderAccountId)}",
  "phone": "{get_phone(msg.senderAccountId)}",
  "messageTimestamp": "{msg.messageTimestamp}",
  "messageId": "{msg.messageId}",
  "origin": "{msg.origin}",
  "listId": "{msg.listId}"
}
```

| campo | tipo | o que é |
|---|---|---|
| `chatId` | texto | identificador do chat |
| `message` | texto | o que o remetente escreveu |
| `senderType` | texto | `account` (mensagem orgânica) ou `system` (enviada por um sistema) |
| `email`, `name`, `phone` | texto | do comprador |
| `messageTimestamp` | data/hora | `yyyy-MM-ddThh24:mm:ss.ms` (sem fuso) |
| `messageId` | texto | identificador da mensagem |
| `origin` | texto | `buyer` (comprador) ou `seller` (vendedor) |
| `listId` | texto | identificador do anúncio |

### 1.6 Mandar mensagem (não estava no que o Pedro colou; conferido no site)

```
POST https://apps.olx.com.br/autoservice/v1/chat/send     Authorization: Bearer <token>
Body: { "textMessage": "...", "messageId": "<um id nosso>", "chatId": "<o do chat>" }
  200 enviada · 401 token inválido · 400 body inválido / conta sem integração / IP · 500 erro interno
```

### 1.7 Notificações gerais (NÃO usamos: "quero por enquanto só o endpoint de chat")

Modelo de toda notificação dos webhooks da OLX (ex.: `AD_STATUS`):

```json
{
  "id": "<identificador único>", "topic": "<tipo>", "created_at": "<data e hora>",
  "data": { "...": "conforme o tipo", "actions": { "view": "https://www.olx.com.br/vi/1223432423.htm" } }
}
```

## 2. O limite que importa

O webhook dispara **nos anúncios da própria conta** (a conta é a VENDEDORA e quem
escreve é o comprador). A documentação não cobre a conversa em que a nossa conta é
a COMPRADORA — que é o caso da abordagem da captação, em que a Nay escreve no
anúncio de um proprietário. Só o primeiro teste de verdade diz se essas conversas
chegam; pela documentação, não chegam.

## 3. O nosso lado

| peça | onde |
|---|---|
| conta, segredo do webhook e token | `privado.olx_conta` (banco da Nay; migração 314) |
| conversas e mensagens | `privado.olx_chat`, `privado.olx_chat_mensagem` |
| recebe da OLX | `POST /api/public/olx-chat/<conta>/<segredo>` → `crm_olx_chat_receber` |
| começa a autorização | `GET /api/olx/conectar?conta=<conta>` (logado no CRM) |
| volta da OLX com o código | `GET /api/olx/oauth` → troca pelo token, grava e liga o webhook |
| lista e conversa | `GET /api/olx/chat?conta=` · `GET /api/olx/chat/<id>?conta=` |
| responder | `POST /api/olx/chat/<id>` → `/autoservice/v1/chat/send` |
| tela | `crm/src/components/Chat/ChatOlxContas.tsx` (aba Chat OLX, uma aba por conta) |

- As contas são `proprietarios` e `corretores`. Cada uma tem o seu token e o seu
  endereço de webhook, com um segredo no caminho: a OLX não assina a chamada, então
  quem prova que é ela é o segredo (e o IP fica gravado em cada mensagem).
- `client_id` e `client_secret` ficam no `.env` do CRM: `OLX_CLIENT_ID` e
  `OLX_CLIENT_SECRET`. Sem eles o botão "Conectar" avisa o que falta.
- A mesma mensagem não entra duas vezes (`messageId` é único por conversa). O que
  nós mandamos é gravado com o `messageId` que geramos; se a OLX devolver o eco, ele
  cai na mesma linha.
- A hora mostrada é a em que a mensagem CHEGOU a nós: o `messageTimestamp` da OLX
  vem sem fuso e fica guardado como veio.
- A lista de anúncios que o bot consultou (migração 309) continua na aba, no botão
  "Consultas do bot".
