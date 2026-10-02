#!/bin/bash
# Instala o vigia do WhatsApp da Nay na VPS1 (02/10/2026). Ver vigia_whatsapp.py.
#
# Monta /root/vigia_whatsapp/config.json com as duas instâncias da Z-API e o id do grupo de avisos.
# Nenhum segredo é impresso nem vai para o git:
#   - a instância da Parceria vem do .env do nay-core (a mesma do nó "Enviar Z-API" do n8n);
#   - a da Captação vem do banco do CRM, como em /root/migracao_captacao/zapi_webhooks.py;
#   - o grupo é achado pelo NOME, e só vale se os dois números estiverem nele.
# Rodar de novo é seguro: os ajustes (intervalo, lembrete...) que já estiverem no config ficam.
#
# Uso (da raiz do nayia, no Git Bash):
#   scp scripts/servidor/vigia_whatsapp.py nay-srv1894338:/root/vigia_whatsapp/   (a pasta é criada aqui, rode este antes)
#   ssh nay-srv1894338 'bash -s' < scripts/servidor/vigia_whatsapp_instalar.sh
set -euo pipefail
exec < /dev/null
PASTA=/root/vigia_whatsapp
mkdir -p "$PASTA" && chmod 700 "$PASTA"
[ -f "$PASTA/vigia_whatsapp.py" ] || { echo "falta copiar o vigia_whatsapp.py para $PASTA (a pasta já existe agora)"; exit 1; }

GRUPO_NOME="${GRUPO_NOME:-Altarquia Imob easy AI a sinistra do mercado}" python3 - <<'PY'
import json, os, re, subprocess, urllib.request

PASTA = "/root/vigia_whatsapp"
NOME_DO_GRUPO = os.environ["GRUPO_NOME"]

def env(caminho):
    d = {}
    for l in open(caminho, encoding="utf-8", errors="ignore"):
        m = re.match(r"\s*([A-Z0-9_]+)=(.*)", l)
        if m: d[m.group(1)] = m.group(2).strip().strip('"').strip("'")
    return d

core = env("/docker/nay-core/.env")
assert core.get("ZAPI_BASE_URL") and core.get("ZAPI_CLIENT_TOKEN"), "o .env do nay-core não tem a instância da Parceria"

fonte = open("/root/migracao_captacao/zapi_webhooks.py", encoding="utf-8").read()
inst = re.search(r'^INST\s*=\s*"([^"]+)"', fonte, re.M).group(1)
integ = re.search(r'^INTEGRACAO\s*=\s*"([^"]+)"', fonte, re.M).group(1)
seg = json.loads(subprocess.check_output([
    "docker", "exec", "nay-postgres", "psql", "-U", "nay", "-d", "crmdb", "-At", "-c",
    "SELECT secret FROM integration_secrets WHERE integration_id = '%s'" % integ]).decode().strip())

instancias = {
    "parceria": {"rotulo": "Nay de Parceria", "base": core["ZAPI_BASE_URL"].rstrip("/"), "client_token": core["ZAPI_CLIENT_TOKEN"],
                 "vizinha": "captacao", "banco": True},
    "captacao": {"rotulo": "Nay de Captação", "base": "https://api.z-api.io/instances/%s/token/%s" % (inst, seg["instance_token"]),
                 "client_token": seg["client_token"], "vizinha": "parceria", "banco": False},
}

def chamar(i, caminho):
    req = urllib.request.Request(i["base"] + caminho, headers={"Client-Token": i["client_token"]})
    try:
        return json.loads(urllib.request.urlopen(req, timeout=25).read() or b"{}")
    except Exception as e:
        return {"_erro": type(e).__name__}

grupo = None
for nome, i in instancias.items():
    st = chamar(i, "/status")
    dev = chamar(i, "/device")
    i["final"] = str(dev.get("phone", ""))[-4:] if isinstance(dev, dict) else ""
    print("%-9s conectado: %s | número final %s" % (nome, st.get("connected") if isinstance(st, dict) else "?", i["final"] or "?"))
    if not (isinstance(st, dict) and st.get("connected")):
        continue
    for pagina in range(1, 10):
        gs = chamar(i, "/groups?page=%d&pageSize=100" % pagina)
        if not isinstance(gs, list) or not gs:
            break
        for g in gs:
            if str(g.get("name") or "").strip().lower() == NOME_DO_GRUPO.strip().lower():
                grupo = grupo or str(g.get("phone") or g.get("id"))

antigo = {}
try:
    antigo = json.load(open(PASTA + "/config.json", encoding="utf-8"))
except (OSError, ValueError):
    pass
for nome, i in instancias.items():           # sem o número lido agora, vale o que já estava guardado
    i["final"] = i["final"] or antigo.get("instancias", {}).get(nome, {}).get("final", "")
grupo = grupo or antigo.get("grupo")
assert grupo, "não achei o grupo %r em nenhum dos dois números" % NOME_DO_GRUPO
assert all(i["final"] for i in instancias.values()), "não consegui ler o número de uma das instâncias (está desconectada?)"

meta = chamar(next(i for i in instancias.values()), "/group-metadata/%s" % grupo)
finais = sorted(str(p.get("phone", ""))[-4:] for p in (meta.get("participants", []) if isinstance(meta, dict) else []))
dentro = [i["final"] in finais for i in instancias.values()]
print("grupo %r: %d participantes (finais %s) | os dois números estão nele: %s" % (NOME_DO_GRUPO, len(finais), ", ".join(finais), all(dentro)))
assert not finais or all(dentro), "um dos números não está no grupo: ele não conseguiria avisar"

conf = {k: v for k, v in antigo.items() if k not in ("instancias", "grupo", "grupo_nome")}
conf.update(grupo=grupo, grupo_nome=NOME_DO_GRUPO, instancias=instancias)
tmp = PASTA + "/config.json.tmp"
with open(os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w", encoding="utf-8") as f:
    json.dump(conf, f, ensure_ascii=False, indent=1)
os.replace(tmp, PASTA + "/config.json")
print("config.json gravado (só o root lê); ajustes guardados:", {k: v for k, v in conf.items() if k not in ("instancias", "grupo", "grupo_nome")} or "os padrões do script")
PY
chmod 600 "$PASTA/config.json"

cat > /etc/cron.d/vigia-whatsapp <<'CRON'
# Vigia do WhatsApp da Nay (02/10/2026): avisa no grupo quando um número desconecta da Z-API,
# guarda a fila presa e reenvia devagar na volta. Ver /root/vigia_whatsapp/vigia_whatsapp.py.
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
* * * * * root flock -n /run/vigia_whatsapp_parceria.lock python3 /root/vigia_whatsapp/vigia_whatsapp.py parceria >> /var/log/vigia_whatsapp.log 2>&1
* * * * * root flock -n /run/vigia_whatsapp_captacao.lock python3 /root/vigia_whatsapp/vigia_whatsapp.py captacao >> /var/log/vigia_whatsapp.log 2>&1
CRON
chmod 644 /etc/cron.d/vigia-whatsapp
echo "cron instalado: /etc/cron.d/vigia-whatsapp (a cada minuto, um por número)"
for n in parceria captacao; do python3 "$PASTA/vigia_whatsapp.py" "$n" --situacao; done
