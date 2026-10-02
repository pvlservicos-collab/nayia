#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Vigia do WhatsApp da Nay (Pedro, 02/10/2026).

"Quando um número desconectar, o outro número (parceria ou captação) manda lá no nosso grupo um
aviso claro avisando que a Nay caiu, e limpa a fila que ficou e reenvia a fila de forma mais lenta,
para a Nay não cair."

O que aconteceu em 02/10: o WhatsApp da Parceria desconectou da Z-API às 14:45 e ninguém soube. A
Z-API continuou ACEITANDO os envios (a caixa marcava "enviado") e guardou 68 mensagens na fila dela;
quando reconectou, às 16:00, soltou as 68 em dois minutos.

O que este vigia faz, uma vez por minuto, para UMA instância (o cron chama uma vez para cada):
  1. Pergunta à Z-API se o número está conectado.
  2. CAIU (duas leituras seguidas desconectado): avisa no grupo PELO OUTRO número.
  3. Enquanto está fora: tira da fila da Z-API o que ficou preso e guarda aqui no disco (primeiro
     guarda, depois apaga), para a Z-API não despejar tudo de uma vez na volta. Lembra o grupo de
     tempos em tempos.
  4. VOLTOU: avisa no grupo e reenvia o que guardou DEVAGAR (uma mensagem a cada `intervalo_s`),
     só em horário de gente, e nada velho demais. Cada reenvio troca o id da mensagem no banco
     (caixa da Nay e CRM), para a citação e o eco continuarem batendo.

Não toca em nenhuma função da Nay: a caixa continua igual. Tudo o que é segredo (instância, tokens,
id do grupo) mora em config.json no servidor, criado por vigia_whatsapp_instalar.sh; nada disso é
escrito no log.

Uso (VPS1, root; quem chama é o /etc/cron.d/vigia-whatsapp):
    python3 vigia_whatsapp.py parceria
    python3 vigia_whatsapp.py captacao
    python3 vigia_whatsapp.py parceria --teste      # manda UMA linha de teste ao grupo pela vizinha
    python3 vigia_whatsapp.py parceria --situacao   # só mostra o que o vigia sabe (não envia nada)
"""
import datetime as dt
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

RAIZ = os.environ.get("VIGIA_RAIZ") or os.path.dirname(os.path.abspath(__file__))
MANAUS = dt.timezone(dt.timedelta(hours=-4))
ID_SEGURO = re.compile(r"^[A-Za-z0-9_.:@-]{4,80}$")
PADRAO = {"intervalo_s": 15, "lembrete_min": 30, "validade_h": 12, "reenvio_das": 7, "reenvio_ate": 21,
          "leituras_para_cair": 2, "tentativas": 3}


# ---------------------------------------------------------------- utilidades
def agora():
    return dt.datetime.now(MANAUS)


def hora(iso):
    try:
        return dt.datetime.fromisoformat(iso).astimezone(MANAUS).strftime("%H:%M")
    except (TypeError, ValueError):
        return "?"


def duracao(segundos):
    minutos = max(1, int(segundos // 60))
    if minutos < 60:
        return "%d min" % minutos
    return "%dh%02d" % (minutos // 60, minutos % 60)


def log(nome, msg):
    print("%s [%s] %s" % (agora().strftime("%Y-%m-%d %H:%M:%S"), nome, msg), flush=True)


def ler_json(caminho, padrao):
    try:
        with open(caminho, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return padrao


def gravar_json(caminho, dado):
    tmp = caminho + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(dado, f, ensure_ascii=False)
    os.replace(tmp, caminho)


def arquivo(prefixo, nome, ext="json"):
    return os.path.join(RAIZ, "%s_%s.%s" % (prefixo, nome, ext))


def guardar_fora(nome, entrada, motivo):
    """O que não foi reenviado fica escrito, com o motivo, para alguém poder olhar depois."""
    with open(arquivo("nao_reenviadas", nome, "jsonl"), "a", encoding="utf-8") as f:
        f.write(json.dumps({"quando": agora().isoformat(), "motivo": motivo, "entrada": entrada}, ensure_ascii=False) + "\n")


# ---------------------------------------------------------------- Z-API
def api(inst, metodo, caminho, corpo=None, timeout=20):
    """Chama a Z-API. Nunca devolve nem registra a URL (ela carrega a instância e o token)."""
    dados = json.dumps(corpo).encode("utf-8") if corpo is not None else None
    req = urllib.request.Request(inst["base"] + caminho, data=dados, method=metodo,
                                 headers={"Client-Token": inst["client_token"], "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            bruto = r.read()
    except urllib.error.HTTPError as e:
        bruto = e.read()
        try:
            return json.loads(bruto or b"{}")
        except ValueError:
            return {"_erro": "HTTP %s" % e.code}
    except Exception as e:  # rede, tempo esgotado: só o tipo, sem a mensagem (pode trazer a URL)
        return {"_erro": type(e).__name__}
    try:
        return json.loads(bruto or b"{}")
    except ValueError:
        return {"_erro": "resposta sem JSON"}


def conectado(inst):
    """True, False, ou None quando a Z-API não respondeu (aí não se conclui nada)."""
    r = api(inst, "GET", "/status")
    if not isinstance(r, dict) or "connected" not in r:
        return None
    return bool(r.get("connected"))


def id_do_envio(r):
    if not isinstance(r, dict):
        return None
    return r.get("messageId") or r.get("id") or r.get("zaapId")


def puxar_fila(inst):
    """Tudo o que está na fila da Z-API. None = não consegui ler (então não se apaga nada)."""
    itens = []
    for pagina in range(1, 26):
        r = api(inst, "GET", "/queue?page=%d&pageSize=200" % pagina, timeout=30)
        if not isinstance(r, list):
            return None if pagina == 1 else itens
        itens += [x for x in r if isinstance(x, dict)]
        if len(r) < 200:
            break
    return itens


def entrada_da_fila(item):
    """Um item da fila da Z-API vira o que é preciso para mandar de novo."""
    baixo = {str(k).lower(): v for k, v in item.items()}

    def campo(*nomes):
        for n in nomes:
            v = baixo.get(n)
            if v not in (None, "", -1):
                return v
        return None

    ids = [str(baixo[k]) for k in ("messageid", "zaapid", "_id", "id") if baixo.get(k)]
    imagem = campo("image", "imageurl") or next(
        (v for k, v in baixo.items() if "image" in k and isinstance(v, str) and v.startswith(("http", "data:"))), None)
    texto = campo("message", "text")
    tipo = "imagem" if imagem else ("texto" if isinstance(texto, str) and texto.strip() else "?")
    criado = campo("created", "createdat")
    try:
        criado = float(criado)
        criado = criado / 1000.0 if criado > 1e11 else criado
    except (TypeError, ValueError):
        criado = None
    return {"ids": ids, "fone": str(campo("phone") or ""), "tipo": tipo,
            "texto": texto if tipo == "texto" else None, "imagem": imagem,
            "legenda": campo("caption") if tipo == "imagem" else None,
            "criado": criado, "guardado": time.time(), "tentativas": 0, "bruto": item}


def chave_da_entrada(e):
    return "|".join(e["ids"]) or "%s|%s|%s|%s" % (e["fone"], e.get("texto"), e.get("imagem"), e.get("criado"))


def enviar(inst, e):
    if e["tipo"] == "imagem":
        corpo = {"phone": e["fone"], "image": e["imagem"]}
        if e.get("legenda"):
            corpo["caption"] = e["legenda"]
        return api(inst, "POST", "/send-image", corpo, timeout=45)
    return api(inst, "POST", "/send-text", {"phone": e["fone"], "message": e["texto"]}, timeout=30)


# ---------------------------------------------------------------- banco (pelo container, no próprio servidor)
def psql(banco, sql):
    try:
        r = subprocess.run(["docker", "exec", "nay-postgres", "psql", "-U", "nay", "-d", banco, "-At",
                            "-v", "ON_ERROR_STOP=1", "-c", sql], capture_output=True, text=True, timeout=30)
    except Exception:
        return None
    return r.stdout.strip() if r.returncode == 0 else None


def lista_sql(ids):
    bons = [i for i in ids if ID_SEGURO.match(i)]
    return "ARRAY[%s]::text[]" % ", ".join("'%s'" % i for i in bons) if bons else None


def completar_do_banco(e):
    """Item da fila que eu não soube ler (tipo "?"): a caixa da Nay sabe o que era."""
    ids = lista_sql(e["ids"])
    if not ids:
        return
    d = psql("naydb", "SELECT nai_whatsapp_da_fila(%s)" % ids)
    try:
        d = json.loads(d) if d else None
    except ValueError:
        d = None
    if not d:
        return
    e["fone"] = e["fone"] or d.get("telefone") or ""
    if d.get("tipo") == "imagem" and d.get("imagem"):
        e.update(tipo="imagem", imagem=d["imagem"])
    elif d.get("tipo") == "texto" and d.get("texto"):
        e.update(tipo="texto", texto=d["texto"])


def trocar_id(inst, e, resposta):
    """A mensagem saiu de novo com outro id: a caixa da Nay e o CRM passam a conhecer o id novo."""
    novo, antigos = id_do_envio(resposta), lista_sql(e["ids"])
    if not novo or not ID_SEGURO.match(str(novo)) or not antigos:
        return
    if inst.get("banco"):
        corpo = json.dumps(resposta, ensure_ascii=False)
        if "$vg$" not in corpo:
            psql("naydb", "SELECT nai_whatsapp_reenviado(%s, '%s', $vg$%s$vg$::jsonb)" % (antigos, novo, corpo))
    psql("crmdb", "UPDATE lead_activities SET metadata = jsonb_set(metadata, '{zapi_message_id}', to_jsonb('%s'::text)) "
                  "WHERE created_at > now() - interval '4 days' AND metadata->>'zapi_message_id' = ANY (%s)" % (novo, antigos))


# ---------------------------------------------------------------- avisos no grupo
def avisar(conf, nome, texto, tambem_a_propria=False):
    """Manda ao grupo pelo OUTRO número. Só por número conectado: desconectado, a Z-API aceitaria e
    o aviso ficaria preso na fila dela. Devolve por qual número saiu (ou None)."""
    ordem = [conf["instancias"][nome]["vizinha"]] + ([nome] if tambem_a_propria else [])
    for quem in ordem:
        inst = conf["instancias"].get(quem)
        if not inst or conectado(inst) is not True:
            continue
        if id_do_envio(api(inst, "POST", "/send-text", {"phone": conf["grupo"], "message": texto})):
            return quem
    return None


def quem_e(inst):
    return "*%s* (final %s)" % (inst["rotulo"], inst["final"])


def texto_caiu(inst, est):
    return ("🚨 *A NAY CAIU* 🚨\n"
            "O WhatsApp da %s desconectou por volta das %s.\n"
            "Enquanto estiver fora, ela não recebe nem manda nada.\n\n"
            "*O que fazer:* abrir o painel da Z-API e ler o QR code com o celular desse número.\n\n"
            "Não reenviem nada por enquanto: o que ficar preso eu guardo e mando devagar quando ela voltar."
            % (quem_e(inst), hora(est.get("caiu_em"))))


def texto_lembrete(inst, est, fila):
    fora = (agora() - dt.datetime.fromisoformat(est["caiu_em"])).total_seconds()
    return ("⚠️ A %s continua *fora do ar* há %s.\n"
            "Falta ler o QR code no painel da Z-API com o celular desse número.%s"
            % (quem_e(inst), duracao(fora),
               "\n%d mensagem(ns) guardada(s) para reenviar quando ela voltar." % len(fila) if fila else ""))


def texto_voltou(conf, inst, est, fila):
    fora = (agora() - dt.datetime.fromisoformat(est["caiu_em"])).total_seconds()
    t = "✅ *A Nay voltou.*\nO WhatsApp da %s reconectou às %s, depois de %s fora." % (
        quem_e(inst), agora().strftime("%H:%M"), duracao(fora))
    if fila:
        pessoas = len({e["fone"] for e in fila})
        t += ("\n\nGuardei %d mensagem(ns) que ficaram presas, para %d pessoa(s). Vou mandar devagar, uma a cada %d "
              "segundos (uns %s), para não derrubar o número de novo. Não precisa reenviar."
              % (len(fila), pessoas, conf["intervalo_s"], duracao(len(fila) * conf["intervalo_s"])))
    else:
        t += "\n\nNão ficou nada preso na fila."
    return t + "\n\nO que mandaram para ela enquanto estava fora não chegou ao sistema: vale olhar no celular."


def texto_fim(inst, r):
    t = "✅ Fila da %s reenviada: %d mensagem(ns)." % (quem_e(inst), r.get("ok", 0))
    sobras = []
    if r.get("vencidas"):
        sobras.append("%d antiga(s) demais" % r["vencidas"])
    if r.get("falhas"):
        sobras.append("%d que a Z-API recusou" % r["falhas"])
    if r.get("sem_conteudo"):
        sobras.append("%d que não consegui remontar" % r["sem_conteudo"])
    if sobras:
        t += "\nNão mandei: " + ", ".join(sobras) + "."
        if r.get("finais"):
            t += " Eram para os finais " + ", ".join(sorted(set(r["finais"]))) + "."
    return t


# ---------------------------------------------------------------- a fila guardada
def guardar_fila(nome, inst, fila):
    """Tira da Z-API o que ficou preso. Primeiro grava no disco, depois apaga lá."""
    itens = puxar_fila(inst)
    if not itens:
        return 0
    ja = {chave_da_entrada(e) for e in fila}
    novas = [e for e in (entrada_da_fila(i) for i in itens) if chave_da_entrada(e) not in ja]
    fila.extend(novas)
    gravar_json(arquivo("fila", nome), fila)
    api(inst, "DELETE", "/queue", timeout=30)
    resto = puxar_fila(inst)
    if resto:
        # A Z-API não apagou: ela mesma vai soltar essas na volta. Tiro da minha lista para não sair em dobro.
        ficaram = {chave_da_entrada(entrada_da_fila(i)) for i in resto}
        fila[:] = [e for e in fila if chave_da_entrada(e) not in ficaram]
        gravar_json(arquivo("fila", nome), fila)
        log(nome, "a Z-API não limpou a fila (%d continuam lá); essas ela mesma solta" % len(resto))
        return 0
    if novas:
        log(nome, "guardei %d mensagem(ns) da fila da Z-API e limpei a fila de lá (guardadas: %d)" % (len(novas), len(fila)))
    return len(novas)


def reenviar(conf, nome, inst, est, fila):
    """Manda o que está guardado, devagar. Cabe em uma rodada de um minuto; o resto fica para a próxima."""
    if not fila or not (conf["reenvio_das"] <= agora().hour < conf["reenvio_ate"]):
        return
    r = est.setdefault("reenvio", {})
    fim = time.time() + 48
    while fila and time.time() < fim:
        e = fila[0]
        motivo = None
        if (time.time() - (e.get("criado") or e["guardado"])) / 3600.0 > conf["validade_h"]:
            motivo = "vencidas"
        else:
            if e["tipo"] == "?" and inst.get("banco"):
                completar_do_banco(e)
            if e["tipo"] == "?" or not e["fone"]:
                motivo = "sem_conteudo"
        if motivo is None:
            espera = conf["intervalo_s"] - (time.time() - est.get("ultimo_reenvio", 0))
            if espera > 0:
                if time.time() + espera > fim:
                    break
                time.sleep(espera)
            resposta = enviar(inst, e)
            est["ultimo_reenvio"] = time.time()
            if id_do_envio(resposta):
                trocar_id(inst, e, resposta)
                r["ok"] = r.get("ok", 0) + 1
            else:
                e["tentativas"] = e.get("tentativas", 0) + 1
                if e["tentativas"] < conf["tentativas"]:
                    gravar_json(arquivo("fila", nome), fila)
                    break   # tenta de novo na próxima rodada
                motivo = "falhas"
        if motivo:
            r[motivo] = r.get(motivo, 0) + 1
            r.setdefault("finais", []).append(e["fone"][-4:])
            guardar_fora(nome, e, motivo)
        fila.pop(0)
        gravar_json(arquivo("fila", nome), fila)
        gravar_json(arquivo("estado", nome), est)
    if not fila:
        log(nome, "fila reenviada: %s" % {k: v for k, v in r.items() if k != "finais"})
        avisar(conf, nome, texto_fim(inst, r), tambem_a_propria=True)
        est.pop("reenvio", None)


# ---------------------------------------------------------------- uma rodada
def rodar(nome, conf):
    inst = conf["instancias"][nome]
    est = ler_json(arquivo("estado", nome), {"estado": "ok", "ruins": 0})
    fila = ler_json(arquivo("fila", nome), [])
    c = conectado(inst)
    est["ultima_leitura"] = agora().isoformat()

    if c is None:
        est["sem_resposta"] = est.get("sem_resposta", 0) + 1
        if est["sem_resposta"] in (5, 60):
            log(nome, "a Z-API não responde há %d leituras" % est["sem_resposta"])
    elif c:
        est["sem_resposta"] = 0
        est["ruins"] = 0
        if est["estado"] == "fora":
            por = avisar(conf, nome, texto_voltou(conf, inst, est, fila), tambem_a_propria=True)
            log(nome, "VOLTOU (fora desde %s); aviso pelo número: %s; guardadas: %d" % (hora(est.get("caiu_em")), por, len(fila)))
            est.update(estado="ok", voltou_em=agora().isoformat(), aviso_pendente=False)
            est["reenvio"] = {}
        est["ultima_boa"] = agora().isoformat()
    else:
        est["sem_resposta"] = 0
        est["ruins"] = est.get("ruins", 0) + 1
        if est["estado"] == "ok" and est["ruins"] >= conf["leituras_para_cair"]:
            est.update(estado="fora", caiu_em=est.get("ultima_boa") or agora().isoformat(), aviso_pendente=True, ultimo_aviso=None)
            log(nome, "CAIU (última leitura boa: %s)" % hora(est["caiu_em"]))
        if est["estado"] == "fora":
            guardar_fila(nome, inst, fila)
            if est.get("aviso_pendente"):
                por = avisar(conf, nome, texto_caiu(inst, est))
                if por:
                    est.update(aviso_pendente=False, ultimo_aviso=time.time())
                log(nome, "aviso da queda pelo número: %s" % por)
            elif (time.time() - (est.get("ultimo_aviso") or 0) >= conf["lembrete_min"] * 60
                  and conf["reenvio_das"] <= agora().hour < conf["reenvio_ate"]):
                if avisar(conf, nome, texto_lembrete(inst, est, fila)):
                    est["ultimo_aviso"] = time.time()

    gravar_json(arquivo("estado", nome), est)
    if c and est["estado"] == "ok":
        reenviar(conf, nome, inst, est, fila)
        gravar_json(arquivo("estado", nome), est)
    return est


def carregar_config():
    conf = dict(PADRAO)
    conf.update(ler_json(os.path.join(RAIZ, "config.json"), {}))
    return conf


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    nome, conf = argv[1], carregar_config()
    if nome not in conf.get("instancias", {}):
        print("instância desconhecida: %s (tenho: %s)" % (nome, ", ".join(conf.get("instancias", {}))))
        return 2
    inst = conf["instancias"][nome]
    if "--situacao" in argv:
        est = ler_json(arquivo("estado", nome), {})
        print("%s | conectado agora: %s | vigia: %s | caiu: %s | voltou: %s | guardadas: %d" % (
            quem_e(inst), conectado(inst), est.get("estado"), hora(est.get("caiu_em")), hora(est.get("voltou_em")),
            len(ler_json(arquivo("fila", nome), []))))
        return 0
    if "--teste" in argv:
        por = avisar(conf, nome, "✅ Teste do vigia da Nay: se a %s cair, o aviso chega aqui por este número." % quem_e(inst))
        print("teste do aviso da %s: saiu pelo número %s" % (inst["rotulo"], por))
        return 0 if por else 1
    rodar(nome, conf)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
