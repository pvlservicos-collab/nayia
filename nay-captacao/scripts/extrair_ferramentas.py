"""Tira do fluxo VIVO do n8n as ferramentas do agente da captação e grava `captacao/ferramentas.json`.

A Nay de captação em Python usa as MESMAS ferramentas do fluxo (nome, descrição, SQL e parâmetros). Em vez de
copiar à mão -- e perder uma vírgula --, este script lê a foto do fluxo e gera o arquivo. Rode de novo sempre que
uma ferramenta mudar no n8n, até o dia em que o n8n sair.

Uso:  python scripts/extrair_ferramentas.py <workflows.json da foto> [saida.json]
A foto vem de scripts/foto_n8n.js rodado no container n8n-captacao da VPS2 (os segredos já saem apagados de lá).
"""
import json
import re
import sys
from pathlib import Path

FLUXO = "CjsUJefRYcQIIi1F"
DE_AI = re.compile(r"\$fromAI\('([^']+)',\s*'([^']*)'(?:,\s*'string')?(?:,\s*'([^']*)')?\)")


def extrair(caminho: Path) -> list[dict]:
    fluxos = json.loads(caminho.read_text(encoding="utf-8"))
    fluxo = next(f for f in fluxos if f["id"] == FLUXO)
    ligadas = {nome for nome, c in fluxo["connections"].items() if c.get("ai_tool")}
    ferramentas = []
    for no in fluxo["nodes"]:
        if no["name"] not in ligadas:
            continue
        p = no["parameters"]
        if no["type"].endswith("postgresTool"):
            troca = (p.get("options") or {}).get("queryReplacement") or ""
            params = [{"chave": m.group(1), "descricao": m.group(2), "opcional": m.group(3) is not None}
                      for m in DE_AI.finditer(troca)]
            ferramentas.append({"nome": no["name"], "descricao": p.get("toolDescription") or "", "sql": p["query"],
                                "params": params})
        elif no["type"].endswith("toolWorkflow"):
            # escalar_ao_tel: no n8n é um sub-fluxo; aqui o serviço executa (captacao/escalar.py)
            ferramentas.append({"nome": no["name"], "descricao": p.get("description") or "", "sql": None, "params": [
                {"chave": "assunto", "descricao": "Resuma em 2 a 5 palavras o que ele pediu", "opcional": False},
                {"chave": "disse", "descricao": "o que ele disse, nas palavras dele", "opcional": True}]})
    return ferramentas


if __name__ == "__main__":
    entrada = Path(sys.argv[1])
    saida = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(__file__).resolve().parent.parent / "captacao" / "ferramentas.json"
    fs = extrair(entrada)
    saida.write_text(json.dumps(fs, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    for f in fs:
        print(f"{f['nome']}: {len(f['params'])} parâmetro(s) [{', '.join(q['chave'] + ('?' if q['opcional'] else '') for q in f['params'])}]"
              f"{'' if f['sql'] else ' (sem SQL: executada pelo serviço)'}")
    print("gravado em", saida)
