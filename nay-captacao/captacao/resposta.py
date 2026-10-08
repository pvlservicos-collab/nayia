"""O portão de saída: o que o modelo escreveu vira os balões que saem -- ou nada.

Tradução do nó "Preparar resposta" do fluxo do n8n. São as garantias que o prompt sozinho não deu:
emoji nunca sai; SILENCIO não vira mensagem; frase que promete retorno do Tel é cortada (a escalada é calada);
frase que diz que ela não vê a imagem é cortada; no máximo três balões. Função pura.

As expressões são as do fluxo. `re.ASCII` deixa `\\w` e `\\b` como no JavaScript de lá (só letras sem acento).
"""
from __future__ import annotations

import random
import re
from dataclasses import dataclass

EMOJI = re.compile("[\U0001F000-\U0001FAFF☀-➿⬀-⯿️‍]")
EH_SILENCIO = re.compile(r"^[\W\d_]*sil[eê]ncio[\W\d_]*$", re.I)
PROMESSA_TEL = re.compile(
    r"\bTel\b[^.!?\n]*\b(pass\w*|repass\w*|avis\w*|lev\w*|encaminh\w*|contato|retorn\w*|respond\w*|fala\w*|fale|ligar?|liga"
    r"|verific\w*|regist\w*|anot\w*|convers\w*|avali\w*|ver isso|v[eê] isso)"
    r"|\b(pass\w*|repass\w*|lev\w*|encaminh\w*|avis\w*)\b[^.!?\n]*\b(pro|para o|ao)\s+Tel\b"
    r"|\bvou (verificar|confirmar|checar|ver isso)\b|\b(j[aá] )?te retorno\b|\bretorno (em breve|j[aá]|logo)\b"
    r"|\bentr\w*\s+em\s+contato\b|\b(vai|v[aã]o)\s+(te\s+|lhe\s+)?(retornar|responder|ligar)\b", re.I | re.ASCII)
NAO_VE = re.compile(
    r"\bn[aã]o\s+(consigo|consegui|d[aá]\s+(pra|para)|posso|estou conseguindo|t[oô] conseguindo)\s+"
    r"(ver|abrir|visualizar|enxergar|baixar|carregar|ler|ouvir)\b"
    r"|\b(imagens?|fotos?|arquivos?|v[ií]deos?|anexos?)\s+n[aã]o\s+(abr\w*|carreg\w*|apar\w*|cheg\w*|vei[ao]|vieram)"
    r"|\bn[aã]o\s+(vejo|enxergo|recebi)\s+(a|as|o|os|sua|suas|seu|seus)?\s*(imagens?|fotos?|arquivos?|v[ií]deos?)",
    re.I | re.ASCII)
_PROT = re.compile(r"\b(Sr|Sra|Dr|Dra|Srta)\.")


@dataclass
class Balao:
    texto: str
    pausa: int
    # a pergunta do turno, guardada no lead (só no último balão)
    pergunta: str | None = None


def _sem(padrao: re.Pattern, texto: str) -> str:
    """Tira as frases que casam com o padrão. "Sr." e "Sra." não terminam frase."""
    prot = _PROT.sub(lambda m: m.group(1) + "\u0001", texto)
    frases = [f for f in re.split(r"(?<=[.!?])\s+|\n+", prot) if f.strip() and not padrao.search(f.replace("\u0001", "."))]
    return " ".join(frases).replace("\u0001", ".").strip()


def limpar(saida: str) -> str:
    """O texto do modelo sem emoji, sem promessa de retorno e sem "não consigo ver". Vazio = não responde."""
    bruto = EMOJI.sub("", str(saida or ""))
    bruto = re.sub(r"[ \t]{2,}", " ", bruto)
    bruto = re.sub(r" +([!?.,])", r"\1", bruto).strip()
    if not bruto or EH_SILENCIO.match(bruto):
        return ""
    partes = [_sem(NAO_VE, _sem(PROMESSA_TEL, p)) for p in re.split(r"\n\s*\n", bruto)]
    limpo = "\n\n".join(p for p in partes if p)
    return "" if not limpo or EH_SILENCIO.match(limpo) else limpo


def baloes(saida: str, sorteio: random.Random | None = None) -> list[Balao]:
    """Até três balões, um por linha em branco, com a pausa de gente entre eles."""
    r = sorteio or random
    limpo = limpar(saida)
    partes = [p.strip() for p in re.split(r"\n\s*\n", limpo) if p.strip() and not EH_SILENCIO.match(p.strip())][:3]
    if not partes:
        return []
    com_pergunta = next((p for p in reversed(partes) if "?" in p), None)
    return [Balao(texto=p, pausa=(3 + r.randrange(5)) if i == 0 else (4 + r.randrange(6)),
                  pergunta=com_pergunta if i == len(partes) - 1 else None)
            for i, p in enumerate(partes)]
