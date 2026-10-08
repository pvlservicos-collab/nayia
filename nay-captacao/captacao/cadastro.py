"""A resposta do proprietário vai para o CADASTRO do imóvel (migração 321), de 5 em 5 minutos.

Pedro, 08/10/2026: "os cadastros dos [proprietários] que responderam as captações já estão atualizando os imóveis deles
e a data de contratos deles nos sites? organiza logo para atualizar tudo" e "o que está disponível e caso não tenha
foto ele puxe".

Quem decide o que entra é o banco (`captacao_aplicar_pendentes`): situação, valor do aluguel e fim do contrato, só
depois de 15 minutos de silêncio na conversa, e o que não pode entrar sozinho fica anotado em `captacao_aplicado`.
Aqui fica só o que o banco não faz: BAIXAR a foto que o dono mandou na conversa e entregá-la à API do site, que a guarda
em fotos-captacao/crm/<código>/ (a mesma rota do botão "Atualizar" do card do CRM). Com a foto no imóvel, a rodada
seguinte do banco põe o "disponível" no site.

Vale para TODA a captação (número oficial e Z-API): a rotina lê `captacao_leads`, não a fila deste serviço.
"""
from __future__ import annotations

import logging

import requests

from captacao import config

log = logging.getLogger("captacao.cadastro")
TENTATIVAS_POR_FOTO = 3
_falhou: dict[str, int] = {}
_avisou_sem_segredo = False


def _trazer(codigo: int, foto_id: str, url: str, pedir=requests) -> str | None:
    """Baixa a foto da conversa e entrega à API do site. Devolve o erro, ou None quando entrou."""
    try:
        r = pedir.get(url, timeout=30)
        if r.status_code != 200 or len(r.content) < 1024:
            return f"não baixei (HTTP {r.status_code}, {len(r.content)} bytes)"
        e = pedir.post(f"{config.SITE_API_URL}/api/captacao/crm/imovel/{codigo}/foto", data=r.content, timeout=40,
                       headers={"x-captacao-segredo": config.FOTO_SEGREDO, "x-foto-id": foto_id,
                                "Content-Type": "application/octet-stream"})
        j = e.json() if e.headers.get("content-type", "").startswith("application/json") else {}
        return None if j.get("ok") else f"a API do site recusou (HTTP {e.status_code}): {j.get('erro') or 'sem resposta legível'}"
    except (requests.RequestException, ValueError) as exc:
        return f"{exc.__class__.__name__}: {str(exc)[:120]}"


def fotos(conn, trazer=_trazer) -> list[str]:
    """As fotos que o dono mandou na conversa e ainda não estão no imóvel dele."""
    global _avisou_sem_segredo
    from captacao import banco   # aqui dentro: as partes puras deste arquivo são testadas sem o psycopg2
    pendentes = banco.linhas(conn, "SELECT * FROM captacao_fotos_a_puxar() LIMIT 60")
    if not pendentes:
        return []
    if not config.FOTO_SEGREDO:
        if not _avisou_sem_segredo:
            log.warning("há %d foto(s) da conversa para trazer, mas falta CAPTACAO_FOTO_SEGREDO no .env", len(pendentes))
            _avisou_sem_segredo = True
        return []
    feito = []
    for f in pendentes:
        if _falhou.get(f["foto_id"], 0) >= TENTATIVAS_POR_FOTO:
            continue
        erro = trazer(f["codigo"], f["foto_id"], f["url"])
        if erro:
            _falhou[f["foto_id"]] = _falhou.get(f["foto_id"], 0) + 1
            feito.append(f"foto {f['ordem']} do imóvel {f['codigo']} NÃO entrou: {erro}")
        else:
            feito.append(f"foto {f['ordem']} do imóvel {f['codigo']} entrou no cadastro")
    return feito


def respostas(conn) -> list[str]:
    """O que os donos disseram e ainda não estava no cadastro."""
    from captacao import banco
    feito = []
    for r in banco.linhas(conn, "SELECT * FROM captacao_aplicar_pendentes()"):
        mudou = "; ".join(f"{k}: {v.get('de')} -> {v.get('para')}" for k, v in (r["mudou"] or {}).items())
        conferir = " | ".join(r["conferir"] or [])
        if mudou or conferir:
            feito.append(f"imóvel {r['codigo']} (lead {r['lead_id']}): {mudou or 'nada mudou'}"
                         + (f" || CONFERIR: {conferir}" if conferir else ""))
    return feito


def rodada(conn) -> list[str]:
    return fotos(conn) + respostas(conn)
