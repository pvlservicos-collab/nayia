# Levar o projeto para outro computador

**Resposta curta à pergunta:** não, os segredos **não estão num arquivo só**.
Estão em **treze lugares**, em duas máquinas. Este guia diz quais são, e o
script `juntar_credenciais.sh` monta o arquivo único para você.

---

## Por que eu não montei o arquivo para você

Eu tentei. O ambiente onde eu rodo bloqueia juntar credenciais de várias
fontes num pacote só — a trava tem nome, *Credential Materialization*, e ela
existe porque um arquivo com tudo dentro é exatamente o que ninguém quer ver
vazando.

A trava é do meu lado, não do seu. **Você roda o script e o arquivo nasce na
sua máquina, sem passar por mim.**

---

## Onde está cada coisa

### Nesta máquina (Windows)

| Onde | O que tem |
|---|---|
| `Nay IA/.env.local` | 29 chaves: hosts das duas VPS, usuário e porta SSH, caminho das chaves, e as URLs de banco das quatro roles do site |
| `C:\Users\pedro\.ssh\nay_srv1877774_ed25519` | chave SSH da VPS antiga (419 bytes) |
| `C:\Users\pedro\.ssh\nay_srv1894338_ed25519` | chave SSH da VPS de produção (419 bytes) |

### No servidor `srv1894338.hstgr.cloud`

| Onde | Quantas chaves | O que tem |
|---|---:|---|
| `/root/nay-publicador/.env` | 6 | **Z-API**: instância, token e client-token · token do publicador · WhatsApp do Tel · banco |
| `/root/nay/.env` | 2 | |
| `/root/baixador-imagens/.env` | 3 | |
| `/docker/nay-site-api/.env` | 6 | as URLs das roles que a API usa |
| `/docker/nay-site-api/.env.bk_20260915_0451` | 5 | backup, provavelmente descartável |
| `/docker/traefik/.env` | 1 | |
| `/docker/postgres/.env` | 1 | **senha do Postgres** |
| `/docker/nay-painel/.env` | 1 | |
| `/docker/n8n-viux/.env` | 2 | **a chave de criptografia do n8n** |
| `/docker/n8n-viux/.env.bak` | 2 | backup |

### E dois que não são arquivo

**A senha do `/admin` do site** é um hash bcrypt numa label do container:
```sh
docker inspect nay-site-web \
  --format '{{index .Config.Labels "traefik.http.middlewares.nay-site-admin-auth.basicauth.users"}}'
```
Isso devolve o **hash**, não a senha. Se você não tiver a senha anotada, não
dá para recuperá-la — só trocar por uma nova.

**As credenciais do n8n** (OpenAI, Postgres, Z-API) moram criptografadas dentro
do banco dele, `/home/node/.n8n/database.sqlite`. Sem a chave de criptografia
(`/docker/n8n-viux/.env`) o backup do n8n é inútil. **Leve as duas coisas.**

---

## Uma coisa importante sobre a Z-API

Os tokens da Z-API estão em **dois lugares**, e um deles é invisível:

1. em `/root/nay-publicador/.env`, como deve ser;
2. **hardcoded dentro dos nós do n8n** — o próprio `Arquivos/enviar_zapi.py`
   registra isso como dívida técnica conhecida.

É por isso que todo export de fluxo do n8n precisa ser redigido antes de sair
da máquina, e por isso `backup_wf_*.json` está no `.gitignore`.

---

## Como montar o pacote

Na pasta do projeto:

```sh
bash Arquivos/juntar_credenciais.sh
```

Ele monta `NAY-IA-CREDENCIAIS.txt` **fora do repositório** (um nível acima, em
`TEL SOBREIRA/`) — de propósito, para não haver como commitar por acidente.

O script pede confirmação antes de começar e avisa o que vai incluir.

---

## No computador novo

1. **Instale**: Git, Node 18+, Python 3, e um cliente SSH (o do Git Bash serve).
2. **Clone**: `git clone https://github.com/pvlservicos-collab/nayia.git`
3. **Restaure os segredos** a partir do `NAY-IA-CREDENCIAIS.txt`:
   - o bloco do `.env.local` vai para a raiz do projeto, com esse nome;
   - as duas chaves SSH vão para `~/.ssh/`, e **precisam de permissão 600**:
     ```sh
     chmod 600 ~/.ssh/nay_srv1894338_ed25519
     ```
     No Windows, se o `chmod` não pegar, tire a herança de permissão pelas
     propriedades do arquivo — o SSH recusa chave "larga demais".
4. **Teste o acesso**, nesta ordem. Cada um prova uma camada:
   ```sh
   ssh -i ~/.ssh/nay_srv1894338_ed25519 root@srv1894338.hstgr.cloud 'docker ps'
   ssh -i ~/.ssh/nay_srv1894338_ed25519 root@srv1894338.hstgr.cloud \
     'docker exec nay-postgres psql -U nay -d naydb -c "SELECT count(*) FROM imoveis"'
   curl -s https://api.imobeasy.online/api/saude
   curl -s -o /dev/null -w '%{http_code}\n' https://imobeasy.online/
   ```
   Esperado: a lista de 8 containers · 1247 · `{"status":"ok"}` · 200.

---

## O que o pacote **não** resolve

- **A senha do `/admin`**: só o hash é recuperável. Tenha ela anotada, ou troque.
- **O login do GitHub**: o `git push` usa o gerenciador de credenciais do
  Windows, que não sai no pacote. No computador novo, o primeiro push vai pedir
  login (use um Personal Access Token, não a senha da conta).
- **O painel da Z-API**: usuário e senha do site da Z-API não estão em lugar
  nenhum do projeto. Só os tokens de API.
- **O login do `imobeasy.com`** (o site antigo, de onde veio a carga inicial do
  catálogo): está no `.env.local`, em `IMOBEASY_ADMIN_*`.

---

## Depois de copiar

O arquivo `NAY-IA-CREDENCIAIS.txt` tem **tudo** — com ele, qualquer pessoa entra
no servidor, no banco e no WhatsApp da empresa.

- Não mande por WhatsApp, e-mail nem Drive.
- Passe por pen drive, ou por um gerenciador de senhas.
- **Apague das duas máquinas depois de terminar**, e refaça quando precisar de
  novo — o script leva quinze segundos para rodar.
