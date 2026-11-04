"""O grupo CADASTRO DE IMÓVEL IMOBEASY: cada leva que o Tel encaminha vira um imóvel no site (Rascunho), com as fotos
no nosso servidor, e o checklist do que já tem e do que ela vai perguntar.

Leva sem imóvel e com telefone é o contato que faltava: entra na ficha que pediu o número (a marcada, ou a última que
está esperando). Leva sem imóvel e sem telefone ("ok", "obrigado") só fica lida.
"""
from __future__ import annotations

import logging

from cadastro import autorizacao, banco, campos, condominio, config, envio, fluxo, modelo, site
from cadastro import ficha as fichas
from cadastro import leva as levas
from cadastro.leva import Leva, Mensagem

log = logging.getLogger("cadastro.grupo")


def levas_fechadas(conn) -> list[Leva]:
    linhas = banco.linhas(conn, banco.NOVAS_DO_GRUPO, {"grupo": config.GRUPO_ID, "desde": config.DESDE_H * 3600})
    todas = levas.separar([Mensagem(**r) for r in linhas], config.LEVA_SILENCIO_S)
    return [lv for lv in todas if levas.fechada(lv, fluxo.agora(), config.LEVA_SILENCIO_S)]


def achar_condominio(conn, ficha: dict) -> dict:
    nome = ficha.get("condominio")
    if not nome or ficha.get("condo_id") or ficha.get("_condo_nao") or ficha.get("_condo_candidato"):
        return ficha
    o_que, cond = condominio.escolher(banco.linhas(conn, banco.CONDOMINIO, (nome, ficha.get("bairro"))))
    if o_que == "ligar":
        return condominio.ligar(ficha, cond)
    if o_que == "confirmar":
        return {**ficha, "_condo_candidato": {"id": cond["id"], "nome": cond["nome"], "bairro": cond.get("bairro")}}
    return ficha


def papel_de(conn, fone: str | None, dito: str | None) -> str | None:
    if fone and banco.uma(conn, banco.E_CORRETOR, (fone,))["sim"]:
        return "corretor"
    return dito if dito in ("corretor", "proprietario") else None


def _dono(nome: str | None, fone: str | None) -> dict:
    return {k: v for k, v in (("nome", nome), ("telefone", levas.fone_bonito(fone))) if v}


def tratar(conn, leva: Leva) -> None:
    """Uma leva fechada. Cada passo grava antes do próximo: se cair no meio, a ficha diz onde parou."""
    citada = _ficha_citada(conn, leva)
    saida = modelo.ler_leva(leva.texto, len(leva.fotos))
    fones = levas.fones_do_texto(leva.texto)
    dito = levas.normalizar_fone(*m.groups()) if (m := levas.FONE.search(saida.get("contato_telefone") or "")) else None
    if dito and dito not in fones:
        fones.append(dito)
    if not leva.fotos and not levas.parece_anuncio(leva.texto, saida):
        # 23/10: o Tel decide no grupo se ela fala com o contato ("pode", "não", "espera", "para", "não pergunta X")
        conversa = autorizacao.ficha_da_conversa(conn, citada, leva.quem_mandou.get("tel")) if leva.texto.strip() else None
        if conversa and autorizacao.escutar(conn, conversa, leva.texto, leva.ids[0]):
            citada = citada or conversa["id"]
        if fones and not saida.get("e_imovel"):
            _contato_que_faltava(conn, leva, fones, saida, citada)
            banco.linhas(conn, banco.MARCAR_LIDAS, {"ids": leva.ids, "cadastro": citada})
            return
        # 22/10 (Pedro: "vê se a IA de cadastro entende o que o Tel manda no grupo complementando o que faltou"): o
        # "4 banheiros" depois do Vila Palmas virou o imóvel 9056 e o "64m2" do Paradise Lake ficou só lido. O que vem
        # sem foto e sem cara de anúncio, até 24 h depois de um cadastro do grupo (ou marcando a mensagem dele), é
        # COMPLEMENTO desse cadastro.
        alvo = citada or _ficha_recente(conn)
        if alvo and _complemento(conn, leva, saida, alvo):
            return
        banco.linhas(conn, banco.MARCAR_LIDAS, {"ids": leva.ids, "cadastro": alvo})
        return
    if not saida.get("e_imovel") and not leva.fotos:
        banco.linhas(conn, banco.MARCAR_LIDAS, {"ids": leva.ids, "cadastro": citada})
        return
    _nova_ficha(conn, leva, saida, fones)


COMPLEMENTO_H = 24


def _ficha_recente(conn) -> int | None:
    r = banco.uma(conn, "SELECT id FROM privado.cadastro_whats WHERE grupo_id = %s AND estado <> 'cancelado' "
                        "AND codigo IS NOT NULL AND criado_em > now() - make_interval(hours => %s) ORDER BY id DESC LIMIT 1",
                  (config.GRUPO_ID, COMPLEMENTO_H))
    return r["id"] if r else None


def _complemento(conn, leva: Leva, saida: dict, alvo: int) -> bool:
    """Grava no cadastro (e na ficha) o que o Tel disse; o que ele disse vale (é a correção dele). Devolve se gravou."""
    c = fluxo.ler(conn, alvo)
    novo = {k: v for k, v in fichas.do_modelo(saida).items() if not k.startswith("_") and k != "descricao"}
    if not c or not c.get("codigo") or not novo:
        return False
    antes = c["ficha"] or {}
    ficha = achar_condominio(conn, fichas.juntar(antes, novo))
    chaves = set(novo) | ({"condo_id"} if ficha.get("condo_id") and not antes.get("condo_id") else set())
    liberou = False
    try:
        corpo = fichas.para_o_site({k: ficha[k] for k in chaves if k in ficha})
        if corpo:
            # 04/11: pelo mesmo PUT da trava -- o condomínio que o Tel disse aqui põe Disponível o que esperava por ele
            liberou = fluxo.gravar_no_site(conn, {**c, "ficha": ficha}, corpo)
    except Exception as e:  # noqa: BLE001
        fluxo.avisar_erro(conn, c, "Não consegui gravar o complemento do cadastro", e)
        return True
    fluxo.gravar(conn, c["id"], ficha=ficha)
    banco.linhas(conn, banco.MARCAR_LIDAS, {"ids": leva.ids, "cadastro": c["id"]})
    o_que = ", ".join(campos.resumo_do_que_tem(novo)) or ", ".join(campos.rotulos(list(novo)))
    envio.grupo(conn, f"Anotado no imóvel {c['codigo']}: {o_que}." + (" Com o condomínio, ele ficou Disponível." if liberou else ""),
                c["id"], citar=leva.ids[0])
    log.info("complemento do cadastro %s (imóvel %s): %s", c["id"], c["codigo"], sorted(novo))
    return True


def _ficha_citada(conn, leva: Leva) -> int | None:
    if not leva.citados:
        return None
    r = banco.uma(conn, "SELECT cadastro_id FROM privado.cadastro_whats_postada WHERE message_id = ANY(%s) "
                        "AND cadastro_id IS NOT NULL ORDER BY em DESC LIMIT 1", (leva.citados,))
    return r["cadastro_id"] if r else None


def _nova_ficha(conn, leva: Leva, saida: dict, fones: list[str]) -> None:
    ficha = fichas.do_modelo(saida)
    fone = fones[0] if fones else None
    nome = levas.nome_do_contato(leva.texto) or ficha.pop("_contato_nome", None)
    ficha.pop("_contato_nome", None)
    papel = papel_de(conn, fone, ficha.pop("_papel", None))
    ficha = achar_condominio(conn, ficha)
    # 04/11 (Pedro: "Precisa ter o condomínio obrigatório ... a Nay não pode cadastrar sem"): apartamento/casa de
    # condomínio sem o condomínio da tabela nasce Rascunho; vira Disponível quando ele chega (fluxo.gravar_no_site)
    if campos.exige_condominio(ficha.get("tipo")) and not ficha.get("condo_id"):
        ficha["_sem_condominio"] = True
    ficha["_fotos"] = 0
    ficha["_quem_mandou"] = leva.quem_mandou       # 23/10: é a quem ela pede a autorização (autorizacao.py)
    c = banco.uma(conn, """
        INSERT INTO privado.cadastro_whats (grupo_id, mensagens, texto, fotos, contato_tel, contato_nome, papel, ficha, canal)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s) RETURNING *""",
        (config.GRUPO_ID, leva.ids, leva.texto, banco.json([m.midia_url for m in leva.fotos]), fone, nome, papel,
         banco.json(ficha), fluxo.canal_do_contato(conn, fone, papel)))
    banco.linhas(conn, banco.MARCAR_LIDAS, {"ids": leva.ids, "cadastro": c["id"]})
    try:
        corpo = fichas.para_o_site(ficha)
        corpo.setdefault("privado", {})["observacoes"] = (
            f"Cadastrado pela Nay pelo grupo CADASTRO DE IMÓVEL IMOBEASY em {fluxo.agora():%d/%m/%Y} (ficha {c['id']}).")
        if ficha.get("_interno"):
            # 02/11 (REGRA_DOS_CAMPOS): o que é só da equipe vai junto, em Uso interno › Observações
            corpo["privado"]["observacoes"] += "\n" + str(ficha["_interno"]).strip()
        if fone:
            corpo["proprietario"] = _dono(nome, fone)
        codigo = site.criar_imovel(corpo)
        gravar = {"codigo": codigo}
        # 30/10 (Pedro: "estão vindo como rascunho do grupo de cadastro, não é para ser assim, é para ficar disponível"):
        # nasce Disponível; o de corretor já como parceiro, na mesma gravação (assim nem passa pelo site)
        # 04/11: menos o que espera o condomínio (`_sem_condominio`): fica Rascunho, e o 400 da trava não derruba a ficha
        c = {**c, **gravar, "ficha": ficha}
        parceiro = {"e_parceiro": True} if papel == "corretor" else {}
        if ficha.get("_sem_condominio"):
            if parceiro:
                site.salvar_imovel(codigo, parceiro)
        else:
            fluxo.gravar_no_site(conn, c, {"status": "Disponível", **parceiro})
        subiram, erros = site.subir_fotos(codigo, [m.midia_url for m in leva.fotos])
        ficha["_fotos"] = subiram
        fluxo.gravar(conn, c["id"], codigo=codigo, ficha=ficha, estado="na_fila" if fone else "sem_contato")
        c["estado"] = "na_fila" if fone else "sem_contato"
    except Exception as e:  # noqa: BLE001
        fluxo.avisar_erro(conn, c, "Não consegui cadastrar o imóvel que chegou no grupo", e)
        return
    envio.grupo(conn, checklist(conn, c, erros), c["id"], citar=leva.ids[0])


def checklist(conn, c: dict, erros_de_foto: list[str] | None = None) -> str:
    f = c["ficha"]
    ctx = fluxo.contexto(conn, c)
    falta = campos.faltam(f, ctx)
    # 04/11: desde 30/10 ele nasce Disponível; o que espera o condomínio fica em rascunho, e o grupo sabe por quê
    situacao = "em rascunho até eu ter o condomínio" if f.get("_sem_condominio") else "disponível"
    linhas = [f"📋 Imóvel {c['codigo']} {situacao}: {campos.descricao_do_imovel(f)}."]
    tem = campos.resumo_do_que_tem(f)
    linhas.append("✅ Já tenho: " + (", ".join(tem) if tem else "quase nada do texto") + ".")
    if f.get("_condo_candidato"):
        linhas.append(f"🏢 O condomínio parece ser o {f['_condo_candidato']['nome']}: vou confirmar.")
    if erros_de_foto:
        linhas.append(f"⚠️ {len(erros_de_foto)} foto(s) não subiram: {erros_de_foto[0]}")
    if not c.get("contato_tel"):
        linhas.append("❓ Falta: " + (", ".join(campos.rotulos(falta)) or "nada") + ".")
        linhas.append("📞 Não achei o número do corretor ou do proprietário. Me manda o contato aqui (pode marcar esta "
                      "mensagem) que eu pergunto o resto.")
        return "\n".join(linhas)
    linhas.append(f"👤 Contato: {fluxo.quem(c)}" + ("" if c.get("papel") else " (não sei se é dono ou corretor)"))
    if falta:
        # 23/10 (Pedro): as dúvidas vêm primeiro no grupo; falar com o contato só com o "pode" do Tel (autorizacao.py)
        linhas.append("❓ Dúvidas: " + ", ".join(campos.rotulos(falta)) + ".")
    return "\n".join(linhas)


def _contato_que_faltava(conn, leva: Leva, fones: list[str], saida: dict, citada: int | None) -> None:
    alvo = citada or (banco.uma(conn, "SELECT id FROM privado.cadastro_whats WHERE estado = 'sem_contato' AND "
                                      "criado_em > now() - interval '3 days' ORDER BY id DESC LIMIT 1") or {}).get("id")
    if not alvo:
        return
    c = fluxo.ler(conn, alvo)
    if c["estado"] not in ("sem_contato", "na_fila"):
        return
    fone = fones[0]
    nome = levas.nome_do_contato(leva.texto) or saida.get("contato_nome") or c.get("contato_nome")
    papel = papel_de(conn, fone, saida.get("papel")) or c.get("papel")
    try:
        site.salvar_imovel(c["codigo"], {"proprietario": _dono(nome, fone), **({"e_parceiro": True} if papel == "corretor" else {})})
    except Exception as e:  # noqa: BLE001
        fluxo.avisar_erro(conn, c, "Não consegui gravar o contato", e)
        return
    canal = fluxo.canal_do_contato(conn, fone, papel)
    ficha = dict(c["ficha"])
    if ficha.get("_autorizacao") == "pedida":
        ficha["_autorizacao"] = None          # o pedido era para falar com outra pessoa: pede de novo, com o nome novo
    fluxo.gravar(conn, c["id"], contato_tel=fone, contato_nome=nome, papel=papel, estado="na_fila", canal=canal, ficha=ficha)
    c = {**c, "contato_tel": fone, "contato_nome": nome, "papel": papel, "canal": canal, "ficha": ficha}
    envio.grupo(conn, f"Anotado: {fluxo.quem(c)} é o contato do imóvel {c['codigo']}.", c["id"], citar=leva.ids[0])
