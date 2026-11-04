"""A API do site: o MESMO caminho da aba Editar imóvel. Quem grava, acha o dono pelo telefone, liga o condomínio e
põe a foto de pé é ela (nay-site-api/app.py e fotos_api.py); aqui só a chamada, com o segredo de máquina do painel
(X-Painel-Crm, que só abre /admin/api/imoveis*)."""
from __future__ import annotations

import logging
from urllib.parse import urlparse

import requests

from cadastro import config

log = logging.getLogger("cadastro.site")
# de onde a Z-API serve as mídias (o link expira: baixar na hora)
HOSTS_DA_MIDIA = ("z-api.io", "backblazeb2.com", "amazonaws.com", "whatsapp.net")


class FalhaDoSite(Exception):
    pass


class FaltaCondominio(FalhaDoSite):
    """O 400 da trava do condomínio (04/11, Pedro: "a Nay não pode cadastrar sem"): apartamento/casa de condomínio não
    passa para Disponível sem o condo_id. Quem chama grava o resto e o imóvel fica como estava (fluxo.gravar_no_site)."""


def _cab() -> dict:
    return {"X-Painel-Crm": config.PAINEL_SEGREDO}


def _resposta(r: requests.Response, o_que: str) -> dict:
    try:
        j = r.json()
    except ValueError:
        j = {}
    if r.status_code == 400 and isinstance(j, dict) and j.get("falta") == "condominio":
        raise FaltaCondominio(f"{o_que}: {j.get('erro')}")
    if r.status_code >= 400:
        raise FalhaDoSite(f"{o_que}: HTTP {r.status_code} {j.get('detalhes') or j.get('motivo') or j.get('erro') or r.text[:200]}")
    return j if isinstance(j, dict) else {}


def criar_imovel(corpo: dict) -> int:
    r = requests.post(f"{config.SITE_API_URL}/admin/api/imoveis", json=corpo, headers=_cab(), timeout=40)
    return int(_resposta(r, "criar o imóvel")["codigo"])


def salvar_imovel(codigo: int, corpo: dict) -> dict:
    r = requests.put(f"{config.SITE_API_URL}/admin/api/imoveis/{codigo}", json=corpo, headers=_cab(), timeout=40)
    return _resposta(r, f"salvar o imóvel {codigo}")


def criar_condominio(corpo: dict) -> int:
    """Nome que já existe devolve 409 com o id dele: liga no que existe (nunca dois condomínios iguais)."""
    r = requests.post(f"{config.SITE_API_URL}/admin/api/imoveis/condominios", json=corpo, headers=_cab(), timeout=40)
    if r.status_code == 409:
        return int(r.json()["id"])
    j = _resposta(r, "criar o condomínio")
    cid = j.get("id") or (j.get("condominio") or {}).get("id")
    if not cid:
        raise FalhaDoSite(f"criar o condomínio: a resposta não trouxe o id ({str(j)[:200]})")
    return int(cid)


def baixar(url: str) -> bytes:
    host = (urlparse(url).hostname or "").lower()
    if not any(host == h or host.endswith("." + h) for h in HOSTS_DA_MIDIA):
        raise FalhaDoSite(f"a foto vem de um endereço que não é do WhatsApp ({host})")
    r = requests.get(url, timeout=60)
    if r.status_code != 200 or len(r.content) < 2000:
        raise FalhaDoSite(f"não consegui baixar a foto (HTTP {r.status_code}, {len(r.content)} bytes)")
    return r.content


def subir_foto(codigo: int, conteudo: bytes) -> None:
    r = requests.post(f"{config.SITE_API_URL}/admin/api/imoveis/{codigo}/fotos", data=conteudo, timeout=90,
                      headers={**_cab(), "Content-Type": "application/octet-stream"})
    _resposta(r, f"subir a foto do imóvel {codigo}")


def subir_fotos(codigo: int, urls: list[str]) -> tuple[int, list[str]]:
    """Baixa e sobe cada foto, na ordem (a primeira vira a capa). Devolve (quantas subiram, os erros)."""
    subiram, erros = 0, []
    for url in urls:
        try:
            subir_foto(codigo, baixar(url))
            subiram += 1
        except (FalhaDoSite, requests.RequestException) as e:
            log.warning("foto do %s: %s", codigo, e)
            erros.append(str(e)[:160])
    return subiram, erros
