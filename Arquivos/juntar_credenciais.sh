#!/usr/bin/env bash
# =====================================================================
# JUNTA TODOS OS SEGREDOS DO PROJETO NO .env.local
#
# Pedido do Tel (19/09/2026): "junte tudo no env local" -- para poder levar
# o projeto inteiro para outro computador copiando um arquivo so.
#
# Os segredos estao espalhados em 13 lugares, em duas maquinas. Este script
# busca todos e acrescenta ao `.env.local`, em secoes marcadas.
#
# RODE DAQUI:  bash Arquivos/juntar_credenciais.sh
#
# O QUE ELE FAZ, nesta ordem:
#   1. faz backup do .env.local atual (com data no nome);
#   2. puxa os 8 arquivos .env do servidor por SSH;
#   3. le o hash da senha do /admin (label do traefik);
#   4. embute as duas chaves SSH privadas, para o arquivo bastar sozinho;
#   5. escreve tudo no .env.local, entre marcadores.
#
# E IDEMPOTENTE: rodar de novo apaga o bloco anterior e refaz. Nao duplica.
#
# O .env.local ja esta no .gitignore. Confira antes de commitar qualquer
# coisa:  git status --porcelain | grep env
# =====================================================================
set -u

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV="$RAIZ/.env.local"
CHAVE="$HOME/.ssh/nay_srv1894338_ed25519"
CHAVE_VELHA="$HOME/.ssh/nay_srv1877774_ed25519"
SRV="root@srv1894338.hstgr.cloud"
INI="# ===== INICIO DO BLOCO JUNTADO AUTOMATICAMENTE ====="
FIM="# ===== FIM DO BLOCO JUNTADO AUTOMATICAMENTE ====="

echo
echo "  Isto vai juntar TODOS os segredos do projeto em:"
echo "    $ENV"
echo
echo "  Depois disso, esse arquivo sozinho da acesso ao servidor, ao banco"
echo "  e ao WhatsApp da empresa. Nao mande por WhatsApp, e-mail nem Drive."
echo
printf "  Continuar? [s/N] "
read -r RESP
case "$RESP" in s|S|sim|SIM) ;; *) echo "  cancelado."; exit 0 ;; esac

[ -f "$ENV" ] || { echo "ERRO: nao achei $ENV"; exit 1; }
[ -f "$CHAVE" ] || { echo "ERRO: nao achei a chave SSH $CHAVE"; exit 1; }

# ---- 1. backup -------------------------------------------------------
BK="$ENV.bk_$(date +%Y%m%d_%H%M%S)"
cp "$ENV" "$BK"
echo "  backup: $(basename "$BK")"

# ---- 2. tira o bloco anterior, se houver -----------------------------
if grep -qF "$INI" "$ENV"; then
  awk -v ini="$INI" -v fim="$FIM" '
    index($0, ini) { pulando = 1 }
    !pulando { print }
    index($0, fim) { pulando = 0 }
  ' "$BK" > "$ENV"
  echo "  bloco anterior removido (refazendo)"
fi

# ---- 3. monta o bloco novo -------------------------------------------
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

{
  echo ""
  echo "$INI"
  echo "# Montado por Arquivos/juntar_credenciais.sh em $(date '+%d/%m/%Y %H:%M')."
  echo "# Rode o script de novo para atualizar -- ele refaz este bloco inteiro."
  echo ""
} >> "$TMP"

echo "  buscando os .env do servidor..."
ssh -i "$CHAVE" -o StrictHostKeyChecking=no -o ConnectTimeout=25 "$SRV" '
for f in /root/nay-publicador/.env /root/nay/.env /root/baixador-imagens/.env \
         /docker/nay-site-api/.env /docker/traefik/.env /docker/postgres/.env \
         /docker/nay-painel/.env /docker/n8n-viux/.env; do
  [ -f "$f" ] || continue
  echo "# ---------- servidor: $f ----------"
  grep -vE "^[[:space:]]*(#|$)" "$f"
  echo
done
echo "# ---------- senha do /admin do site (HASH bcrypt, nao e a senha) ----------"
docker inspect nay-site-web \
  --format "{{index .Config.Labels \"traefik.http.middlewares.nay-site-admin-auth.basicauth.users\"}}" \
  2>/dev/null | sed "s/^/ADMIN_SITE_BASICAUTH_HASH=/"
echo
' >> "$TMP" 2>/dev/null || { echo "  ERRO: nao consegui ler o servidor."; exit 1; }

# ---- 4. as chaves SSH, para o arquivo bastar sozinho -----------------
{
  echo "# ---------- chave SSH da VPS de producao (srv1894338) ----------"
  echo "# Salve o miolo em ~/.ssh/nay_srv1894338_ed25519 e rode: chmod 600 nesse arquivo."
  sed 's/^/# /' "$CHAVE"
  echo
  if [ -f "$CHAVE_VELHA" ]; then
    echo "# ---------- chave SSH da VPS antiga (srv1877774, sem container) ----------"
    sed 's/^/# /' "$CHAVE_VELHA"
    echo
  fi
  echo "$FIM"
} >> "$TMP"

cat "$TMP" >> "$ENV"

# ---- 5. prova -------------------------------------------------------
echo
echo "  PRONTO."
echo "    arquivo...: $ENV"
echo "    tamanho...: $(wc -c < "$ENV") bytes  (antes: $(wc -c < "$BK"))"
echo "    valores...: $(grep -cE '^[A-Z][A-Z0-9_]*=' "$ENV")"
echo "    secoes....: $(grep -c '^# ----------' "$ENV")"
echo
if git -C "$RAIZ" check-ignore -q .env.local 2>/dev/null; then
  echo "    git.......: .env.local esta IGNORADO. Nao vai para o GitHub."
else
  echo "    git.......: ATENCAO -- o .env.local NAO esta ignorado. Nao commite."
fi
echo
echo "  Para levar: copie o .env.local e a pasta do projeto (ou clone do GitHub)."
echo "  Leia Arquivos/MUDAR-DE-COMPUTADOR.md para os passos na maquina nova."
echo "  Apague o arquivo das duas maquinas quando terminar."
echo
