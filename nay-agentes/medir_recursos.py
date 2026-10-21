#!/usr/bin/env python3
"""Uso de recursos da VPS1 por FUNÇÃO, em porcentagem da máquina, para o painel "Uso de recursos" da aba Início.

Pedro, 20/10/2026: "cria ali na aba início lá no site normal um painel Uso de recursos, que separa todos os recursos da
vps por função em porcentagem de uso da minha vps atual da hostinger".

Roda pelo cron a cada 5 min (nay-agentes.cron) e escreve /docker/nay-site-web/public/admin/dados/recursos.json.
Só leitura no sistema:
  CPU      cada serviço systemd e cada container é um cgroup (cgroup v2): a CPU que ele usou desde a medida anterior
           (cpu.stat usage_usec) dividida pelo tempo × núcleos. "Sistema" é o total da máquina (/proc/stat) menos as
           funções: kernel, docker, tailscale, journald...
  Memória  o que cada cgroup tem em uso de verdade (memória dos programas e kernel que não se libera; o cache de
           arquivo e o slab recuperável ficam de fora, porque o sistema os devolve quando precisa). "Sistema" = memória em uso da máquina (MemTotal − MemAvailable) menos as funções.
  Disco    uma vez por hora (du com prioridade baixa): as pastas e os volumes de cada função, as cópias de segurança,
           as imagens e o cache de build do Docker (docker system df). "Sistema" = o resto do usado.
Guarda a medida anterior e as últimas 24 h em /var/lib/nay-recursos/estado.json (média de 24 h e o gráfico).
"""
import json, os, re, subprocess, time

SAIDA = os.environ.get("NAY_RECURSOS_SAIDA", "/docker/nay-site-web/public/admin/dados/recursos.json")
ESTADO = os.environ.get("NAY_RECURSOS_ESTADO", "/var/lib/nay-recursos/estado.json")
CG = "/sys/fs/cgroup"
HISTORIA = 288            # 24 h de medidas de 5 min
DISCO_A_CADA_S = 3600

# cada função: o que é dela em CPU/memória (serviços systemd, containers, fatias do cgroup) e no disco (pastas e volumes)
FUNCOES = [
    {"id": "nay_nova", "nome": "Nay Parceria (Nay nova)", "cor": "#ff6fa8",
     "faz": "o núcleo que atende os corretores na Parceria: conversa, envio e o que sai pelo WhatsApp",
     "containers": ["nay-core", "nay-core-worker", "nay-core-enviador"], "pastas": ["/docker/nay-core", "/docker/nay-core-nova"]},
    {"id": "treino", "nome": "Nay nova · treino e testes", "cor": "#c58bff",
     "faz": "a cópia da Nay nova que roda as conversas de treino, sem mandar nada",
     "containers": ["nay-core-treino"]},
    {"id": "nay_velha", "nome": "Nay antiga (n8n, envio e publicador)", "cor": "#ff9830",
     "faz": "o fluxo do n8n, o enviador manual, o publicador dos grupos e o baixador de imagens",
     "containers": ["n8n-viux-n8n-1", "nay-painel"],
     "servicos": ["nay-enviador-manual", "nay-publicador", "baixador-imagens"],
     "pastas": ["/root/nay-publicador", "/docker/nay-painel", "/docker/n8n-viux"], "volumes": ["n8n-viux_n8n_data"]},
    {"id": "captacao", "nome": "Nay de captação (proprietários)", "cor": "#4fc4cf",
     "faz": "a Nay que conversa com os donos pelo número oficial e o disparo dos modelos",
     "servicos": ["nay-captacao"], "pastas": ["/root/nay-captacao"]},
    {"id": "olx", "nome": "OLX", "cor": "#8ab8ff", "faz": "a Nay do WhatsApp da OLX, os chats e a busca de parceiros",
     "servicos": ["nay-olx"], "pastas": ["/root/nay-olx"]},
    {"id": "grupos", "nome": "Captação pelos grupos", "cor": "#73bf69",
     "faz": "lê os pedidos dos grupos e compara com os imóveis", "servicos": ["nay-grupos"], "pastas": ["/root/nay-grupos"]},
    {"id": "cadastro", "nome": "Cadastro pelo WhatsApp", "cor": "#b6d96b",
     "faz": "o grupo CADASTRO DE IMÓVEL: cria o imóvel e pergunta o que falta", "servicos": ["nay-cadastro"],
     "pastas": ["/root/nay-cadastro"]},
    {"id": "crm", "nome": "CRM", "cor": "#5794f2", "faz": "crm.imobeasy.online: as conversas, as etapas e os cards",
     "containers": ["crm-imobeasy"], "pastas": ["/docker/crm"]},
    {"id": "site", "nome": "Site, admin e API", "cor": "#fade2a", "faz": "imobeasy.online, o admin, a API e o roteador (Traefik)",
     "containers": ["nay-site-api", "nay-site-web", "traefik-traefik-1"],
     "pastas": ["/docker/nay-site-web", "/docker/nay-site-api", "/docker/traefik"],
     "volumes": ["traefik-letsencrypt", "traefik_traefik-letsencrypt"]},
    {"id": "banco", "nome": "Banco de dados", "cor": "#f2495c", "faz": "o Postgres: naydb (Nay, imóveis, captação) e crmdb (CRM)",
     "containers": ["nay-postgres"], "pastas": ["/docker/postgres"], "volumes": ["postgres_nay_pgdata"]},
    {"id": "rotinas", "nome": "Rotinas agendadas", "cor": "#e0a3ff",
     "faz": "o que o cron roda: medidores, conferência do CRM, gerador de posts, colagens, cópias",
     "servicos": ["cron"], "pastas": ["/root/nay-posts", "/root/nay-colagem"]},
    {"id": "acessos", "nome": "Acessos (SSH e Agente Claude)", "cor": "#9fa8b8",
     "faz": "quem entra pelo SSH: a equipe, as sessões do Claude e o Agente Claude da VPS2",
     "fatias": ["user.slice"], "servicos": ["ssh"]},
    {"id": "copias", "nome": "Cópias de segurança", "cor": "#7fd6b0", "faz": "backups do banco, do n8n e da Nay (só disco)",
     "pastas": ["/root/backups", "/root/backups-n8n", "/root/backups-banco", "/root/backups-nay", "/root/backups-para-fora",
                "/root/backups-funcoes", "/var/backups"]},
    {"id": "docker_imagens", "nome": "Programas instalados (imagens Docker)", "cor": "#6b7a99",
     "faz": "as imagens de que os containers sobem (só disco)", "docker_df": "Images"},
    {"id": "docker_cache", "nome": "Cache de build do Docker", "cor": "#4a5468",
     "faz": "sobras das montagens (cada publicação do CRM deixa uma); o Docker diz quanto dá para liberar (só disco)",
     "docker_df": "Build Cache"},
    {"id": "logs", "nome": "Registros (logs)", "cor": "#a0a0b4", "faz": "os registros do sistema e das rotinas (só disco)",
     "pastas": ["/var/log"]},
]
SISTEMA = {"id": "sistema", "nome": "Sistema", "cor": "#3d4250",
           "faz": "o Linux, o Docker, o Tailscale e o que não é de nenhuma função acima"}


def ler(caminho, padrao=""):
    try:
        with open(caminho) as f:
            return f.read()
    except OSError:
        return padrao


def cmd(*a, timeout=120):
    try:
        return subprocess.run(a, capture_output=True, text=True, timeout=timeout).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


def cpu_total():
    """(ocupado, total) em jiffies, de /proc/stat."""
    v = [int(x) for x in ler("/proc/stat").splitlines()[0].split()[1:]]
    ocioso = v[3] + (v[4] if len(v) > 4 else 0)
    return sum(v[:8]) - ocioso, sum(v[:8])


def meminfo():
    m = {}
    for l in ler("/proc/meminfo").splitlines():
        k, _, resto = l.partition(":")
        m[k] = int(resto.split()[0]) * 1024
    return m


def cgroups():
    """caminho do cgroup de cada coisa medida: serviço, container e fatia."""
    ids = {}
    for l in cmd("docker", "ps", "--no-trunc", "--format", "{{.ID}} {{.Names}}").splitlines():
        if " " in l:
            i, n = l.split(" ", 1)
            ids[n.strip()] = i
    caminhos = {}
    for f in FUNCOES:
        for c in f.get("containers", []):
            if c in ids:
                caminhos[("c", c)] = f"{CG}/system.slice/docker-{ids[c]}.scope"
        for s in f.get("servicos", []):
            caminhos[("s", s)] = f"{CG}/system.slice/{s}.service"
        for fa in f.get("fatias", []):
            caminhos[("f", fa)] = f"{CG}/{fa}"
    return caminhos


def uso_cpu(caminho):
    m = re.search(r"usage_usec (\d+)", ler(caminho + "/cpu.stat"))
    return int(m.group(1)) if m else None


# o que o sistema NÃO devolve quando precisa: a memória dos programas e o kernel que não se libera. Fica de fora o
# cache de arquivo e o slab recuperável (um `du` grande faz o slab da sessão dele inchar e some sozinho depois).
MEM_EM_USO = ("anon", "shmem", "kernel_stack", "pagetables", "slab_unreclaimable", "sock", "percpu")


def uso_mem(caminho):
    st = dict(l.split() for l in ler(caminho + "/memory.stat").splitlines() if len(l.split()) == 2)
    return sum(int(st.get(k, 0)) for k in MEM_EM_USO)


def tamanho_docker(texto):
    """"56.38GB" -> bytes (o docker usa potências de 1000)."""
    m = re.match(r"([\d.]+)\s*([kKMGT]?B)", texto.strip())
    if not m:
        return 0
    return int(float(m.group(1)) * {"B": 1, "kB": 1e3, "KB": 1e3, "MB": 1e6, "GB": 1e9, "TB": 1e12}[m.group(2)])


def du(caminhos):
    existe = [c for c in caminhos if os.path.exists(c)]
    if not existe:
        return 0
    s = cmd("ionice", "-c3", "nice", "-n19", "du", "-sxbc", *existe, timeout=900)
    ultima = s.strip().splitlines()[-1:] or ["0"]
    return int(ultima[0].split()[0]) if ultima[0].split()[0].isdigit() else 0


def medir_disco():
    st = os.statvfs("/")
    total, livre = st.f_blocks * st.f_frsize, st.f_bavail * st.f_frsize
    usado = total - st.f_bfree * st.f_frsize
    df = {}
    for l in cmd("docker", "system", "df", "--format", "{{.Type}}\t{{.Size}}\t{{.Reclaimable}}").splitlines():
        p = l.split("\t")
        if len(p) >= 3:
            df[p[0]] = (tamanho_docker(p[1]), tamanho_docker(p[2]))
    bytes_ = {}
    for f in FUNCOES:
        b = du(f.get("pastas", []) + [f"/var/lib/docker/volumes/{v}/_data" for v in f.get("volumes", [])])
        if f.get("docker_df"):
            b += df.get(f["docker_df"], (0, 0))[0]
        bytes_[f["id"]] = b
    bytes_["sistema"] = max(0, usado - sum(bytes_.values()))
    return {"medido_em": int(time.time()), "total": total, "usado": usado, "livre": livre, "bytes": bytes_,
            "pct": {k: round(v * 100 / total, 2) for k, v in bytes_.items()},
            "liberavel_cache": df.get("Build Cache", (0, 0))[1]}


def main():
    agora = time.time()
    try:
        estado = json.loads(ler(ESTADO, "{}") or "{}")
    except ValueError:
        estado = {}
    ocupado, total = cpu_total()
    caminhos = cgroups()
    cpu_cg = {"|".join(k): uso_cpu(v) for k, v in caminhos.items()}
    nproc = os.cpu_count() or 1
    mem = meminfo()

    # CPU desde a medida anterior
    cpu_pct = None
    ant = estado.get("anterior")
    if ant and 0 < agora - ant["t"] < 1800:
        dt = agora - ant["t"]
        d_total = total - ant["total"]
        total_pct = 100 * (ocupado - ant["ocupado"]) / d_total if d_total > 0 else 0
        cpu_pct = {}
        for f in FUNCOES:
            us = 0
            for k, v in cpu_cg.items():
                if v is not None and k.split("|", 1)[1] in f.get("containers", []) + f.get("servicos", []) + f.get("fatias", []):
                    antes = ant["cg"].get(k)
                    if antes is not None and v >= antes:
                        us += v - antes
            cpu_pct[f["id"]] = round(100 * us / (dt * 1e6 * nproc), 2)
        cpu_pct["sistema"] = round(max(0.0, total_pct - sum(cpu_pct.values())), 2)
        cpu_pct["_total"] = round(total_pct, 2)

    # memória agora
    mem_b = {}
    for f in FUNCOES:
        mem_b[f["id"]] = sum(uso_mem(v) for k, v in caminhos.items()
                             if k[1] in f.get("containers", []) + f.get("servicos", []) + f.get("fatias", []))
    em_uso = mem["MemTotal"] - mem["MemAvailable"]
    mem_b["sistema"] = max(0, em_uso - sum(mem_b.values()))
    mem_pct = {k: round(v * 100 / mem["MemTotal"], 2) for k, v in mem_b.items()}
    mem_pct["_total"] = round(em_uso * 100 / mem["MemTotal"], 2)

    historia = [h for h in estado.get("historia", []) if agora - h["t"] < 86400 + 600][-(HISTORIA - 1):]
    if cpu_pct is not None:
        historia.append({"t": int(agora), "cpu": cpu_pct, "mem": mem_pct})

    disco = estado.get("disco")
    if not disco or agora - disco.get("medido_em", 0) >= DISCO_A_CADA_S:
        disco = medir_disco()

    def media(campo):
        vals = [h[campo] for h in historia]
        if not vals:
            return None
        chaves = {k for v in vals for k in v}
        return {k: round(sum(v.get(k, 0) for v in vals) / len(vals), 2) for k in chaves}

    st = os.statvfs("/")
    saida = {
        "medido_em": int(agora),
        "servidor": {"nome": os.uname().nodename, "provedor": "Hostinger", "cpus": nproc, "memoria": mem["MemTotal"],
                     "disco": st.f_blocks * st.f_frsize, "carga": ler("/proc/loadavg").split()[:3]},
        "funcoes": [{k: f[k] for k in ("id", "nome", "cor", "faz")}
                    | {"itens": f.get("containers", []) + f.get("servicos", []) + f.get("fatias", []),
                       "so_disco": not (f.get("containers") or f.get("servicos") or f.get("fatias"))}
                    for f in FUNCOES] + [SISTEMA | {"itens": [], "so_disco": False}],
        "agora": {"cpu": cpu_pct, "mem": mem_pct, "mem_bytes": mem_b},
        "media24h": {"cpu": media("cpu"), "mem": media("mem"), "medidas": len(historia)},
        "disco": disco,
        "historia": historia,
    }
    os.makedirs(os.path.dirname(ESTADO), exist_ok=True)
    estado = {"anterior": {"t": agora, "ocupado": ocupado, "total": total, "cg": cpu_cg},
              "historia": historia, "disco": disco}
    for caminho, dado in ((ESTADO, estado), (SAIDA, saida)):
        tmp = caminho + ".tmp"
        with open(tmp, "w") as f:
            json.dump(dado, f, separators=(",", ":"))
        os.chmod(tmp, 0o644)
        os.replace(tmp, caminho)


if __name__ == "__main__":
    main()
