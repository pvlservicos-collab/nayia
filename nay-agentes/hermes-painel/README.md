# hermes-painel

A seção **Hermes** da página Agentes do admin (`admin/agentes.html`): um quadrado por perfil do Hermes da VPS2 e,
em "Abrir", a mesa do agente — conversa, o navegador dele ao vivo (com clique e teclado), tarefas agendadas, skills e
ferramentas, memória, logs e reiniciar/parar o serviço. Pedro, 13/10/2026.

## O caminho de um pedido

    navegador do Pedro ─ senha do /admin ─► API do site (VPS1)  /admin/api/hermes/...
        ─ Tailscale + segredo de máquina ─► ponte (VPS2, 100.113.222.11:8650)
            ├─► API local do Hermes (127.0.0.1:8642 telegram, :8643 corretores)   conversa, tarefas, skills
            ├─► Chrome do perfil por CDP (127.0.0.1:9301 telegram, :9302 corretores)   foto da tela, clique, tecla
            ├─► systemd   estado, memória, reiniciar/parar
            └─► arquivos do perfil em /root/.hermes/profiles/<perfil>   memória, logs, tarefas (leitura)

- A ponte só escuta no endereço do Tailscale e só responde com o `X-Painel-Token`. O segredo nunca vai à página.
- A rota do site confere a senha do admin e, para escrever, exige o cabeçalho `X-Painel-Hermes: 1`, que só a própria
  tela manda (formulário de outro site não consegue).

## O que foi criado na VPS2 (nada do Hermes foi editado)

| o quê | onde |
|---|---|
| a ponte | `/opt/hermes-painel/ponte.py`, serviço `hermes-painel` |
| o Chrome (cópia do que o Playwright do Hermes baixou) | `/opt/hermes-painel/chrome` |
| perfis e segredos (só root) | `/etc/hermes-painel/perfis.json`, `ponte.env`, `gateway-<perfil>.env` |
| o Chrome de cada perfil | `hermes-chrome-<perfil>.service`: usuário sem privilégio, teto de 1,1 GB, logins em `/var/lib/hermes-chrome/<perfil>` |
| a porta que acorda o Chrome | `hermes-chrome-<perfil>-porta.socket`: a primeira ligação sobe o Chrome; 20 min parado, desliga |
| a API local e o navegador do agente | drop-in `hermes-gateway-<perfil>.service.d/painel.conf` (`API_SERVER_*` e `BROWSER_CDP_URL`) |

Com o `BROWSER_CDP_URL`, o Hermes passa a usar ESTE Chrome para qualquer tarefa de site (também as pedidas pelo
Telegram), no lugar do navegador em nuvem que estava na configuração. É o que permite ver e assumir a tela.

O perfil `telegram` nasceu com o modelo `tencent/hy3:free` pela Nous, que em 13/10 estava sem login (não respondia
a nada). `./nay-agentes/hermes-painel/publicar.sh telegram-luna` troca para o `gpt-5.6-luna`, o mesmo do `corretores`.

O perfil `pessoal` está com o serviço bloqueado (masked) no servidor: a ponte mostra tarefas, skills, memória e logs
dele, mas não o liga nem conversa.

## Publicar e desfazer

`./nay-agentes/hermes-painel/publicar.sh` (ver o cabeçalho do arquivo para a ordem). Desfazer na VPS2:
`bash /root/hermes-painel-fonte/instalar.sh desfazer` e reiniciar os dois gateways.

Agente novo do Hermes: uma entrada em `perfis.json` e uma linha em `PERFIS` no `instalar.sh` (portas livres).
