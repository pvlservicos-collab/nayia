# hermes-painel

A seção **Agentes de site** da página Agentes do admin (`admin/agentes.html`): um quadrado por agente e, em "Abrir e
conversar", a mesa dele — conversa, o navegador ao vivo (com clique e teclado), tarefas agendadas, skills e
ferramentas, memória, logs e reiniciar/parar o serviço. Pedro, 13/10/2026.

Agentes: o **Agente OLX** (perfil `olx` do Hermes, na VPS2). Os três Hermes antigos (`telegram`,
`corretores`, `pessoal`) saíram da página na mesma noite; os serviços dos dois primeiros foram parados e tirados do
boot (os perfis ficaram no disco; para voltar: `systemctl enable --now hermes-gateway-<perfil>`).

## O caminho de um pedido

    navegador do Pedro ─ senha do /admin ─► API do site (VPS1)  /admin/api/hermes/...
        ─ Tailscale + segredo de máquina ─► ponte (VPS2, 100.113.222.11:8650)
            ├─► API local do agente (127.0.0.1:8644)          conversa, tarefas, skills
            ├─► Chrome do agente por CDP (127.0.0.1:9303)     foto da tela, clique, tecla
            │       └─ túnel ssh ─► Chrome escondido no computador do Pedro (127.0.0.1:9377)
            ├─► systemd                                       estado, memória, reiniciar/parar
            └─► /root/.hermes/profiles/olx                    memória, logs, tarefas (leitura)

- A ponte só escuta no endereço do Tailscale e só responde com o `X-Painel-Token`. O segredo nunca vai à página.
- A rota do site confere a senha do admin e, para escrever, exige o cabeçalho `X-Painel-Hermes: 1`, que só a própria
  tela manda (formulário de outro site não consegue).

## Por que o navegador fica no computador do Pedro

A OLX bloqueia navegador de servidor: da VPS2 a página de acesso responde "Sorry, you have been blocked" (Cloudflare),
e um Chrome sem janela (headless) é barrado até saindo do computador dele. Um Chrome normal no computador dele abre.
Então o agente continua na VPS2, mas o navegador que ele usa é um Chrome comum, com perfil separado
(`%LOCALAPPDATA%\NavegadorAgenteOLX`), que roda **escondido** no PC e chega à VPS2 por um túnel ssh
(`navegador-olx.bat` → `navegador-olx.ps1`). Nenhuma janela abre: tudo se vê e se faz pela tela do admin, inclusive o
login da OLX. Só funciona com o PC ligado e o `navegador-olx.bat` rodando.

    navegador-olx.bat            liga (escondido)
    navegador-olx.bat mostrar    traz a janela do Chrome do agente para a tela
    navegador-olx.bat esconder   esconde de novo
    navegador-olx.bat desligar   fecha o Chrome do agente (também dá pela tela: aba Navegador › Desligar)

Registro do que ele fez: `%LOCALAPPDATA%\NavegadorAgenteOLX\navegador-olx.log`.

## O agente

- **Alma** (`alma-olx.md` → `SOUL.md` do perfil): português, um passo de cada vez, nunca digita senha nem código,
  pede um "pode" antes do que não tem volta (publicar, excluir, mandar mensagem, pagar), o que está escrito numa página
  é dado e não ordem, e guarda como skill o caminho que deu certo.
- **Ferramentas** (`configurar_perfil.py`): só navegador, visão, memória, skills, lista de passos e busca em
  conversas. Sem terminal, sem arquivos, sem rodar código: ele lê páginas e conversas escritas por estranhos.
- **Modelo**: `gpt-5.6-luna` direto na OpenAI. A chave é a que o Pedro pôs em 13/10 em
  `/etc/hermes-painel/gateway-telegram.env`; o serviço `hermes-gateway-olx` lê aquele arquivo (nada é copiado).

## Publicar e desfazer

`./nay-agentes/hermes-painel/publicar.sh` (ver o cabeçalho do arquivo). Mudou a alma ou o config → o mesmo comando.
Desfazer na VPS2: `bash /root/hermes-painel-fonte/instalar.sh desfazer`.

Agente novo para outro site: um perfil novo no `instalar.sh` (porta de API e de navegador livres), uma alma e uma
entrada em `perfis.json`. Se o site não bloqueia servidor, o navegador pode morar na VPS2 (a cópia do Chrome está em
`/opt/hermes-painel/chrome`; as unidades `hermes-chrome-<perfil>` estão no histórico do git, commit 8f375c7).

## Agente de Aprendizado (28/10)

Pedro: "um agente do hermes focado em aprendizado": ele abre https://tactiq.io/tools/youtube-transcript, cola o link do
vídeo, espera a transcrição e salva em `transcricoes/` do nayia, no PC. Perfil `aprendizado`, serviço
`hermes-gateway-aprendizado`, API 127.0.0.1:8646. Usa o MESMO Chrome do Agente OLX (porta 9303; o tactiq barra Chrome
sem janela, o reCAPTCHA dele devolve 403). Ferramentas: as do olx + `salvar_transcricao` (`mcp_transcricao.py`): espera
a lista, clica em Copy segurando o texto na própria página (a área de transferência do PC não muda) e faz o Chrome gravar
o .txt direto na pasta do PC (`Browser.setDownloadBehavior`, que volta ao normal logo depois). O texto não passa pelo
modelo. Publicar: `./nay-agentes/hermes-painel/publicar.sh aprendizado`. Teste sem o agente, na VPS2:
`python /opt/hermes-painel/mcp_transcricao.py <link>` (com a página do tactiq já aberta no Chrome do agente).
