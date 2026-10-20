"""O que vale para os dois lados (grupo e privado): gravar a ficha, salvar no site, a próxima pergunta e o fim.

Uma ficha anda assim (privado.cadastro_whats.estado):
  juntando     -> a leva chegou e o imóvel está sendo criado no site (Rascunho) com as fotos
  sem_contato  -> não veio o número do corretor/proprietário: ela pede no grupo e espera
  na_fila      -> pronto para perguntar (fora do horário, ou a pessoa está respondendo outra ficha)
  perguntando  -> uma pergunta por vez no privado; a resposta chega pela porta (nai_abrir_turno, bloco 428)
  concluido    -> perguntou tudo: o imóvel fica Disponível (com tipo, bairro e valor) e o grupo sabe
  sem_resposta -> passou o prazo sem resposta: fica como está e o grupo sabe o que faltou
  erro         -> algo falhou (site, modelo): o grupo sabe e a equipe completa à mão
"""
from __future__ import annotations

import logging
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
    return {"papel_conhecido": bool(c.get("papel")), "taxa_no_condominio": taxa}


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
    envio.grupo(conn, texto, c["id"] if c else None)


def proxima(conn, c: dict, primeira: bool = False) -> None:
    """Manda a próxima pergunta (uma só), ou conclui."""
    falta = campos.faltam(c["ficha"], contexto(conn, c))
    if not falta:
        concluir(conn, c, "concluido")
        return
    chave = falta[0]
    pergunta = campos.POR_CHAVE[chave].texto(c["ficha"])
    if primeira:
        baloes = [config.ABERTURA, f"É sobre {campos.descricao_do_imovel(c['ficha'])}. {pergunta}"]
    else:
        baloes = [pergunta]
    if not envio.privado(conn, c["contato_tel"], c.get("contato_nome"), baloes):
        raise RuntimeError("a pergunta não entrou na caixa da Nay")
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


def concluir(conn, c: dict, como: str) -> None:
    """Fim da ficha. Com tipo, bairro e valor o imóvel fica Disponível (Pedro, 20/10); sem eles, fica Rascunho."""
    c = _criar_condominio_novo(conn, c)
    ctx = contexto(conn, c)
    faltou_essencial = [k for k in campos.falta_essencial(c["ficha"], ctx) if k in ESSENCIAL_PARA_PUBLICAR]
    extra = {} if faltou_essencial else {"status": "Disponível"}
    if not faltou_essencial and c.get("papel") == "corretor":
        extra["e_parceiro"] = True       # parceiro fica fora do site e nunca vai a corretor (regra de 27/09 e 400)
    salvar_no_site(c, extra)
    if como == "concluido" and c.get("contato_tel") and c.get("estado") == "perguntando":
        envio.privado(conn, c["contato_tel"], c.get("contato_nome"), ["Pronto, cadastro concluído. Muito obrigada!"])
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
    if cod:
        linhas.append(config.LINK_DO_EDITOR.format(codigo=cod))
    return "\n".join(linhas)
