#!/usr/bin/env bash
# =====================================================================
# MONTA A PASTA COM TODOS OS SEGREDOS DO PROJETO
#
# Pedido do Tel (19/09/2026): "de que adianta isso se os arquivos sensiveis
# nao sao subidos para o github? junte todos eles numa pasta para eu copiar
# e colar no outro pc".
#
# Ele tem razao: clonar do GitHub da o codigo e mais nada. Sem os .env o
# projeto nao sobe, e sem as chaves SSH nao da nem para entrar no servidor.
#
# A PASTA E MELHOR QUE UM ARQUIVO SO: cada arquivo mantem o nome e o
# caminho de destino, entao restaurar e copiar de volta -- nao e recortar
# pedaco de um blocao e adivinhar onde cada um vai.
#
# RODE DAQUI:  bash Arquivos/juntar_credenciais.sh
#
# A pasta nasce FORA do repositorio (um nivel acima), de proposito: assim
# nao existe o caminho de commitar por acidente.
# =====================================================================
set -u

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESTINO="$(cd "$RAIZ/.." && pwd)/NAY-IA-SEGREDOS"
CHAVE="$HOME/.ssh/nay_srv1894338_ed25519"
CHAVE_VELHA="$HOME/.ssh/nay_srv1877774_ed25519"
SRV="root@srv1894338.hstgr.cloud"

echo
echo "  Isto monta a pasta com TODOS os segredos do projeto:"
echo "    $DESTINO"
echo
echo "  Com ela, qualquer pessoa entra no servidor, no banco e no WhatsApp"
echo "  da empresa. Pen drive ou gerenciador de senhas -- nao WhatsApp,"
echo "  nao e-mail, nao Drive."
echo
printf "  Continuar? [s/N] "
read -r RESP
case "$RESP" in s|S|sim|SIM) ;; *) echo "  cancelado."; exit 0 ;; esac

[ -f "$RAIZ/.env.local" ] || { echo "ERRO: nao achei $RAIZ/.env.local"; exit 1; }
[ -f "$CHAVE" ]           || { echo "ERRO: nao achei a chave SSH $CHAVE"; exit 1; }

rm -rf "$DESTINO"
mkdir -p "$DESTINO/windows/ssh" \
         "$DESTINO/servidor/root/nay-publicador" \
         "$DESTINO/servidor/root/nay" \
         "$DESTINO/servidor/root/baixador-imagens" \
         "$DESTINO/servidor/docker/nay-site-api" \
         "$DESTINO/servidor/docker/traefik" \
         "$DESTINO/servidor/docker/postgres" \
         "$DESTINO/servidor/docker/nay-painel" \
         "$DESTINO/servidor/docker/n8n-viux"

# ---- 1. o que esta nesta maquina ------------------------------------
echo "  copiando o desta maquina..."
cp "$RAIZ/.env.local"      "$DESTINO/windows/.env.local"
cp "$CHAVE"                "$DESTINO/windows/ssh/"
[ -f "$CHAVE.pub" ]        && cp "$CHAVE.pub"       "$DESTINO/windows/ssh/"
[ -f "$CHAVE_VELHA" ]      && cp "$CHAVE_VELHA"     "$DESTINO/windows/ssh/"
[ -f "$CHAVE_VELHA.pub" ]  && cp "$CHAVE_VELHA.pub" "$DESTINO/windows/ssh/"

# ---- 2. os .env do servidor, cada um no seu caminho -----------------
echo "  buscando os .env do servidor..."
FALHOU=0
baixa() {  # baixa <caminho no servidor> <caminho local>
  if scp -q -i "$CHAVE" -o StrictHostKeyChecking=no "$SRV:$1" "$2" 2>/dev/null; then
    echo "    ok   $1"
  else
    echo "    --   $1  (nao existe ou sem acesso)"
    FALHOU=$((FALHOU+1))
  fi
}
baixa /root/nay-publicador/.env    "$DESTINO/servidor/root/nay-publicador/.env"
baixa /root/nay/.env               "$DESTINO/servidor/root/nay/.env"
baixa /root/baixador-imagens/.env  "$DESTINO/servidor/root/baixador-imagens/.env"
baixa /docker/nay-site-api/.env    "$DESTINO/servidor/docker/nay-site-api/.env"
baixa /docker/traefik/.env         "$DESTINO/servidor/docker/traefik/.env"
baixa /docker/postgres/.env        "$DESTINO/servidor/docker/postgres/.env"
baixa /docker/nay-painel/.env      "$DESTINO/servidor/docker/nay-painel/.env"
baixa /docker/n8n-viux/.env        "$DESTINO/servidor/docker/n8n-viux/.env"

# ---- 3. os dois que nao sao arquivo ---------------------------------
echo "  lendo o que nao esta em arquivo..."
ssh -i "$CHAVE" -o StrictHostKeyChecking=no -o ConnectTimeout=25 "$SRV" '
docker inspect nay-site-web \
  --format "{{index .Config.Labels \"traefik.http.middlewares.nay-site-admin-auth.basicauth.users\"}}" 2>/dev/null
' > "$DESTINO/servidor/_senha_do_admin_HASH.txt" 2>/dev/null

# O sqlite do n8n guarda as credenciais CRIPTOGRAFADAS. Sem a chave que
# esta em /docker/n8n-viux/.env, este arquivo nao serve para nada -- por
# isso os dois viajam juntos.
echo "  copiando o banco do n8n (credenciais criptografadas)..."
ssh -i "$CHAVE" -o StrictHostKeyChecking=no "$SRV" \
  'docker exec n8n-viux-n8n-1 cat /home/node/.n8n/database.sqlite' \
  > "$DESTINO/servidor/n8n_database.sqlite" 2>/dev/null

# ---- 4. um dump do banco, para subir em outro lugar se precisar -----
printf "  Incluir um dump do Postgres (~4 MB)? [s/N] "
read -r DUMP
case "$DUMP" in s|S|sim|SIM)
  echo "  gerando o dump..."
  ssh -i "$CHAVE" -o StrictHostKeyChecking=no "$SRV" \
    'docker exec nay-postgres pg_dump -U nay -d naydb -Fc' \
    > "$DESTINO/servidor/naydb_$(date +%Y%m%d).dump" 2>/dev/null
  ;;
esac

# ---- 5. o mapa, dentro da propria pasta -----------------------------
cat > "$DESTINO/LEIA-ME.txt" <<'TXT'
SEGREDOS DO PROJETO NAY IA
==========================

O que e cada coisa, e para onde ela volta.

windows/.env.local
    Vai para a RAIZ do projeto, com esse nome. 29 chaves: os hosts das duas
    VPS, usuario e porta SSH, e as URLs de banco das quatro roles do site.

windows/ssh/nay_srv1894338_ed25519      <- a VPS de PRODUCAO, e a que importa
windows/ssh/nay_srv1877774_ed25519      <- a VPS antiga, hoje sem container
    Vao para ~/.ssh/ e PRECISAM de permissao 600:
        chmod 600 ~/.ssh/nay_srv1894338_ed25519
    No Windows, se o chmod nao pegar: propriedades do arquivo > Seguranca >
    Avancado > desativar heranca > deixar so o seu usuario. O SSH recusa
    chave "larga demais" e nao explica direito o motivo.

servidor/...
    Os .env do servidor, cada um no caminho em que ele mora la. So servem se
    voce for REINSTALAR o servidor -- no dia a dia eles ja estao no lugar.
    Para devolver:  bash restaurar_no_servidor.sh

servidor/_senha_do_admin_HASH.txt
    O hash bcrypt da senha do /admin do site. E o HASH, nao a senha: nao da
    para recuperar a original, so trocar por uma nova.

servidor/n8n_database.sqlite
    O banco do n8n, com os fluxos e as credenciais (OpenAI, Postgres, Z-API)
    CRIPTOGRAFADAS. Sem a chave que esta em
    servidor/docker/n8n-viux/.env este arquivo e inutil. Os dois andam juntos.

servidor/naydb_*.dump   (se voce escolheu incluir)
    Dump do Postgres. Restaura com:
        pg_restore -U nay -d naydb --clean --if-exists ARQUIVO.dump


O QUE NAO ESTA AQUI, E POR QUE
------------------------------
* O login do GitHub. Fica no gerenciador de credenciais do Windows. No PC
  novo o primeiro push vai pedir -- use um Personal Access Token.
* O usuario e a senha do painel da Z-API (o site deles). Aqui so estao os
  tokens de API.
* A senha do /admin em texto. So o hash existe.


NO COMPUTADOR NOVO, NESTA ORDEM
-------------------------------
1. git clone https://github.com/pvlservicos-collab/nayia.git
2. copie windows/.env.local para a raiz do projeto
3. copie windows/ssh/* para ~/.ssh/ e ajuste a permissao
4. teste, um de cada vez:
     ssh -i ~/.ssh/nay_srv1894338_ed25519 root@srv1894338.hstgr.cloud 'docker ps'
     ssh -i ~/.ssh/nay_srv1894338_ed25519 root@srv1894338.hstgr.cloud \
       'docker exec nay-postgres psql -U nay -d naydb -c "SELECT count(*) FROM imoveis"'
     curl -s https://api.imobeasy.online/api/saude
   Esperado: 8 containers, 1247, e {"status":"ok"}.

DEPOIS DE USAR, APAGUE ESTA PASTA DAS DUAS MAQUINAS.
Refazer leva quinze segundos: bash Arquivos/juntar_credenciais.sh
TXT

# ---- 6. o script que devolve os .env ao servidor --------------------
cat > "$DESTINO/restaurar_no_servidor.sh" <<'TXT'
#!/usr/bin/env bash
# Devolve os .env para um servidor REINSTALADO. Nao rode contra o servidor
# que esta no ar sem saber o que esta fazendo -- ele sobrescreve.
set -eu
CHAVE="${1:-$HOME/.ssh/nay_srv1894338_ed25519}"
SRV="${2:-root@srv1894338.hstgr.cloud}"
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/servidor"
printf "Sobrescrever os .env de %s ? [s/N] " "$SRV"; read -r R
case "$R" in s|S|sim|SIM) ;; *) echo cancelado; exit 0 ;; esac
cd "$AQUI"
find root docker -name ".env" | while read -r f; do
  ssh -i "$CHAVE" "$SRV" "mkdir -p /$(dirname "$f")"
  scp -q -i "$CHAVE" "$f" "$SRV:/$f" && echo "ok  /$f"
done
echo "Pronto. Reinicie os containers que precisarem."
TXT
chmod +x "$DESTINO/restaurar_no_servidor.sh" 2>/dev/null || true

# ---- 7. prova -------------------------------------------------------
echo
echo "  PRONTO."
echo "    pasta.....: $DESTINO"
echo "    arquivos..: $(find "$DESTINO" -type f | wc -l)"
echo "    tamanho...: $(du -sh "$DESTINO" 2>/dev/null | cut -f1)"
[ "$FALHOU" -gt 0 ] && echo "    ATENCAO...: $FALHOU arquivo(s) do servidor nao vieram (veja acima)"
echo
echo "    fora do repositorio? $( case "$DESTINO" in "$RAIZ"*) echo 'NAO -- CUIDADO';; *) echo 'sim, nao tem como commitar';; esac )"
echo
echo "  Leia o LEIA-ME.txt de dentro dela. Apague das duas maquinas depois."
echo
