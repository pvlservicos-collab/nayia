# Vistto — Sistema de Vistoria de Imóveis

App mobile do vistoriador (offline), painel administrativo com fluxo de aprovação, leitura de contrato por IA, assinatura ClickSign e laudo público compartilhável.

| Onde | Endereço | Quem usa |
|---|---|---|
| Painel administrativo | `https://SEU-DOMINIO/admin/` | Imobiliária / administrador |
| App do vistoriador (PWA) | `https://SEU-DOMINIO/app/` | Vistoriador no celular (instala na tela inicial) |
| Laudo público | `https://SEU-DOMINIO/v/<código>` | Locatário, locador, qualquer pessoa com o link |
| Contestação | `https://SEU-DOMINIO/c/<código>` | Locatário (pelo QR Code do laudo) |

Acesso inicial (definido no `.env`; padrão se não definir):
- Administrador: `admin@vistto.app` / `admin123`
- Vistoriador de exemplo: `vistoriador@vistto.app` / `123456`

> Troque as senhas logo após o primeiro acesso (Configurações → Usuários e vistoriadores).

---

## 1. Subir na VPS com Docker (recomendado)

Requisitos: VPS Linux (Ubuntu 22/24) com 2 GB de RAM, Docker e um domínio apontando para o IP da VPS (registro **A**).

```bash
# 1. Instale o Docker (se ainda não tiver)
curl -fsSL https://get.docker.com | sh

# 2. Envie o zip para a VPS e descompacte
unzip vistto-vistorias.zip -d /opt/vistto && cd /opt/vistto

# 3. Configure
cp .env.example .env
nano .env        # ajuste DOMAIN, PUBLIC_URL, APP_SECRET e ADMIN_*

# 4. Suba (o Caddy gera o HTTPS automaticamente)
docker compose up -d --build

# Logs
docker compose logs -f app
```

Pronto: acesse `https://SEU-DOMINIO/admin/`.

**Por que HTTPS é obrigatório:** câmera, microfone, localização e o modo offline (service worker) só funcionam em HTTPS no celular. O `docker-compose.yml` já inclui o Caddy, que emite e renova o certificado sozinho.

### Atualizar para uma nova versão
```bash
cd /opt/vistto && unzip -o nova-versao.zip && docker compose up -d --build
```
Os dados ficam nas pastas `data/` (banco) e `uploads/` (fotos, áudios, PDFs) e não são apagados.

### Backup
Copie as pastas `data/` e `uploads/` (ex.: `tar czf backup-$(date +%F).tgz data uploads`).

---

## 2. Subir sem Docker (Node + PM2 + Nginx)

```bash
# Node 22+ e Chromium (para o PDF)
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs chromium-browser fonts-liberation nginx certbot python3-certbot-nginx
# (em algumas versões do Ubuntu o pacote é "chromium"; ajuste CHROME_PATH no .env se precisar)

cd /opt/vistto && npm ci --omit=dev
cp .env.example .env && nano .env
sudo npm i -g pm2 && pm2 start deploy/ecosystem.config.js && pm2 save && pm2 startup

sudo cp deploy/nginx.conf.example /etc/nginx/sites-available/vistto   # edite o domínio
sudo ln -s /etc/nginx/sites-available/vistto /etc/nginx/sites-enabled/
sudo certbot --nginx -d vistorias.seudominio.com.br
```

Para testar no computador: `npm install && npm start` → http://localhost:3000

---

## 3. Integrações (Painel → Configurações → Parâmetros → Integrações)

Tudo funciona sem integrações (modo demonstração), e cada uma pode ser ligada depois:

| Integração | Sem configurar | Configurada |
|---|---|---|
| **ClickSign** | Modo simulação: você confirma cada assinatura no painel | Envelope real na ClickSign, e-mail de assinatura para cada parte, webhook atualiza o status |
| **SMTP** | E-mails ficam na “Caixa de saída” (menu E-mails) | E-mails de vistoria inicial/final e do documento assinado (com PDF anexo) são enviados |
| **IA (Anthropic/Claude)** | Extrator local lê contratos de locação em PDF digital | IA lê qualquer contrato (inclusive escaneado) e descreve itens a partir das fotos |

**ClickSign:** gere o *Access Token* em ClickSign → Configurações → API. Use `sandbox` para testes e `production` depois. Cadastre o webhook com a URL mostrada no painel (`https://SEU-DOMINIO/api/webhooks/clicksign`) e, se quiser, defina o segredo HMAC.

**Gmail como SMTP:** host `smtp.gmail.com`, porta `587`, usuário = seu e-mail, senha = *senha de app* do Google.

---

## 4. Como o fluxo funciona

1. **Vistoriador (app):** Nova vistoria → modalidade → cômodos (adição rápida + nomes próprios que ficam salvos na lista) → em cada cômodo: fotos (botão verde), itens/móveis com estado (Novo/Bom/Regular/Mau), funcionamento, quantidade, fotos exclusivas, observações com **botão de áudio** (transcreve) e vídeo → liga **Inconformidade** → título, descrição e foto da avaria → marca **bolinhas vermelhas** → dados (anexa o contrato e a IA preenche) → envia.
   Sem internet, tudo fica salvo no aparelho e sobe sozinho quando conectar.
2. **Painel → Aprovações:** a vistoria chega em “Recebidas do app”. Ao abrir, ela entra no fluxo de 6 etapas:
   1. Fotos e cômodos — revisar fotos, mover fotos para itens, criar avarias a partir de fotos, marcar bolinhas.
   2. Contrato (IA) — anexar o PDF; a IA extrai imóvel, partes e contrato; você escolhe o que aplicar.
   3. Dados do laudo — completar o que faltar para ficar igual ao modelo (checklist de completude ao lado).
   4. Revisão do laudo — pré-visualização idêntica ao link público + PDF prévia.
   5. Aprovação — gera o **link público** e envia o **e-mail de vistoria inicial** (entrada) ou **final** (saída).
   6. Assinaturas — gera o PDF e envia à **ClickSign** com os e-mails das partes. Quando todos assinam, o PDF assinado é salvo e **enviado por e-mail** a todos.
3. **Laudo público:** abas *Laudo completo* (tudo por extenso, avarias no final com o cômodo acima do título e todas as fotos com data), *Fotos* (todas, por cômodo) e *Inconformidades* (por cômodo). Compartilhar, imprimir/PDF e QR Codes de mídias e contestação.
4. **Vistoria de saída:** em uma vistoria de entrada aprovada, “Gerar vistoria de saída” copia cômodos e itens; o laudo de saída mostra o estado de cada item na entrada.

**Telas do app:** o menu *Telas do app* mostra todas as telas do mobile ao vivo (dados de demonstração), sem precisar abrir o celular.

---

## 5. Estrutura do projeto

```
server/            API (Express) + banco SQLite (node:sqlite, sem dependências nativas)
  routes/api.js    rotas do app e do painel
  routes/public.js laudo público, PDF, contestação, webhook ClickSign
  services/        laudo (HTML), pdf (Chromium), clicksign, mailer, ai, workflow
public/app/        app do vistoriador (PWA offline, IndexedDB)
public/admin/      painel administrativo
public/laudo/      estilo e script do laudo público
deploy/            Caddyfile, Nginx, PM2
data/  uploads/    banco e arquivos (persistentes)
```

Comandos úteis: `npm run reset` (apaga o banco para recomeçar), `SEED_DEMO=false` no `.env` para começar sem vistorias de exemplo.
