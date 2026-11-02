"""AS FOTOS DO ANÚNCIO DA OLX GUARDADAS NO NOSSO SITE (Pedro, 02/11/2026: "9115 esse imóvel está com imagens bugadas").

Até aqui a Nay dos corretores (buscas.cadastrar) e o pré-cadastro da OLX (parceiro.precadastrar) gravavam no imovel_fotos o
link do CDN da OLX (img.olx.com.br). Pelo WhatsApp a foto ia (o servidor baixa sem dizer de onde vem), mas no site, no admin e
no CRM o navegador abre a foto a partir de uma página nossa, e a OLX recusa (403) foto pedida de outro site: a foto aparecia
quebrada. E some de vez quando o anúncio sai da OLX.

Agora a foto é baixada para a mesma pasta das fotos da OLX do admin (fotos-captacao/olx/<código>/NN.jpg, servida pelo site
em https://imobeasy.online/fotos-captacao/...) e o cadastro grava o NOSSO endereço. Se não baixar, fica o link da OLX (melhor
do que nenhuma foto) e o log diz qual.
"""
from __future__ import annotations

import logging
import os
from urllib.parse import urlparse

import requests

log = logging.getLogger("olx.fotos")

PASTA = os.environ.get("NAY_FOTOS_DIR", "/docker/nay-site-web/public/fotos-captacao")
URL_PUBLICA = os.environ.get("NAY_FOTOS_URL", "https://imobeasy.online/fotos-captacao")
DONO_DA_PASTA = 1000   # o nginx do site e a API gravam como 1000
MAXIMO, MINIMO = 15 * 1024 * 1024, 2_000
NAVEGADOR = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124 Safari/537.36",
             "Accept": "image/avif,image/webp,image/*,*/*;q=0.8"}


def da_olx(url: str) -> bool:
    return (urlparse(str(url or "")).hostname or "").endswith("olx.com.br")


def extensao(conteudo: bytes) -> str | None:
    if conteudo[:3] == b"\xff\xd8\xff":
        return "jpg"
    if conteudo[:8] == b"\x89PNG\r\n\x1a\n":
        return "png"
    if conteudo[:4] == b"RIFF" and conteudo[8:12] == b"WEBP":
        return "webp"
    return None


def baixar(url: str) -> tuple[bytes, str]:
    """Só foto de verdade: a OLX responde 404 com um quadrado cinza dentro, e quem pega isso é o status."""
    r = requests.get(url, headers=NAVEGADOR, timeout=25)
    if r.status_code != 200:
        raise ValueError(f"resposta {r.status_code}")
    conteudo = r.content
    if not MINIMO <= len(conteudo) <= MAXIMO:
        raise ValueError(f"tamanho estranho ({len(conteudo)} bytes)")
    ext = extensao(conteudo)
    if not ext:
        raise ValueError("não é jpg, png nem webp")
    return conteudo, ext


def gravar(codigo: int, ordem: int, conteudo: bytes, ext: str) -> str:
    pasta = os.path.join(PASTA, "olx", str(int(codigo)))
    os.makedirs(pasta, exist_ok=True)
    nome = f"{int(ordem):02d}.{ext}"
    parcial = os.path.join(pasta, nome + ".parcial")
    with open(parcial, "wb") as f:
        f.write(conteudo)
    os.replace(parcial, os.path.join(pasta, nome))   # ou existe inteira, ou não existe
    for caminho in (pasta, os.path.join(pasta, nome)):
        try:
            os.chown(caminho, DONO_DA_PASTA, DONO_DA_PASTA)
        except (OSError, AttributeError):   # no Windows (os testes) não há chown
            pass
    return f"{URL_PUBLICA}/olx/{int(codigo)}/{nome}"


def guardar(codigo: int, ordem: int, url: str) -> str:
    """O endereço que vai para o imovel_fotos: o nosso, se baixou; o da OLX, se não."""
    if not da_olx(url):
        return url
    try:
        conteudo, ext = baixar(url)
        return gravar(codigo, ordem, conteudo, ext)
    except Exception as exc:  # noqa: BLE001 -- foto que não baixou não derruba o cadastro
        log.warning("#%s foto %s não baixou (%s): fica o link da OLX", codigo, ordem, exc)
        return url
