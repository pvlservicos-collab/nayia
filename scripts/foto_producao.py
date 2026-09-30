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


def fluxos(bruto: Path, destino: Path) -> list[str]:
    pasta = destino / "n8n"
    _limpar(pasta)
    pasta.mkdir(parents=True, exist_ok=True)
    nomes = []
    for w in json.loads((bruto / "workflows.json").read_text(encoding="utf-8")):
        texto = limpo(json.dumps(w, ensure_ascii=False, indent=1))
        (pasta / (_nome_de_arquivo(w["nome"]) + ".json")).write_text(texto + "\n", encoding="utf-8")
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
    nomes = fluxos(bruto, destino)
    cron(bruto, destino)
    config_e_prompts(banco, destino)
    shutil.copy(bruto / "n8n_env.txt", destino / "n8n_variaveis_de_ambiente.txt")
    (destino / "LEIA.md").write_text(
        "# Foto da produção (gerada por scripts/foto_producao.sh; não edite à mão)\n\n"
        f"Tirada em {datetime.now():%d/%m/%Y %H:%M}. Segredos trocados por {R}; telefones só com os 4 últimos.\n\n"
        f"- funcoes/: {n} funções vivas do schema public, uma por arquivo (nome e tipos dos argumentos)\n"
        f"- n8n/: os fluxos ativos ({', '.join(nomes)})\n"
        "- cron/: o crontab do root e /etc/cron.d do srv1894338\n"
        "- nai_config.tsv, prompts/ (nai_prompt com versão), n8n_variaveis_de_ambiente.txt (só os nomes)\n",
        encoding="utf-8")
    print(f"producao/: {n} funções, {len(nomes)} fluxos ({', '.join(nomes)}), "
          f"{len(banco['config'] or [])} chaves de config, {len(banco['prompts'] or [])} prompts")
    return 0


if __name__ == "__main__":
    sys.exit(main(Path(sys.argv[1]), Path(sys.argv[2])))
