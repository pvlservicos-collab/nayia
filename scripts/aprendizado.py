#!/usr/bin/env python3
"""Aprendizado do YouTube: o que a rotina noturna precisa para virar ideias no Obsidian (Pedro, 28/10/2026).

O Agente de Aprendizado salva as transcrições em `transcricoes/` (nayia). As ideias moram no vault do Obsidian:
    IMOBEASY/Estratégia/Vídeos/   uma nota por vídeo (propriedade youtube_id)
    IMOBEASY/Estratégia/Ideias/   uma nota por ideia (propriedades numero, nota, nota_claude, prazo...)

    python scripts/aprendizado.py pendentes          transcrições que ainda não viraram nota de vídeo
    python scripts/aprendizado.py texto <id|arquivo>  o texto corrido da transcrição, com a hora a cada ~12 linhas,
                                                      gravado em transcricoes/_texto/<id>.txt (o caminho é impresso)
    python scripts/aprendizado.py ideias             as ideias que já existem (para não repetir) e o próximo número
Só lê e escreve arquivos locais; não fala com servidor nenhum.
"""
import io
import os
import re
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TRANSCRICOES = os.path.join(RAIZ, "transcricoes")
VAULT = os.environ.get("OBSIDIAN_VAULT", r"C:\Users\pedro\Documents\Obsidian Vault")
ESTRATEGIA = os.path.join(VAULT, "IMOBEASY", "Estratégia")
VIDEOS = os.path.join(ESTRATEGIA, "Vídeos")
IDEIAS = os.path.join(ESTRATEGIA, "Ideias")

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")


def propriedades(caminho):
    """O frontmatter simples (chave: valor) de uma nota."""
    t = io.open(caminho, encoding="utf-8").read()
    m = re.match(r"---\n(.*?)\n---", t, re.S)
    out = {}
    for linha in (m.group(1).splitlines() if m else []):
        k, _, v = linha.partition(":")
        out[k.strip()] = v.strip().strip('"')
    return out


def id_do_arquivo(nome):
    m = re.search(r"\[([\w-]{6,})\]\.txt$", nome)
    return m.group(1) if m else os.path.splitext(nome)[0]


def transcricoes():
    if not os.path.isdir(TRANSCRICOES):
        return []
    return sorted(f for f in os.listdir(TRANSCRICOES) if f.endswith(".txt"))


def ids_estudados():
    if not os.path.isdir(VIDEOS):
        return set()
    return {propriedades(os.path.join(VIDEOS, f)).get("youtube_id", "") for f in os.listdir(VIDEOS) if f.endswith(".md")}


def pendentes():
    feitos = ids_estudados()
    lista = [f for f in transcricoes() if id_do_arquivo(f) not in feitos]
    if not lista:
        print("Nenhuma transcrição nova: todas já viraram nota de vídeo.")
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
    if not os.path.isdir(IDEIAS):
        print("Ainda não há ideias. Próximo número: 1")
        return
    maior = 0
    for f in sorted(os.listdir(IDEIAS)):
        if not f.endswith(".md"):
            continue
        p = propriedades(os.path.join(IDEIAS, f))
        n = int(p.get("numero") or 0)
        maior = max(maior, n)
        print("#%s\tnota %s (Claude %s)\t%s\t%s\t%s" % (p.get("numero"), p.get("nota"), p.get("nota_claude"),
                                                      p.get("prazo"), p.get("titulo"), p.get("video")))
    print("Próximo número: %d" % (maior + 1))


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "pendentes":
        pendentes()
    elif cmd == "texto" and len(sys.argv) > 2:
        texto(sys.argv[2])
    elif cmd == "ideias":
        ideias()
    else:
        print(__doc__)
