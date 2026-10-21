"""As ferramentas de LEITURA dos chats de projeto do Agente Claude: banco e códigos das duas VPS, sem mudar nada.

Pedro, 20/10/2026: "criei uns terminais do claude na minha vps em /agentes mas eles não estão lendo o banco de dados
e os códigos da minha vps"; escolha dele: "Ler tudo, sem mudar". O Claude do projeto continua SEM terminal: só estas
quatro ferramentas, cada uma com um comando fixo (o Claude passa os valores, nunca o comando).

- consultar_banco: naydb ou crmdb, com o papel nay_leitura (só SELECT; privado.* e vagas.* ficam fora, como já eram;
  no crmdb, a 451 abriu a leitura menos as tabelas de senha e token), UMA instrução por vez e em transação só leitura.
- ler_arquivo, listar, procurar: VPS1 (site, CRM, n8n, nay-core, Nay velha) ou VPS2 (este painel, Hermes, finanças),
  como root, mas sem abrir arquivo de segredo (.env, chaves, tokens, o login do Claude).

Roda com o Python do Hermes (tem o pacote mcp), lançado pelo claude-agente no modo "projeto" (--mcp-config).
"""
import re
import shlex
import subprocess

from mcp.server.fastmcp import FastMCP

VPS1 = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "-i", "/root/.ssh/agente_claude_vps1",
        "root@100.86.114.74"]
SERVIDORES = ("vps1", "vps2")
BANCOS = ("naydb", "crmdb")
MAX = 200_000  # caracteres por resposta
# arquivos que nunca são abertos nem procurados: segredos do servidor
SEGREDO = re.compile(r"(^|/)\.env($|[./_-])|\.env$|(^|/)\.ssh(/|$)|authorized_keys|(^|/)id_(rsa|ed25519|ecdsa|dsa)"
                     r"|\.(pem|key|p12|pfx)$|^/etc/(shadow|gshadow|sudoers|agente-claude)|^/proc(/|$)|^/sys(/|$)"
                     r"|(^|/)\.claude(\.json)?(/|$)|(^|/)\.hermes/auth|credentials|\.pgpass|\.netrc|(^|/)secrets?(/|$)",
                     re.I)
FORA_DA_BUSCA = ("--exclude=.env", "--exclude=*.env", "--exclude=.env.*", "--exclude=*.pem", "--exclude=*.key",
                 "--exclude=authorized_keys", "--exclude=id_*", "--exclude=*.json.bak*", "--exclude-dir=.ssh",
                 "--exclude-dir=.git", "--exclude-dir=node_modules", "--exclude-dir=.claude", "--exclude-dir=secrets",
                 "--exclude-dir=__pycache__", "--exclude-dir=.next", "--exclude-dir=proc", "--exclude-dir=sys")
# só uma instrução de leitura: o papel já não grava, e a transação só leitura barra função que grave
LEITURA = re.compile(r"^\s*(select|with|explain|table|show|values)\b", re.I)

mcp = FastMCP("leitura")


def _rodar(servidor, comando, timeout=90):
    """Roda um comando montado AQUI (os valores do Claude entram com shlex.quote) na VPS pedida."""
    if servidor not in SERVIDORES:
        return f"servidor tem de ser um destes: {', '.join(SERVIDORES)}"
    cmd = (VPS1 + [comando]) if servidor == "vps1" else ["bash", "-c", comando]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return f"passou de {timeout} s"
    saida = (r.stdout or "") + (("\n[erro] " + r.stderr.strip()) if r.stderr.strip() else "")
    return (saida[:MAX] + "\n[cortado em 200 mil caracteres]") if len(saida) > MAX else (saida or "(vazio)")


def _caminho(servidor, caminho):
    """O caminho de verdade (links resolvidos), ou o motivo de recusa."""
    if not caminho or not caminho.startswith("/"):
        return None, "use o caminho completo, começando com /"
    real = _rodar(servidor, f"readlink -f -- {shlex.quote(caminho)}", timeout=20).strip()
    if not real.startswith("/"):
        return None, real
    if SEGREDO.search(caminho) or SEGREDO.search(real):
        return None, "arquivo de segredo (chave, senha, token): não é aberto por aqui"
    return real, None


def _uma_instrucao(sql):
    """Tira comentários e textos entre aspas e confere: começa lendo e não tem um segundo comando depois do ;."""
    s = re.sub(r"--[^\n]*|/\*.*?\*/", " ", sql, flags=re.S)
    s = re.sub(r"\$([A-Za-z_]*)\$.*?\$\1\$|'(?:[^']|'')*'|\"(?:[^\"]|\"\")*\"", "''", s, flags=re.S)
    return bool(LEITURA.match(s)) and not s.strip().rstrip(";").count(";")


@mcp.tool()
def consultar_banco(banco: str, sql: str) -> str:
    """Consulta SÓ LEITURA no Postgres da VPS1. banco: "naydb" (Nay velha e nova, imóveis, visitas, captação: o
    schema public; core_* é a Nay nova) ou "crmdb" (o CRM: leads, mensagens, etapas). UMA instrução por vez,
    começando com SELECT, WITH, EXPLAIN, TABLE, SHOW ou VALUES. Limite de 60 s. Para descobrir colunas:
    SELECT column_name, data_type FROM information_schema.columns WHERE table_name = '...'."""
    if banco not in BANCOS:
        return f"banco tem de ser um destes: {', '.join(BANCOS)}"
    if sql.lstrip().startswith("\\") or not _uma_instrucao(sql):
        return "só uma instrução de leitura por vez (SELECT, WITH, EXPLAIN, TABLE, SHOW ou VALUES)"
    comando = ("docker exec -e PGOPTIONS='-c default_transaction_read_only=on -c statement_timeout=60000' "
               f"nay-postgres psql -U nay_leitura -d {banco} -X -A -F ' | ' -P pager=off -c {shlex.quote(sql)}")
    return _rodar("vps1", comando)


@mcp.tool()
def ler_arquivo(servidor: str, caminho: str, de_linha: int = 1, ate_linha: int = 2000) -> str:
    """Lê um arquivo de código ou texto. servidor: "vps1" (site em /docker/nay-site-web e /docker/nay-site-api, CRM em
    /docker/crm, Nay nova em /docker/nay-core, n8n em /docker/n8n-viux, scripts do root em /root) ou "vps2" (este
    painel em /opt/agente-claude, Hermes em /opt/hermes-painel, finanças e portal em /docker). Caminho completo.
    Lê de de_linha a ate_linha (padrão: as 2000 primeiras), com o número de cada linha."""
    real, erro = _caminho(servidor, caminho)
    if erro:
        return erro
    a, b = max(1, int(de_linha)), max(1, int(ate_linha))
    return _rodar(servidor, f"[ -f {shlex.quote(real)} ] || {{ echo 'não é arquivo (use listar)'; exit; }}; "
                            f"awk 'NR>={a} && NR<={b} {{printf \"%6d\\t%s\\n\", NR, $0}} NR>{b} {{exit}}' "
                            f"-- {shlex.quote(real)}")


@mcp.tool()
def listar(servidor: str, pasta: str, nome: str = "", profundidade: int = 2) -> str:
    """Lista uma pasta: tipo (d = pasta, f = arquivo, l = link), tamanho, data de mudança e caminho. nome filtra pelo
    nome do arquivo (ex.: "*.py"). profundidade de 1 a 6 (padrão 2). Até 1000 linhas; pula .git e node_modules."""
    real, erro = _caminho(servidor, pasta)
    if erro:
        return erro
    p = min(6, max(1, int(profundidade)))
    filtro = f"-name {shlex.quote(nome)} " if nome else ""
    return _rodar(servidor, f"find {shlex.quote(real)} -maxdepth {p} \\( -name .git -o -name node_modules -o "
                            f"-name __pycache__ \\) -prune -o {filtro}-printf '%y %10s %TY-%Tm-%Td %TH:%TM %p\\n' "
                            f"| sort -k5 | head -1000")


@mcp.tool()
def procurar(servidor: str, texto: str, pasta: str, arquivos: str = "", maiusculas_iguais: bool = True) -> str:
    """Procura um texto (expressão regular, como no grep -E) nos arquivos de uma pasta, com arquivo:linha. arquivos
    filtra pelo nome (ex.: "*.py", "*.sql"). Até 300 linhas de resultado. Pula segredos, .git e node_modules."""
    real, erro = _caminho(servidor, pasta)
    if erro:
        return erro
    if not texto:
        return "diga o texto a procurar"
    opcoes = ["-rnIE", "--max-count=50"] + (["-i"] if maiusculas_iguais else []) + list(FORA_DA_BUSCA)
    if arquivos:
        opcoes.append("--include=" + arquivos)
    return _rodar(servidor, f"grep {' '.join(shlex.quote(o) for o in opcoes)} -e {shlex.quote(texto)} -- "
                            f"{shlex.quote(real)} | cut -c1-400 | head -300")


if __name__ == "__main__":
    mcp.run()
