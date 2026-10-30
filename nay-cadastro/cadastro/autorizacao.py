"""A AUTORIZAÇÃO DO TEL (Pedro, 23/10/2026): "ele manda primeiro as dúvidas no grupo, e quando precisa falar com
proprietário fala o nome dele e pede permissão no grupo para o Tel e só dispara para o corretor ou proprietário a dúvida
depois da autorização do Tel, ela escuta o que o Tel falar no grupo e age segundo isso". E, no mesmo dia: "é melhor ele
perguntar do número que enviou as primeiras informações de imóvel e não fixar isso no número do Tel": o pedido marca
(@) quem mandou o imóvel no grupo (ficha["_quem_mandou"]: o 8595 da equipe ou o Tel), e vale a resposta dessa pessoa;
a do Tel também vale (é o dono).

O checklist (no_grupo) lista as dúvidas. Depois, numa mensagem só dela, o pedido: "@quem mandou, posso falar com FULANO ...?".
Nada sai no privado antes do "pode" (no_privado.iniciar pergunta a `precisa_autorizar`).

ficha["_autorizacao"]: None (ainda não pediu) | 'pedida' | 'sim' | 'nao'; ficha["_pedido_msg"]: o id da mensagem do pedido.
O que quem decide escreve no grupo sobre a ficha (marcando uma mensagem dela, ou a última que espera a autorização, ou a que
está perguntando) passa pelo modelo (modelo.ler_decisao): autoriza, não autoriza (ele mesmo vê), esperar, parar, e
quais dúvidas perguntar só ou pular. O dado do imóvel que disserem segue indo ao cadastro (no_grupo._complemento).
"""
from __future__ import annotations

import logging

from cadastro import banco, campos, config, envio, fluxo, modelo

log = logging.getLogger("cadastro.autorizacao")
ESPERA_DECISAO_H = 24          # a ficha que pediu a autorização há mais que isto não é mais "a última" (só marcando)


def precisa_autorizar(conn, c: dict) -> bool:
    """Falta perguntar algo e ainda não foi liberado no grupo: o privado não começa."""
    return (c["ficha"] or {}).get("_autorizacao") != "sim" and bool(campos.faltam(c["ficha"], fluxo.contexto(conn, c)))


def _por_onde(c: dict) -> str:
    return "pelo número de leads" if c.get("canal") == "leads" else "pelo número da Parceria"


def _so_digitos(t: str | None) -> str:
    return "".join(ch for ch in str(t or "") if ch.isdigit())


def quem_decide(c: dict) -> dict:
    """Quem mandou o imóvel no grupo ({tel, nome}); ficha antiga, sem isso: vazio (vale o Tel)."""
    return (c["ficha"] or {}).get("_quem_mandou") or {}


def pode_decidir(conn, c: dict, remetente: str | None) -> bool:
    """A mensagem é de quem mandou o imóvel, ou do Tel (o dono)."""
    r = _so_digitos(remetente)[-8:]
    if not r:
        return False
    tel = _so_digitos((banco.uma(conn, "SELECT nai_cfg('tel_telefone') AS t") or {}).get("t"))[-8:]
    return r == _so_digitos(quem_decide(c).get("tel"))[-8:] or r == tel


def texto_do_pedido(conn, c: dict) -> str:
    falta = campos.faltam(c["ficha"], fluxo.contexto(conn, c))
    q = _so_digitos(quem_decide(c).get("tel"))
    return (f"🙋 {'@' + q if q else 'Tel'}, posso falar com {fluxo.quem(c)} {_por_onde(c)} sobre o imóvel {c['codigo']}?\n"
            f"Vou perguntar: {', '.join(campos.rotulos(falta))}.\n"
            "Responda marcando esta mensagem: *pode* ou *não*. Também pode dizer o que perguntar, o que pular, "
            "ou já responder as dúvidas aqui.")


def pedir(conn) -> None:
    """As fichas prontas para perguntar (com contato e com dúvida) pedem a autorização no grupo, uma vez."""
    for c in banco.linhas(conn, "SELECT * FROM privado.cadastro_whats WHERE estado = 'na_fila' AND codigo IS NOT NULL "
                                "AND contato_tel IS NOT NULL ORDER BY id"):
        # 30/10: o que o anúncio e a ficha anterior do mesmo imóvel já dizem entra antes (não vira pedido nem pergunta)
        c = fluxo.com_o_que_ja_sabemos(conn, {**c, "ficha": fluxo.com_elevador(conn, c["ficha"] or {})})
        c = fluxo.com_taxa_sabida(conn, c)
        f = c["ficha"] or {}
        if f.get("_autorizacao") or not campos.faltam(f, fluxo.contexto(conn, c)):
            continue
        q = quem_decide(c).get("tel")
        mid = envio.grupo(conn, texto_do_pedido(conn, c), c["id"], mencionar=[q] if q else None)
        if not mid:
            continue
        fluxo.gravar(conn, c["id"], ficha={**f, "_autorizacao": "pedida", "_pedido_msg": mid})
        log.info("ficha %s: pediu a %s autorização para falar com %s", c["id"], quem_decide(c).get("nome") or "o Tel",
                 fluxo.quem(c))


def ficha_da_conversa(conn, citada: int | None, remetente: str | None) -> dict | None:
    """A ficha de que a pessoa está falando: a da mensagem marcada; senão a última esperando a autorização; senão a que
    está perguntando agora. Só se ela pode decidir sobre essa ficha (quem mandou o imóvel, ou o Tel)."""
    if citada:
        c = fluxo.ler(conn, citada)
        ok = bool(c) and c["estado"] in ("na_fila", "perguntando", "sem_contato")
        return c if ok and pode_decidir(conn, c, remetente) else None
    candidatas = banco.linhas(conn, """
        SELECT * FROM privado.cadastro_whats
         WHERE grupo_id = %(g)s AND (
               (estado = 'na_fila' AND ficha->>'_autorizacao' = 'pedida' AND atualizado_em > now() - make_interval(hours => %(h)s))
            OR estado = 'perguntando')
         ORDER BY (estado = 'na_fila') DESC, atualizado_em DESC LIMIT 10""", {"g": config.GRUPO_ID, "h": ESPERA_DECISAO_H})
    return next((c for c in candidatas if pode_decidir(conn, c, remetente)), None)


def escutar(conn, c: dict, texto: str, citar: str | None) -> bool:
    """O que quem mandou o imóvel (ou o Tel) disse sobre a ficha. Devolve se decidiu alguma coisa (aí ela responde)."""
    ctx = fluxo.contexto(conn, c)
    falta = campos.faltam({**c["ficha"], "_so_perguntar": None}, ctx)
    duvidas = {k: campos.POR_CHAVE[k].rotulo for k in falta}
    situacao = (f"IMÓVEL {c['codigo']}: {campos.descricao_do_imovel(c['ficha'])}. CONTATO: {fluxo.quem(c)}. "
                + ("VOCÊ JÁ ESTÁ PERGUNTANDO A ELE." if c["estado"] == "perguntando" else "VOCÊ PEDIU A AUTORIZAÇÃO E ESPERA."))
    d = modelo.ler_decisao(situacao, duvidas, texto)
    return aplicar(conn, c, d, citar)


def aplicar(conn, c: dict, d: dict, citar: str | None) -> bool:
    dec, so, pular = d["decisao"], d["so_perguntar"], d["pular"]
    if dec == "nenhuma" and not so and not pular:
        return False
    f = dict(c["ficha"])
    if pular:
        f["_pular"] = list(dict.fromkeys([*(f.get("_pular") or []), *pular]))
    if so:
        f["_so_perguntar"] = so
    if dec == "autoriza":
        f["_autorizacao"] = "sim"
    elif dec == "nao_autoriza":
        f["_autorizacao"] = "nao"
    elif dec == "parar":
        f["_so_esperar"] = True
    fluxo.gravar(conn, c["id"], ficha=f)
    c = {**c, "ficha": f}
    nome = c.get("contato_nome") or "o contato"
    falta = campos.faltam(f, fluxo.contexto(conn, c))
    log.info("ficha %s: o Tel decidiu %s (só %s, pular %s)", c["id"], dec, so, pular)
    if dec in ("nao_autoriza", "parar"):
        envio.grupo(conn, f"Certo, não falo mais com {nome} sobre o imóvel {c['codigo']}.", c["id"], citar=citar)
        fluxo.concluir(conn, c, "concluido", despedir=False)
        return True
    if dec == "esperar":
        envio.grupo(conn, f"Ok, espero você liberar para falar com {nome}.", c["id"], citar=citar)
        return True
    if dec == "autoriza" or f.get("_autorizacao") == "sim":
        if not falta:
            envio.grupo(conn, f"Certo! Não falta nada para perguntar a {nome}: vou fechar o cadastro.", c["id"], citar=citar)
        else:
            quando = "" if fluxo.no_horario() else f" a partir das {config.HORA_INICIO}h"
            envio.grupo(conn, f"Certo! Vou perguntar a {nome}{quando}: {', '.join(campos.rotulos(falta))}.", c["id"], citar=citar)
        return True
    # só ajustou a lista, sem liberar ainda
    envio.grupo(conn, "Anotado. " + (f"Quando liberar, pergunto a {nome}: {', '.join(campos.rotulos(falta))}." if falta
                                      else "Não sobrou dúvida para perguntar."), c["id"], citar=citar)
    return True
