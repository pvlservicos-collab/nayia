"""AS DÚVIDAS ACOMPANHADAS ATÉ O FIM (nayia 512; Pedro, 28/10/2026).

O caso: o Felipe (...0843) pediu fotos da parte de trás da casa 9051; a Nay disse "vou verificar e já retorno", o agente
perguntou à dona (Yara) e ela respondeu "Vou solicitar". Aí ninguém voltou: a rotina donos() da vps2 leva ao agente só a
primeira resposta do dono e fecha. Pedro: "preciso que seja criado um script de dúvida, relacionando pessoas diferentes,
e seja disparado um cron de tempos em tempos para ver se os proprietários ou os corretores responderam as dúvidas dos
leads ... pode ser um cron 2 vezes de manhã e 2 vezes à tarde e uma no fim do dia que checa tudo, dá um jeito aí para a
Nay não esquecer ninguém".

Cada dúvida (privado.duvida) liga QUEM perguntou (o lead do 8595, da pergunta_fila; ou o corretor da Parceria, da
core_pendencia), o IMÓVEL e QUEM SABE (o proprietário, ou o corretor dono do anúncio). A cada rodada lemos as conversas
dos dois lados desde a dúvida, o modelo diz em que pé está, e a regra daqui decide:

    já respondida / não era dúvida / desistiu  -> encerra (e tira da fila)
    o dono respondeu                          -> a resposta (e as fotos) vão a quem perguntou
    o dono vai ver / não respondeu            -> o cliente sabe uma vez que estamos esperando; o dono ganha até 2
                                                 lembretes (3 h sem resposta; 20 h depois do "vou ver"); depois, ao Tel
    ninguém perguntou ao dono (1 h depois)    -> perguntamos (pela linha em que ele já conversa, nunca o oficial)
    o dono não sabe / sem contato             -> ao Tel (a da Leads volta ao PV dele; a da Parceria, às Notificações)

O que está com o Tel no PV (fila/perguntada) só é conferido: se o dono respondeu ou alguém já respondeu, sai da fila.

    cd /root/nay-olx && set -a && . ./.env && set +a && .venv/bin/python -m olx.duvidas [--fim-do-dia] [--ensaio]

--fim-do-dia confere também as velhas e manda o resumo às Notificações do CRM. --ensaio lê e decide sem mandar nem
gravar nada (tudo numa transação desfeita). Chave privado.olx_config.duvidas_rotina: sim | teste (= ensaio) | nao.
"""
from __future__ import annotations

import argparse
import json
import logging
import re
from datetime import timedelta

import requests

from olx import banco, grupo, modelo, visita, whatsapp

log = logging.getLogger("olx.duvidas")

IMPORTA_DIAS = 5          # a dúvida mais velha que isso não entra
VELHA_DIAS = 7            # aberta há mais que isso: encerra (vai no resumo do fim do dia)
ESPERA_SEM_RESPOSTA_H = 3
ESPERA_VAI_VER_H = 20
AO_TEL_DEPOIS_H = 20      # depois dos lembretes, quanto mais esperamos antes de passar ao Tel
MAX_LEMBRETES = 2
AVISO_AO_CLIENTE_H = 2    # o cliente sabe que estamos esperando depois de 2 h sem a resposta
PERGUNTA_AO_DONO_H = 1    # o agente da vps2 pergunta ao dono no primeiro minuto; passada 1 h sem isso, perguntamos
EQUIPE_NA_CONVERSA_MIN = 30
HORARIO_DE_MANDAR = (8, 19)   # Manaus
MAX_FOTOS = 8
NO = "olx.duvidas"
ABERTAS = ("aberta", "esperando_dono", "com_o_tel")
SITUACOES = ("nao_e_duvida", "cliente_ja_respondido", "cliente_desistiu", "dono_respondeu", "dono_vai_ver",
             "dono_sem_resposta", "dono_nao_perguntado", "dono_nao_sabe")

PROMPT = """Você acompanha as DÚVIDAS que a Nay (Imob Easy, imobiliária em Manaus) não soube responder na hora. Uma dúvida liga
três pessoas: o CLIENTE que perguntou (um lead do WhatsApp ou um corretor parceiro), o IMÓVEL e QUEM SABE a resposta (o
proprietário, ou o corretor dono do anúncio). Leia as duas conversas e diga em que pé está.

Situações (escolha UMA):
- "nao_e_duvida": o que ficou anotado não é uma pergunta a responder ("Serve sim", "me envia", só um código, um card
  colado) ou é algo que a Nay resolve sozinha (mandar o card ou as fotos que já temos).
- "cliente_ja_respondido": depois da dúvida, alguém da Imob Easy (a Nay, o Tel, a equipe) já respondeu ao cliente o que
  ele perguntou.
- "cliente_desistiu": o cliente disse que não quer mais, fechou outro, ou a pergunta perdeu o sentido.
- "dono_respondeu": quem sabe já respondeu (texto ou fotos) e o cliente ainda não recebeu.
- "dono_vai_ver": ele disse que vai ver, solicitar ou confirmar, e ainda não trouxe a resposta.
- "dono_sem_resposta": perguntamos a ele e ele não respondeu nada.
- "dono_nao_perguntado": ninguém perguntou ainda a quem sabe.
- "dono_nao_sabe": ele disse que não sabe, não tem, ou mandou falar com outra pessoa.

Escreva (vazio quando não se aplica):
- "resposta": em dono_respondeu, o que vai ao cliente na voz da Nay: no máximo 2 frases, só o que responde, nada além do
  que o dono disse. Se ele mandou fotos, uma frase dizendo que são as fotos (elas vão junto).
- "fotos": true se o dono mandou fotos que respondem à dúvida.
- "aviso_ao_cliente": em dono_vai_ver ou dono_sem_resposta, uma frase curta ao cliente: ainda estamos aguardando o
  proprietário sobre <o assunto> e avisamos assim que tiver a resposta. Sem prazo. Use o tratamento indicado. Vazio
  se alguém da Imob Easy já disse ao cliente, depois da dúvida, que está vendo ou esperando isso.
- "lembrete_ao_dono": em dono_vai_ver ou dono_sem_resposta, um lembrete curto e educado sobre a MESMA dúvida ("Oi,
  Yara! Conseguiu ver as fotos da parte de trás da casa? O cliente segue interessado."). Nome só o do cadastro, nunca
  sigla; sem nome, sem nome.
- "pergunta_ao_dono": em dono_nao_perguntado, a mensagem a quem sabe: "Olá <nome>, eu estou com um cliente interessado
  no <imóvel> (código X) e ele perguntou <a dúvida>. Você pode me informar?"
- "resumo": uma linha para a equipe: o que foi perguntado, a quem, e o que falta.

Regras: português do Brasil, sem emoji, sem link, sem telefone. Ao cliente, nunca fale de comissão, de negociação nem o
nome do proprietário. Devolva SÓ JSON:
{"situacao": "...", "resposta": "", "fotos": false, "aviso_ao_cliente": "", "lembrete_ao_dono": "", "pergunta_ao_dono": "", "resumo": ""}"""


def _so8(t) -> str:
    return re.sub(r"\D", "", str(t or ""))[-8:]


def _hora(t) -> str:
    return t.astimezone(whatsapp.MANAUS).strftime("%d/%m %H:%M") if t else "?"


def _horas(a, b) -> float:
    return (a - b).total_seconds() / 3600 if a and b else 0.0


# ───────────────────────────── entrar: as dúvidas novas, juntando as repetidas
def _dono_do_imovel(conn, codigo) -> dict:
    if not codigo:
        return {"dono_motivo": "sem_imovel"}
    d = banco.linhas(conn, """SELECT d.nome, d.telefone, d.motivo, coalesce(i.e_parceiro, false) AS parceiro
                                FROM nai_proprietario_do_imovel(%s) d LEFT JOIN imoveis i ON i.codigo = %s LIMIT 1""",
                     (codigo, codigo))
    if not d:
        return {"dono_motivo": "sem_cadastro"}
    fone = re.sub(r"\D", "", d[0].get("telefone") or "")
    if fone.startswith("55") and len(fone) in (12, 13):
        fone = fone[2:]
    return {"dono_tel": fone if len(fone) >= 10 else None, "dono_nome": d[0].get("nome"),
            "dono_papel": "corretor" if d[0].get("parceiro") else "proprietario",
            "dono_motivo": d[0].get("motivo") or (None if len(fone) >= 10 else "sem_telefone")}


def _juntar_ou_entrar(conn, origem: str, n: dict, linha: str, papel: str) -> str:
    """A mesma pessoa, o mesmo imóvel, dentro de 3 dias e ainda aberta: é a mesma dúvida (a 2944 da Esther entrou 5
    vezes em 30 min). A pergunta nova, se diferente, vai junto."""
    igual = banco.linhas(conn, """SELECT id, pergunta FROM privado.duvida
                                   WHERE linha = %s AND estado IN ('aberta', 'esperando_dono', 'com_o_tel')
                                     AND right(regexp_replace(cliente_tel, '\\D', '', 'g'), 8) = %s
                                     AND coalesce(codigo, 0) = coalesce(%s, 0)
                                     AND perguntada_em > %s - interval '3 days' ORDER BY id LIMIT 1""",
                         (linha, _so8(n["chave"]), n.get("codigo"), n["criada_em"]))
    if igual:
        g = igual[0]
        junta = "" if (whatsapp.parecida(n["pergunta"], g["pergunta"], 0.55)
                       or whatsapp._mesmo_assunto(n["pergunta"], g["pergunta"])) else "\nE também: " + n["pergunta"].strip()
        banco.um(conn, """UPDATE privado.duvida SET juntas = juntas || %s::bigint, pergunta = left(pergunta || %s, 2000),
                           atualizada_em = now() WHERE id = %s""", (n["id"], junta, g["id"]))
        return "juntou"
    lead = None
    if linha == "captacao":
        lead = banco.um(conn, """SELECT id FROM privado.olx_lead_whatsapp WHERE right(telefone, 8) = %s
                                  ORDER BY criado_em DESC LIMIT 1""", (_so8(n["chave"]),))
    dono = _dono_do_imovel(conn, n.get("codigo"))
    banco.um(conn, """INSERT INTO privado.duvida (origem, origem_id, linha, cliente_tel, cliente_nome, cliente_papel, lead_id,
                                                  codigo, pergunta, perguntada_em, dono_tel, dono_nome, dono_papel, dono_motivo)
                      VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s) ON CONFLICT DO NOTHING""",
             (origem, n["id"], linha, re.sub(r"\D", "", n["chave"]), n.get("cliente"), papel, lead, n.get("codigo"),
              n["pergunta"][:2000], n["criada_em"], dono.get("dono_tel"), dono.get("dono_nome"), dono.get("dono_papel"),
              dono.get("dono_motivo")))
    return "entrou"


def importar(conn) -> dict:
    conta = {"entrou": 0, "juntou": 0}
    for n in banco.linhas(conn, """
            SELECT f.id, f.chave, f.cliente, f.codigo, f.pergunta, f.criada_em FROM pergunta_fila f
             WHERE f.linha = 'captacao' AND f.estado IN ('agente', 'fila', 'perguntada')
               AND f.criada_em > now() - make_interval(days => %s)
               AND NOT EXISTS (SELECT 1 FROM privado.duvida d WHERE d.origem = 'pergunta_fila'
                                AND (d.origem_id = f.id OR f.id = ANY (d.juntas)))
             ORDER BY f.id""", (IMPORTA_DIAS,)):
        conta[_juntar_ou_entrar(conn, "pergunta_fila", n, "captacao", "lead")] += 1
    for n in banco.linhas(conn, """
            SELECT p.id, p.chave, p.codigo, p.pergunta, p.criado_em AS criada_em,
                   (SELECT coalesce(nullif(btrim(k.nome_completo), ''), nullif(btrim(k.nome_whatsapp), ''))
                      FROM nai_contato k WHERE k.chave = p.chave LIMIT 1) AS cliente
              FROM core_pendencia p
             WHERE p.criado_em > now() - make_interval(days => %s)
               AND NOT EXISTS (SELECT 1 FROM pergunta_fila f WHERE f.origem = 'core_pendencia' AND f.origem_id = p.id
                                AND f.estado IN ('respondida', 'descartada'))
               AND NOT EXISTS (SELECT 1 FROM privado.duvida d WHERE d.origem = 'core_pendencia'
                                AND (d.origem_id = p.id OR p.id = ANY (d.juntas)))
             ORDER BY p.id""", (IMPORTA_DIAS,)):
        conta[_juntar_ou_entrar(conn, "core_pendencia", n, "parceria", "corretor")] += 1
    return conta


# ───────────────────────────── ler: as duas conversas desde a dúvida
def _fila_ids(d: dict) -> list[int]:
    return [int(d["origem_id"]), *[int(x) for x in d.get("juntas") or []]] if d["origem"] == "pergunta_fila" else []


def conversa_do_cliente(conn, d: dict) -> list[dict]:
    desde = d["perguntada_em"] - timedelta(hours=1)
    if d["linha"] == "captacao" and d.get("lead_id"):
        lead = whatsapp._lead(conn, d["lead_id"])
        saida = []
        for m in whatsapp._conversa(conn, lead) if lead else []:
            if m.get("criada_em") and m["criada_em"] < desde:
                continue
            if m.get("direcao") == "recebida":
                quem = "Cliente"
            elif m.get("nossa") or m.get("origem") == "resposta":
                quem = "Nay"
            else:
                quem = "Equipe" + (f" ({m['quem']})" if m.get("quem") else "")
            saida.append({"em": m.get("criada_em"), "quem": quem, "texto": (m.get("texto") or f"[{m.get('origem')}]")})
        return saida
    return [{"em": m["criada_em"], "quem": "Corretor" if m["direcao"] == "recebida" else "Imob Easy", "texto": _texto(m)}
            for m in banco.linhas(conn, """
                SELECT m.criada_em, m.direcao, m.origem, m.texto, m.audio_url, m.midia_url, c.transcricao
                  FROM mensagens m LEFT JOIN core_mensagem c ON c.message_id = m.message_id
                 WHERE right(regexp_replace(m.telefone, '\\D', '', 'g'), 8) = %s AND m.criada_em > %s
                 ORDER BY m.id LIMIT 60""", (_so8(d["cliente_tel"]), desde))]


_OUVIDOS: dict[str, str] = {}


def transcrever(url: str) -> str:
    """O áudio da Parceria que o núcleo não transcreveu (o dono não passa pela Nay nova): o mesmo modelo barato do núcleo
    (gpt-4o-mini-transcribe, US$ 0,003/min). Falhou = '' e o modelo vê só [audio]."""
    if url in _OUVIDOS:
        return _OUVIDOS[url]
    texto = ""
    try:
        chave = modelo._chave()
        a = requests.get(url, timeout=30)
        if chave and a.status_code == 200 and a.content:
            r = requests.post("https://api.openai.com/v1/audio/transcriptions", timeout=90,
                              headers={"Authorization": f"Bearer {chave}"},
                              files={"file": ("audio.ogg", a.content)},
                              data={"model": "gpt-4o-mini-transcribe", "language": "pt"})
            if r.status_code == 200:
                texto = str(r.json().get("text") or "").strip()
    except (requests.RequestException, ValueError):
        pass
    _OUVIDOS[url] = texto
    return texto


def _texto(m: dict) -> str:
    t = (m.get("texto") or "").strip() or (m.get("transcricao") or "").strip()
    url = m.get("audio_url") or m.get("midia_url")
    if not t and m.get("origem") == "audio" and url:
        t = transcrever(url)
        t = f"[áudio] {t}" if t else ""
    return t or f"[{m.get('origem')}]"


def conversa_do_dono(conn, d: dict) -> tuple[list[dict], list[str]]:
    """O que se falou com quem sabe, nas duas linhas, desde a dúvida; e as fotos que ele mandou pela Parceria (a Z-API
    guarda o link; as do 8595 não têm link aqui: o resumo diz para a equipe encaminhar)."""
    if not d.get("dono_tel"):
        return [], []
    linhas = banco.linhas(conn, """
        SELECT * FROM (
          SELECT m.criada_em, m.direcao, m.origem, m.texto, m.midia_url, m.audio_url, c.transcricao, 'Parceria' AS linha
            FROM mensagens m LEFT JOIN core_mensagem c ON c.message_id = m.message_id
           WHERE right(regexp_replace(m.telefone, '\\D', '', 'g'), 8) = %(t)s AND m.criada_em > %(desde)s
          UNION ALL
          SELECT criada_em, direcao, origem, texto, NULL, NULL, NULL, '8595' FROM captacao_mensagens
           WHERE right(regexp_replace(coalesce(telefone, ''), '\\D', '', 'g'), 8) = %(t)s AND criada_em > %(desde)s
        ) x ORDER BY criada_em LIMIT 60""", {"t": _so8(d["dono_tel"]), "desde": d["perguntada_em"] - timedelta(minutes=10)})
    conversa = [{"em": m["criada_em"], "quem": ("Dono" if m["direcao"] == "recebida" else "Imob Easy") + f" ({m['linha']})",
                 "texto": _texto(m), "direcao": m["direcao"]} for m in linhas]
    fotos = [m["midia_url"] for m in linhas if m["direcao"] == "recebida" and m["origem"] == "imagem" and m.get("midia_url")]
    return conversa, fotos[:MAX_FOTOS]


def _bloco(msgs: list[dict]) -> str:
    return "\n".join(f"[{_hora(m['em'])}] {m['quem']}: {str(m['texto']).strip()[:400]}" for m in msgs[-40:]) or "(nada)"


def montar_turno(d: dict, cliente: list[dict], dono: list[dict], fotos: list[str], agora, tratamento: str) -> str:
    quem_sabe = (f"{'o corretor dono do anúncio' if d.get('dono_papel') == 'corretor' else 'o proprietário'} "
                 f"{d.get('dono_nome') or '(sem nome no cadastro)'}") if d.get("dono_tel") else \
        f"sem contato ({d.get('dono_motivo') or 'sem cadastro'})"
    feito = []
    if d.get("dono_perguntado_em"):
        feito.append(f"perguntamos a quem sabe em {_hora(d['dono_perguntado_em'])}")
    if d.get("cobrancas"):
        feito.append(f"{d['cobrancas']} lembrete(s), o último em {_hora(d.get('dono_cobrado_em'))}")
    feito.append("o cliente já sabe que estamos esperando" if d.get("cliente_avisado_em") else
                 "o cliente ainda não foi avisado da espera")
    if fotos:
        feito.append(f"o dono mandou {len(fotos)} foto(s)")
    return (f"DÚVIDA (#{d['id']}, {_hora(d['perguntada_em'])}, há {_horas(agora, d['perguntada_em']):.0f} h): {d['pergunta']}\n"
            f"CLIENTE: {d.get('cliente_nome') or 'sem nome'} "
            f"({'lead do WhatsApp' if d['cliente_papel'] == 'lead' else 'corretor parceiro'}); tratamento: {tratamento}\n"
            f"IMÓVEL: {('#' + str(d['codigo']) + ' ' + (d.get('imovel') or '')).strip() if d.get('codigo') else '(sem código)'}\n"
            f"QUEM SABE: {quem_sabe}\nJÁ FEITO: {'; '.join(feito)}\n\n"
            f"CONVERSA COM O CLIENTE (desde a dúvida):\n{_bloco(cliente)}\n\n"
            f"CONVERSA COM QUEM SABE (desde a dúvida):\n{_bloco(dono)}")


# ───────────────────────────── decidir: a regra, sem banco (os testes moram aqui)
def decidir(d: dict, r: dict, agora, equipe_agora: bool = False) -> list[str]:
    s = r.get("situacao")
    if s in ("nao_e_duvida", "cliente_ja_respondido", "cliente_desistiu"):
        return ["encerrar"]
    if s == "dono_respondeu" and (str(r.get("resposta") or "").strip() or r.get("fotos")):
        return ["entregar"]
    if d.get("estado") == "com_o_tel" or d.get("com_o_tel_no_pv"):
        return []                                   # está com o Tel: aqui só se confere
    idade = _horas(agora, d["perguntada_em"])
    if s == "dono_nao_perguntado":
        if idade < PERGUNTA_AO_DONO_H:
            return []
        if d.get("dono_tel") and not d.get("dono_motivo") and str(r.get("pergunta_ao_dono") or "").strip():
            return ["perguntar_dono"]
        return ["ao_tel"]
    if s == "dono_nao_sabe":
        return ["ao_tel"]
    if s not in ("dono_vai_ver", "dono_sem_resposta"):
        return []
    acoes = []
    if (not d.get("cliente_avisado_em") and idade >= AVISO_AO_CLIENTE_H and not equipe_agora
            and str(r.get("aviso_ao_cliente") or "").strip()):
        acoes.append("avisar_cliente")
    marcos = [d.get("dono_cobrado_em"), d.get("dono_perguntado_em")]
    if s == "dono_vai_ver":
        marcos.append(d.get("ultima_do_dono"))
    base = max([m for m in marcos if m] or [d["perguntada_em"]])
    espera = ESPERA_VAI_VER_H if s == "dono_vai_ver" else ESPERA_SEM_RESPOSTA_H
    if (d.get("cobrancas") or 0) >= MAX_LEMBRETES:
        if _horas(agora, base) >= AO_TEL_DEPOIS_H:
            acoes.append("ao_tel")
    elif _horas(agora, base) >= espera and d.get("dono_tel") and str(r.get("lembrete_ao_dono") or "").strip():
        acoes.append("lembrar_dono")
    return acoes


# ───────────────────────────── fazer
class Rodada:
    def __init__(self, conn, ensaio: bool):
        self.conn, self.ensaio = conn, ensaio
        self.agora = banco.um(conn, "SELECT now()")
        h = self.agora.astimezone(whatsapp.MANAUS).hour
        self.pode_mandar = HORARIO_DE_MANDAR[0] <= h < HORARIO_DE_MANDAR[1]
        self._conectada = None
        self.ver = False

    def conectada(self) -> bool:
        if self._conectada is None:
            self._conectada = whatsapp.conectada()
        return self._conectada

    def equipe_agora(self, d: dict) -> bool:
        if d["linha"] == "captacao" and d.get("lead_id"):
            lead = whatsapp._lead(self.conn, d["lead_id"])
            g = whatsapp._gente_escreveu(self.conn, lead, None) if lead else None
            return bool(g and _horas(self.agora, g) * 60 < EQUIPE_NA_CONVERSA_MIN)
        return bool(banco.um(self.conn, """SELECT EXISTS (SELECT 1 FROM mensagens WHERE direcao = 'enviada'
                                             AND right(regexp_replace(telefone, '\\D', '', 'g'), 8) = %s
                                             AND criada_em > now() - make_interval(mins => %s))""",
                             (_so8(d["cliente_tel"]), EQUIPE_NA_CONVERSA_MIN)))

    # -- ao cliente
    def ao_cliente(self, d: dict, texto: str, fotos: list[str] = ()) -> str:
        if self.ensaio:
            return "ensaio"
        if d["linha"] == "captacao":
            lead = whatsapp._lead(self.conn, d["lead_id"]) if d.get("lead_id") else {}
            if not lead or lead.get("humano_em") or lead.get("etapa") == "finalizado":
                return "a Nay não está na conversa"
            if not self.conectada():
                return "8595 desconectado"
            whatsapp.mandar_texto(self.conn, lead, texto)
            for url in fotos:
                whatsapp._mandar(self.conn, lead, "/send-image", {"image": url}, "foto", d.get("codigo"))
            return "mandado"
        if not banco.um(self.conn, "SELECT nay_duvida_mandar_pela_parceria(%s, %s)", (d["cliente_tel"], texto)):
            return "o corretor não tem contato na Parceria"
        for url in fotos if d.get("codigo") else []:
            banco.um(self.conn, "SELECT nay_duvida_mandar_pela_parceria(%s, '', %s, %s)", (d["cliente_tel"], url, d["codigo"]))
        return "mandado"

    # -- a quem sabe
    def ao_dono(self, d: dict, texto: str, motivo: str) -> str:
        if self.ensaio:
            return "ensaio"
        linha = d.get("dono_linha") or visita.linha_do_dono(self.conn, d["dono_tel"])
        if linha == "captacao" and not self.conectada():
            return "8595 desconectado"
        saiu = visita.mandar_ao_dono(self.conn, d.get("lead_id") or 0, d["dono_tel"], d.get("dono_nome"), texto,
                                     motivo, linha)
        banco.um(self.conn, "UPDATE privado.duvida SET dono_linha = %s WHERE id = %s", (saiu, d["id"]))
        return f"pela {saiu}"

    def fila(self, d: dict, sql: str, params: tuple = ()) -> None:
        ids = _fila_ids(d)
        if ids and not self.ensaio:
            banco.um(self.conn, sql, (*params, ids))

    def fazer(self, d: dict, r: dict, acoes: list[str], fotos: list[str]) -> list[str]:
        feito, muda = [], {}
        resumo = str(r.get("resumo") or "")[:300]
        for a in acoes:
            if a in ("avisar_cliente", "lembrar_dono", "perguntar_dono", "entregar") and not self.pode_mandar:
                feito.append(f"{a}: fora do horário")
                continue
            if a == "encerrar":
                muda["estado"] = "encerrada"
                self.fila(d, """UPDATE pergunta_fila SET estado = 'descartada', respondida_em = now(),
                                 detalhe = concat_ws(' · ', nullif(detalhe, ''), %s)
                                 WHERE id = ANY (%s) AND estado IN ('agente', 'fila')""",
                          ("rotina das dúvidas (512): " + (r.get("situacao") or ""),))
                feito.append("encerrada")
            elif a == "entregar":
                texto = str(r.get("resposta") or "").strip() or "Seguem as fotos que o proprietário mandou."
                if d.get("codigo") and d["linha"] == "captacao":
                    texto = whatsapp.texto_da_resposta({"resposta": texto, "codigo": d["codigo"], "imovel": d.get("imovel")})
                elif d.get("codigo"):
                    texto = f"Sobre o #{d['codigo']}" + (f" ({d['imovel']})" if d.get("imovel") else "") + f": {texto}"
                manda = fotos if r.get("fotos") else []
                como = self.ao_cliente(d, texto, manda)
                if como not in ("mandado", "ensaio"):
                    self.aviso(d, "duvida", f"A resposta da dúvida chegou, mas não mandei ({como}): {texto}")
                muda.update(estado="respondida", resposta=texto[:2000], respondida_em=self.agora)
                self.fila(d, """UPDATE pergunta_fila SET estado = 'respondida', resposta = %s, respondida_em = now(),
                                 entregue_em = now(), detalhe = concat_ws(' · ', nullif(detalhe, ''), 'respondida pelo dono (512)')
                                 WHERE id = ANY (%s) AND estado IN ('agente', 'fila', 'perguntada')""", (texto[:2000],))
                if d.get("com_o_tel_no_pv") == "perguntada" and not self.ensaio:
                    banco.um(self.conn, "SELECT pergunta_fila_perguntar_proxima()")
                if d.get("codigo") and str(r.get("resposta") or "").strip() and not self.ensaio:
                    banco.um(self.conn, """SELECT nay_gravar_conhecimento(%s::text, coalesce(nay_assunto_do_imovel(%s),
                                             'pergunta: ' || left(lower(%s), 120)), %s, 'dono (rotina das dúvidas, 512)')""",
                             (d["codigo"], d["pergunta"], d["pergunta"], str(r["resposta"]).strip()))
                feito.append(f"entregue ({como}{', ' + str(len(manda)) + ' foto(s)' if manda else ''})")
            elif a == "avisar_cliente":
                como = self.ao_cliente(d, str(r["aviso_ao_cliente"]).strip())
                if como in ("mandado", "ensaio"):
                    muda["cliente_avisado_em"] = self.agora
                feito.append(f"cliente avisado da espera ({como})")
            elif a == "lembrar_dono":
                como = self.ao_dono(d, str(r["lembrete_ao_dono"]).strip(), f"lembrete da dúvida #{d['id']}")
                if not como.startswith("8595"):
                    muda.update(dono_cobrado_em=self.agora, cobrancas=(d.get("cobrancas") or 0) + 1, estado="esperando_dono")
                feito.append(f"lembrete ao dono ({como})")
            elif a == "perguntar_dono":
                texto = str(r["pergunta_ao_dono"]).strip()
                ids = _fila_ids(d)
                if ids and not self.ensaio:
                    banco.um(self.conn, "SELECT nay_leads_perguntar_ao_dono(%s, %s, %s, %s)",
                             (ids[0], d["dono_tel"], d.get("dono_nome"), texto))
                    como = "pela fila da Nay Leads (493)"
                else:
                    como = self.ao_dono(d, texto, f"dúvida do corretor (#{d['id']})")
                if not como.startswith("8595"):
                    muda.update(dono_perguntado_em=self.agora, estado="esperando_dono")
                feito.append(f"perguntado ao dono ({como})")
            elif a == "ao_tel":
                muda["estado"] = "com_o_tel"
                if d["linha"] == "captacao":
                    self.fila(d, """UPDATE pergunta_fila SET estado = 'fila',
                                     ordem = (SELECT coalesce(max(ordem), 0) + 1 FROM pergunta_fila),
                                     detalhe = concat_ws(' · ', nullif(detalhe, ''), %s)
                                     WHERE id = ANY (%s) AND estado = 'agente'""",
                              ("a rotina das dúvidas (512) não conseguiu: " + resumo[:150],))
                    feito.append("ao PV do Tel")
                else:
                    feito.append("às Notificações do CRM")
                self.aviso(d, "duvida", f"Dúvida sem resposta, precisa de alguém: {resumo or d['pergunta'][:200]}")
        if acoes and r.get("situacao") in ("dono_vai_ver", "dono_sem_resposta") and "estado" not in muda \
                and d.get("estado") == "aberta":
            muda["estado"] = "esperando_dono"
        self.gravar(d, r, feito, muda)
        return feito

    def aviso(self, d: dict, tipo: str, texto: str) -> None:
        quem = f"{d.get('cliente_nome') or 'sem nome'} ({'Leads' if d['linha'] == 'captacao' else 'Parceria'}, " \
               f"{d['cliente_tel']})"
        corpo = f"{quem}" + (f", #{d['codigo']}" if d.get("codigo") else "") + f": {texto}"
        if self.ensaio:
            print("   [aviso ao CRM]", corpo[:300])
            return
        banco.um(self.conn, "SELECT nay_aviso_equipe('nay-olx', %s, %s, %s, %s)",
                 (tipo, texto.split(":")[0][:120], corpo[:3000], d["cliente_tel"]))

    def gravar(self, d: dict, r: dict, feito: list[str], muda: dict) -> None:
        passo = {"em": self.agora.isoformat(), "situacao": r.get("situacao"), "feito": feito,
                 "resumo": str(r.get("resumo") or "")[:300]}
        sets = ", ".join(f"{k} = %s" for k in muda)
        banco.um(self.conn, f"""UPDATE privado.duvida SET situacao = %s, resumo = %s, checada_em = now(),
                                   checagens = checagens + 1, historico = historico || %s::jsonb, atualizada_em = now()
                                   {', ' + sets if sets else ''} WHERE id = %s""",
                 (r.get("situacao"), passo["resumo"], json.dumps([passo], ensure_ascii=False), *muda.values(), d["id"]))


def _completar(conn, d: dict) -> dict:
    """O que muda de uma rodada para outra: o estado na pergunta_fila, o imóvel, a pergunta ao dono feita pela fila da
    Nay Leads (493) e a última vez que ele escreveu."""
    ids = _fila_ids(d)
    if ids:
        est = [x["estado"] for x in banco.linhas(conn, "SELECT estado FROM pergunta_fila WHERE id = ANY (%s)", (ids,))]
        d["com_o_tel_no_pv"] = "perguntada" if "perguntada" in est else ("fila" if "fila" in est and "agente" not in est else None)
        d["fila_respondida"] = bool(est) and all(e in ("respondida", "descartada") for e in est)
        if not d.get("dono_perguntado_em"):
            p = banco.linhas(conn, """SELECT min(enviado_em) AS em, min(linha) AS linha FROM privado.nay_leads_dono_pergunta
                                       WHERE fila = ANY (%s) AND estado = 'enviada'""", (ids,))
            if p and p[0]["em"]:
                d["dono_perguntado_em"], d["dono_linha"] = p[0]["em"], d.get("dono_linha") or p[0]["linha"]
                banco.um(conn, "UPDATE privado.duvida SET dono_perguntado_em = %s, dono_linha = %s WHERE id = %s",
                         (d["dono_perguntado_em"], d["dono_linha"], d["id"]))
    if d.get("codigo"):
        d["imovel"] = banco.um(conn, "SELECT nullif(btrim(condominio_nome), '') FROM imoveis WHERE codigo = %s", (d["codigo"],))
    return d


def checar(conn, rodada: Rodada, d: dict, chamar=None) -> list[str]:
    d = _completar(conn, d)
    if d.get("fila_respondida"):
        rodada.gravar(d, {"situacao": "fila_respondida", "resumo": "respondida ou descartada na fila"}, ["encerrada"],
                      {"estado": "encerrada"})
        return ["já respondida na fila"]
    if _horas(rodada.agora, d["perguntada_em"]) > VELHA_DIAS * 24:
        rodada.gravar(d, {"situacao": "velha", "resumo": d.get("resumo") or ""}, ["encerrada: velha"], {"estado": "encerrada"})
        return ["encerrada: velha"]
    cliente = conversa_do_cliente(conn, d)
    dono, fotos = conversa_do_dono(conn, d)
    ditas = [m["em"] for m in dono if m.get("direcao") == "recebida"]
    d["ultima_do_dono"] = max(ditas) if ditas else None
    if not d.get("dono_perguntado_em"):
        nossas = [m["em"] for m in dono if m.get("direcao") == "enviada" and m["em"] >= d["perguntada_em"]]
        if nossas:
            d["dono_perguntado_em"] = min(nossas)
            banco.um(conn, "UPDATE privado.duvida SET dono_perguntado_em = %s WHERE id = %s", (d["dono_perguntado_em"], d["id"]))
    trat = "você"
    if d.get("lead_id"):
        lead = whatsapp._lead(conn, d["lead_id"])
        trat = (whatsapp.tratamento(lead)[0] or "você") if lead else "você"
    turno = montar_turno(d, cliente, dono, fotos, rodada.agora, trat)
    try:
        r = (chamar or (lambda p, t: modelo.chamar(p, t, no=NO)))(PROMPT, turno)
    except Exception as e:  # noqa: BLE001 -- uma dúvida não para as outras
        log.warning("dúvida %s: o modelo falhou (%s)", d["id"], e)
        return [f"modelo falhou: {e}"]
    if r.get("situacao") not in SITUACOES:
        return [f"situação desconhecida: {r.get('situacao')}"]
    equipe = rodada.equipe_agora(d)
    acoes = decidir(d, r, rodada.agora, equipe)
    if rodada.ver:
        print(f"\n----- #{d['id']}\n{turno}\n=> {json.dumps(r, ensure_ascii=False)}\n=> equipe na conversa: {equipe}; "
              f"ações: {acoes}", flush=True)
    return [r["situacao"], *rodada.fazer(d, r, acoes, fotos)]


# ───────────────────────────── o resumo do fim do dia
def resumo_do_dia(conn) -> tuple[str, str]:
    abertas = banco.linhas(conn, """SELECT * FROM privado.duvida WHERE estado IN ('aberta', 'esperando_dono', 'com_o_tel')
                                     ORDER BY estado DESC, perguntada_em""")
    hoje = banco.linhas(conn, """SELECT estado, count(*) AS n FROM privado.duvida
                                  WHERE atualizada_em::date = now()::date AND estado IN ('respondida', 'encerrada')
                                  GROUP BY 1""")
    feitas = {h["estado"]: h["n"] for h in hoje}
    nomes = {"aberta": "aberta", "esperando_dono": "esperando quem sabe", "com_o_tel": "com o Tel"}
    linhas = [f"• {d.get('cliente_nome') or 'sem nome'} ({d['cliente_tel']}, {'Leads' if d['linha'] == 'captacao' else 'Parceria'})"
              + (f" #{d['codigo']}" if d.get("codigo") else "")
              + f" — {nomes[d['estado']]} desde {_hora(d['perguntada_em'])}: {d.get('resumo') or d['pergunta'][:160]}"
              for d in abertas]
    titulo = f"Dúvidas: {len(abertas)} em aberto"
    texto = (f"{titulo}; hoje {feitas.get('respondida', 0)} respondida(s) pelo dono e {feitas.get('encerrada', 0)} "
             f"encerrada(s).\n" + ("\n".join(linhas[:40]) if linhas else "Nenhuma esperando."))
    return titulo, texto


def rodar(conn, ensaio: bool = False, fim_do_dia: bool = False, chamar=None, so: str | None = None) -> list[str]:
    """`so`: só as dúvidas de quem tem esse final de telefone (e mostra o que o modelo leu e disse)."""
    rodada = Rodada(conn, ensaio)
    rodada.ver = bool(so)
    saida = [f"importadas: {importar(conn)}"]
    for d in banco.linhas(conn, """SELECT * FROM privado.duvida WHERE estado IN ('aberta', 'esperando_dono', 'com_o_tel')
                                    ORDER BY perguntada_em"""):
        if so and not d["cliente_tel"].endswith(so):
            continue
        if not conn.autocommit:
            banco.um(conn, "SAVEPOINT duvida")       # no ensaio, um erro não estraga a transação das outras
        try:
            feito = checar(conn, rodada, d, chamar)
        except Exception as e:  # noqa: BLE001
            log.exception("dúvida %s", d["id"])
            if not conn.autocommit:
                banco.um(conn, "ROLLBACK TO SAVEPOINT duvida")
            feito = [f"erro: {type(e).__name__}: {e}"]
        saida.append(f"#{d['id']} {d['linha']} {d.get('cliente_nome') or d['cliente_tel']}"
                     + (f" #{d['codigo']}" if d.get("codigo") else "") + ": " + " · ".join(feito))
    if fim_do_dia:
        titulo, texto = resumo_do_dia(conn)
        saida.append(texto)
        if not ensaio:
            banco.um(conn, "SELECT nay_aviso_equipe('nay-olx', 'relatorio', %s, %s, NULL)", (titulo, texto[:3900]))
    return saida


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ensaio", action="store_true")
    ap.add_argument("--fim-do-dia", action="store_true")
    ap.add_argument("--so", help="só o cliente com esse final de telefone, mostrando a leitura (ex.: --so 0843)")
    a = ap.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(message)s")
    conn = banco.conectar()
    chave = (banco.um(conn, "SELECT valor FROM privado.olx_config WHERE chave = 'duvidas_rotina'") or "nao").strip().lower()
    if chave == "nao" and not a.ensaio:
        print("duvidas_rotina = nao: nada feito")
        return
    ensaio = a.ensaio or chave == "teste"
    if ensaio:
        conn.autocommit = False
    try:
        for linha in rodar(conn, ensaio=ensaio, fim_do_dia=a.fim_do_dia, so=a.so):
            print(linha, flush=True)
    finally:
        if ensaio:
            conn.rollback()
        conn.close()


if __name__ == "__main__":
    main()
