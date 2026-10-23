"""O privado: "Só para concluir o cadastro do imóvel, pode me confirmar umas informações por favor?" e uma pergunta por
vez até acabar (Pedro, 20/10). A resposta chega pela porta da Nay (nai_abrir_turno, bloco 428) em
privado.cadastro_whats_entrada; foto que ele mandar vai para o imóvel.

A pergunta que já saiu não volta, respondida ou não (a regra de 20/10 do Tel: "não ficar pedindo 2 vezes a mesma
coisa"). Sem resposta em AVISO_SEM_RESPOSTA_H, o grupo sabe; em ENCERRA_SEM_RESPOSTA_H, a ficha fecha com o que tem.
"""
from __future__ import annotations

import logging

from cadastro import autorizacao, banco, campos, condominio, config, envio, fluxo, modelo, no_grupo, site
from cadastro import ficha as fichas

log = logging.getLogger("cadastro.privado")


def iniciar(conn) -> None:
    """As fichas na fila: começa a conversa de quem pode (no horário, sem outra ficha aberta, sem gente no chat)."""
    if not fluxo.no_horario():
        return
    for c in banco.linhas(conn, "SELECT * FROM privado.cadastro_whats WHERE estado = 'na_fila' ORDER BY id"):
        if banco.uma(conn, banco.OCUPADO, {"id": c["id"], "tel": c["contato_tel"]})["sim"]:
            continue
        # o papel pode ter chegado depois da ficha: o canal é conferido de novo antes da primeira pergunta
        canal = fluxo.canal_do_contato(conn, c["contato_tel"], c.get("papel"))
        if canal != c.get("canal"):
            fluxo.gravar(conn, c["id"], canal=canal)
            c = {**c, "canal": canal}
        if fluxo.gente_no_chat(conn, c):
            continue
        # 23/10 (Pedro): só fala com o corretor ou o proprietário depois do "pode" do Tel no grupo (antes de ler a
        # conversa anterior, que chama o modelo: a ficha esperando o Tel passa por aqui a cada volta)
        if autorizacao.precisa_autorizar(conn, c):
            continue
        try:
            fluxo.proxima(conn, o_que_ja_disse(conn, c), primeira=True)
        except Exception as e:  # noqa: BLE001
            fluxo.avisar_erro(conn, c, "Não consegui começar a conversa do cadastro", e)


def do_chat_pausado(conn) -> None:
    """A resposta que a porta deu ao Tel (chat pausado) entra na fila do cadastro; a próxima pergunta não sai (fluxo).
    E (479) o que ele respondeu pelo 8595, nas fichas que perguntam por lá."""
    for r in banco.linhas(conn, banco.DO_CHAT_PAUSADO):
        log.info("ficha %s: resposta do chat pausado entrou na fila", r["cadastro_id"])
    for r in banco.linhas(conn, banco.DO_8595):
        log.info("ficha %s: resposta pelo 8595 entrou na fila", r["cadastro_id"])


# o que a conversa de antes não decide: valor e taxa são do anúncio encaminhado ("2.000,00" solto pode ser o condomínio)
NAO_DA_CONVERSA = ("valor_venda", "valor_aluguel", "taxa_condominio", "iptu", "descricao")


def o_que_ja_disse(conn, c: dict) -> dict:
    """479 (Tel, 23/10, a Ana: disse "É andar alto / Oitavo" pelo 8595 e a Parceria perguntou o andar): antes da primeira
    pergunta, o que ele disse de 3 h antes da ficha até agora (8595 e Parceria) preenche o que falta. Só completa."""
    texto = (banco.uma(conn, banco.CONVERSA_RECENTE, {"tel": c["contato_tel"], "desde": c["criado_em"]})
             or {}).get("texto")
    if not texto:
        return c
    ficha = dict(c["ficha"])
    novo = {k: v for k, v in fichas.do_modelo(modelo.ler_leva(texto, 0)).items()
            if not k.startswith("_") and k not in NAO_DA_CONVERSA and not campos.tem(ficha, k)}
    if not novo:
        return c
    ficha = fichas.juntar(ficha, novo)
    fluxo.gravar(conn, c["id"], ficha=ficha)
    c = {**c, "ficha": ficha}
    fluxo.salvar_no_site(c)
    log.info("ficha %s: da conversa em volta do encaminhamento veio %s", c["id"], sorted(novo))
    return c


def responder(conn) -> bool:
    """Uma resposta (a mais antiga que já está pronta). True se tratou alguma."""
    entradas = banco.linhas(conn, banco.RESERVAR_RESPOSTA, {"silencio": config.RESPOSTA_SILENCIO_S})
    if not entradas:
        return False
    c = fluxo.ler(conn, entradas[0]["cadastro_id"])
    ids = [x["id"] for x in entradas]
    try:
        c = ler_a_resposta(conn, c, entradas)
        fluxo.salvar_no_site(c)
        banco.linhas(conn, banco.FEITAS, (ids,))
        fluxo.proxima(conn, c)
    except modelo.FalhaDoModelo:
        # a resposta volta para a fila e o worker espera um pouco antes de tentar de novo
        banco.linhas(conn, "UPDATE privado.cadastro_whats_entrada SET status = 'Recebido' WHERE id = ANY(%s)", (ids,))
        raise
    except Exception as erro:  # noqa: BLE001
        banco.linhas(conn, banco.FEITAS, (ids,))
        fluxo.avisar_erro(conn, c, "Não consegui ler a resposta do cadastro", erro)
    return True


def ler_a_resposta(conn, c: dict, entradas: list[dict]) -> dict:
    """A ficha com o que ele respondeu (e as fotos que mandou). Grava e devolve a linha atualizada."""
    texto = "\n".join(e["texto"] for e in entradas if e.get("texto")).strip()
    midias = [m for e in entradas for m in (e.get("midias") or [])]
    ficha = dict(c["ficha"])
    chave = c.get("pergunta")
    papel = c.get("papel")
    if midias and c.get("codigo"):
        subiram, _erros = site.subir_fotos(c["codigo"], midias)
        ficha["_fotos"] = int(ficha.get("_fotos") or 0) + subiram
    fora = False
    if texto and chave:
        decidido = condominio.resposta_da_confirmacao(texto) if chave == "condominio_confirma" else None
        if decidido is True:
            ficha = condominio.ligar(ficha, ficha["_condo_candidato"])
        elif decidido is False:
            ficha["_condo_nao"] = True
        else:
            pergunta = campos.POR_CHAVE[chave].texto(ficha)
            saida = modelo.ler_resposta(pergunta, chave, texto, ", ".join(campos.resumo_do_que_tem(ficha)))
            novo = fichas.do_modelo(saida)
            novo.pop("_contato_nome", None)
            if chave == "condominio_confirma" and saida.get("respondeu") and not novo.get("condominio"):
                ficha["_condo_nao"] = True
            ficha = fichas.juntar(ficha, novo)
            fora = bool(saida.get("fora_do_assunto")) and not novo
    if ficha.get("_papel") in ("corretor", "proprietario"):
        papel = ficha["_papel"]
    ficha = no_grupo.achar_condominio(conn, ficha)
    if chave:
        ficha["_feitas"] = list(dict.fromkeys([*(ficha.get("_feitas") or []), chave]))
    fluxo.gravar(conn, c["id"], ficha=ficha, papel=papel)
    if papel != c.get("papel") and papel == "corretor" and c.get("codigo"):
        site.salvar_imovel(c["codigo"], {"e_parceiro": True})
    if fora:
        envio.grupo(conn, f"💬 {fluxo.quem(c)} mandou, sobre outra coisa (imóvel {c['codigo']}): «{texto[:400]}»",
                    c["id"])
    return {**c, "ficha": ficha, "papel": papel}


def cobrar(conn) -> None:
    """Sem resposta: avisa o grupo uma vez; depois do prazo, fecha com o que tem."""
    for c in banco.linhas(conn, """
            SELECT * FROM privado.cadastro_whats
             WHERE estado = 'perguntando' AND pergunta_em < now() - make_interval(secs => %s)
               AND NOT EXISTS (SELECT 1 FROM privado.cadastro_whats_entrada e
                                WHERE e.cadastro_id = cadastro_whats.id AND e.status <> 'Feito')""",
                          (config.AVISO_SEM_RESPOSTA_H * 3600,)):
        try:
            horas = (fluxo.agora() - c["pergunta_em"]).total_seconds() / 3600
            if horas >= config.ENCERRA_SEM_RESPOSTA_H:
                fluxo.concluir(conn, c, "sem_resposta")
            elif c.get("cobrada_em") is None:
                pergunta = campos.POR_CHAVE[c["pergunta"]].texto(c["ficha"]) if c.get("pergunta") else ""
                envio.grupo(conn, f"⏳ {fluxo.quem(c)} ainda não respondeu sobre o imóvel {c['codigo']}. "
                                  f"A pergunta foi: «{pergunta}»", c["id"])
                fluxo.gravar(conn, c["id"], cobrada_em=fluxo.agora())
        except Exception as e:  # noqa: BLE001
            fluxo.avisar_erro(conn, c, "Não consegui fechar o cadastro sem resposta", e)
