#!/usr/bin/env python3
"""Aprendizado do YouTube: o que a rotina noturna precisa para virar Ideias refinadas (Pedro, 28/10/2026).

O Agente de Aprendizado salva as transcrições em `transcricoes/` (nayia). As ideias moram no BANCO (514) e aparecem em
admin › Aprendizado › Ideias refinadas. O vault do Obsidian só é LIDO, como contexto da empresa (Pedro, 29/10: "eu não
pedi para pôr nada no obsidian, tu só vai ler o obsidian para ver as informações da imobeasy").

    python scripts/aprendizado.py pendentes          transcrições cujo vídeo ainda não está em aprendizado_video
    python scripts/aprendizado.py texto <id|arquivo>  o texto corrido da transcrição, com a hora a cada ~12 linhas,
                                                      gravado em transcricoes/_texto/<id>.txt (o caminho é impresso)
    python scripts/aprendizado.py ideias             as ideias que já existem (para não repetir) e o próximo número
    python scripts/aprendizado.py gravar <json>      grava o vídeo e as ideias (aprendizado_gravar) pelo `nay aplicar`
O JSON do gravar: {"video": {youtube_id, titulo, quem, link, data, duracao, defende, nao_serve},
                   "ideias": [{numero, titulo, area, prazo, nota_claude, sugestao, como_hoje, onde_ajuda,
                               porque_prazo, do_video}]}. Ideia com número que já existe atualiza o texto e a
nota_claude; a nota que o Pedro deu na barrinha fica.
"""
import io
import json
import os
import re
import subprocess
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TRANSCRICOES = os.path.join(RAIZ, "transcricoes")
NAY = os.path.join(RAIZ, "scripts", "nay")

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")


def banco(sql):
    """As linhas de uma consulta (só leitura) pelo `nay q`, como listas de colunas."""
    r = subprocess.run(["bash", NAY, "q", sql], capture_output=True, text=True, encoding="utf-8")
    if r.returncode:
        sys.exit("O banco não respondeu: %s" % (r.stderr or r.stdout).strip()[:300])
    linhas = r.stdout.strip().splitlines()[1:]          # a 1ª é o cabeçalho
    return [l.split(" | ") for l in linhas if l and not re.match(r"^\(\d+ rows?\)$", l)]


def id_do_arquivo(nome):
    m = re.search(r"\[([\w-]{6,})\]\.txt$", nome)
    return m.group(1) if m else os.path.splitext(nome)[0]


def transcricoes():
    if not os.path.isdir(TRANSCRICOES):
        return []
    return sorted(f for f in os.listdir(TRANSCRICOES) if f.endswith(".txt"))


def pendentes():
    feitos = {l[0] for l in banco("SELECT youtube_id FROM aprendizado_video")}
    lista = [f for f in transcricoes() if id_do_arquivo(f) not in feitos]
    if not lista:
        print("Nenhuma transcrição nova: todos os vídeos já estão em Ideias refinadas.")
    for f in lista:
        tam = os.path.getsize(os.path.join(TRANSCRICOES, f))
        print("%s\t%s\t%d caracteres" % (id_do_arquivo(f), f, tam))


def texto(alvo):
    arq = next((f for f in transcricoes() if alvo in (f, id_do_arquivo(f))), None)
    if not arq:
        sys.exit("Não achei a transcrição %r em %s" % (alvo, TRANSCRICOES))
    linhas = io.open(os.path.join(TRANSCRICOES, arq), encoding="utf-8").read().splitlines()
    falas = [(m.group(1), m.group(2)) for m in (re.match(r"^(\d{2}:\d{2}):\d{2}\S*\s+(.*)$", l) for l in linhas) if m]
    if not falas:   # transcrição colada sem hora: vale o texto como está
        corrido = "\n".join(l for l in linhas if not l.startswith("#"))
    else:
        blocos = []
        for i in range(0, len(falas), 12):
            pedaco = falas[i:i + 12]
            blocos.append("[%s] %s" % (pedaco[0][0], " ".join(t for _, t in pedaco)))
        corrido = "\n".join(blocos)
    os.makedirs(os.path.join(TRANSCRICOES, "_texto"), exist_ok=True)
    saida = os.path.join(TRANSCRICOES, "_texto", id_do_arquivo(arq) + ".txt")
    io.open(saida, "w", encoding="utf-8").write(corrido + "\n")
    cab = [l for l in linhas[:4] if l.startswith("#")]
    print("\n".join(cab))
    print("Texto corrido (%d caracteres): %s" % (len(corrido), saida))


def ideias():
    linhas = banco("SELECT i.numero, i.nota, i.nota_claude, i.nota_revisada, i.prazo, i.titulo, coalesce(v.titulo, '') "
                   "FROM aprendizado_ideia i LEFT JOIN aprendizado_video v USING (youtube_id) ORDER BY i.numero")
    for n, nota, claude, rev, prazo, titulo, video in linhas:
        print("#%s\tnota %s%s (Claude %s)\t%s\t%s\t%s" % (n, nota, " revisada" if rev == "t" else "", claude, prazo,
                                                        titulo, video))
    print("Próximo número: %d" % (max([int(l[0]) for l in linhas] or [0]) + 1))


PRAZOS = ("curto", "medio", "longo")
CAMPOS = ("numero", "titulo", "prazo", "nota_claude", "sugestao", "como_hoje", "onde_ajuda")


def gravar(caminho):
    dados = json.load(io.open(caminho, encoding="utf-8"))
    for i in dados.get("ideias", []):
        falta = [c for c in CAMPOS if i.get(c) in (None, "")]
        if falta:
            sys.exit("Ideia %s sem %s" % (i.get("numero"), ", ".join(falta)))
        if i["prazo"] not in PRAZOS:
            sys.exit("Ideia %s: prazo %r (vale %s)" % (i["numero"], i["prazo"], ", ".join(PRAZOS)))
    corpo = json.dumps(dados, ensure_ascii=False)
    tag = "j"
    while "$%s$" % tag in corpo:
        tag += "j"
    sql = "BEGIN;\nSELECT aprendizado_gravar($%s$%s$%s$::jsonb);\nCOMMIT;\n" % (tag, corpo, tag)
    arq_sql = os.path.splitext(caminho)[0] + ".sql"
    io.open(arq_sql, "w", encoding="utf-8", newline="\n").write(sql)
    r = subprocess.run(["bash", NAY, "aplicar", arq_sql], text=True, encoding="utf-8")
    sys.exit(r.returncode)


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "pendentes":
        pendentes()
    elif cmd == "texto" and len(sys.argv) > 2:
        texto(sys.argv[2])
    elif cmd == "ideias":
        ideias()
    elif cmd == "gravar" and len(sys.argv) > 2:
        gravar(sys.argv[2])
    else:
        print(__doc__)
