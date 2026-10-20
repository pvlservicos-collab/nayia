# Agente Claude (VPS2, separado da Nay)

Pedido do Pedro, 20/10/2026: um agente que manda mensagens pré-setadas ao Claude conforme as regras dele,
num canto próprio da VPS para metrificar sozinho, rápido e otimizado.

- **Por onde fala com o Claude:** `claude -p` (Claude Code) logado na conta do Pedro. Não usa navegador: os termos do
  claude.ai proíbem robô no site, e o navegador seria lento e pesado. Escolha dele na conversa de 20/10.
- **Onde mora:** VPS2 (`ssh nay-srv1877774`), usuário `agclaude` (sem sudo), `/opt/agente-claude`. Não toca no Hermes
  (`/root/.hermes`) nem em nada da Nay. Claude Code em `/opt/agente-claude/.local/bin/claude`.
- **Rápido:** cada disparo é um `claude -p` sem ferramentas, sem MCP, sem salvar sessão, sem tráfego extra, rodando
  numa pasta vazia (não lê CLAUDE.md). Várias regras no mesmo comando vão em paralelo.

## Arquivos na VPS
| | |
|---|---|
| `agente` | o comando (este `agente.py`) |
| `regras.json` | as regras: `nome → {mensagem, modelo, sistema?, esforco?, timeout_s?, ativa?}` (ver `regras.exemplo.json`) |
| `metricas.db` | SQLite, tabela `execucoes`: tempo total, tempo do Claude e da API, tokens, cache, custo equivalente, resposta, erro |
| `.env` | `CLAUDE_CODE_OAUTH_TOKEN=...` (o login; modo 600, fora do git) |

## Uso
```
ssh nay-srv1877774
runuser -u agclaude -- /opt/agente-claude/agente regras
runuser -u agclaude -- /opt/agente-claude/agente disparar teste
runuser -u agclaude -- /opt/agente-claude/agente metricas 30
runuser -u agclaude -- /opt/agente-claude/agente ultimas 5
```

## Login (uma vez)
No PC do Pedro: `claude setup-token` (abre o navegador, entra na conta, imprime um token que vale 1 ano).
O token vai para `/opt/agente-claude/.env` como `CLAUDE_CODE_OAUTH_TOKEN=...`.

## Cron (o Pedro cria)
Linha em `/etc/cron.d/agente-claude`, sempre como o usuário `agclaude`:
```
0 8 * * * agclaude /opt/agente-claude/agente disparar minha-regra >> /opt/agente-claude/cron.log 2>&1
```
O `agente` carrega o `.env` sozinho.

`US$ eq` nas métricas é o que a chamada custaria na API; na assinatura não é cobrado, mas conta no limite de uso.
