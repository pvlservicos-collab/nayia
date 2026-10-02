# Como ligar o Grok a um webhook de um sistema nosso

Tutorial geral, escrito em 02/10/2026 depois de ligar três webhooks ao Grok (aviso
ao Tel, consulta de imóveis, cadastro de imóveis). Vale para qualquer webhook novo
que more nos nossos servidores.

## 1. A regra que vale sempre: a rede do Grok corta HTTPS para a gente

O computador do Grok sai para a internet pela Cloudflare (WARP + Gateway). Esse
filtro **corta HTTPS para os nossos servidores**: a conexão abre na porta 443 e cai
sem trocar um byte. Foi medido dos dois lados, mais de uma vez. Não é o seu PC e não
é a VPS: é a rede dele, e de dentro dela não tem conserto.

Há três caminhos. **Pergunte ao bot qual ele aceita antes de escrever o prompt** —
cada bot decide, e eles não decidem igual:

1. **HTTPS pelo seu computador** (o preferido). O bot roda a chamada a partir do seu
   PC, que está conectado ao app e chega ao servidor sem bloqueio (testado: do seu
   PC o HTTPS com o token responde). É HTTPS normal com `Authorization: Bearer`,
   sem nada especial. Custo: o seu PC tem de estar ligado e conectado, e ele pede a
   sua aprovação no começo.
2. **Pedir ao suporte do Grok Bot para liberar o domínio** na rede dele. É o
   conserto de verdade: depois disso o HTTPS normal funciona de qualquer lugar. Peça
   em paralelo, mesmo usando o caminho 1.
3. **Porta 80 com o pedido lacrado** (cifrado e assinado com o token, que nunca
   viaja). Passa pelo filtro da rede dele — e é exatamente por isso que **um bot pode
   se recusar a usar**: é contornar o bloqueio da própria rede. O bot do aviso ao Tel
   aceitou em 01/10 e manda por aí desde então; o da consulta de imóveis recusou em
   02/10 ("serve pra passar por fora do bloqueio de rede do meu computador, e isso eu
   não faço"). Recusa de bot não se discute: usa-se o caminho 1 ou o 2.

Consequências práticas:

- Todo webhook nosso aceita os dois jeitos: HTTPS com `Authorization: Bearer` e
  porta 80 com o pedido lacrado. O servidor não muda conforme o caminho escolhido.
- O prompt do bot traz **um caminho só**, o que ele aceitou. Prompt com dois
  caminhos faz o bot tentar o errado primeiro e voltar reclamando.

## 2. O que decidir antes de pedir o webhook

Cinco perguntas. Com elas respondidas, o webhook sai certo de primeira.

1. **Quem chama?** Um bot = um webhook = um token. Se dois bots diferentes vão
   chamar, são dois webhooks separados, mesmo que pareçam "a mesma coisa": token,
   limite, rota e prompt de cada um. O token de um não pode abrir o do outro.
2. **O que o bot manda?** A lista de campos, quais são obrigatórios, e um exemplo
   de verdade. Se o próprio bot já escreveu o formato que quer, mande o texto dele.
3. **O que volta?** O que o bot precisa ler para decidir o próximo passo.
4. **O webhook só lê, ou grava?** Se grava, o que protege contra bobagem do bot:
   aprovação humana, limite por hora, recusa quando falta algo essencial. Instrução
   no prompt o modelo esquece; a recusa no servidor não.
5. **O que acontece se o bot mandar duas vezes?** Tem de dar o mesmo resultado, não
   duplicar.

## 3. O que pedir ao Claude

Uma frase basta, se ela tiver as cinco respostas:

> Cria um webhook para o Grok [fazer X]. Quem chama é o bot [nome]. Ele manda
> [campos]. Volta [resposta]. [Só lê / grava em Y, com aprovação de gente]. Me dá o
> prompt pronto com o token.

O que tem de vir de volta, sempre:

- a **URL** e o **token** (um por webhook);
- a **função pronta** de chamada pela porta 80;
- um **teste de conexão que não grava nada**;
- o **prompt** para colar no bot, com cada campo explicado;
- a prova de que foi **testado de fora** (de outra máquina, pela internet).

## 4. O molde do webhook (o que existe por baixo)

Para quem for mexer no código. Os três webhooks seguem o mesmo molde:

| peça | onde | o que faz |
|---|---|---|
| rota | `crm/src/app/api/public/<nome>/route.ts` | recebe, confere quem é, repassa ao banco |
| quem pode entrar | `crm/src/lib/botDeImoveis.ts` (`pedidoDoBot`) | Bearer por HTTPS; pedido lacrado pela porta 80; limite por minuto; um token por webhook |
| o lacre | `crm/src/lib/avisoLacrado.ts` | abre o pedido cifrado e confere a assinatura |
| a regra | função no banco, `SECURITY DEFINER`, com `GRANT` só para `nay_disparo` | faz o trabalho e devolve JSON |
| porta 80 | `/docker/traefik/dynamic/<nome>.yml` (cópia em `scripts/servidor/`) | deixa passar só o POST daquela rota; prioridade 3000000000 |
| token | `/docker/crm/app/.env`, uma variável por webhook | fora do git |

Regras que custaram erro para aprender:

- **Resposta de erro nunca vazia.** Sempre JSON com `ok: false` e `erro`. Resposta
  vazia o bot lê como "não achei" ou "deu certo".
- **A regra essencial fica no banco**, não só no prompt (ex.: sem autorização do
  proprietário o cadastro é recusado).
- **Dado pessoal em schema `privado`**, nunca no `public`: a `/api/tabelas` do site
  lê o `public` inteiro sem senha.
- **Ensaiar com o papel certo**: `SET LOCAL ROLE nay_site_escrita` (ou `nay_disparo`)
  e ROLLBACK. Foi assim que apareceu a permissão que faltava.
- **Testar a matriz cruzada**: o token de um webhook tem de dar 401 no outro.

## 5. O prompt para colar no Grok (molde)

Troque o que está entre `<< >>`. A ordem importa: conexão primeiro, campos depois.

O bloco CONEXÃO muda conforme o caminho que o bot aceitou (seção 1). Para o caminho
1 (HTTPS pelo seu computador), o bloco inteiro é este, e os itens 1) e 5) do molde
abaixo saem:

```
CONEXÃO
A rede do seu computador não completa HTTPS para o servidor da Imob Easy. Rode as
chamadas A PARTIR DO COMPUTADOR DO PEDRO, que está conectado a você e chega lá:
  POST https://<<host>>/api/public/<<rota>>
  Headers: Authorization: Bearer <<token deste webhook>>
           Content-Type: application/json
  Corpo: o JSON descrito abaixo.
Se o computador do Pedro estiver desligado ou desconectado, pare e avise o Pedro no
chat. Não tente outro caminho.
```

O molde completo, na variante da porta 80 (caminho 3, só para o bot que aceitar):

```
VOCÊ <<o que o bot faz, em uma linha>>.

CONEXÃO — LEIA ANTES DE QUALQUER CHAMADA
A sua rede sai pela Cloudflare (WARP + Gateway), que corta HTTPS para o servidor da
Imob Easy. Portanto:
- NÃO use https://<<host>>. Não tente de novo, não troque de versão de TLS.
- Use SEMPRE http://<<host>> (porta 80) com o PEDIDO LACRADO, pela função abaixo.
- NÃO mande o header Authorization pela porta 80: ele é recusado.

1) DEFINA A FUNÇÃO (uma vez por sessão):

<<nome_da_funcao>>() {  # uso: <<nome_da_funcao>> <arquivo.json>
  TOKEN="<<token deste webhook>>"
  H=$(date +%s)
  C=$(openssl enc -aes-256-cbc -pbkdf2 -iter 100000 -md sha256 -salt -pass "pass:$TOKEN" -base64 -A < "$1")
  A=$(printf '%s' "$H.$C" | openssl dgst -sha256 -hmac "$TOKEN" | sed 's/^.* //')
  printf '{"hora":%s,"cifrado":"%s","assinatura":"%s"}' "$H" "$C" "$A" > /tmp/pedido.json
  curl -s -m 60 -X POST "http://<<host>>/api/public/<<rota>>" -H "Content-Type: application/json" --data-binary @/tmp/pedido.json
}

2) TESTE A CONEXÃO AGORA:
   <<um pedido que não grava nada>>
   Resposta certa: <<o que tem de voltar>>. Se veio isso, diga ao Pedro "conexão OK".

3) CAMPOS — COMO ENVIAR CADA UM
   <<campo>>   <<tipo>>. <<o que é>>. Ex.: <<exemplo>>
   ...
   O que não souber, mande null. NUNCA invente valor.

4) O QUE VOLTA
   Sucesso: <<o JSON e como ler cada campo>>
   Recusa:  <<cada código de erro e o que fazer>>
   SÓ É SUCESSO a resposta que for JSON com <<"ok": true>>. Qualquer outra coisa é
   falha: tente de novo em 1 minuto, até 3 vezes; se continuar, avise o Pedro no chat.

5) SE DER ERRO DE CONEXÃO
   "assinatura não confere"    -> token ou arquivo errado; confira a função.
   "hora fora da janela"       -> relógio da máquina errado (tolerância: 5 min).
   "pedido repetido"           -> cada pedido vale uma vez; chame a função de novo.
   HTTP 429                    -> espere 1 minuto.
   openssl ou curl não existem -> pare e avise o Pedro no chat.

<<as regras do negócio: quando chamar, quando NÃO chamar, e quando lembrar o Pedro>>
```

## 6. Como saber que chegou

1. O bot roda o **teste de conexão** do prompt e diz o que voltou.
2. Se ele disser que não chegou, **não adivinhe**: peça ao Claude para "ligar a
   escuta" no servidor e mande o bot tentar de novo. A escuta mostra de que IP veio,
   em que porta bateu e se algum dado chegou.
3. O que cada resultado quer dizer:

| o que a escuta mostra | o que é |
|---|---|
| conexão na 443 vinda de IP da Cloudflare, sem dados, fecha em segundos | o bot tentou HTTPS: mande usar a função da porta 80 |
| nada chegou | o bot nem tentou, ou errou o endereço |
| pedido na 80 e resposta 401 "assinatura não confere" | token errado no prompt, ou o bot mexeu na função |
| pedido na 80 e resposta 401 "hora fora da janela" | relógio do bot errado |
| pedido na 80 e resposta 200 | funcionou |

Para saber se o problema é o seu PC: abra o endereço `https://` no navegador. Se
abrir, não é o seu PC.

## 7. Trocar um token

Se um token vazar: editar a variável no `/docker/crm/app/.env`, subir o CRM e colar
o token novo no prompt daquele bot. Os outros webhooks não são afetados, porque cada
um tem o seu.

## 8. Os webhooks que já existem

| webhook | rota | token (.env do CRM) | documento |
|---|---|---|---|
| aviso ao Tel | `/api/public/aviso-ao-tel` | `AVISO_TEL_CHAVE` | cabeçalho de `crm/src/app/api/public/aviso-ao-tel/route.ts` |
| consulta de imóveis | `/api/public/imovel-consulta` e `/vincular` | `BOT_IMOVEIS_CHAVE` | `webhook-consulta.md` |
| cadastro de imóveis | `/api/public/imovel-cadastro` | `BOT_CADASTRO_CHAVE` | `webhook-cadastro.md` |
