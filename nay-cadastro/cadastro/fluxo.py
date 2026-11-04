"""O que vale para os dois lados (grupo e privado): gravar a ficha, salvar no site, a próxima pergunta e o fim.

Uma ficha anda assim (privado.cadastro_whats.estado):
  juntando     -> a leva chegou e o imóvel está sendo criado no site (Rascunho) com as fotos
  sem_contato  -> não veio o número do corretor/proprietário: ela pede no grupo e espera
  na_fila      -> pronto para perguntar (fora do horário, ou a pessoa está respondendo outra ficha)
  perguntando  -> uma pergunta por vez no privado; a resposta chega pela porta (nai_abrir_turno, bloco 428), ou pelo
                  8595 (captacao_mensagens) quando canal = 'leads' (479)
  concluido    -> perguntou tudo: o imóvel fica Disponível (com tipo, bairro e valor; e o condomínio, quando o tipo
                  pede: 04/11) e o grupo sabe
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
# 04/11 (Pedro: "Precisa ter o condomínio obrigatório ... a Nay não pode cadastrar sem"): o condomínio entra no essencial;
# a pergunta "condominio" só cabe nos tipos que pedem (campos.exige_condominio), então casa de rua e sala não esperam por ele
ESSENCIAL_PARA_PUBLICAR = ("tipo", "valor", "bairro", "condominio")


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


def com_taxa_sabida(conn, c: dict) -> dict:
    """A TAXA DE CONDOMÍNIO JÁ SABIDA (Pedro, 30/10: "a gente já sabe que é padrão; só perguntar se o imóvel tiver uma
    quantidade de quartos diferente de qualquer outro imóvel desse condomínio"): com o condomínio cadastrado e os
    quartos, a taxa vem da ficha do condomínio ou de outro imóvel dele com os mesmos quartos; vai para a ficha e para o
    imóvel, e a pergunta da taxa não sai. Sem nenhum dos dois, ela pergunta."""
    f = c["ficha"]
    if campos.tem(f, "taxa_condominio") or not f.get("condo_id") or not f.get("quartos"):
        return c
    r = banco.uma(conn, banco.TAXA_JA_SABIDA, {"id": f["condo_id"], "quartos": int(f["quartos"]), "codigo": c.get("codigo")})
    if not r or not r.get("valor"):
        return c
    ficha = {**f, "taxa_condominio": float(r["valor"]), "_taxa_de": r["de"]}
    gravar(conn, c["id"], ficha=ficha)
    c = {**c, "ficha": ficha}
    salvar_no_site(conn, c)
    log.info("cadastro %s: taxa de condomínio %s pelo que já se sabe (%s)", c["id"], r["valor"], r["de"])
    return c


# O ANDAR QUE O ANÚNCIO JÁ DIZ (Pedro, 30/10: "ela fica fazendo as mesmas perguntas que já tem na conversa"): o Jean mandou
# "▫️ Andar alto" no texto e ela perguntou "O andar é baixo, médio ou alto?" -- o modelo pôs "andar alto" só nas
# características, e o andar da ficha ficou vazio.
ANDAR_NO_TEXTO = re.compile(r"\bandar\s+(alto|m[eé]dio|baixo)\b|\b(\d{1,2})\s*[ºo°]?\s*andar\b|\b(t[eé]rreo)\b", re.I)

# O MESMO IMÓVEL QUE JÁ PASSOU POR AQUI (Pedro, 30/10: "se o proprietário respondeu, isso deve ser adicionado ao cadastro
# para as próximas vezes, e nunca perguntar duas vezes a mesma coisa"): o Estilo Ponta Negra do Jean voltou ao grupo
# em 30/10 (ficha 20) com o mesmo texto de 23/10 (ficha 9, onde ele já tinha dito andar, banheiros e taxa). Mesmo
# contato, mesmo condomínio, mesmos quartos e a mesma área (ou o mesmo valor): o que ele respondeu antes vale de novo.
MESMO_IMOVEL_ANTES = """
SELECT c.id, c.codigo, c.ficha FROM privado.cadastro_whats c
 WHERE c.id <> %(id)s AND c.id < %(id)s AND c.ficha <> '{}'::jsonb
   AND right(regexp_replace(coalesce(c.contato_tel, ''), '\\D', '', 'g'), 8) = %(tel8)s
   AND (c.ficha->>'condo_id' = %(condo)s OR lower(btrim(c.ficha->>'condominio')) = lower(btrim(%(nome)s)))
   AND (c.ficha->>'quartos') = %(quartos)s
   AND (abs(coalesce((c.ficha->>'area_util')::numeric, -1) - %(area)s) <= 2
        OR coalesce(c.ficha->>'valor_aluguel', c.ficha->>'valor_venda') = %(valor)s)
 ORDER BY c.id DESC LIMIT 1
"""
# o que não passa de uma ficha para outra: o controle de cada conversa e o que é do anúncio novo
NAO_HERDA = {"descricao"}


def andar_do_anuncio(ficha: dict, texto: str | None = None) -> str | None:
    for t in [texto or "", ficha.get("descricao") or ""] + [str(x) for x in ficha.get("caracteristicas") or []]:
        m = ANDAR_NO_TEXTO.search(t)
        if m:
            if m.group(1):
                return "Andar " + campos.sem_acento(m.group(1)).replace("medio", "médio")
            return m.group(2) if m.group(2) else "Térreo"
    return None


def com_o_que_ja_sabemos(conn, c: dict) -> dict:
    """Antes de qualquer pergunta: o andar escrito no anúncio e o que o mesmo contato já respondeu sobre o mesmo imóvel
    numa ficha anterior vão para a ficha (e para o imóvel no site); a pergunta dessas coisas não sai."""
    f = dict(c["ficha"] or {})
    mudou = []
    if not campos.tem(f, "andar"):
        andar = andar_do_anuncio(f, c.get("texto"))
        if andar:
            f["andar"] = andar
            mudou.append("andar (do anúncio)")
    tel8 = re.sub(r"\D", "", c.get("contato_tel") or "")[-8:]
    if tel8 and f.get("quartos") and (f.get("condo_id") or f.get("condominio")):
        valor = f.get("valor_aluguel") or f.get("valor_venda")
        antes = banco.uma(conn, MESMO_IMOVEL_ANTES, {
            "id": c["id"], "tel8": tel8, "condo": str(f.get("condo_id") or ""), "nome": f.get("condominio") or "",
            "quartos": str(f["quartos"]), "area": float(f.get("area_util") or -100),
            "valor": str(valor) if valor else "-"})
        if antes:
            herdou = [k for k, v in (antes["ficha"] or {}).items()
                      if not k.startswith("_") and k not in NAO_HERDA and v not in (None, "", [], {}) and not campos.tem(f, k)]
            for k in herdou:
                f[k] = antes["ficha"][k]
            # e o que já foi perguntado a ele sobre este imóvel e ficou sem resposta (o Jean, 23/10: "vou ter que perguntar
            # para o proprietário") também não volta: fica para a equipe completar (ficou_sem)
            ja_feitas = [k for k in (antes["ficha"] or {}).get("_feitas") or [] if k not in (f.get("_feitas") or [])]
            if ja_feitas:
                f["_feitas"] = list(f.get("_feitas") or []) + ja_feitas
            if herdou or ja_feitas:
                f["_herdado_de"] = antes["codigo"]
                mudou.append(f"{', '.join(herdou) or 'nada novo'} e perguntas já feitas {', '.join(ja_feitas) or '-'} "
                             f"(da ficha {antes['id']}, imóvel {antes['codigo']})")
    if not mudou:
        return c
    gravar(conn, c["id"], ficha=f)
    c = {**c, "ficha": f}
    salvar_no_site(conn, c)
    log.info("cadastro %s: já se sabia %s; essas perguntas não saem", c["id"], "; ".join(mudou))
    return c


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


def salvar_no_site(conn, c: dict, extra: dict | None = None) -> bool:
    """O que já se sabe vai para o imóvel a cada resposta: se a conversa parar no meio, o que veio já está salvo.
    Devolve se o imóvel ficou Disponível nesta gravação (gravar_no_site)."""
    if not c.get("codigo"):
        return False
    corpo = fichas.para_o_site(c["ficha"])
    corpo.pop("descricao", None)          # a descrição é a do anúncio, gravada na criação; não reescreve
    return gravar_no_site(conn, c, {**corpo, **(extra or {})})


def gravar_no_site(conn, c: dict, corpo: dict) -> bool:
    """O PUT do imóvel, com a trava do condomínio (Pedro, 04/11: "Precisa ter o condomínio obrigatório ... a Nay não pode
    cadastrar sem, nem manualmente"). O imóvel que nasceu Rascunho só por falta do condomínio (`_sem_condominio`,
    no_grupo._nova_ficha) vira Disponível na gravação em que o condomínio da tabela (condo_id) chega -- a regra de 30/10
    ("é para ficar disponível") com o condomínio. E o 400 da trava não derruba a ficha: o resto é gravado sem a
    situação, o imóvel fica como estava e a ficha guarda que falta o condomínio. Devolve se a situação Disponível foi."""
    f = c["ficha"]
    if f.get("_sem_condominio") and f.get("condo_id") and "status" not in corpo:
        corpo = {**corpo, "status": "Disponível", **({"e_parceiro": True} if c.get("papel") == "corretor" else {})}
    try:
        site.salvar_imovel(c["codigo"], corpo)
    except site.FaltaCondominio as e:
        log.warning("cadastro %s: %s -- gravo o resto e o imóvel fica como está", c["id"], e)
        resto = {k: v for k, v in corpo.items() if k != "status"}
        if resto:
            site.salvar_imovel(c["codigo"], resto)
        if not f.get("_sem_condominio"):
            f["_sem_condominio"] = True       # na própria ficha (c["ficha"]): quem gravar a ficha depois leva junto
            gravar(conn, c["id"], ficha=f)
        return False
    if corpo.get("status") == "Disponível" and f.pop("_sem_condominio", None):
        gravar(conn, c["id"], ficha=f)
        log.info("cadastro %s: o condomínio chegou e o imóvel %s ficou Disponível", c["id"], c["codigo"])
    return corpo.get("status") == "Disponível"


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
    c = com_taxa_sabida(conn, c)
    c = com_o_que_ja_sabemos(conn, c)
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
    """Fim da ficha. Com tipo, bairro e valor o imóvel fica Disponível (Pedro, 20/10); sem eles, fica Rascunho. O
    condomínio, nos tipos que pedem, também (04/11): sem ele, fica Rascunho e o grupo sabe que falta."""
    c = _criar_condominio_novo(conn, c)
    ctx = contexto(conn, c)
    faltou_essencial = [k for k in campos.falta_essencial(c["ficha"], ctx) if k in ESSENCIAL_PARA_PUBLICAR]
    extra = {} if faltou_essencial else {"status": "Disponível"}
    if not faltou_essencial and c.get("papel") == "corretor":
        extra["e_parceiro"] = True       # parceiro fica fora do site e nunca vai a corretor (regra de 27/09 e 400)
    publicou = salvar_no_site(conn, c, extra)
    if extra.get("status") and c.get("codigo") and not publicou:
        faltou_essencial = ["condominio"]    # 04/11: a trava do site recusou (o tipo pede e o condomínio não ligou)
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
