# Webhook de CONSULTA de imóveis (bot que consulta)

Este webhook é de **um bot só**: o que pergunta se um anúncio já está no banco da
Imob Easy. Ele **não cadastra nada**. O cadastro é outro webhook, de outro bot, com
outro token — ver `webhook-cadastro.md`.

## Como chamar

```
POST https://crm.imobeasy.online/api/public/imovel-consulta
Authorization: Bearer <TOKEN_DA_CONSULTA>
Content-Type: application/json
```

O token está no servidor, em `BOT_IMOVEIS_CHAVE` (`/docker/crm/app/.env`). Ele só
abre a consulta e o registro de link.

## Entrada

JSON. Só `link` é obrigatório; campo `null` ou ausente não desclassifica ninguém,
só não conta ponto.

```json
{
  "link": "https://am.olx.com.br/regiao-de-manaus/imoveis/venda-apartamento-smart-residence-downtown-1540696600",
  "portal": "olx",
  "id_anuncio": "1540696600",
  "titulo": "Venda apartamento SMART RESIDENCE DOWNTOWN",
  "tipo": "apartamento",
  "finalidade": "venda",
  "preco": 990000,
  "cidade": "Manaus",
  "uf": "AM",
  "bairro": "Centro",
  "endereco": null,
  "cep": null,
  "condominio_nome": "Smart Residence Downtown",
  "area_m2": null,
  "quartos": null,
  "suites": null,
  "banheiros": null,
  "vagas": null,
  "valor_condominio": null,
  "anunciante_nome": "Acris Imob",
  "telefone": null
}
```

## Saída

```json
{
  "consulta_ok": true,
  "total_candidatos": 2,
  "melhor_score": 92,
  "entendido": { "...": "como o anúncio foi lido (link, id, bairro, condomínio, preço...)" },
  "candidatos": [
    {
      "id_imovel": "123",
      "score": 92,
      "confianca": "alta",
      "campos_que_bateram": ["condominio_nome", "bairro", "preco"],
      "campos_divergentes": [{ "campo": "preco", "banco": 950000, "anuncio": 990000 }],
      "dados": {
        "titulo": "...", "tipo": "...", "preco": 950000, "preco_venda": 950000, "preco_aluguel": null,
        "bairro": "...", "cidade": "...", "endereco": "Avenida Joaquim Nabuco", "numero": "1908",
        "complemento": null, "cep": "...", "condominio_nome": "...",
        "area_m2": 120, "quartos": 3, "suites": 1, "banheiros": 2, "vagas": 2, "valor_condominio": 650,
        "links_portais": ["..."], "proprietario_telefone_final": "**99",
        "status": "Disponível", "no_mercado": true, "publicado_no_site": true, "de_parceiro": false,
        "atualizado_em": "2026-09-20"
      }
    }
  ]
}
```

- Sem candidatos: `"total_candidatos": 0` e `"candidatos": []`.
- Erro: `"consulta_ok": false` com `"erro"` (HTTP 400, 401, 422, 429 ou 502). **Nunca
  vem resposta vazia.** Qualquer coisa que não seja JSON com `consulta_ok: true` é
  falha, não é "não é nosso": tente de novo.
- No máximo 10 candidatos, por `score` (0 a 100).
- `endereco` traz **só a rua**; o número vem em `numero` e o resto em `complemento`
  (migração 262, a pedido do bot: no sistema dele são campos separados).

## Como a nota é dada

| sinal | pontos |
|---|---|
| mesmo link ou mesmo id do portal | 100 |
| mesmo telefone do proprietário | 45 |
| condomínio igual (parecido: 20) | 35 |
| área em até 3% (até 10%: 12) | 20 |
| preço em até 2% (até 15%: 15) | 20 |
| bairro ou CEP | 10 |
| rua | 10 |
| tipo 5 · quartos 5 · vagas 2 · suítes 2 · banheiros 1 | |

- `confianca: "alta"`: mesmo link/id, mesmo telefone, ou condomínio igual + área em até 3%.
- `"media"`: nota de 45 para cima. `"baixa"`: de 30 a 44. Abaixo de 30 não entra.
- Outra cidade não é candidato (a não ser por link ou telefone).
- Um condomínio tem várias unidades: vários candidatos com a mesma nota são unidades
  diferentes. Desempate por `campos_divergentes`.
- `status` pode ser Vendido, Alugado ou Removido: o imóvel já foi nosso.

## Registrar o link (depois de confirmado que é o mesmo imóvel)

```
POST https://crm.imobeasy.online/api/public/imovel-consulta/vincular
Authorization: Bearer <TOKEN_DA_CONSULTA>
{ "id_imovel": "4679", "link": "<link do anúncio>", "portal": "olx" }
```

Resposta: `{ "ok": true, "id_imovel", "link", "id_anuncio", "ja_estava", "mensagem" }` ou
`{ "ok": false, "erro" }`. A próxima consulta desse anúncio bate por link (nota 100).
O mesmo anúncio não entra em dois imóveis: a resposta diz em qual ele já está.

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

O token puro é recusado na porta 80.

## Limite

120 pedidos por minuto.

## Onde está no código

`crm/src/app/api/public/imovel-consulta/` · `crm/src/lib/botDeImoveis.ts` ·
`crm_imovel_candidatos(jsonb)` e `crm_imovel_vincular_anuncio(...)` (migração 258) ·
porta 80: `scripts/servidor/traefik-imovel-consulta.yml`.
