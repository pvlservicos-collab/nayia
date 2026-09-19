# nayia

Atendimento e captação por WhatsApp da **Imob Easy** (Manaus). São quatro
produtos que dividem um banco de dados e um servidor.

---

## Sumário

| # | Peça | O que faz | Onde mora |
|---|------|-----------|-----------|
| 1 | **Nay antiga** | Fluxo n8n original: recebe TODA mensagem e roteia | n8n `Nay- recebe mensagem` |
| 2 | **NAI atendimento locação** | O atendimento novo ao corretor: busca imóvel, manda card e fotos, agenda visita | [`Arquivos/nai/`](Arquivos/nai/) |
| 3 | **Nay captação** | Campanha temporária: liga para proprietário e descobre a situação do imóvel | [`Arquivos/captacao_*`](Arquivos/) |
| 4 | **Site + admin** | `imobeasy.online` — catálogo público e painel de controle | [`imob-easy/`](imob-easy/), [`nay-site-api/`](nay-site-api/) |

Tudo roda em `srv1894338.hstgr.cloud`, em containers Docker:
`nay-postgres`, `n8n-viux-n8n-1`, `nay-site-web`, `nay-site-api`, `nay-painel`,
`traefik`.

---

## Esqueleto: por onde uma mensagem passa

```
WhatsApp ──▶ Z-API ──▶ webhook do n8n (fluxo "Nay- recebe mensagem")
                            │
                            ├─ roteador "NAI ou Nay?" ─▶ NAI atendimento locação
                            │                              │
                            │                              ├─ nai_abrir_turno()   ← abre o turno, decide o papel
                            │                              ├─ modelo (Haiku 4.5)  ← decide o que responder
                            │                              ├─ nai_enfileirar_resposta()  ← 17 conferências
                            │                              └─ nai_saida          ← A CAIXA DE SAÍDA
                            │                                     │
                            │                                     └─ nai_liberar_saida()
                            │                                          pausa · janela · repetida ·
                            │                                          "o Tel assumiu" · modo teste
                            │                                          │
                            └─ Nay antiga (pausada desde agosto)       └──▶ Z-API ──▶ WhatsApp
```

**Nada sai sem passar por `nai_saida`.** O gatilho `nai_saida_validar` recusa
destino que não é parte daquele turno ou daquela visita, e `nai_liberar_saida`
aplica as travas na hora de mandar. Quando alguém diz "ela não respondeu",
o lugar de olhar é `SELECT estado, bloqueio FROM nai_saida` — não o texto.

---

## Mapa das pastas

```
Arquivos/              fonte de tudo que roda no servidor
  nai/                 o atendimento de locação, em arquivos numerados 01..40
  CLAUDE.md            o manual longo do projeto — leia antes de mexer
  HISTORICO-APRENDIZADO.md   o que já deu errado e por quê
  REGRAS-E-BUGS.md
nay-publicador/        espelho do que está DEPLOYADO no servidor (/root/nay-publicador)
imob-easy/             site e admin (HTML/JS estático)
nay-site-api/          API Flask que o site consome
nay-painel/            painel interno
```

Os arquivos de `Arquivos/nai/` são numerados **na ordem em que devem ser
aplicados**. Cada um traz no cabeçalho o pedido do Tel que o originou e a
decisão de projeto — o "porquê" mora no arquivo, não só o "o quê".

---

## Banco

Postgres `naydb`. Acesso:

```sh
docker exec nay-postgres psql -U nay -d naydb -c "SELECT ..."
```

Tabelas centrais:

| Tabela | Para que serve |
|---|---|
| `imoveis` | o catálogo (1.247), sincronizado do site |
| `corretores` | quem a Nay pode atender (`pode_falar`) |
| `nai_contato` | uma linha por **chave** de WhatsApp |
| `nai_turno` | cada rodada de conversa |
| `nai_saida` | a caixa de saída — toda mensagem passa aqui |
| `nai_visita` | as visitas agendadas |
| `nai_config` | os interruptores da NAI |
| `captacao_*` | a campanha de proprietários |

---

## Duas armadilhas que já custaram caro

**1. O banco está À FRENTE destes arquivos.** Funções foram corrigidas direto
em produção e nem sempre voltaram para cá. Antes de editar qualquer função
`nai_*`, puxe a versão viva e patche em cima dela:

```sh
docker exec nay-postgres psql -U nay -d naydb -At \
  -c "SELECT pg_get_functiondef(oid) FROM pg_proc WHERE proname='nai_liberar_saida'"
```

Reaplicar um `.sql` antigo apaga trabalho em silêncio, sem erro nenhum.

**2. A mesma pessoa tem duas linhas em `nai_contato`** — uma pelo telefone e
outra pelo `@lid` do chat. Regra que lê `nai_contato` por id sem usar
`nai_contato_irmaos()` vai enxergar metade da verdade.

---

## Segredos

Não estão no repositório, e não devem entrar. As credenciais (VPS, Postgres,
Z-API) moram em `.env.local`, que está no `.gitignore`. Os scripts leem de
variável de ambiente: `ZAPI_INSTANCIA`, `ZAPI_TOKEN`, `ZAPI_CLIENT_TOKEN`.

Os backups de fluxo do n8n (`backup_wf_*.json`) **têm token dentro dos nós** e
por isso também estão ignorados.
