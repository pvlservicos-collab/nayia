# Índice do pacote — Cérebro da Nay

Gerado em 19/09/2026 16:19 (horário de Brasília).

**Esta é a versão boa de TODOS os arquivos.** Se você tem cópia anterior de
qualquer um deles, substitua — os três primeiros mudaram depois da primeira
entrega e eu avisei errado que não tinham mudado.

Confira que recebeu as versões certas comparando o md5:

```
ARQUIVO                            LINHAS  MD5
64_trace.sql                          725  fb6a4796bb8589f08e586064287b3f24
teste_64_trace.sql                    452  1e806bebc0082abab95f2f3e1ae76fb7
65_setores_e_inventario.sql           504  6443c23e0cc837ad2b5a6d95ed66d2ad
66_regras.sql                         276  922063114fe313ac8fcd04c7f118e023
trace_api.py                          333  d6a83d35e19b4e730e53599432fd777e
nay-cerebro.html                      368  e6d6107e65dbcf2977c84e372883b3d6
nay-cerebro.js                        773  931616f999119696057f3033b216bad7
PASSO-A-PASSO.md                      492  feb06a22d1fbe171222ec43a12275a66
```

## A ordem

| # | Arquivo | Onde vai | O que é |
|---|---|---|---|
| 1 | `64_trace.sql` | `Arquivos/nai/` → aplicar no banco | O trace: `nai_evento`, `nai_tracar`, `nai_trilha`, as views |
| 2 | `teste_64_trace.sql` | `Arquivos/nai/` → rodar | 67 verificações, em transação com ROLLBACK |
| 3 | `65_setores_e_inventario.sql` | `Arquivos/nai/` → aplicar | Os 12 setores, o classificador, a foto e o detector de desvio |
| 4 | `66_regras.sql` | `Arquivos/nai/` → aplicar | As 17 regras com nome e texto, e quantas vezes ela ignora cada uma |
| 5 | `trace_api.py` | ao lado do `app.py` | Blueprint Flask, 6 rotas, só leitura |
| 6 | `nay-cerebro.html` | `imob-easy/admin/` | A tela |
| 7 | `nay-cerebro.js` | `imob-easy/assets/js/` | A lógica da tela |
| 8 | `PASSO-A-PASSO.md` | — | O roteiro. **Comece por ele.** |

Os SQL têm dependência entre si: o 65 e o 66 usam `nai_setor`, que nasce no 64.
Aplicar fora de ordem falha com "relation nai_setor does not exist".

## O que foi verificado antes de sair

Numa instalação **do zero**, contra um PostgreSQL 16 limpo:

- os três `.sql` aplicados na ordem: **0 erros**
- a bateria: **67 de 67**, e o ROLLBACK confirmado (nada fica gravado)
- 12 setores, 3 chaves de trace, 17 regras (9 paredes), marco zero tirado
- as 6 rotas da API: **200**
- a tela renderizada em Chromium: 17 regras, 4 abas, mapa com 12 setores,
  **zero erro de JavaScript**

O que **não** pôde ser testado daqui são os quatro nós do n8n (passo 5) —
dependem do fluxo de produção.

## Se algum passo falhar

Pare e diga qual. Cada passo do roteiro tem o "desfazer" logo abaixo dele, e o
trace inteiro desliga com um UPDATE:

```sql
UPDATE nai_config SET valor='desligado' WHERE chave='trace_nivel';
```
