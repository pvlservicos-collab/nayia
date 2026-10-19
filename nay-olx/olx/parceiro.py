"""BUSCAR IMÓVEL DE PARCEIRO NA OLX (416, Pedro 19/10/2026): a ordem que a Nay do WhatsApp abre quando o nosso catálogo
não tem nada para o cliente (olx/whatsapp.py, `_buscar_e_mandar`). Roda numa linha própria dentro do serviço nay-olx.

  pendente  -> busca na OLX pelo Chrome do PC (olx/busca_olx.py, a nota da aba Grupos); nada >= nota_min: grupo
  achou     -> abre o anúncio; o telefone (descrição ou nossa base de scrap) -> "já falamos com ele?"
     sim    -> pergunta pelo número em que falamos (Parceria ou Captação) se está disponível; pausa a Nay da Parceria
               para ele; espera a resposta (`busca_parceiro_espera_h`)
                 disponível -> o imóvel vai ao cliente pelo 8595 (sem link, sem dizer "parceiro"); grupo avisado
                 não / outra coisa / sem resposta -> grupo; a Nay para de falar com o cliente (a equipe assume)
     não    -> grupo: "Achei esse imóvel ... chamar na OLX pelo anúncio"; a Nay para de falar com o cliente
Em TESTE (`busca_parceiro = teste`) a pergunta vai ao primeiro número de `whatsapp_teste`, nunca ao anunciante.
"""
from __future__ import annotations

import logging
import re
import threading
import time

from olx import banco, busca_olx, cdp, grupo, modelo, whatsapp

log = logging.getLogger("nay-olx.parceiro")
ABERTAS = ("pendente", "buscando", "sem_navegador", "perguntado")
LINHA_DA_ORIGEM = {"parceria": "parceria", "parceria_saida": "parceria", "nay": "parceria", "nay_saida": "parceria",
                   "core_saida": "parceria", "corretores": "parceria", "envio_saida": "parceria",
                   "captacao": "captacao", "captacao_saida": "captacao"}
MOTIVO_DA_PAUSA = "busca de parceiro na OLX"


def _cfg(conn) -> dict:
    c = banco.chaves(conn)
    return {"modo": (c.get("busca_parceiro") or "nao").strip().lower(), "nota_min": float(c.get("busca_parceiro_nota_min") or 88),
            "espera_h": float(c.get("busca_parceiro_espera_h") or 4), "cdp": c.get("busca_parceiro_cdp") or "http://127.0.0.1:9304",
            "sem_nav_min": float(c.get("busca_parceiro_sem_navegador_min") or 15),
            "teste": [re.sub(r"\D", "", x) for x in re.split(r"[,;\s]+", c.get("whatsapp_teste") or "") if len(re.sub(r"\D", "", x)) >= 10]}


def _marcar(conn, bid: int, **campos) -> None:
    sets = ", ".join(f"{k} = %s" for k in campos) + ", atualizado_em = now()"
    vals = [banco.js(v) if isinstance(v, (dict, list)) else v for v in campos.values()]
    banco.um(conn, f"UPDATE privado.olx_busca_parceiro SET {sets} WHERE id = %s", (*vals, bid))
    conn.commit()


def _aviso(o: dict, texto: str) -> None:
    whatsapp._grupo(("[teste] " if o["teste"] else "") + "Busca na OLX · " + texto)


def _cliente(lead: dict) -> str:
    return whatsapp.quem(lead)


def _parar_cliente(conn, lead: dict, motivo: str) -> None:
    """'ela vai aguardar uma resposta humana nossa ... não vai mandar mais nada pra ele'."""
    whatsapp._marcar(conn, lead["id"], humano_em=banco.um(conn, "SELECT now()"), parada_motivo=motivo[:200])
    conn.commit()


# ── o contato do anunciante ──
def bate_com_a_mascara(tel: str, mascarado: str | None) -> bool:
    """A OLX mostra o começo do número ("(92) 99981-****"): o telefone que começa igual é o do anunciante."""
    pref = re.sub(r"\D", "", mascarado or "")
    if pref.startswith("55") and (len(pref) >= 12 or re.match(r"\s*\+\s*55", mascarado or "")):
        pref = pref[2:]
    return len(pref) >= 4 and tel.startswith(pref)


def telefones_do_anuncio(conn, det: dict) -> list[str]:
    """Os números do anunciante: os da descrição e os que a nossa base de scrap (407) já tem para o mesmo anunciante.
    O que bate com o começo que a OLX mostra vem primeiro (a descrição às vezes cita o número do porteiro, do síndico)."""
    tels = list(banco.um(conn, "SELECT scrap_telefones_do_texto(%s)", (det.get("descricao") or "",)) or [])
    if det.get("anunciante_id"):
        base = banco.um(conn, """
            SELECT array_agg(DISTINCT t) FROM (
              SELECT unnest(a.telefones) AS t FROM scrap_anuncio a WHERE a.anunciante_id = %(a)s
              UNION SELECT c.telefone FROM scrap_contato c WHERE c.anunciante_id = %(a)s) x""", {"a": str(det["anunciante_id"])})
        tels += [t for t in (base or []) if t and t not in tels]
    return sorted(tels, key=lambda t: not bate_com_a_mascara(t, det.get("telefone_mascarado")))


def linha_conhecida(conn, tel: str) -> tuple[str | None, str | None]:
    """(linha, nome): em que número já falamos com ele. Sem conversa nossa = (None, nome que tivermos)."""
    return escolher_linha(*_o_que_sabemos(conn, tel))


def _o_que_sabemos(conn, tel: str) -> tuple[list[str], str | None, bool]:
    f = banco.linhas(conn, "SELECT origens FROM privado.falou_conosco WHERE chave = nay_fone_chave(nay_fone_com_ddi(%s))", (tel,))
    corretor = banco.linhas(conn, "SELECT nome FROM corretores WHERE nai_chave(telefone) = nai_chave(%s) LIMIT 1", (tel,))
    origens = list(f[0]["origens"] if f else []) + (["corretores"] if corretor else [])
    # pela Captação, nunca quem é dono da campanha nem cliente da OLX: as Nays de lá responderiam a resposta dele
    de_la = bool(banco.um(conn, """
        SELECT EXISTS (SELECT 1 FROM captacao_leads l WHERE l.telefone_chave = nay_fone_chave(nay_fone_com_ddi(%(t)s)))
            OR EXISTS (SELECT 1 FROM privado.olx_lead_whatsapp w WHERE right(w.telefone, 8) = right(%(t)s, 8))""", {"t": tel}))
    return origens, (corretor[0]["nome"] if corretor else None), de_la


def escolher_linha(origens: list[str], nome: str | None, e_cliente_da_captacao: bool) -> tuple[str | None, str | None]:
    linhas = {LINHA_DA_ORIGEM[o] for o in origens if o in LINHA_DA_ORIGEM}
    if "parceria" in linhas:
        return "parceria", nome
    if "captacao" in linhas and not e_cliente_da_captacao:
        return "captacao", nome
    return None, nome


def _instancia(linha: str) -> dict | None:
    conf = grupo._conf_do_vigia() or {}
    return (conf.get("instancias") or {}).get(linha)


def _mandar_pela_linha(linha: str, tel: str, texto: str) -> str:
    inst = _instancia(linha)
    if not inst:
        raise RuntimeError(f"sem a instância da {linha}")
    r = grupo._zapi(inst, "POST", "/send-text", {"phone": "55" + tel[-11:], "message": texto}, timeout=40)
    mid = str((r or {}).get("messageId") or (r or {}).get("id") or "") if isinstance(r, dict) else ""
    if not mid:
        raise RuntimeError((r or {}).get("_erro") if isinstance(r, dict) else "sem resposta da Z-API")
    return mid


def _pausar_parceria(conn, tel: str, titulo: str, pausar: bool) -> None:
    """A Nay da Parceria não responde a resposta dele enquanto esperamos (quem já estava parado por gente fica como está;
    no fim, só sai a pausa que for nossa)."""
    if pausar:
        banco.um(conn, """SELECT count(nai_parar_chat(id, %s)) FROM nai_contato
                           WHERE chave = nai_chave(%s) AND humano_assumiu_em IS NULL""",
                 (f"{MOTIVO_DA_PAUSA}: perguntamos se {titulo[:80]} está disponível", tel))
    else:
        banco.um(conn, """UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL
                           WHERE chave = nai_chave(%s) AND humano_motivo LIKE %s""", (tel, MOTIVO_DA_PAUSA + "%"))
    conn.commit()


def pergunta(nome: str | None, a: dict) -> str:
    primeiro = ((nome or "").strip().split() or [""])[0].capitalize()
    onde = ", ".join(x for x in (a.get("preco_texto"), a.get("bairro")) if x)
    return (f"Olá{', ' + primeiro if primeiro else ''}! Tudo bem? Aqui é a Nay, da Imob Easy. Vi o seu anúncio na OLX: "
            f"*{a.get('titulo')}*{' (' + onde + ')' if onde else ''}. Ele ainda está disponível? Tenho um cliente com esse "
            f"perfil.\n{a.get('url')}")


# ── os passos ──
def _buscar(conn, o: dict, c: dict, lead: dict) -> None:
    if not cdp.no_ar(c["cdp"]):
        if time.time() - o["criado_em"].timestamp() > c["sem_nav_min"] * 60:
            _marcar(conn, o["id"], estado="sem_navegador")
            _aviso(o, f"o cliente {_cliente(lead)} procura {whatsapp._resumo_dos_filtros(o['filtros'])}, mas o navegador do "
                      "Agente OLX no computador está desligado: a busca não rodou. Separar opções para ele.")
        return
    _marcar(conn, o["id"], estado="buscando", tentativas=o["tentativas"] + 1)
    cands = busca_olx.buscar(conn, c["cdp"], o["filtros"])
    bons = [x for x in cands if x["nota"] >= c["nota_min"]]
    resumo = [{"nota": x["nota"], **x["anuncio"]} for x in cands[:8]]
    if not bons:
        mais = (f" (o mais perto: nota {cands[0]['nota']:.0f}, {cands[0]['anuncio'].get('url')})" if cands else "")
        _marcar(conn, o["id"], estado="sem_resultado", candidatos=resumo)
        _aviso(o, f"o cliente {_cliente(lead)} procura {whatsapp._resumo_dos_filtros(o['filtros'])}: nada na OLX com nota "
                  f"{c['nota_min']:.0f} ou mais{mais}. Separar opções para ele.")
        return
    melhor = bons[0]
    det = busca_olx.detalhe(c["cdp"], melhor["anuncio"]["url"]) or {}
    escolhido = {**melhor["anuncio"], **{k: v for k, v in det.items() if v}}
    tels = telefones_do_anuncio(conn, det)
    linha, nome, tel = None, det.get("anunciante") or melhor["anuncio"].get("anunciante"), None
    for t in tels:
        linha, nome_base = linha_conhecida(conn, t)
        if linha:
            tel, nome = t, nome_base or nome
            break
    cab = (f"Achei esse imóvel com correspondência de {melhor['nota']:.0f}% para o cliente {_cliente(lead)}: "
           f"{escolhido.get('titulo')} · {escolhido.get('preco_texto') or ''} · {escolhido.get('bairro') or ''}.\n"
           f"Anúncio: {escolhido.get('url')}\nAnunciante: {nome or 'sem nome'}")
    if not linha:
        _marcar(conn, o["id"], estado="no_grupo", candidatos=resumo, escolhido=escolhido, nota=melhor["nota"],
                contato_tel=(tels[0] if tels else None), contato_nome=nome)
        _aviso(o, cab + (f" · telefone na descrição: {tels[0]}" if tels else " · sem telefone no anúncio") +
               "\nNão falamos com ele ainda: chamar na OLX pelo anúncio. A Nay parou de responder esse cliente: a conversa é nossa agora.")
        _parar_cliente(conn, lead, "busca na OLX: imóvel achado, a equipe chama o anunciante")
        return
    destino = c["teste"][0] if o["teste"] and c["teste"] else tel
    texto = pergunta(nome, escolhido)
    if o["teste"]:
        texto = f"[teste: iria para {nome or ''} {tel} pela {linha}]\n" + texto
    mid = _mandar_pela_linha(linha, destino, texto)
    if linha == "parceria":
        _pausar_parceria(conn, destino, escolhido.get("titulo") or "o imóvel", True)
    _marcar(conn, o["id"], estado="perguntado", candidatos=resumo, escolhido=escolhido, nota=melhor["nota"],
            contato_tel=destino, contato_nome=nome, linha=linha, pergunta_mid=mid, perguntado_em=banco.um(conn, "SELECT now()"))
    _aviso(o, cab + f" ({tel})\nJá falamos com ele pela {'Parceria' if linha == 'parceria' else 'Captação'}: perguntei agora se "
                    "está disponível. Se ele disser que sim, a Nay manda ao cliente.")


def _resposta(conn, o: dict) -> str:
    """O que ele escreveu depois da pergunta, na linha da pergunta (vazio = ainda nada)."""
    if o["linha"] == "parceria":
        sql = """SELECT texto, criada_em FROM mensagens WHERE direcao = 'recebida' AND criada_em > %s
                    AND nai_chave(telefone) = nai_chave(%s) ORDER BY criada_em"""
    else:
        sql = """SELECT texto, criada_em FROM captacao_mensagens WHERE direcao = 'recebida' AND criada_em > %s
                    AND nay_fone_chave(telefone) = nay_fone_chave(nay_fone_com_ddi(%s)) ORDER BY criada_em"""
    ls = banco.linhas(conn, sql, (o["perguntado_em"], o["contato_tel"]))
    if not ls or time.time() - ls[-1]["criada_em"].timestamp() < 25:      # espera ele terminar de escrever
        return ""
    return "\n".join(l["texto"] for l in ls if (l["texto"] or "").strip())


SIM = re.compile(r"\b(sim|dispon[ií]vel|t[aá] dispon|est[aá] sim|ainda est[aá]|tem sim|ok)\b", re.I)
NAO = re.compile(r"\b(n[aã]o|alugad[oa]|vendid[oa]|indispon[ií]vel|j[aá] foi|fechad[oa])\b", re.I)


def disponivel(texto: str) -> str:
    """'sim' | 'nao' | 'duvida'. O modelo lê; sem ele, as palavras decidem só quando são claras."""
    try:
        r = modelo.chamar('Leia a resposta de um corretor à pergunta "o imóvel do seu anúncio ainda está disponível?". '
                          'Devolva só JSON {"disponivel": "sim" | "nao" | "duvida"}. "duvida" = ele não respondeu a '
                          "pergunta, impôs condição, ou fez outra pergunta.", texto[:1500])
        v = str(r.get("disponivel") or "").lower()
        if v in ("sim", "nao", "duvida"):
            return v
    except Exception:  # noqa: BLE001
        log.exception("o modelo não leu a resposta")
    s, n = bool(SIM.search(texto)), bool(NAO.search(texto))
    return "sim" if s and not n else "nao" if n and not s else "duvida"


def mandar_ao_cliente(conn, lead: dict, a: dict) -> None:
    linhas = [f"Achei mais uma opção para você:\n\n*{a.get('titulo')}*", f"📍 {a.get('bairro') or 'Manaus'}"]
    medidas = " · ".join(x for x in (f"{a['quartos']} quartos" if a.get("quartos") else "", a.get("area") or "") if x)
    if medidas:
        linhas.append("🛏 " + medidas)
    if a.get("preco_texto"):
        linhas.append("💰 " + str(a["preco_texto"]) + (f" + condomínio {a['condominio']}" if a.get("condominio") else ""))
    whatsapp._mandar(conn, lead, "/send-text", {"message": "\n".join(linhas)}, "olx_parceiro", texto_no_crm="\n".join(linhas))
    for url in (a.get("fotos") or [])[:6]:
        time.sleep(whatsapp.ENTRE_ENVIOS_S)
        whatsapp._mandar(conn, lead, "/send-image", {"image": url}, "olx_parceiro")
    time.sleep(whatsapp.DEPOIS_DAS_FOTOS_S)
    whatsapp.mandar_texto(conn, lead, "O que achou dessa?")
    conn.commit()


def _esperar(conn, o: dict, c: dict, lead: dict) -> None:
    a, nome = o["escolhido"] or {}, o["contato_nome"] or "o anunciante"
    texto = _resposta(conn, o)
    if not texto:
        if time.time() - o["perguntado_em"].timestamp() > c["espera_h"] * 3600:
            _marcar(conn, o["id"], estado="sem_resposta")
            _pausar_parceria(conn, o["contato_tel"], "", False)
            _aviso(o, f"{nome} ({o['contato_tel']}) não respondeu em {c['espera_h']:.0f} h se {a.get('titulo')} está disponível "
                      f"({a.get('url')}). A Nay parou de responder o cliente {_cliente(lead)}: seguir com ele.")
            _parar_cliente(conn, lead, "busca na OLX: o anunciante não respondeu")
        return
    veredito = disponivel(texto)
    _pausar_parceria(conn, o["contato_tel"], "", False)
    if veredito == "sim":
        mandar_ao_cliente(conn, lead, a)
        _marcar(conn, o["id"], estado="confirmado", resposta_texto=texto[:1000], resposta_em=banco.um(conn, "SELECT now()"))
        _aviso(o, f"{nome} ({o['contato_tel']}) confirmou que {a.get('titulo')} está disponível. A Nay mandou ao cliente "
                  f"{_cliente(lead)}. Anúncio: {a.get('url')}. Se ele quiser visitar, combinar com {nome}.")
        return
    _marcar(conn, o["id"], estado="negado" if veredito == "nao" else "no_grupo", resposta_texto=texto[:1000],
            resposta_em=banco.um(conn, "SELECT now()"))
    _aviso(o, f"{nome} ({o['contato_tel']}) respondeu sobre {a.get('titulo')}: \"{texto[:300]}\". "
              f"{'Não está disponível. ' if veredito == 'nao' else ''}A Nay parou de responder o cliente {_cliente(lead)}: "
              f"seguir com ele. Anúncio: {a.get('url')}")
    _parar_cliente(conn, lead, "busca na OLX: o anunciante respondeu e precisa de gente")


def uma_volta(conn) -> int:
    c = _cfg(conn)
    if c["modo"] not in ("teste", "sim"):
        return 0
    banco.um(conn, """UPDATE privado.olx_busca_parceiro SET estado = 'pendente'
                       WHERE estado = 'buscando' AND atualizado_em < now() - interval '10 minutes'""")
    conn.commit()
    feitas = 0
    for o in banco.linhas(conn, """SELECT * FROM privado.olx_busca_parceiro WHERE estado IN ('pendente', 'perguntado')
                                    ORDER BY id LIMIT 5"""):
        lead = whatsapp._lead(conn, o["lead"])
        try:
            if o["estado"] == "pendente":
                _buscar(conn, o, c, lead)
            else:
                _esperar(conn, o, c, lead)
            feitas += 1
        except cdp.SemNavegador as e:
            conn.rollback()
            log.warning("busca %s: sem navegador (%s)", o["id"], e)
            _marcar(conn, o["id"], estado="pendente")
        except Exception as e:  # noqa: BLE001
            conn.rollback()
            log.exception("busca %s falhou", o["id"])
            _marcar(conn, o["id"], estado="erro", erro=f"{type(e).__name__}: {e}"[:300])
            _aviso(o, f"a busca do cliente {_cliente(lead)} deu erro ({type(e).__name__}). Separar opções para ele.")
    return feitas


def laco() -> None:
    conn = None
    while True:
        try:
            if conn is None or conn.closed:
                conn = banco.conectar()
            uma_volta(conn)
            conn.rollback()
        except Exception:  # noqa: BLE001
            log.exception("a volta da busca de parceiro falhou")
            try:
                conn.close()
            except Exception:  # noqa: BLE001
                pass
            conn = None
            time.sleep(30)
        time.sleep(15)


def iniciar() -> threading.Thread:
    t = threading.Thread(target=laco, name="nay-busca-parceiro", daemon=True)
    t.start()
    return t
