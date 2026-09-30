// Foto dos fluxos ATIVOS do n8n, lida do sqlite em modo SÓ LEITURA. Roda DENTRO
// do container do n8n (foto_producao.sh). Os segredos são apagados AQUI, antes de
// sair do servidor: instância e token da Z-API, cabeçalhos e campos de token/
// chave/senha, "Bearer ...", chaves sk-..., JWT e ?token= em URL.
const s = require(process.env.SQLITE3_PATH);
const db = new s.Database("/home/node/.n8n/database.sqlite", s.OPEN_READONLY);
const SEGREDO = /token|apikey|api_key|api-key|secret|senha|password|authorization|credencial/i;
const R = "<REDIGIDO>";

function texto(x) {
  return x
    .replace(/(instances\/)[^\/"'\s]+(\/token\/)[^\/"'\s]+/gi, `$1${R}$2${R}`)
    .replace(/(Bearer\s+)[A-Za-z0-9._~+\/=-]{12,}/g, `$1${R}`)
    .replace(/\bsk-[A-Za-z0-9_-]{16,}/g, R)
    .replace(/\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/g, R)
    .replace(/([?&](?:token|key|apikey|secret|senha)=)[^&"'\s]+/gi, `$1${R}`);
}

function limpar(v) {
  if (typeof v === "string") return texto(v);
  if (Array.isArray(v)) return v.map(limpar);
  if (v && typeof v === "object") {
    const o = {};
    for (const [k, x] of Object.entries(v)) {
      if (k === "value" && typeof v.name === "string" && SEGREDO.test(v.name)) o[k] = R;
      else if (typeof x === "string" && SEGREDO.test(k) && k !== "credentials") o[k] = R;
      else o[k] = limpar(x);
    }
    return o;
  }
  return v;
}

db.all("SELECT id, name, active, nodes, connections, settings, updatedAt FROM workflow_entity WHERE active = 1 ORDER BY name",
  [], (e, linhas) => {
    if (e) { console.error("ERRO", e.message); process.exit(1); }
    const fluxos = linhas.map(l => limpar({
      id: l.id, nome: l.name, ativo: !!l.active, atualizado_em: l.updatedAt,
      nodes: JSON.parse(l.nodes || "[]"), connections: JSON.parse(l.connections || "{}"),
      settings: JSON.parse(l.settings || "{}"),
    }));
    process.stdout.write(JSON.stringify(fluxos));
  });
