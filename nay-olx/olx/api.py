"""A API da OLX: as chamadas e a leitura do que ela responde.

Documentação (developers.olx.com.br, lida em 13/10/2026):
  PUT  /autoupload/import              {access_token, ad_list}   inserir, editar (inserir de novo) e remover anúncios
  POST /autoupload/import/<token>      {access_token}            o que aconteceu com cada anúncio daquela importação
  GET  /autoupload/v1/published        Authorization: Bearer     a situação de todos os anúncios da conta (paginado)
  POST /autoservice/v1/chat/send       Authorization: Bearer     responder uma conversa do chat

AS CHAMADAS ficam em cima; A LEITURA das respostas fica embaixo, em funções puras (tests/test_olx.py), porque é ali
que mora a decisão: o que virou anúncio, o que a OLX recusou e por quê.

O token da conta nunca vai para o registro: quem chama registra o que as funções de leitura devolvem.
"""
from __future__ import annotations

import logging
import re
from dataclasses import dataclass, field

import requests

from olx import config

log = logging.getLogger("olx.api")
NAVEGADOR = {"User-Agent": "Mozilla/5.0"}   # sem isto a OLX responde com a página de bloqueio


class ErroDaOlx(Exception):
    """A OLX não respondeu, ou respondeu algo que não dá para ler. Nada foi decidido: tenta-se de novo depois."""


def _json(r: requests.Response) -> dict:
    try:
        j = r.json()
    except ValueError as e:
        raise ErroDaOlx(f"HTTP {r.status_code} sem JSON") from e
    if not isinstance(j, (dict, list)):
        raise ErroDaOlx(f"HTTP {r.status_code} com resposta inesperada")
    return j


def _pedir(metodo: str, caminho: str, **kw) -> requests.Response:
    try:
        return requests.request(metodo, config.OLX_APPS + caminho, timeout=config.ESPERA_S,
                                headers={**NAVEGADOR, **kw.pop("headers", {})}, **kw)
    except requests.RequestException as e:
        raise ErroDaOlx(f"não consegui falar com a OLX: {e.__class__.__name__}") from e


# ── as chamadas ──────────────────────────────────────────────────────────────────────────────────────────────

def importar(token: str, anuncios: list[dict]) -> dict:
    """Manda os anúncios (inserir/editar e remover vão na mesma lista). Devolve o JSON da OLX."""
    r = _pedir("PUT", "/autoupload/import", json={"access_token": token, "ad_list": anuncios})
    return _json(r)


def status_da_importacao(token: str, import_token: str) -> dict:
    r = _pedir("POST", f"/autoupload/import/{import_token}", json={"access_token": token})
    return _json(r)


def publicados(token: str, paginas: int = 50) -> list[dict]:
    """Todos os anúncios da conta com a situação de cada um ({id, list_id, status}); `id` é o nosso, quando subiu por nós."""
    tudo: list[dict] = []
    pagina: str | None = None
    for _ in range(paginas):
        r = _pedir("GET", "/autoupload/v1/published", params={"page_token": pagina} if pagina else None,
                   headers={"Authorization": f"Bearer {token}"})
        if r.status_code != 200:
            raise ErroDaOlx(f"a lista de anúncios respondeu HTTP {r.status_code}")
        j = _json(r)
        tudo.extend(x for x in (j.get("data") or []) if isinstance(x, dict))
        pagina = j.get("next_token")
        if not pagina:
            break
    return tudo


def enviar_no_chat(token: str, chat_id: str, texto: str, message_id: str) -> tuple[bool, str]:
    """Responde uma conversa. Devolve (saiu?, o motivo quando não saiu)."""
    r = _pedir("POST", "/autoservice/v1/chat/send", headers={"Authorization": f"Bearer {token}"},
               json={"textMessage": texto, "messageId": message_id, "chatId": chat_id})
    if r.status_code == 200:
        return True, ""
    return False, {401: "o token da conta não vale mais: conecte a conta de novo no CRM",
                   400: "a OLX recusou (mensagem inválida ou conta sem a integração de chat)"}.get(
                       r.status_code, f"a OLX respondeu HTTP {r.status_code}")


# ── a leitura ────────────────────────────────────────────────────────────────────────────────────────────────

# o statusCode da importação -> o que gravamos em privado.olx_config.permissao
PERMISSAO = {0: "ok", -2: "bloqueado", -5: "fora_do_ar", -6: "sem_permissao", -7: "sem_vaga", -8: "sem_vaga"}
POR_EXTENSO = {
    0: "a OLX aceitou a importação",
    -1: "erro inesperado na OLX",
    -2: "a OLX bloqueou a conta por um tempo, por excesso de chamadas",
    -3: "a lista foi sem anúncio nenhum",
    -4: "um anúncio falhou na validação e a OLX cancelou a importação inteira",
    -5: "a importação da OLX está fora do ar",
    -6: "sem permissão: a conta não tem plano profissional habilitado para integração de anúncios",
    -7: "a conta não tem vaga para tantos anúncios",
    -8: "só parte dos anúncios entrou: o limite da conta acabou",
}


@dataclass
class Importacao:
    """O que a OLX respondeu, na hora, a uma importação."""
    codigo: int
    aceita: bool                      # entrou na fila da OLX (falta a moderação)
    token: str | None                 # para perguntar depois o que aconteceu
    mensagem: str
    erros: dict[str, str] = field(default_factory=dict)   # o nosso id -> o motivo (statusCode -4)
    ignorados: set[str] = field(default_factory=set)      # ficaram de fora por limite (statusCode -8)

    @property
    def permissao(self) -> str | None:
        return PERMISSAO.get(self.codigo)


def ler_importacao(j: dict) -> Importacao:
    try:
        codigo = int(j.get("statusCode"))
    except (TypeError, ValueError) as e:
        raise ErroDaOlx("a OLX respondeu sem statusCode") from e
    bruto = str(j.get("statusMessage") or "")
    erros: dict[str, str] = {}
    for e in j.get("errors") or []:
        if isinstance(e, dict) and e.get("id") is not None:
            motivos = [str(m.get("category") or m.get("error") or m) for m in (e.get("messages") or []) if m]
            erros[str(e["id"])] = ", ".join(motivos) or str(e.get("status") or "erro")
    # -8: "... The following ads were ignored due to limit exceeded: IE1V, IE2L"
    ignorados = set(re.findall(r"IE\d+[VL]", bruto.split(":", 1)[1])) if codigo == -8 and ":" in bruto else set()
    mensagem = POR_EXTENSO.get(codigo, "resposta desconhecida da OLX") + (f" ({bruto})" if bruto else "")
    return Importacao(codigo=codigo, aceita=codigo in (0, -8), token=(j.get("token") or None), mensagem=mensagem,
                      erros=erros, ignorados=ignorados)


def _motivos(a: dict) -> str:
    partes: list[str] = []
    m = a.get("message")
    for x in (m if isinstance(m, list) else [m] if m else []):
        partes.append(str(x.get("error") or x.get("category") or x) if isinstance(x, dict) else str(x))
    for x in (a.get("image_errors") or a.get("imageErrors") or []):
        if isinstance(x, dict):
            partes.append(f"foto: {x.get('status') or 'erro'}")
    return ", ".join(dict.fromkeys(p for p in partes if p))


def ler_status(j: dict) -> dict[str, dict]:
    """A consulta do token -> {o nosso id: {estado, list_id, url, mensagem}}.

    `estado` é o que vai para `privado.olx_anuncio.estado`, ou None enquanto a OLX não decidiu (pending / queued):
      inserir ou editar aceito -> publicado · recusado pela moderação -> recusado · erro -> erro
      remover aceito -> removido · remover que falhou -> publicado (continua no ar, com o motivo)
    """
    saida: dict[str, dict] = {}
    ads = j.get("ads") or {}
    for ad_id, a in (ads.items() if isinstance(ads, dict) else []):
        if not isinstance(a, dict):
            continue
        status = str(a.get("status") or "").lower()
        remover = str(a.get("operation") or "").lower() == "delete"
        if status in ("accepted", "accept"):
            estado = "removido" if remover else "publicado"
        elif status == "refused":
            estado = "publicado" if remover else "recusado"
        elif status == "error":
            estado = "publicado" if remover else "erro"
        else:
            estado = None
        motivo = _motivos(a)
        if remover and estado == "publicado":
            motivo = "a OLX não removeu: " + (motivo or status)
        saida[str(ad_id)] = {"estado": estado, "list_id": str(a["list_id"]) if a.get("list_id") else None,
                             "url": a.get("url") or None, "mensagem": motivo or None}
    return saida
