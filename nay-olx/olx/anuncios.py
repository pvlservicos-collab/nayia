"""Os anúncios: sobem do cadastro, acompanham o cadastro e saem quando o imóvel sai.

Pedro, 13/10/2026: "quero fazer tudo no automático, tanto subir anúncio, quanto responder".

QUEM DECIDE É O BANCO (migração 364): `olx_anuncios_plano()` devolve o que a rodada faz -- remover o que saiu do
cadastro, atualizar o que mudou, publicar os novos até o teto -- com o anúncio já no formato da OLX. Aqui só se
manda, se pergunta o que aconteceu e se conta ao banco.

TRÊS PASSOS, cada um chamado pelo serviço no seu tempo (olx/worker.py):
  rodada()    manda o plano numa importação só. Com `publicar = nao` (como nasce) não manda nada.
  conferir()  pergunta à OLX o que a moderação fez com o que mandamos (publicou, recusou, removeu).
  situacao()  lê a lista de anúncios da conta: o que expirou, o que alguém apagou pelo site.

Pela linha de comando (no servidor, com o .env carregado):
  python -m olx.anuncios plano             o que a próxima rodada faria. NÃO fala com a OLX.
  python -m olx.anuncios ver 3050 venda    o anúncio de um imóvel, como iria (ou por que não vai)
  python -m olx.anuncios sonda [conta]     pergunta à OLX se a conta pode publicar pela API. Não publica nada.
  python -m olx.anuncios rodada            uma rodada agora (só anda com publicar = sim)
  python -m olx.anuncios publicar 5758 ... publica JÁ estes códigos (ordem de gente: ignora publicar e teto)
  python -m olx.anuncios conferir | situacao
"""
from __future__ import annotations

import json
import logging
import sys

from olx import api, banco

log = logging.getLogger("olx.anuncios")

# A SONDA: a remoção de um id que não existe. Não cria nem apaga anúncio; a resposta diz se a conta pode importar
# (0), se não tem plano de integração (-6), se está bloqueada (-2)...
SONDA = [{"id": "IE-SONDA-0", "operation": "delete"}]


def sondar(conn, conta: str) -> api.Importacao:
    token = banco.token_da_conta(conn, conta)
    if not token:
        raise api.ErroDaOlx(f"a conta {conta} não está conectada à OLX")
    r = api.ler_importacao(api.importar(token, SONDA))
    if r.permissao:
        banco.um(conn, "SELECT olx_permissao_gravar(%s, %s)", (r.permissao, f"{r.mensagem} (conta {conta})"))
    return r


def plano(conn) -> list[dict]:
    return banco.linhas(conn, "SELECT * FROM olx_anuncios_plano()")


def rodada(conn, cfg: dict[str, str]) -> dict:
    """Manda o plano à OLX. Devolve {"feito": ..., "nao": True quando a OLX disse não e vale esperar}."""
    if cfg.get("publicar") != "sim":
        return {"feito": "desligado (publicar = nao)"}
    conta = cfg.get("conta_que_publica") or ""
    if not conta:
        return {"feito": "sem conta escolhida (conta_que_publica)"}
    token = banco.token_da_conta(conn, conta)
    if not token:
        return {"feito": f"a conta {conta} não está conectada à OLX"}
    itens = plano(conn)
    if not itens:
        return {"feito": "nada a mandar"}

    r = api.ler_importacao(api.importar(token, [p["anuncio"] for p in itens]))
    if r.permissao:
        banco.um(conn, "SELECT olx_permissao_gravar(%s, %s)", (r.permissao, f"{r.mensagem} (conta {conta})"))
    quantos = {a: sum(1 for p in itens if p["acao"] == a) for a in ("publicar", "atualizar", "remover")}

    if r.aceita:
        for p in itens:
            if p["ad_id"] in r.ignorados:
                continue
            banco.um(conn, "SELECT olx_anuncio_enviado(%s, %s, %s, %s, %s, %s::jsonb, %s, %s)",
                     (p["ad_id"], p["codigo"], p["negocio"], conta, "delete" if p["acao"] == "remover" else "insert",
                      banco.js(p["anuncio"]) if p["acao"] != "remover" else None, p["hash"], r.token))
        log.info("rodada: %s | publicar %d, atualizar %d, remover %d | %d ficaram de fora por limite", r.mensagem,
                 quantos["publicar"], quantos["atualizar"], quantos["remover"], len(r.ignorados))
        return {"feito": r.mensagem, "mandados": len(itens) - len(r.ignorados), "nao": bool(r.ignorados)}

    if r.codigo == -4:
        # um anúncio falhou e a OLX cancelou tudo: quem falhou fica marcado (e sai das próximas rodadas por 6 h);
        # os outros não foram mandados e vão na rodada seguinte
        marcados = 0
        for p in itens:
            motivo = r.erros.get(p["ad_id"])
            if motivo and p["acao"] != "remover":
                banco.um(conn, "SELECT olx_anuncio_falhou(%s, %s, %s, %s, %s::jsonb, %s, %s)",
                         (p["ad_id"], p["codigo"], p["negocio"], conta, banco.js(p["anuncio"]), p["hash"],
                          f"a OLX recusou na validação: {motivo}"))
                marcados += 1
        log.warning("rodada: %s | marcados com erro: %s", r.mensagem, r.erros or "nenhum id veio na resposta")
        # sem saber quem falhou não dá para tirar ninguém da lista: espera, senão a mesma lista falha a cada volta
        return {"feito": r.mensagem, "erros": r.erros, "nao": marcados == 0}

    log.warning("rodada: a OLX não aceitou (%s)", r.mensagem)
    return {"feito": r.mensagem, "nao": True}


def publicar_lista(conn, cfg: dict[str, str], codigos: list[int], conta: str = "", lote: int = 5) -> dict:
    """Publica JÁ os imóveis pedidos à mão (Pedro, 14/10: "Dispara esses na olx", com a lista do Tel), venda e/ou
    locação conforme o cadastro. É uma ordem de gente: não olha `publicar` nem o teto. Cada imóvel fica registrado
    como os da rodada, então o serviço confere a moderação e depois atualiza ou remove sozinho.
    Vai em lotes pequenos porque um anúncio que falha cancela a importação inteira (-4)."""
    conta = conta or cfg.get("conta_que_publica") or "proprietarios"
    token = banco.token_da_conta(conn, conta)
    if not token:
        raise api.ErroDaOlx(f"a conta {conta} não está conectada à OLX")
    prontos, fora = [], []
    for c in codigos:
        for negocio in ("venda", "locacao"):
            m = banco.um(conn, "SELECT olx_anuncio_montar(%s, %s)", (c, negocio)) or {}
            if m.get("ok"):
                prontos.append({"codigo": c, "negocio": negocio, "ad_id": m["ad_id"], "anuncio": m["anuncio"], "hash": m["hash"]})
            else:
                motivo = m.get("barrado") or "; ".join(m.get("falta") or []) or "não monta"
                if not (negocio == "locacao" and "sem valor de aluguel" in motivo):   # só de venda: normal
                    fora.append(f"{c} {negocio}: {motivo}")
    enviados, falhas = [], []
    fila = list(prontos)
    while fila:
        grupo, fila = fila[:lote], fila[lote:]
        for tentativa in range(2):
            r = api.ler_importacao(api.importar(token, [p["anuncio"] for p in grupo]))
            if r.aceita:
                for p in grupo:
                    if p["ad_id"] in r.ignorados:
                        falhas.append(f"{p['ad_id']}: a OLX deixou de fora (limite)")
                        continue
                    banco.um(conn, "SELECT olx_anuncio_enviado(%s, %s, %s, %s, 'insert', %s::jsonb, %s, %s)",
                             (p["ad_id"], p["codigo"], p["negocio"], conta, banco.js(p["anuncio"]), p["hash"], r.token))
                    enviados.append(p["ad_id"])
                log.info("lote: %s | %s", r.mensagem, ", ".join(p["ad_id"] for p in grupo))
                break
            if r.codigo == -4 and r.erros and tentativa == 0:
                ruins = [p for p in grupo if p["ad_id"] in r.erros]
                for p in ruins:
                    banco.um(conn, "SELECT olx_anuncio_falhou(%s, %s, %s, %s, %s::jsonb, %s, %s)",
                             (p["ad_id"], p["codigo"], p["negocio"], conta, banco.js(p["anuncio"]), p["hash"],
                              f"a OLX recusou na validação: {r.erros[p['ad_id']]}"))
                    falhas.append(f"{p['ad_id']}: {r.erros[p['ad_id']]}")
                grupo = [p for p in grupo if p["ad_id"] not in r.erros]
                if grupo:
                    continue        # o resto do lote vai de novo, sem quem falhou
                break
            falhas.extend(f"{p['ad_id']}: {r.mensagem}" for p in grupo)
            log.warning("lote recusado: %s", r.mensagem)
            break
    return {"conta": conta, "enviados": enviados, "falhas": falhas, "fora": fora}


def publicar_pedidos(conn) -> int:
    """396 (Pedro, 16/10: "anunciar na OLX ... um popup de anúncio manualmente"): o que a pessoa pediu no popup do editar
    imóvel (privado.olx_anuncio_pedido, com o texto que ela mexeu) vai à OLX agora, um por vez. Ordem de gente: não olha
    `publicar` nem o teto. Fica registrado como os da rodada (o serviço confere a moderação); o hash é o do cadastro na
    hora do pedido, então a rodada não troca o texto dela enquanto o cadastro não mudar."""
    feitos = 0
    for p in banco.linhas(conn, """UPDATE privado.olx_anuncio_pedido SET estado = 'enviando'
                                    WHERE id = (SELECT id FROM privado.olx_anuncio_pedido WHERE estado = 'pendente'
                                                 ORDER BY id LIMIT 1 FOR UPDATE SKIP LOCKED)
                                  RETURNING *"""):
        def fim(estado: str, resultado: str) -> None:
            banco.um(conn, """UPDATE privado.olx_anuncio_pedido SET estado = %s, resultado = %s, feito_em = now()
                               WHERE id = %s""", (estado, resultado[:500], p["id"]))
        token = banco.token_da_conta(conn, p["conta"])
        if not token:
            fim("falhou", f"a conta {p['conta']} não está conectada à OLX")
            continue
        try:
            r = api.ler_importacao(api.importar(token, [p["anuncio"]]))
        except api.ErroDaOlx as e:
            fim("falhou", f"a OLX não respondeu: {e}")
            continue
        if r.aceita and p["ad_id"] not in r.ignorados:
            banco.um(conn, "SELECT olx_anuncio_enviado(%s, %s, %s, %s, 'insert', %s::jsonb, %s, %s)",
                     (p["ad_id"], p["codigo"], p["negocio"], p["conta"], banco.js(p["anuncio"]), p["hash"], r.token))
            fim("enviado", f"a OLX aceitou: {r.mensagem}. Agora passa pela moderação dela.")
            log.info("pedido %s: %s enviado à OLX", p["id"], p["ad_id"])
            feitos += 1
        else:
            motivo = (r.erros or {}).get(p["ad_id"]) or ("a OLX deixou de fora (limite da conta)" if r.aceita else r.mensagem)
            banco.um(conn, "SELECT olx_anuncio_falhou(%s, %s, %s, %s, %s::jsonb, %s, %s)",
                     (p["ad_id"], p["codigo"], p["negocio"], p["conta"], banco.js(p["anuncio"]), p["hash"],
                      f"pedido do popup: {motivo}"))
            fim("falhou", str(motivo))
            log.warning("pedido %s: a OLX recusou %s: %s", p["id"], p["ad_id"], motivo)
    return feitos


def conferir(conn) -> int:
    """O que a moderação da OLX fez com o que mandamos. Devolve quantos anúncios mudaram de estado."""
    pendentes = banco.linhas(conn, "SELECT * FROM olx_anuncios_a_conferir()")
    mudaram = 0
    por_importacao: dict[tuple[str, str], list[dict]] = {}
    for a in pendentes:
        por_importacao.setdefault((a["conta"], a["import_token"]), []).append(a)
    for (conta, import_token), grupo in por_importacao.items():
        token = banco.token_da_conta(conn, conta)
        if not token:
            continue
        lidos = api.ler_status(api.status_da_importacao(token, import_token))
        for a in grupo:
            s = lidos.get(a["ad_id"])
            if not s or not s["estado"]:
                continue        # a OLX ainda não decidiu
            banco.um(conn, "SELECT olx_anuncio_resultado(%s, %s, %s, %s, %s)",
                     (a["ad_id"], s["estado"], s["list_id"], s["url"], s["mensagem"]))
            mudaram += 1
            log.info("conferência: %s -> %s%s", a["ad_id"], s["estado"], f" ({s['mensagem']})" if s["mensagem"] else "")
            if s["mensagem"] and "NOT_ENOUGH_AD_SLOTS" in s["mensagem"]:
                banco.um(conn, "SELECT olx_permissao_gravar('sem_vaga', %s)",
                         (f"a conta {conta} não tem vaga para mais anúncios (NOT_ENOUGH_AD_SLOTS)",))
    return mudaram


def situacao(conn) -> int:
    """A situação de cada anúncio nosso na lista da conta (publicado, expirado, apagado pelo site...)."""
    vistos = 0
    for l in banco.linhas(conn, "SELECT DISTINCT conta FROM privado.olx_anuncio WHERE estado <> 'removido'"):
        token = banco.token_da_conta(conn, l["conta"])
        if not token:
            continue
        for a in api.publicados(token):
            ad_id = str(a.get("id") or "")
            if ad_id.startswith("IE") and a.get("status"):
                banco.um(conn, "SELECT olx_anuncio_na_olx(%s, %s, %s)", (ad_id, str(a.get("list_id") or ""), str(a["status"])))
                vistos += 1
    return vistos


def main(argv: list[str]) -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s")
    comando = argv[0] if argv else "plano"
    conn = banco.conectar()
    try:
        cfg = banco.chaves(conn)
        if comando == "plano":
            itens = plano(conn)
            print(f"publicar = {cfg.get('publicar')} | conta = {cfg.get('conta_que_publica') or '(nenhuma)'} | "
                  f"teto = {cfg.get('teto')} | permissão na OLX = {cfg.get('permissao') or '?'}")
            for p in itens:
                a = p["anuncio"]
                print(f"  {p['acao']:9} {p['ad_id']:10} {a.get('subject') or p['motivo'] or ''}"
                      + (f" | R$ {a['price']} | {len(a.get('images') or [])} fotos" if a.get("price") else ""))
            print(f"{len(itens)} na próxima rodada" + ("" if cfg.get("publicar") == "sim" else " (nada sai: publicar = nao)"))
        elif comando == "ver":
            m = banco.um(conn, "SELECT olx_anuncio_montar(%s, %s)", (int(argv[1]), argv[2] if len(argv) > 2 else "venda"))
            print(json.dumps(m, ensure_ascii=False, indent=2))
        elif comando == "sonda":
            conta = argv[1] if len(argv) > 1 else (cfg.get("conta_que_publica") or "proprietarios")
            r = sondar(conn, conta)
            print(f"conta {conta}: {r.mensagem} -> permissão: {r.permissao or 'indefinida'}")
        elif comando == "rodada":
            print(rodada(conn, cfg))
        elif comando == "publicar":
            # python -m olx.anuncios publicar 5758 5754 ... [--conta proprietarios]
            conta = argv[argv.index("--conta") + 1] if "--conta" in argv else ""
            codigos = [int(x) for x in argv[1:] if x.isdigit()]
            r = publicar_lista(conn, cfg, codigos, conta)
            print(f"conta {r['conta']}: {len(r['enviados'])} enviados à OLX: {' '.join(r['enviados']) or '-'}")
            for l in r["falhas"]:
                print("  FALHOU", l)
            for l in r["fora"]:
                print("  não vai", l)
        elif comando == "conferir":
            print(f"{conferir(conn)} anúncio(s) mudaram de estado")
        elif comando == "situacao":
            print(f"{situacao(conn)} anúncio(s) nossos vistos na lista da OLX")
        else:
            print(__doc__)
            return 2
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
