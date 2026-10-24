"""O que vale para os dois lados (grupo e privado): gravar a ficha, salvar no site, a próxima pergunta e o fim.

Uma ficha anda assim (privado.cadastro_whats.estado):
  juntando     -> a leva chegou e o imóvel está sendo criado no site (Rascunho) com as fotos
  sem_contato  -> não veio o número do corretor/proprietário: ela pede no grupo e espera
  na_fila      -> pronto para perguntar (fora do horário, ou a pessoa está respondendo outra ficha)
  perguntando  -> uma pergunta por vez no privado; a resposta chega pela porta (nai_abrir_turno, bloco 428), ou pelo
                  8595 (captacao_mensagens) quando canal = 'leads' (479)
  concluido    -> perguntou tudo: o imóvel fica Disponível (com tipo, bairro e valor) e o grupo sabe
  sem_resposta -> passou o prazo sem resposta: fica como está e o grupo sabe o que faltou
  erro         -> algo falhou (site, modelo): o grupo sabe e a equipe completa à mão
"""
from __future__ import annotations

import logging
import re
from datetime import datetime
from zoneinfo import ZoneInfo

from cadastro import banco, campos, config, envio, site
from cadastro import ficha as fichas
from cadastro.leva import fone_bonito

log = logging.getLogger("cadastro.fluxo")
MANAUS = ZoneInfo("America/Manaus")
ESSENCIAL_PARA_PUBLICAR = ("tipo", "valor", "bairro")


def agora() -> datetime:
    return datetime.now(MANAUS)


def no_horario(quando: datetime | None = None) -> bool:
    q = quando or agora()
    return config.HORA_INICIO <= q.hour < config.HORA_FIM


def gravar(conn, cid: int, **campos_da_linha) -> None:
    sets, vals = [], []
    for k, v in campos_da_linha.items():
        sets.append(f"{k} = %s")
        vals.append(banco.json(v) if k in ("ficha", "fotos", "condominio_novo") else v)
    banco.linhas(conn, f"UPDATE privado.cadastro_whats SET {', '.join(sets)}, atualizado_em = now() WHERE id = %s",
                 (*vals, cid))


def ler(conn, cid: int) -> dict:
    return banco.uma(conn, "SELECT * FROM privado.cadastro_whats WHERE id = %s", (cid,))


def contexto(conn, c: dict) -> dict:
    f = c["ficha"]
    taxa = False
    if f.get("condo_id"):
        taxa = banco.uma(conn, banco.TAXA_NO_CONDOMINIO, {"id": f["condo_id"], "quartos": f.get("quartos")})["sim"]
    return {"papel_conhecido": bool(c.get("papel")), "papel": c.get("papel"), "taxa_no_condominio": taxa}


def com_elevador(conn, ficha: dict) -> dict:
    """O elevador do condomínio cadastrado ("Sim, possui elevador" / "Não possui elevador") decide a pergunta do andar:
    com elevador, o andar; sem, os lances de escada (Tel, 20/10)."""
    if ficha.get("_elevador") or not ficha.get("condo_id"):
        return ficha
    r = banco.uma(conn, "SELECT elevador FROM condominio_ficha WHERE condominio_id = %s", (ficha["condo_id"],))
    texto = campos.sem_acento((r or {}).get("elevador"))
    valor = "nao" if re.search(r"\bnao\b", texto) else "sim" if re.search(r"\bsim\b|possui|\d", texto) else None
    return {**ficha, "_elevador": valor} if valor else ficha


def canal_do_contato(conn, fone: str | None, papel: str | None = None) -> str:
    """'leads' (8595) para todo contato (Pedro, 23/10: "quero tudo pelo número de leads"); a Parceria só para o dono que é
    lead da captação (a Nay de captação responderia junto). `papel` não decide mais (fica na assinatura de quem chama)."""
    if not fone:
        return "parceria"
    return banco.uma(conn, banco.CANAL_DO_CONTATO, {"tel": fone})["canal"]


def gente_no_chat(conn, c: dict) -> bool:
    """Alguém da equipe está com a conversa, no número por onde ela pergunta."""
    if c.get("canal") == "leads":
        return banco.uma(conn, banco.GENTE_NO_8595, {"tel": c["contato_tel"], "min": config.LEADS_GENTE_MIN})["sim"]
    return banco.uma(conn, banco.TEL_COM_A_CONVERSA, (c["contato_tel"],))["sim"]


def quem(c: dict) -> str:
    papel = {"corretor": "corretor", "proprietario": "proprietário"}.get(c.get("papel") or "", "")
    nome = c.get("contato_nome") or "o contato"
    return f"{nome}" + (f", {papel}" if papel else "") + (f", {fone_bonito(c['contato_tel'])}" if c.get("contato_tel") else "")


def salvar_no_site(c: dict, extra: dict | None = None) -> None:
    """O que já se sabe vai para o imóvel a cada resposta: se a conversa parar no meio, o que veio já está salvo."""
    if not c.get("codigo"):
        return
    corpo = fichas.para_o_site(c["ficha"])
    corpo.pop("descricao", None)          # a descrição é a do anúncio, gravada na criação; não reescreve
    site.salvar_imovel(c["codigo"], {**corpo, **(extra or {})})


def avisar_erro(conn, c: dict | None, o_que: str, erro: Exception | str) -> None:
    texto = f"⚠️ {o_que}" + (f" (imóvel {c['codigo']})" if c and c.get("codigo") else "") + f": {str(erro)[:300]}"
    log.error(texto)
    if c:
        gravar(conn, c["id"], estado="erro", erro=str(erro)[:1000])
    # 24/10 (Pedro): "os erros vão pra mim", pela linha da Parceria; o grupo da equipe não recebe mais o erro de sistema
    envio.alerta_de_erro("[nay-cadastro] " + texto)


def proxima(conn, c: dict, primeira: bool = False) -> None:
    """Manda a próxima pergunta (uma só), ou conclui.

    GENTE NO CHAT (Tel, 20/10, com a Raquel: ele pausou a conversa e corrigiu a pergunta à mão): com o Tel ou a
    equipe na conversa, ela não manda mais nada; a resposta que estava esperando ainda é lida (no_privado) e a ficha
    fecha com o que tem. `_so_esperar` na ficha faz o mesmo sem a pausa."""
    c = {**c, "ficha": com_elevador(conn, c["ficha"])}
    falta = campos.faltam(c["ficha"], contexto(conn, c))
    gente = not primeira and (c["ficha"].get("_so_esperar") or gente_no_chat(conn, c))
    if not falta or gente:
        concluir(conn, c, "concluido", despedir=not gente)
        return
    chave = falta[0]
    pergunta = campos.POR_CHAVE[chave].texto(c["ficha"])
    if primeira:
        baloes = [campos.abertura(c.get("contato_nome"), c["ficha"]), pergunta]
    else:
        baloes = [pergunta]
    if not envio.privado(conn, c["contato_tel"], c.get("contato_nome"), baloes, c.get("canal") or "parceria"):
        raise RuntimeError("a pergunta não saiu (caixa da Nay ou 8595)")
    gravar(conn, c["id"], estado="perguntando", pergunta=chave, pergunta_em=agora(), cobrada_em=None,
           perguntas_feitas=(c.get("perguntas_feitas") or 0) + 1)


def _criar_condominio_novo(conn, c: dict) -> dict:
    f = c["ficha"]
    if not f.get("condominio") or f.get("condo_id"):
        return c
    cid = site.criar_condominio(fichas.condominio_para_o_site(f))
    c = {**c, "ficha": {**f, "condo_id": cid}}
    gravar(conn, c["id"], ficha=c["ficha"], condominio_novo={"id": cid, "nome": f["condominio"]})
    return c


def concluir(conn, c: dict, como: str, despedir: bool = True) -> None:
    """Fim da ficha. Com tipo, bairro e valor o imóvel fica Disponível (Pedro, 20/10); sem eles, fica Rascunho."""
    c = _criar_condominio_novo(conn, c)
    ctx = contexto(conn, c)
    faltou_essencial = [k for k in campos.falta_essencial(c["ficha"], ctx) if k in ESSENCIAL_PARA_PUBLICAR]
    extra = {} if faltou_essencial else {"status": "Disponível"}
    if not faltou_essencial and c.get("papel") == "corretor":
        extra["e_parceiro"] = True       # parceiro fica fora do site e nunca vai a corretor (regra de 27/09 e 400)
    salvar_no_site(c, extra)
    if despedir and como == "concluido" and c.get("contato_tel") and c.get("estado") == "perguntando":
        envio.privado(conn, c["contato_tel"], c.get("contato_nome"), ["Pronto, cadastro concluído. Muito obrigada!"],
                      c.get("canal") or "parceria")
    gravar(conn, c["id"], estado=como, pergunta=None, concluido_em=agora())
    envio.grupo(conn, texto_do_fim(c, como, ctx, faltou_essencial), c["id"])


def texto_do_fim(c: dict, como: str, ctx: dict, faltou_essencial: list[str]) -> str:
    f = c["ficha"]
    cod = c.get("codigo")
    situacao = "Rascunho (falta " + ", ".join(campos.rotulos(faltou_essencial)) + ")" if faltou_essencial else (
        "Disponível, como parceiro (fora do site)" if c.get("papel") == "corretor" else "Disponível")
    cabeca = (f"✅ Cadastro do imóvel {cod} concluído" if como == "concluido"
              else f"⌛ Encerrei o cadastro do imóvel {cod}: {c.get('contato_nome') or 'o contato'} não respondeu")
    linhas = [f"{cabeca} ({campos.descricao_do_imovel(f)}).", f"Situação: {situacao}."]
    tem = campos.resumo_do_que_tem(f)
    if tem:
        linhas.append("Ficou assim: " + ", ".join(tem) + ".")
    sem = campos.ficou_sem(f, ctx) + ([c["pergunta"]] if como != "concluido" and c.get("pergunta") else [])
    sem = [s for s in dict.fromkeys(sem) if not campos.POR_CHAVE[s].preenchida(f)]
    if sem:
        linhas.append("Sem resposta: " + ", ".join(campos.rotulos(sem)) + ".")
    # o que nem chegou a ser perguntado (o Tel pegou a conversa, ou a ficha fechou antes): a equipe completa
    nao_perguntado = [k for k in campos.faltam(f, ctx) if k not in sem]
    if nao_perguntado:
        linhas.append("Ficou faltando: " + ", ".join(campos.rotulos(nao_perguntado)) + ".")
    if cod:
        linhas.append(config.LINK_DO_EDITOR.format(codigo=cod))
    return "\n".join(linhas)
