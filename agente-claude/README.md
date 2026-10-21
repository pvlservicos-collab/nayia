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

## Projetos (aba Projetos do painel)
Pedido de 20/10: "um projeto para cada um desses contextos que vai analisar uma parte da minha empresa ... vários
quadrados ... deixa um campo para eu digitar ... a que revisa a Nay de uma forma otimizada porque no futuro eu vou subir
todas as conversas da Nay para ele". Seis projetos: Estratégia, Visitas, Métricas, Financeiro, Análise das respostas e
Nay Parceria (revisão), cada um com o contexto que o Tel escreveu (`projetos/<id>/contexto.md`).

- `projetos.py`: cada conversa é uma sessão do Claude Code (`--session-id` na primeira mensagem, `--resume` depois);
  as mensagens e as métricas também vão para `metricas.db` (tabelas `conversas` e `mensagens`). Uma resposta por vez
  em cada conversa, em segundo plano; a tela acompanha a cada 2,5 s.
- O Claude do projeto só LÊ: Read, Glob e Grep na pasta do projeto e o MCP `leitura` (`mcp_leitura.py`, 20/10:
  "não estão lendo o banco de dados e os códigos da minha vps"). São quatro ferramentas de comando fixo, sem terminal:
  `consultar_banco` (naydb/crmdb com o papel `nay_leitura`, uma instrução de leitura por vez, transação só leitura;
  o crmdb foi aberto pela 451, menos senha e token), `ler_arquivo`, `listar` e `procurar` (vps1 e vps2, como root,
  recusando .env, chaves e o login do Claude). O `CLAUDE.md` da pasta é refeito a cada
  mensagem: cabeçalho (o que ele pode, data e hora de Manaus e Brasília) + `como-ler-os-dados.md` + o contexto.
- Anexos em `dados/anexos` (até 50 MB; `.xlsx` vira um `.csv` por aba, com os valores que o Excel salvou).
- Contexto, modelo e esforço se editam na tela. **No servidor está a verdade**: o `publicar.sh` só cria projeto que
  ainda não existe lá e só atualiza o `como-ler-os-dados.md`.
- **Nay:** `importar_nay.py` (botão "Importar conversas da Nay") lê `core_turno` + `core_saida` do naydb (VPS1, read only,
  pela chave da VPS2) e grava `dados/conversas/indice.tsv`, `AAAA-MM-DD/_resumo.txt` e uma conversa por corretor por
  dia, com o RESULTADO (visita marcada, escalada e motivo, corretor sumiu). Telefone só com os 4 últimos dígitos.
  Tudo (desde 07/10, 456 conversas) leva menos de 1 s e ocupa 2 MB. O Claude lê o índice e abre só o que precisa.

## Horário marcado (só o Claude, sem o Hermes)
Pedro/Tel, 20/10: "precisa do gpt no hermes? ... ou poderia ser só o Claude?" → só o Claude. Cada regra tem `horario`
(HH:MM, Brasília) e `dias` (todos, seg-sex, seg-sab); cada projeto tem `agenda` {horario, dias, mensagem} no ⚙ do
quadro. O `agendador()` do `painel.py` olha a hora a cada 20 s e dispara; o que já saiu fica em `agenda_feita.json`
(um reinício no mesmo minuto não repete). A mensagem do projeto entra na conversa atual do quadro, marcada "agendada".
A resposta fica no painel (escolha dele: "só no painel").

O **Hermes do Claude** (perfil `claude`, `nay-agentes/hermes-painel/alma-claude.md`, `instalar-claude.sh`) foi
desligado em 20/10 (`hermes-gateway-claude` parado e fora do boot; saiu do `perfis.json`); o perfil ficou em
`/root/.hermes/profiles/claude`. `mcp_agente.py` ficou sem uso.

## A tela dos projetos
Os seis chats ficam abertos ao mesmo tempo, 3 em cima e 3 embaixo ("deixa os chats já lá abertos em quadradinhos
separados"): cada quadro tem a conversa, o campo de digitar, a lista de conversas (e "+ Nova conversa"), ⤢ para
ampliar e ⚙ para contexto e modelo, horário e anexos. A cada 10 s a tela confere se algum projeto mudou sozinho.

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
