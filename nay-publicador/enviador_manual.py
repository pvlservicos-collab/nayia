"""
O ENVIADOR MANUAL DE IMÓVEIS (Pedro, 06/10/2026).

"transforma em Python e implementa como função na VPS, 100% online e funcionando independente, separado da nova
Nay". Entrega o que alguém PEDIU para mandar -- a aba Enviar imóvel do site e do CRM, o "Me envia" do /imoveis e o
comando ENVIA -- sem passar pelo n8n e sem depender da Nay (nem da antiga, nem da nova).

COMO FUNCIONA (migração 301)
  Quem pede grava o card e as fotos em nai_saida com papel_destino = 'entrega' (nai_enviar_imoveis_para). A cada
  poucos segundos este serviço chama nai_liberar_saida(NULL, true): o banco aplica as travas de sempre (contato
  mudou, Tel com a conversa, parceria, janela de horário...), marca cada mensagem liberada como 'enviando' e a
  devolve com a rota e o corpo da Z-API. Aqui cada uma é conferida de novo, de forma independente (o mesmo
  "check duplo" do nó "Conferir cabeçalho" do n8n), mandada pela Z-API e gravada com nai_confirmar_envio (ou
  nai_registrar_bloqueio) -- as mesmas funções que o n8n usava, então o resto do sistema não percebe diferença.
  A pausa da Nay (PARAR ATENDIMENTO) não vale aqui (migração 300).

ONDE RODA
  srv1894338, serviço systemd `nay-enviador-manual` (reinicia sozinho; sobe junto com a máquina):
      systemctl status nay-enviador-manual
      journalctl -u nay-enviador-manual -n 50
  Credenciais: /root/nay-publicador/.env (DATABASE_URL e ZAPI_*; a mesma instância da Nay). Nada de segredo
  aparece no log; telefone só com os 4 últimos dígitos.

ENSAIO (não manda nada)
      .venv/bin/python enviador_manual.py --ensaio
  pede um envio para um número que não existe, libera, confere e mostra o que mandaria -- tudo numa transação
  que termina em ROLLBACK -- e testa a conexão com a Z-API (só leitura do status da instância).
"""
import json
import os
import re
import signal
import sys
import threading
import time
from datetime import datetime

import psycopg2
import psycopg2.extras
import requests

import agenda_nai

INTERVALO_S = 3          # sem nada na fila, olha de novo a cada 3 s
ENTRE_ENVIOS_S = 2       # o mesmo espaço do n8n (batchInterval 2000 ms) entre uma mensagem e a próxima
SINAL_DE_VIDA = "/root/nay-publicador/logs/enviador_manual.vivo"

parar = False


def log(msg):
    print(datetime.now().strftime("%Y-%m-%d %H:%M:%S"), msg, flush=True)


def fim4(fone):
    d = re.sub(r"\D", "", str(fone or ""))
    return "…" + d[-4:] if d else "?"


# o check duplo (porte do "Conferir cabeçalho") e a Z-API moram em conferir.py (550): a agenda da Nay velha
# (agenda_nai.py) usa os mesmos
from conferir import TIMEOUT_ZAPI_S, chave, enviar_zapi, motivo_para_nao_enviar, zapi_base, zapi_cabecalho  # noqa: E402,F401


# ---------------------------------------------------------------- o laço
def conectar(nome="nay-enviador-manual"):
    conn = psycopg2.connect(os.environ["DATABASE_URL"], connect_timeout=10,
                            application_name=nome)
    conn.autocommit = False
    return conn


def liberar(conn):
    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute("SET statement_timeout = '60s'")
        cur.execute("SELECT * FROM nai_liberar_saida(NULL::bigint, true)")
        linhas = cur.fetchall()
    conn.commit()      # as liberadas ficam 'enviando' (ou 'bloqueado'/'simulado') de vez
    return linhas


def gravar(conn, sql, args):
    with conn.cursor() as cur:
        cur.execute(sql, args)
        r = cur.fetchone()
    conn.commit()
    return r[0] if r else None


def citacao_do_grupo(conn, j):
    """A mensagem do grupo que a negociação da captação ativa responde em particular (373), ou None."""
    if j.get("rota") != "send-text":
        return None
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT site_captacao_grupos_citacao(%s)", (j["id"],))
            r = cur.fetchone()
        conn.commit()
    except psycopg2.Error as e:
        conn.rollback()
        log("citação de %s não lida: %s" % (j["id"], str(e).strip()[:160]))
        return None
    c = r[0] if r else None
    return c if c and c.get("grupo") and c.get("message_id") else None


def uma_rodada(conn):
    linhas = liberar(conn)
    for n, j in enumerate(linhas):
        motivo = motivo_para_nao_enviar(j)
        if motivo:
            gravar(conn, "SELECT nai_registrar_bloqueio(%s, %s)", (j["id"], motivo))
            log("bloqueado %s -> %s (%s)" % (j["id"], fim4(j.get("telefone")), motivo))
            continue
        if n:
            time.sleep(ENTRE_ENVIOS_S)
        resp = None
        citacao = citacao_do_grupo(conn, j)
        if citacao:
            # 373 (Pedro, 15/10/2026: "como se eu tivesse marcado a mensagem do cara no grupo e chamado no pv"): a
            # mensagem de negociação vai como "Responder em particular" à mensagem dele no grupo
            resp = enviar_zapi(j["rota"], {**j["corpo"], "phone": citacao["grupo"], "messageId": citacao["message_id"],
                                           "privateAnswer": True})
            if resp.get("error"):
                log("resposta em particular %s recusada (%s): vai normal no PV" % (j["id"], str(resp["error"])[:120]))
                resp = None
            else:
                log("resposta em particular %s -> %s, citando a mensagem do grupo" % (j["id"], fim4(j.get("telefone"))))
        if resp is None:
            resp = enviar_zapi(j["rota"], j["corpo"])
        r = gravar(conn, "SELECT nai_confirmar_envio(%s, %s::jsonb)", (j["id"], json.dumps(resp)))
        log("%s %s -> %s cod %s: %s" % (j["rota"], j["id"], fim4(j.get("telefone")), j.get("codigo") or "-", r))
    return len(linhas)


def sinal_de_vida():
    try:
        with open(SINAL_DE_VIDA, "w") as f:
            f.write(datetime.now().isoformat())
    except OSError:
        pass


def rodar():
    def _parar(*_):
        global parar
        parar = True
    signal.signal(signal.SIGTERM, _parar)
    signal.signal(signal.SIGINT, _parar)
    for k in ("DATABASE_URL", "ZAPI_INSTANCIA", "ZAPI_TOKEN", "ZAPI_CLIENT_TOKEN"):
        if not os.environ.get(k):
            log("falta a variável %s no ambiente; saindo" % k)
            sys.exit(2)
    log("enviador manual no ar (a cada %ss)" % INTERVALO_S)
    # 550: a agenda e a saída da Nay velha, fora do n8n, numa linha própria (só age com nai_config em 'python')
    threading.Thread(target=agenda_nai.rodar, name="agenda", daemon=True,
                     args=(lambda: conectar("nay-agenda-nai"), lambda: parar)).start()
    conn = None
    espera_erro = 5
    while not parar:
        try:
            if conn is None or conn.closed:
                conn = conectar()
            feitas = uma_rodada(conn)
            sinal_de_vida()
            espera_erro = 5
            if not feitas:
                time.sleep(INTERVALO_S)
        except psycopg2.Error as e:
            log("banco: %s" % str(e).strip()[:300])
            try:
                if conn is not None:
                    conn.close()
            except psycopg2.Error:
                pass
            conn = None
            time.sleep(espera_erro)
            espera_erro = min(espera_erro * 2, 60)
        except Exception as e:  # noqa: BLE001 -- o serviço não pode morrer por uma mensagem
            log("erro: %s: %s" % (e.__class__.__name__, str(e)[:300]))
            try:
                if conn is not None:
                    conn.rollback()
            except psycopg2.Error:
                conn = None
            time.sleep(espera_erro)
            espera_erro = min(espera_erro * 2, 60)
    log("enviador manual parado")


# ---------------------------------------------------------------- ensaio
def ensaio():
    """Tudo numa transação que termina em ROLLBACK: nada é enviado nem gravado."""
    conn = conectar()
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute("SELECT site_me_envia('92900000001', ARRAY[9020], 'ensaio-enviador-manual') ->> 'mensagem' AS m")
            print("pedido:", cur.fetchone()["m"])
            cur.execute("""UPDATE nai_saida s SET enviar_apos = now() - interval '1 second' FROM nai_contato k
                            WHERE k.id = s.contato_id AND s.estado = 'pendente'
                              AND right(regexp_replace(k.telefone, '\\D', '', 'g'), 8) = '00000001'""")
            cur.execute("SELECT * FROM nai_liberar_saida(NULL::bigint, true)")
            linhas = [l for l in cur.fetchall() if str(l.get("telefone") or "").endswith("00000001")]
        print("liberadas para o número de ensaio:", len(linhas))
        for j in linhas:
            m = motivo_para_nao_enviar(j)
            print("  %-10s cod %-5s %s" % (j["rota"], j.get("codigo") or "-", "MANDARIA" if not m else "barraria: " + m))
    finally:
        conn.rollback()
        conn.close()
    try:
        r = requests.get(zapi_base() + "/status", headers=zapi_cabecalho(), timeout=20)
        st = r.json() if r.headers.get("content-type", "").startswith("application/json") else {}
        print("Z-API: HTTP %s, conectada=%s" % (r.status_code, st.get("connected")))
    except requests.RequestException as e:
        print("Z-API: falhou (%s)" % e.__class__.__name__)


if __name__ == "__main__":
    if "--ensaio" in sys.argv:
        ensaio()
    else:
        rodar()
