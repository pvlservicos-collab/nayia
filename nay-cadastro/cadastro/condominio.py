"""O condomínio que ele escreveu é um dos nossos?

Pedro, 20/10/2026: "quero esse filtro flexível: se ela digitar o nome do condomínio errado ela entenda que é o certo".
A busca é do banco (cadastro_whats_condominio, migração 428: nome sem as palavras genéricas, sem acento, igual / contido
/ parecido); aqui a decisão: liga sozinho quando o melhor está claro, pergunta "É o X?" quando há dúvida, e trata como
condomínio novo quando nada parece.
"""
from __future__ import annotations

import re

from cadastro.campos import sem_acento

# o texto chega sem acento ("é esse" -> "e esse")
SIM = re.compile(r"^\s*(sim|s|ss|isso|exato|exatamente|esse|este|e esse|e sim|e ele|e\s*$|correto|certo|confirmo|"
                 r"positivo|aham|uhum)\b")
NAO = re.compile(r"\b(nao|n|negativo|outro|errado|nenhum)\b")


def escolher(candidatos: list[dict]) -> tuple[str, dict | None]:
    """('ligar', o condomínio) | ('confirmar', o candidato) | ('novo', None)."""
    if not candidatos:
        return "novo", None
    melhor = candidatos[0]
    segundo = candidatos[1] if len(candidatos) > 1 else None
    folga = (float(melhor["parecenca"]) - float(segundo["parecenca"])) if segundo else 1.0
    if melhor["faixa"] <= 3 and (segundo is None or segundo["faixa"] > melhor["faixa"] or folga >= 0.1):
        return "ligar", melhor
    if melhor["faixa"] == 4 and float(melhor["parecenca"]) >= 0.6 and folga >= 0.05:
        return "ligar", melhor
    return "confirmar", melhor


def ligar(ficha: dict, cond: dict) -> dict:
    """Ligou ao cadastrado: o nome é o do cadastro, e o bairro vem dele quando ele não disse."""
    f = {**ficha, "condo_id": int(cond["id"]), "condominio": cond["nome"]}
    f.pop("_condo_candidato", None)
    if cond.get("bairro") and not ficha.get("bairro"):
        f["bairro"] = cond["bairro"]
    return f


def resposta_da_confirmacao(texto: str) -> bool | None:
    """"sim, é esse" -> True; "não, é outro" -> False; o resto -> None (o modelo lê)."""
    t = sem_acento(texto).strip()
    if NAO.search(t) and not SIM.search(t):
        return False
    if SIM.search(t):
        return True
    return None
