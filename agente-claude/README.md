# Agente Claude (VPS2, separado da Nay)

Pedro, 20/10/2026: um agente que manda ao Claude mensagens pré-setadas conforme as regras dele, num canto próprio da
VPS para metrificar sozinho, rápido e otimizado. Depois, no mesmo dia: "quero que instale o claude code terminal na minha
vps, vou usar para o hermes mandar mensagem para o claude em um momento específico do dia ... e esse claude fazer
alterações que eu mandar" — em todas as VPS, como root, ordem escrita no painel, um Hermes só para isso.

- **Por onde fala com o Claude:** `claude -p` (Claude Code) logado na conta do Pedro. Sem navegador: os termos do
  claude.ai proíbem robô no site, e o navegador seria lento e pesado.
- **Rápido:** no modo "responder" o Claude roda sem ferramentas, sem MCP, sem salvar sessão, numa pasta vazia. Várias
  regras no mesmo comando vão em paralelo.

## O caminho de uma ordem

    painel agentes.imobeasy.online ─┐
    Hermes do Claude (hora marcada) ─┼─► agente.py (VPS2) ─► claude-agente da VPS2 ─► claude -p (root)
    terminal / cron ────────────────┘                     └─ ssh Tailscale ─► claude-agente da VPS1 ─► claude -p (root)

Cada regra (`regras.json`) tem: `mensagem`, `servidor` (`vps2` | `vps1`), `modo` (`responder` | `alterar`), `modelo`,
`sistema?`, `esforco?`, `timeout_s?` (padrão 300 s responder, 1800 s alterar), `ativa?`.

- **Modo "alterar":** o Claude do servidor da regra roda como root com terminal, edição de arquivo e web, em /root, e
  responde o que mudou, como conferir e como desfazer. A sessão fica em `/root/.claude/projects` (id em `metricas.db`).
- **`claude-agente`** (`/usr/local/sbin`, nas duas VPS): recebe o pedido em JSON no stdin, roda o Claude, devolve o JSON.
- **VPS2 → VPS1:** chave `/root/.ssh/agente_claude_vps1`, aceita no root da VPS1 só vindo de 100.113.222.11 (`from=`).

## Login (falta)
O Claude Code do root das duas VPS (`/root/.local/bin/claude`) está sem login. Duas formas, em cada VPS:
- `ssh` na VPS, `claude`, `/login` (vale para o terminal e para o agente); ou
- `claude setup-token` no PC e o token em `/etc/agente-claude/claude.env` como `CLAUDE_CODE_OAUTH_TOKEN=...` (o agente
  usa esse primeiro).

## Painel: https://agentes.imobeasy.online (site › Mais › Agente Claude)
Regras (criar, editar, servidor, modo, parar, apagar, Disparar), gráfico do tempo de cada disparo, métricas por regra
e os últimos disparos (onde, quem disparou, resposta). Pedro: "só dá pra entrar nessa tela quem vier do site principal".

    navegador ─ senha do /admin ─► Traefik da VPS1 (agentes.yml) ─ Tailscale + X-Agentes-Token ─► painel.py (VPS2)

- O DNS aponta para a VPS1. `traefik-agentes.yml` é a cópia (sem o segredo) de `/docker/traefik/dynamic/agentes.yml`:
  usa o mesmo middleware `nay-site-admin-auth@docker` do /admin e põe o `X-Agentes-Token`.
- `painel.py` (root) escuta só em `100.113.222.11:8660` e recusa sem o token; gravar/disparar exige também
  `X-Agente: 1`, que só a tela manda. O disparo pela tela vai para segundo plano; a tela acompanha a cada 4 s.
  Token em `/etc/agente-claude/painel.env`. O HTML é lido na partida: mudou o `painel.html`, reinicie o serviço.

## Hermes do Claude (admin › Agentes)
Perfil `claude` do Hermes, serviço `hermes-gateway-claude` (API 127.0.0.1:8645), fonte em `nay-agentes/hermes-painel/`
(`alma-claude.md`, `instalar-claude.sh`, `publicar.sh claude`). Só fala pela tela admin › Agentes. Ferramentas:
memória, agenda (cronjob, fuso de Brasília) e `agente` (`mcp_agente.py`: `listar_regras`, `disparar_regra`). Sem
terminal. Pede-se a ele, por exemplo: "todo dia às 3h dispare a regra X".

## Uso pelo terminal (VPS2, root)
```
/opt/agente-claude/agente regras
/opt/agente-claude/agente disparar teste
/opt/agente-claude/agente metricas 30
/opt/agente-claude/agente ultimas 5
```
Cron, se quiser sem o Hermes: `0 8 * * * root /opt/agente-claude/agente disparar minha-regra` em `/etc/cron.d/`.

## Publicar e desfazer
`./agente-claude/publicar.sh` (as duas VPS) e `./nay-agentes/hermes-painel/publicar.sh claude` (o Hermes).
Desfazer: ver o cabeçalho dos dois scripts; o Traefik, apagar `agentes.yml` na VPS1.

`US$ eq` nas métricas é o que a chamada custaria na API; na assinatura não é cobrado, mas conta no limite de uso.
