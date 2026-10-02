"""Escreve producao/ a partir do que foto_producao.sh trouxe do servidor (pasta .bruto).
Segunda passada de limpeza: segredos que tenham escapado e telefones (só os 4 últimos)."""
from __future__ import annotations

import json
import re
import shutil
import sys
from datetime import datetime
from pathlib import Path

R = "<REDIGIDO>"
_SEGREDOS = (
    (re.compile(r"(instances/)[^/\"'\s]+(/token/)[^/\"'\s]+", re.I), rf"\g<1>{R}\g<2>{R}"),
    (re.compile(r"(Bearer\s+)[A-Za-z0-9._~+/=-]{12,}"), rf"\g<1>{R}"),
    (re.compile(r"\bsk-[A-Za-z0-9_-]{16,}"), R),
    (re.compile(r"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"), R),
    (re.compile(r"([?&](?:token|key|apikey|secret|senha)=)[^&\"'\s]+", re.I), rf"\g<1>{R}"),
)
_FONES = (re.compile(r"(?<!\d)55\d{6,7}(\d{4})(?!\d)"), re.compile(r"\(?\b\d{2}\)?\s9?\d{4}-(\d{4})\b"))


def limpo(t: str | None) -> str:
    s = t or ""
    for rx, troca in _SEGREDOS:
        s = rx.sub(troca, s)
    for rx in _FONES:
        s = rx.sub(lambda m: f"[telefone …{m.group(1)}]", s)
    return s


def _limpar(pasta: Path) -> None:
    """Apaga o CONTEÚDO da pasta, não a pasta: no Windows, pasta aberta num terminal
    não pode ser apagada, e o rmtree deixava a pasta vazia e o mkdir estourava."""
    if not pasta.exists():
        return
    for f in sorted(pasta.rglob("*"), reverse=True):
        if f.is_file():
            f.unlink()
        elif f.is_dir():
            shutil.rmtree(f, ignore_errors=True)


def _nome_de_arquivo(s: str) -> str:
    return re.sub(r"[^\w().,+-]+", "_", s).strip("_")


def funcoes(banco: dict, destino: Path) -> int:
    pasta = destino / "funcoes"
    _limpar(pasta)
    pasta.mkdir(parents=True, exist_ok=True)
    for f in banco["funcoes"] or []:
        tipos = ",".join(t.strip().replace(" ", "_") for t in (f["tipos"] or "").split(",") if t.strip())
        (pasta / _nome_de_arquivo(f"{f['nome']}({tipos}).sql")).write_text(limpo(f["def"]).rstrip() + ";\n",
                                                                          encoding="utf-8")
    return len(banco["funcoes"] or [])


def tabelas(banco: dict, destino: Path) -> int:
    """Uma ficha por tabela/view em producao/tabelas/: colunas, índices, restrições,
    gatilhos, quem pode o quê e QUAIS FUNÇÕES A CITAM. É o que tira do caminho o
    "column does not exist" e o "permission denied" descobertos só no ensaio."""
    pasta = destino / "tabelas"
    _limpar(pasta)
    pasta.mkdir(parents=True, exist_ok=True)
    # cada função é lida UMA vez: os nomes que ela cita e as tabelas em que escreve.
    # (Procurar tabela por tabela em função por função levava a foto de 10 s a 40 s.)
    citam: dict[str, set[str]] = {}
    escrevem_em: dict[str, set[str]] = {}
    for f in banco["funcoes"] or []:
        d = f["def"] or ""
        for palavra in set(re.findall(r"[A-Za-z_][\w.]*", d)):
            citam.setdefault(palavra.removeprefix("public."), set()).add(f["nome"])
        for alvo in set(re.findall(r"(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+(?:ONLY\s+)?([A-Za-z_][\w.]*)", d, re.I)):
            escrevem_em.setdefault(alvo.removeprefix("public."), set()).add(f["nome"])
    for t in banco.get("tabelas") or []:
        nome = t["nome"]
        cheio = nome if t["schema"] == "public" else f"{t['schema']}.{nome}"
        usam = sorted(citam.get(cheio, set()))
        escrevem = sorted(escrevem_em.get(cheio, set()))
        ls = [f"# {cheio}  ({t['tipo']}, ~{t['linhas']} linhas)"]
        if t.get("comentario"):
            ls.append(limpo(t["comentario"]))
        ls.append("\n## colunas")
        for c in t.get("colunas") or []:
            extra = ("  NOT NULL" if c["obrigatoria"] else "") + (f"  padrão {c['padrao']}" if c.get("padrao") else "")
            nota = f"   -- {limpo(c['comentario'])}" if c.get("comentario") else ""
            ls.append(f"{c['nome']}  {c['tipo']}{extra}{nota}")
        for titulo, chave in (("índices", "indices"), ("restrições", "restricoes"), ("gatilhos", "gatilhos")):
            if t.get(chave):
                ls.append(f"\n## {titulo}")
                ls += [limpo(x) for x in t[chave]]
        ls.append("\n## permissões")
        for papel, privs in sorted((t.get("permissoes") or {}).items()):
            ls.append(f"{papel}: {privs}")
        for papel, privs in sorted((t.get("permissoes_por_coluna") or {}).items()):
            ls.append(f"{papel}, só nestas colunas: {privs}")
        if not t.get("permissoes") and not t.get("permissoes_por_coluna"):
            ls.append("(só o dono)")
        ls.append("\n## funções que escrevem aqui")
        ls.append(", ".join(escrevem) or "(nenhuma função; quem escreve é o n8n, o site ou o CRM)")
        ls.append("\n## funções que citam")
        ls.append(", ".join(usam) or "(nenhuma)")
        if t.get("definicao"):
            ls.append("\n## definição da view")
            ls.append(limpo(t["definicao"]))
        (pasta / (_nome_de_arquivo(cheio) + ".md")).write_text("\n".join(ls) + "\n", encoding="utf-8")
    return len(banco.get("tabelas") or [])


def quem_chama(banco: dict, destino: Path) -> None:
    """producao/quem_chama.tsv: para cada função, quem a chama. Antes de mexer numa
    função, é aqui que se vê o que mais muda junto -- sem ir ao servidor."""
    fs = banco["funcoes"] or []
    nomes = sorted({f["nome"] for f in fs})
    chamada_por: dict[str, set[str]] = {}
    for f in fs:   # cada função é lida uma vez: tudo o que ela chama
        for alvo in set(re.findall(r"(?<![\w.])([A-Za-z_]\w*)\s*\(", f["def"] or "")):
            if alvo != f["nome"]:
                chamada_por.setdefault(alvo, set()).add(f["nome"])
    linhas = ["funcao\tchamada_por"]
    for nome in nomes:
        linhas.append(f"{nome}\t{', '.join(sorted(chamada_por.get(nome, set())))}")
    (destino / "quem_chama.tsv").write_text("\n".join(linhas) + "\n", encoding="utf-8")


# o que vale ler de cada nó do n8n, e com que extensão sai
_PARTES_DO_NO = (("jsCode", "js"), ("query", "sql"), ("text", "prompt.txt"), ("jsonBody", "corpo.txt"),
                 ("toolDescription", "descricao.txt"), ("description", "descricao.txt"), ("content", "nota.md"))
_PARTES_DAS_OPCOES = (("systemMessage", "sistema.txt"), ("queryReplacement", "parametros.txt"))


def _nos_do_fluxo(w: dict, pasta: Path) -> None:
    """O fluxo aberto em arquivos: um por pedaço de código/SQL/prompt de cada nó, e
    um _mapa.md com a ordem das ligações. No JSON o código de um nó é UMA linha com
    \\n escapado -- impossível de ler e de procurar; era por isso que cada dúvida
    sobre o fluxo virava um export no servidor."""
    pasta.mkdir(parents=True, exist_ok=True)
    liga = {}
    for origem, saidas in (w.get("connections") or {}).items():
        for tipo, grupos in (saidas or {}).items():
            for g in grupos or []:
                for alvo in g or []:
                    liga.setdefault(origem, []).append(alvo["node"] + ("" if tipo == "main" else f" [{tipo}]"))
    mapa = [f"# {w['nome']}  (id {w.get('id')}, atualizado em {str(w.get('atualizado_em') or '')[:16]})", "",
            "nó | tipo | modelo/extra | vai para", "---|---|---|---"]
    for n in sorted(w.get("nodes") or [], key=lambda x: (x.get("position") or [0, 0])[0]):
        p = n.get("parameters") or {}
        base = _nome_de_arquivo(n["name"])
        for chave, ext in _PARTES_DO_NO:
            v = p.get(chave)
            if isinstance(v, str) and len(v.strip()) > 40:
                (pasta / f"{base}.{ext}").write_text(limpo(v).rstrip() + "\n", encoding="utf-8")
        op = p.get("options") if isinstance(p.get("options"), dict) else {}
        for chave, ext in _PARTES_DAS_OPCOES:
            v = op.get(chave)
            if isinstance(v, str) and len(v.strip()) > 40:
                (pasta / f"{base}.{ext}").write_text(limpo(v).rstrip() + "\n", encoding="utf-8")
        modelo = p.get("model")
        extra = (modelo.get("value") if isinstance(modelo, dict) else modelo) or ""
        if n.get("disabled"):
            extra = (str(extra) + " DESATIVADO").strip()
        if n.get("onError"):
            extra = (str(extra) + f" onError={n['onError']}").strip()
        mapa.append(f"{n['name']} | {n['type'].split('.')[-1]} | {extra} | {', '.join(liga.get(n['name'], []))}")
    (pasta / "_mapa.md").write_text(limpo("\n".join(mapa)) + "\n", encoding="utf-8")


def fluxos(bruto: Path, destino: Path) -> list[str]:
    pasta = destino / "n8n"
    _limpar(pasta)
    pasta.mkdir(parents=True, exist_ok=True)
    nomes = []
    for w in json.loads((bruto / "workflows.json").read_text(encoding="utf-8")):
        texto = limpo(json.dumps(w, ensure_ascii=False, indent=1))
        (pasta / (_nome_de_arquivo(w["nome"]) + ".json")).write_text(texto + "\n", encoding="utf-8")
        _nos_do_fluxo(w, pasta / _nome_de_arquivo(w["nome"]))
        nomes.append(w["nome"])
    return nomes


def cron(bruto: Path, destino: Path) -> None:
    pasta = destino / "cron"
    _limpar(pasta)
    (pasta / "cron.d").mkdir(parents=True, exist_ok=True)
    partes = re.split(r"^### (.+)$", (bruto / "cron.txt").read_text(encoding="utf-8"), flags=re.M)
    (pasta / "root.crontab").write_text(limpo(partes[0]).strip() + "\n", encoding="utf-8")
    for arq, conteudo in zip(partes[1::2], partes[2::2], strict=False):
        (pasta / "cron.d" / Path(arq.strip()).name).write_text(limpo(conteudo).strip() + "\n", encoding="utf-8")


def config_e_prompts(banco: dict, destino: Path) -> None:
    linhas = ["chave\tvalor\tatualizado_em"] + [
        f"{c['chave']}\t{limpo(str(c['valor'])).replace(chr(10), ' ')}\t{(c['atualizado_em'] or '')[:16]}"
        for c in banco["config"] or []]
    (destino / "nai_config.tsv").write_text("\n".join(linhas) + "\n", encoding="utf-8")
    pasta = destino / "prompts"
    _limpar(pasta)
    pasta.mkdir(parents=True, exist_ok=True)
    for p in banco["prompts"] or []:
        cab = (f"<!-- nai_prompt papel={p['papel']} versao={p['versao']} atualizado_em={(p['atualizado_em'] or '')[:16]}"
               f" por={p['atualizado_por'] or '-'} -->\n")
        (pasta / f"{_nome_de_arquivo(p['papel'])}.md").write_text(cab + limpo(p["texto"]) + "\n", encoding="utf-8")


def main(bruto: Path, destino: Path) -> int:
    banco = json.loads((bruto / "banco.json").read_text(encoding="utf-8"))
    destino.mkdir(parents=True, exist_ok=True)
    n = funcoes(banco, destino)
    nt = tabelas(banco, destino)
    quem_chama(banco, destino)
    nomes = fluxos(bruto, destino)
    cron(bruto, destino)
    config_e_prompts(banco, destino)
    shutil.copy(bruto / "n8n_env.txt", destino / "n8n_variaveis_de_ambiente.txt")
    (destino / "LEIA.md").write_text(
        "# Foto da produção (gerada por scripts/foto_producao.sh; não edite à mão)\n\n"
        f"Tirada em {datetime.now():%d/%m/%Y %H:%M}. Segredos trocados por {R}; telefones só com os 4 últimos.\n\n"
        f"- funcoes/: {n} funções vivas do schema public, uma por arquivo (nome e tipos dos argumentos)\n"
        f"- tabelas/: {nt} tabelas e views (public e privado): colunas, índices, restrições, gatilhos,\n"
        "  permissões por papel e as funções que escrevem nelas e que as citam\n"
        "- quem_chama.tsv: para cada função, quem a chama\n"
        f"- n8n/: os fluxos ativos ({', '.join(nomes)}), em JSON e ABERTOS em pasta: um arquivo por\n"
        "  código/SQL/prompt de cada nó e um _mapa.md com o tipo, o modelo e as ligações\n"
        "- cron/: o crontab do root e /etc/cron.d do srv1894338\n"
        "- nai_config.tsv, prompts/ (nai_prompt com versão), n8n_variaveis_de_ambiente.txt (só os nomes)\n",
        encoding="utf-8")
    print(f"producao/: {n} funções, {nt} tabelas, {len(nomes)} fluxos ({', '.join(nomes)}), "
          f"{len(banco['config'] or [])} chaves de config, {len(banco['prompts'] or [])} prompts")
    return 0


if __name__ == "__main__":
    sys.exit(main(Path(sys.argv[1]), Path(sys.argv[2])))
