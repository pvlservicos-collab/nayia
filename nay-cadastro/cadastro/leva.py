"""A LEVA: as mensagens que o Tel encaminha de uma vez no grupo são UM imóvel.

Pedro, 20/10/2026: "ele vai sempre mandar todas as mensagens encaminhadas, então vai ser por grupo de mensagens". O
encaminhamento chega em rajada (texto, fotos, o contato do corretor, segundos uma da outra). A leva fecha quando o
grupo fica `silencio_s` sem mensagem nova; a próxima rajada é o próximo imóvel.

Aqui só a conta: quem lê o banco e quem decide o que fazer com a leva é o worker.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import datetime

# "👤 Contato: Ana Corretora — 5592988887777" (nai_grupo_guardar, migração 428)
CONTATO = re.compile(r"👤\s*Contato:\s*(?P<nome>[^—\n]*?)\s*(?:—\s*(?P<fones>[\d /]+))?\s*$", re.M)
# telefone escrito: +55 (92) 9 9999-9999, 92 99999 9999, 92999999999. O DDD é obrigatório: sem ele "120 m2" e
# "3.500" não viram telefone.
FONE = re.compile(r"(?<![\d.,])(?:\+?\s*55[\s.-]*)?\(?\s*([1-9]\d)\s*\)?[\s.-]*(9[\s.-]*\d{4}|\d{4})[\s.-]*(\d{4})(?![\d.,])")


@dataclass
class Mensagem:
    message_id: str
    enviada_em: datetime
    tipo: str
    texto: str | None = None
    midia_url: str | None = None
    remetente: str | None = None
    citado_id: str | None = None


@dataclass
class Leva:
    mensagens: list[Mensagem] = field(default_factory=list)

    @property
    def ids(self) -> list[str]:
        return [m.message_id for m in self.mensagens]

    @property
    def ultima(self) -> datetime:
        return self.mensagens[-1].enviada_em

    @property
    def texto(self) -> str:
        return "\n".join(m.texto.strip() for m in self.mensagens if m.texto and m.texto.strip())

    @property
    def fotos(self) -> list[Mensagem]:
        return [m for m in self.mensagens if m.tipo == "imagem" and m.midia_url]

    @property
    def citados(self) -> list[str]:
        return [m.citado_id for m in self.mensagens if m.citado_id]


def separar(mensagens: list[Mensagem], silencio_s: int) -> list[Leva]:
    """Corta as mensagens (em ordem de chegada) onde houve mais de `silencio_s` sem nada."""
    levas: list[Leva] = []
    for m in sorted(mensagens, key=lambda x: (x.enviada_em, x.message_id)):
        if levas and (m.enviada_em - levas[-1].ultima).total_seconds() <= silencio_s:
            levas[-1].mensagens.append(m)
        else:
            levas.append(Leva([m]))
    return levas


def fechada(leva: Leva, agora: datetime, silencio_s: int) -> bool:
    return (agora - leva.ultima).total_seconds() > silencio_s


def normalizar_fone(ddd: str, meio: str, fim: str) -> str | None:
    meio = re.sub(r"\D", "", meio)
    numero = meio + fim
    if len(numero) == 8 and numero[0] in "6789":
        numero = "9" + numero          # celular escrito sem o 9 da frente
    if len(numero) != 9:
        return None
    return "55" + ddd + numero


def fones_do_texto(texto: str | None) -> list[str]:
    """Os telefones da leva, sem repetir, na ordem: primeiro os dos cartões de contato, depois os escritos."""
    vistos: list[str] = []
    t = texto or ""
    for m in CONTATO.finditer(t):
        for f in re.findall(r"\d{10,15}", m.group("fones") or ""):
            f = f if f.startswith("55") else "55" + f
            if f not in vistos:
                vistos.append(f)
    for m in FONE.finditer(CONTATO.sub(" ", t)):
        f = normalizar_fone(*m.groups())
        if f and f not in vistos:
            vistos.append(f)
    return vistos


def nome_do_contato(texto: str | None) -> str | None:
    m = CONTATO.search(texto or "")
    nome = (m.group("nome") or "").strip() if m else ""
    return nome or None


def fone_bonito(fone: str | None) -> str:
    d = re.sub(r"\D", "", fone or "")
    if d.startswith("55") and len(d) in (12, 13):
        d = d[2:]
    if len(d) == 11:
        return f"({d[:2]}) {d[2]} {d[3:7]}-{d[7:]}"
    if len(d) == 10:
        return f"({d[:2]}) {d[2:6]}-{d[6:]}"
    return fone or ""


def parece_anuncio(texto: str, saida: dict) -> bool:
    """Um imóvel novo, não um complemento ("4 banheiros", "64m2", "é condomínio novo"): o texto é de anúncio (longo) ou
    traz o valor junto com o tipo ou o condomínio e mais alguma coisa (os quartos, ou texto de anúncio)."""
    t = (texto or "").strip()
    valor = saida.get("valor_venda") or saida.get("valor_aluguel")
    de_anuncio = bool(valor and (saida.get("tipo") or saida.get("condominio")) and (saida.get("quartos") or len(t) >= 80))
    return len(t) >= 250 or de_anuncio
