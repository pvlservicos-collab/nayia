#!/bin/bash
# Põe no .env do nay-core a mesma instância da Z-API que o fluxo "NAI atendimento locação" usa para
# enviar. Nenhum segredo é impresso: a instância e os tokens são lidos do .env do publicador, conferidos
# contra o nó "Enviar Z-API" do n8n (só diz se batem) e gravados no .env do core.
# Uso (VPS1, root): bash core_credenciais_zapi.sh
set -euo pipefail
PUB=/root/nay-publicador/.env
CORE=/docker/nay-core/.env
SQLITE3=/usr/local/lib/node_modules/n8n/node_modules/.pnpm/sqlite3@5.1.7/node_modules/sqlite3

val() { grep -E "^$1=" "$PUB" | head -1 | cut -d= -f2- | tr -d '"'"'"' \r'; }
INST=$(val ZAPI_INSTANCIA); TOK=$(val ZAPI_TOKEN); CLI=$(val ZAPI_CLIENT_TOKEN)
[ -n "$INST" ] && [ -n "$TOK" ] && [ -n "$CLI" ] || { echo "FALTA variável da Z-API no .env do publicador"; exit 1; }

# o nó do n8n: a URL traz instância e token; o cabeçalho traz o Client-Token
NO=$(docker exec -i -e SQLITE3_PATH=$SQLITE3 n8n-viux-n8n-1 node - <<'JS'
const s = require(process.env.SQLITE3_PATH);
const db = new s.Database("/home/node/.n8n/database.sqlite", s.OPEN_READONLY);
db.get("SELECT nodes FROM workflow_entity WHERE name = 'NAI atendimento locação' AND active = 1", (e, r) => {
  if (e || !r) { console.log("ERRO"); return; }
  const n = JSON.parse(r.nodes).find(x => x.name === "Enviar Z-API");
  const url = n.parameters.url, cli = (n.parameters.headerParameters.parameters.find(h => h.name === "Client-Token") || {}).value;
  const m = /instances\/([^/]+)\/token\/([^/]+)\//.exec(url) || [];
  console.log([m[1] || "", m[2] || "", cli || ""].join(" "));
  db.close();
});
JS
)
read -r N_INST N_TOK N_CLI <<< "$NO"
echo "instância do publicador = a do nó Enviar Z-API? $([ "$INST" = "$N_INST" ] && echo SIM || echo NÃO) (final …${N_INST: -4})"
echo "token igual? $([ "$TOK" = "$N_TOK" ] && echo SIM || echo NÃO) | client-token igual? $([ "$CLI" = "$N_CLI" ] && echo SIM || echo NÃO)"
[ -n "$N_INST" ] && [ -n "$N_TOK" ] && [ -n "$N_CLI" ] || { echo "não consegui ler o nó do n8n"; exit 1; }

cp -a "$CORE" "$CORE.bk_$(date +%Y%m%d%H%M)_antes_zapi"
grep -v -E '^(ZAPI_BASE_URL|ZAPI_CLIENT_TOKEN)=' "$CORE" > "$CORE.novo"
# vale o que o FLUXO usa (é por essa instância que o corretor fala com a Nay)
printf 'ZAPI_BASE_URL=https://api.z-api.io/instances/%s/token/%s\nZAPI_CLIENT_TOKEN=%s\n' "$N_INST" "$N_TOK" "$N_CLI" >> "$CORE.novo"
chmod 600 "$CORE.novo" && mv "$CORE.novo" "$CORE"
echo "gravado no .env do core: $(grep -c -E '^(ZAPI_BASE_URL|ZAPI_CLIENT_TOKEN)=.' "$CORE") de 2 variáveis; TEL_TELEFONES definido? $(grep -c -E '^TEL_TELEFONES=.' "$CORE")"
