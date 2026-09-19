# 29 — Estado do publicador e ponto de retomada

*Escrito em 25/08/2026, ao fim de uma sessão longa. Registra exatamente
onde o publicador parou, o que está funcionando, e o passo a passo da
retomada — para a próxima sessão começar sem reconstruir contexto.*

---

## O que está PRONTO e FUNCIONANDO

O backend inteiro do publicador está construído, testado e no ar.

**As nove peças de lógica (Python), todas testadas e commitadas:**
- `buscar_imovel.py` — lê imóvel do anúncio individual do site (com tipo e contagem de vagas corretas)
- `montar_destinos.py` — dado um imóvel, devolve grupos elegíveis; lê do banco (`carregar_grupos_db`), CSV só para teste
- `montar_mensagem.py` — texto por grupo (grupo de venda omite locação)
- `enviar_zapi.py` — envio de texto e fotos, cadência anti-banimento, 3 variáveis de credencial (instância, token, client-token)
- `agendador.py` — decide quais vagas disparam agora (conversão de dia da semana Postgres↔Python validada)
- `interpretar_comando.py` — linguagem natural → operação estruturada, nunca adivinha
- `liberar_vaga.py` — VENDEU/ALUGOU remove só o código vendido, avisa quando esvazia
- `publicador.py` — `processar_comando(texto, conexao)` cola tudo, dispatch das 5 ações
- `db.py` — `conectar()` lê `DATABASE_URL`, RealDictCursor

**Infraestrutura no servidor:**
- Tudo roda em `/root/nay-publicador/`, com `.venv` configurado
- Ponte git funcionando: Mac edita → commit/push → `git pull` no servidor. Repo privado `github.com/Telsobreira/nay-publicador`
- Tabela `grupos` com colunas `aceita_venda`/`aceita_locacao` (só "SÓ TERCEIROS COMPRA, VEN" tem locação=false)
- Tabela `vagas` criada (grade de horários, com os CHECKs de consistência)
- Serviço HTTP `servidor.py` (Flask) rodando como **systemd** (`nay-publicador.service`): sempre ligado, reinicia sozinho, sobe no boot
- Autenticação por token (`PUBLICADOR_TOKEN` no `.env`)

**Validado ponta a ponta no servidor:**
- `VAGAS`, criar vaga, listar de volta — tudo contra o banco real
- Disparo real do 5644 redirecionado ao número do Tel: os 10 grupos vieram do banco, a mensagem saiu certa por grupo, e o grupo "SÓ TERCEIROS COMPRA, VEN" recebeu SÓ venda enquanto os outros 9 receberam venda+locação. **A trava do grupo funciona com dado real.**
- O container do n8n **alcança** o serviço: `http://172.16.0.1:8080/comando` retorna 401 sem token (prova que a rede está aberta)

**Hoje o Tel já pode comandar o publicador — só que pelo terminal do
servidor, não pelo WhatsApp ainda.**

---

## O que FALTA (dois elos)

### Elo A — n8n chamar o serviço pelo WhatsApp (o último passo da integração)

O `Comando do Tel` no n8n hoje reconhece RESPOSTA, DESCARTAR, DESCARTAR
TUDO, PENDENCIAS. Precisa:

1. **Reconhecer os comandos novos** do publicador (`posta`, `VENDEU`,
   `ALUGOU`, `VAGAS`) — no mesmo nó `Comando do Tel`, como mais padrões,
   devolvendo uma ação nova (ex: `acao: 'PUBLICADOR'` com o texto
   original)
2. **Criar um caminho** que, quando a ação for de publicador, chama o
   serviço HTTP via um nó **HTTP Request**:
   - URL: `http://172.16.0.1:8080/comando`
   - Método: POST
   - Header: `Authorization: Bearer <PUBLICADOR_TOKEN>` (o mesmo do
     `.env` do servidor — no n8n, guardar como credencial ou variável,
     nunca em texto puro no nó)
   - Body JSON: `{"texto": "<o comando original do Tel>"}`
3. **Rotear a resposta** (`{"resposta":"..."}`) de volta para o WhatsApp
   do Tel, no mesmo padrão que RESPOSTA/PENDENCIAS já respondem

**Estrutura real do `Comando do Tel` (lida em 25/08):** trava de teste
nas linhas 1-3 (só o número do Tel passa), quebra em linhas na 4, testa
os padrões nas 5-16, devolve `[]` na 17 se nada bateu. Cada comando
devolve `{ json: { acao, p_id, p_texto, tel_tel } }`. O nó só
RECONHECE; a ação acontece em nós conectados depois.

**Cuidados para a retomada:**
- Este é o fluxo `Nay- recebe mensagem` (id `sQuiEjbEDMEbjX5U`) — é
  **produção viva**, atende corretor agora. Qualquer erro afeta
  atendimento real.
- Testar a cada passo, sem quebrar RESPOSTA/DESCARTAR/PENDENCIAS.
- A extensão do navegador esteve **instável** na sessão de 25/08
  (travou/perdeu conexão várias vezes). Recomendação: o Claude guia e o
  Tel executa na tela, passo a passo, em vez de edição direta pela
  extensão — para não deixar o fluxo de produção pela metade.
- Antes de montar: confirmar como o `Comando do Tel` se conecta aos nós
  seguintes (não foi mapeado ainda), para saber onde encaixar o caminho
  novo sem quebrar os existentes.

### Elo B — cron da grade (a parte 2, ainda não iniciada)

A vaga "todo dia às 14h" está gravada, mas **nada dispara ela às 14h**.
Falta um cron no servidor rodando o `agendador.py` de minuto em minuto,
que: lê a grade, decide o que dispara agora, e para cada vaga devida
chama o mesmo caminho de envio (buscar → montar destinos → montar
mensagem por grupo → enviar). Isso é independente do Elo A.

---

## PENDÊNCIA DE SEGURANÇA — rotação de credenciais Z-API (OBRIGATÓRIA)

Durante as sessões, os **três** valores da Z-API apareceram em texto
puro na conversa: ID da instância, token da instância, e Client-Token
(o "Token de segurança da conta"). Os valores não são repetidos aqui
de propósito -- este arquivo vai para o git, e a regra seguida o tempo
todo é que segredo exposto não se repete em lugar novo.

Pela regra seguida o tempo todo (credencial exposta = comprometida), os
três precisam ser rotacionados.

**Onde:** painel Z-API, conta "Tel Sobreira", instância "Imob ease IA".
- Client-Token: aba **Segurança**, item 3 "Token de segurança da conta",
  botão de regenerar (setinha circular). Troca segura, não derruba
  WhatsApp.
- ID/Token da instância: aba **Instâncias Web**. ⚠️ Rotacionar o token da
  instância PODE exigir reconectar o WhatsApp (QR code) → derruba a Nay
  alguns minutos → fazer em momento acompanhado.

**Depois de gerar os novos:** trocar as três linhas no `.env` do
servidor (`/root/nay-publicador/.env`) e reiniciar o serviço
(`systemctl restart nay-publicador`). No n8n, os nós que usam Z-API
(`Enviar Z-API` e outros) também têm o token hardcoded — precisam ser
atualizados lá também (dívida técnica já conhecida: mover para
credencial do n8n em vez de texto puro).

A senha root do servidor também foi trocada 2x nas sessões por
exposição — a atual é a que o Tel definiu por último.

---

## Notas de método que funcionaram (manter)

- O `.env` **nunca** vai para o git (`.gitignore` cobre). Credenciais
  gravadas por comando que não exibe o valor (`docker exec ... printenv`,
  `secrets.token_urlsafe`), nunca coladas no chat.
- Confirmar que "sem erro" ≠ "aplicado": testar `\d tabela`, `git log`
  hash local vs origin, `systemctl status`, leitura fresca do nó.
- Dessincronia git recorrente: o Tel roda `git pull` antes do push
  chegar ao GitHub. Resolver confirmando o hash antes de puxar.
- Terminal do Mac (SSH) é mais estável que o terminal web da Hostinger e
  que a extensão do navegador — preferir para trabalho crítico.
- O Claude Code se auto-registra no `HISTORICO-APRENDIZADO.md` a cada bug
  real corrigido (regra no `CLAUDE.md`), e explica o porquê nos commits.
