# Webhook de CONSULTA de imóveis (bot da OLX)

Este webhook é de **um bot só**: o que acha um anúncio na OLX e pergunta o que
fazer com ele. Desde 08/10/2026 (migração 309) **quem decide é o nosso banco**; o
bot só obedece:

- `acao: "fechar"` — não manda nada e fecha o anúncio;
- `acao: "abordar"` — manda ao anunciante o texto que veio em `mensagem`.

Ele **não cadastra nada**. O cadastro é outro webhook, de outro bot, com outro
token — ver `webhook-cadastro.md`.

## O prompt do bot

```
WEBHOOK DE CONSULTA DE IMÓVEIS — Imob Easy

O QUE É
Antes de falar com qualquer anunciante da OLX, você pergunta ao nosso sistema o
que fazer com o anúncio. Você NÃO decide nada: manda os dados do anúncio e
obedece o campo "acao" da resposta.
  "acao": "fechar"   -> feche o anúncio e vá para o próximo. NÃO mande mensagem.
  "acao": "abordar"  -> mande ao anunciante, pelo chat da OLX, o texto que veio
                        em "mensagem". Exatamente como veio, uma vez só.

REGRAS QUE NÃO TÊM EXCEÇÃO
1. Consulte ANTES de escrever qualquer coisa para o anunciante. Um anúncio = uma
   consulta.
2. Só mande mensagem quando a resposta trouxer "acao": "abordar". Sem essa
   resposta, não mande nada.
3. O texto é o de "mensagem", inteiro e sem mudar uma palavra. Não acrescente
   saudação, assinatura, emoji nem explicação. Não escreva um texto seu.
4. Uma mensagem por anúncio. Se você já mandou, não mande de novo.
5. Se a resposta não for um JSON com "consulta_ok": true, é FALHA: não mande
   mensagem. Tente consultar de novo em 1 minuto, até 3 vezes; se continuar,
   pare e avise o Pedro no chat.

COMO CONSULTAR
  POST https://crm.imobeasy.online/api/public/imovel-consulta
  Headers: Authorization: Bearer <TOKEN_DA_CONSULTA>
           Content-Type: application/json
  Corpo: o JSON descrito abaixo.

CAMPOS (JSON) — leia do anúncio aberto
Obrigatório:
  "link"               o link do anúncio
Preencha tudo o que o anúncio mostrar. O que não aparecer, mande null.
NUNCA invente valor.
  "portal"             "olx"
  "id_anuncio"         o código do anúncio na OLX
  "titulo"             o título do anúncio
  "descricao"          o texto inteiro da descrição
  "tipo"               apartamento | casa | casa de condomínio | terreno | sala |
                       loja | galpão ...
  "finalidade"         "venda" ou "aluguel"
  "preco"              o preço (número, ou texto como "R$ 3.500")
  "cidade", "uf"
  "bairro"             o bairro como a OLX mostra (ex.: "Nossa Senhora das Graças")
  "endereco", "cep"
  "condominio_nome"    o nome do condomínio ou do prédio, se aparecer
  "area_m2", "quartos", "suites", "banheiros", "vagas", "valor_condominio"
  "anunciante_nome"    o nome da conta que anunciou
  "anunciante_perfil"  o link do perfil do anunciante, se houver
  "profissional"       true se a OLX marca a conta como profissional; senão false
  "telefone"           o telefone do anunciante, se o anúncio mostrar
O sistema só decide se vierem "preco", "tipo" (ou "titulo") e "bairro" (ou
"condominio_nome"). Faltando um deles, volta o erro "faltam_campos": leia o que
faltou no anúncio e consulte de novo.

Exemplo:
  {
    "link": "https://am.olx.com.br/regiao-de-manaus/imoveis/apartamento-3-quartos-1540696600",
    "portal": "olx",
    "id_anuncio": "1540696600",
    "titulo": "Apartamento 3 quartos no Vieiralves",
    "descricao": "Apartamento com 3 quartos, sendo 1 suíte...",
    "tipo": "apartamento",
    "finalidade": "venda",
    "preco": 650000,
    "cidade": "Manaus",
    "uf": "AM",
    "bairro": "Nossa Senhora das Graças",
    "endereco": null,
    "cep": null,
    "condominio_nome": null,
    "area_m2": 110,
    "quartos": 3,
    "suites": 1,
    "banheiros": 2,
    "vagas": 2,
    "valor_condominio": 800,
    "anunciante_nome": "Mariana",
    "anunciante_perfil": null,
    "profissional": false,
    "telefone": null
  }

RESPOSTA
  Para abordar (200):
    { "consulta_ok": true, "acao": "abordar", "temos": false, "motivo": "nao_temos",
      "mensagem": "Oii, bom dia! Me chamo Nay Mendes, da Imob Easy. ...",
      "explicacao": "...", "id_consulta": "17" }
    -> mande o texto de "mensagem" ao anunciante, uma vez, sem mudar nada.
    -> se vier "repetido": true, é a mesma mensagem que você já recebeu para este
       anúncio: só mande se ainda NÃO tiver mandado.
  Para fechar (200):
    { "consulta_ok": true, "acao": "fechar", "temos": true, "motivo": "ja_temos",
      "id_imovel": "3050", "explicacao": "...", "id_consulta": "18" }
    -> não mande nada; feche o anúncio. "motivo" diz por quê:
       ja_temos                 o imóvel já está no nosso cadastro
       proprietario_ja_e_nosso  o telefone do anúncio é de um proprietário nosso
       corretor                 o anunciante é corretor ou imobiliária
       dispensa_imobiliaria     o anúncio diz que não quer corretor nem imobiliária
       ja_abordado              a mensagem deste anúncio já foi entregue antes
  Falha (não é sucesso; não mande mensagem):
    { "consulta_ok": false, "codigo_erro": "...", "erro": "..." }
    faltam_campos (400)  complete o que está em "faltam" e consulte de novo
    401                  token errado: pare e avise o Pedro no chat
    429                  espere 1 minuto
    502                  tente de novo em 1 minuto

TESTE DE CONEXÃO (não grava nada e não é ordem)
  Mande o JSON abaixo. A resposta certa tem "consulta_ok": true, "teste": true e
  "acao": "nenhuma". Se veio isso, diga ao Pedro "conexão OK".
  {
    "teste": true,
    "link": "https://am.olx.com.br/regiao-de-manaus/imoveis/teste-de-conexao-1000000001",
    "titulo": "Apartamento de teste",
    "tipo": "apartamento",
    "finalidade": "aluguel",
    "preco": 2500,
    "bairro": "Flores"
  }
  Nunca use "teste": true num anúncio de verdade.

LIMITE: 120 consultas por minuto.
```

## Do nosso lado

- Token: `BOT_IMOVEIS_CHAVE` em `/docker/crm/app/.env`. Só abre este webhook (e o
  `/vincular`, abaixo).
- Quem decide: `crm_anuncio_decidir(jsonb)` (migração 309). Ela chama a
  `crm_imovel_candidatos` (258) para achar os parecidos e a
  `crm_anuncio_mesma_unidade` para dizer se é a **mesma unidade**.
- Cada consulta fica em `privado.anuncio_consulta`: o anúncio, a decisão, o
  motivo, o imóvel parecido e a mensagem entregue.

### Quando é "já temos"

"Condomínio igual + área igual" é a mesma **planta**, não a mesma unidade: 3.549
dos nossos 5.698 imóveis estão em pares (condomínio, área) repetidos. Por isso:

| nível | o que precisa bater |
|---|---|
| link | mesmo link ou mesmo id do portal |
| dono | mesmo lugar (condomínio igual, rua ou CEP) + nome do anunciante igual ao do proprietário + área em 3% ou preço em 2% |
| unidade | imóvel nosso **no mercado** + mesmo lugar + preço em 2% + área em 3% (anúncio sem área: os quartos). Sem condomínio nem rua: bairro + tipo + área + preço + quartos |

Área mais de 10% diferente ou número de quartos diferente: não é a mesma.
Anúncio que diz o condomínio e imóvel nosso de OUTRO condomínio: rua, CEP e
bairro não fecham (310) — na mesma rua há vários prédios de planta parecida.
Vendido, alugado ou removido só fecha por link ou pelo nome do dono.

Medido em 08/10 com 200 imóveis nossos apresentados como anúncio de outro dono:
a regra antiga fecharia 133 por engano; esta fecha 14 (os que têm um gêmeo no
mercado com a mesma planta e o mesmo preço).

### A mensagem

O texto mora na tabela `anuncio_abordagem_texto` (chave `mensagem`), não no código.
Desde a 311 (Pedro, 08/10) é este, igual para todo tipo de imóvel:

```
Oii, {saudacao}! Me chamo Nay Mendes, da Imob Easy.

Tenho uns clientes procurando imóveis na região do seu!

Posso apresentar pra eles?

Se gostarem, eu cuido de tudo: visita, documentação, contrato e assinatura. Sem exclusividade, você continua {anunciando} aqui no OLX.

Me passa seu nome e seu WhatsApp que a gente conversa melhor.
```

- `{saudacao}`: bom dia (05:00–11:59), boa tarde (12:00–17:59), boa noite, pela
  hora de **Manaus**.
- `{anunciando}`: "vendendo" na venda, "anunciando" no aluguel.
- A função ainda aceita `{cliente}` e `{onde}` (a frase do cliente por tipo e "na
  região de <bairro>", da 309); as chaves `cliente_*` ficam guardadas, fora de uso.
- Trocar o texto: `UPDATE anuncio_abordagem_texto SET texto = '...' WHERE chave = 'mensagem'`.
  Marcador que não existe faz a consulta falhar (`codigo_erro: "texto"`) em vez
  de mandar texto quebrado.

### O mesmo anúncio não recebe duas mensagens

A entrega da mensagem fica gravada. Consulta repetida em até 10 minutos devolve
a **mesma** mensagem com `repetido: true` (o bot pode não ter recebido a
resposta); depois disso volta `fechar`, motivo `ja_abordado`.

## Registrar o link (depois de confirmado que é o mesmo imóvel)

```
POST https://crm.imobeasy.online/api/public/imovel-consulta/vincular
Authorization: Bearer <TOKEN_DA_CONSULTA>
{ "id_imovel": "4679", "link": "<link do anúncio>", "portal": "olx" }
```

Resposta: `{ "ok": true, "id_imovel", "link", "id_anuncio", "ja_estava", "mensagem" }` ou
`{ "ok": false, "erro" }`. A próxima consulta desse anúncio bate por link.

## Se o HTTPS não chegar

A rede de alguns bots corta o HTTPS para este servidor. Nesse caso use
`http://crm.imobeasy.online` (porta 80), mesmas rotas, com o **pedido lacrado** — o
token nunca viaja:

```sh
H=$(date +%s)
C=$(printf '%s' "$JSON" | openssl enc -aes-256-cbc -pbkdf2 -iter 100000 -md sha256 -salt -pass "pass:$TOKEN" -base64 -A)
A=$(printf '%s' "$H.$C" | openssl dgst -sha256 -hmac "$TOKEN" | sed 's/^.* //')
# corpo: {"hora":H,"cifrado":"C","assinatura":"A"}
```

O token puro é recusado na porta 80. Ver `COMO-LIGAR-O-GROK-A-UM-WEBHOOK.md`.

## Onde está no código

`crm/src/app/api/public/imovel-consulta/` · `crm/src/lib/botDeImoveis.ts` ·
`crm_anuncio_decidir(jsonb)`, `crm_anuncio_mesma_unidade(jsonb, jsonb)` e
`crm_anuncio_mensagem(jsonb, text, timestamptz)` (migração 309; texto da 311) ·
`crm_imovel_candidatos(jsonb)` e `crm_imovel_vincular_anuncio(...)` (258) ·
porta 80: `scripts/servidor/traefik-imovel-consulta.yml`.
