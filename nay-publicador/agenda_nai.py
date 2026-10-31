"""
A AGENDA E A SAÍDA DA NAY VELHA, FORA DO n8n (Pedro, 31/10/2026: "tire tudo do n8n quero tudo em python"; 550).

É o porte da ponta do fluxo "NAI atendimento locação":
    Agenda (todo minuto) -> Agenda da NAI -> Liberar saída -> Conferir cabeçalho -> Enviar Z-API -> Confirmar envio
                                                                                 \\-> Registrar bloqueio
e da mesma liberação depois de cada turno ("Fechar turno -> Liberar saída"). Os SQL são os mesmos do fluxo; o banco
continua decidindo tudo (pausa, janela, modo teste, repetição, foto que não confere).

DUAS CHAVES (nai_config), cada uma vale na rodada seguinte, e com 'n8n' este laço não faz nada:
  agenda_de = python   a cada 60 s: nai_agenda_tick('python') e o que a Nay velha inicia (nai_liberar_saida(NULL))
  entrada   = python   a cada 3 s: as respostas dos turnos já fechados pela porta nova (nai_liberar_saida(turno))
Voltar atrás = a chave em 'n8n': a guarda está no banco (550), o n8n volta a fazer e este laço para.

Roda como uma linha (thread) do serviço nay-enviador-manual, com a sua própria ligação ao banco.
"""
import json
import time
from datetime import datetime

import psycopg2
import psycopg2.extras

from conferir import enviar_zapi, motivo_para_nao_enviar

QUEM = "python"
AGENDA_A_CADA_S = 60     # o "Agenda (todo minuto)" do n8n
INTERVALO_S = 3          # as respostas de turno saem na hora: olha a cada 3 s
ENTRE_ENVIOS_S = 2       # o batchInterval do nó "Enviar Z-API"

# turno fechado pela porta com resposta esperando. O que passou de 3 min a agenda pega pelo caminho sem turno.
TURNOS_PRONTOS = """
SELECT DISTINCT s.turno_id FROM nai_saida s JOIN nai_turno t ON t.id = s.turno_id
 WHERE s.estado = 'pendente' AND s.papel_destino <> 'entrega' AND s.enviar_apos <= now()
   AND t.fechado_em IS NOT NULL AND s.criado_em > now() - interval '3 minutes'
 ORDER BY 1 LIMIT 20
"""


def log(msg):
    print(datetime.now().strftime("%Y-%m-%d %H:%M:%S"), "agenda:", msg, flush=True)


def fim4(fone):
    d = "".join(c for c in str(fone or "") if c.isdigit())
    return "…" + d[-4:] if d else "?"


def chave_de(conn, nome):
    with conn.cursor() as cur:
        cur.execute("SELECT coalesce(nullif(btrim(nai_cfg(%s, 'n8n')), ''), 'n8n')", (nome,))
        r = cur.fetchone()
    conn.commit()
    return r[0] if r else "n8n"


def tick(conn):
    with conn.cursor() as cur:
        cur.execute("SET statement_timeout = '120s'")
        cur.execute("SELECT nai_agenda_tick(%s)", (QUEM,))
        n = cur.fetchone()[0]
    conn.commit()
    return n


def turnos_prontos(conn):
    with conn.cursor() as cur:
        cur.execute(TURNOS_PRONTOS)
        r = [x[0] for x in cur.fetchall()]
    conn.commit()
    return r


def liberar(conn, turno):
    """A de 2 argumentos (sem a guarda do n8n), só a saída da Nay (a entrega é do enviador manual)."""
    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute("SET statement_timeout = '60s'")
        cur.execute("SELECT * FROM nai_liberar_saida(%s::bigint, false)", (turno,))
        linhas = cur.fetchall()
    conn.commit()      # as liberadas ficam 'enviando' (ou 'bloqueado'/'simulado') de vez
    return linhas


def gravar(conn, sql, args):
    with conn.cursor() as cur:
        cur.execute(sql, args)
        r = cur.fetchone()
    conn.commit()
    return r[0] if r else None


def mandar(conn, linhas):
    """Conferir cabeçalho -> Enviar Z-API -> Confirmar envio / Registrar bloqueio, uma por vez."""
    enviadas = 0
    for j in linhas:
        motivo = motivo_para_nao_enviar(j)
        if motivo:
            gravar(conn, "SELECT nai_registrar_bloqueio(%s, %s)", (j["id"], motivo))
            log("bloqueado %s -> %s (%s)" % (j["id"], fim4(j.get("telefone")), motivo))
            continue
        if enviadas:
            time.sleep(ENTRE_ENVIOS_S)
        resp = enviar_zapi(j["rota"], j["corpo"])
        r = gravar(conn, "SELECT nai_confirmar_envio(%s, %s::jsonb)", (j["id"], json.dumps(resp)))
        enviadas += 1
        log("%s %s -> %s (%s) cod %s: %s" % (j["rota"], j["id"], fim4(j.get("telefone")), j.get("papel") or "-",
                                             j.get("codigo") or "-", r))
    return len(linhas)


def uma_rodada(conn, ultimo_tick):
    """Devolve (quantas mensagens passaram, quando foi o último tick)."""
    feitas = 0
    if chave_de(conn, "entrada") == QUEM:
        for turno in turnos_prontos(conn):
            feitas += mandar(conn, liberar(conn, turno))
    if chave_de(conn, "agenda_de") == QUEM and time.monotonic() - ultimo_tick >= AGENDA_A_CADA_S:
        ultimo_tick = time.monotonic()
        n = tick(conn)
        if n:
            log("tick: %s" % n)
        feitas += mandar(conn, liberar(conn, None))
    return feitas, ultimo_tick


def rodar(conectar, parado):
    """O laço. `conectar()` abre a ligação ao banco; `parado()` diz quando o serviço está saindo."""
    log("no ar (agenda a cada %ss, respostas a cada %ss; só age com a chave em '%s')" % (AGENDA_A_CADA_S, INTERVALO_S, QUEM))
    conn, ultimo_tick, espera_erro = None, -AGENDA_A_CADA_S, 5
    while not parado():
        try:
            if conn is None or conn.closed:
                conn = conectar()
            feitas, ultimo_tick = uma_rodada(conn, ultimo_tick)
            espera_erro = 5
            if not feitas:
                time.sleep(INTERVALO_S)
        except Exception as e:  # noqa: BLE001 -- uma rodada ruim não derruba o serviço nem o enviador manual
            log("erro: %s: %s" % (e.__class__.__name__, str(e).strip()[:300]))
            try:
                if conn is not None:
                    conn.close()
            except psycopg2.Error:
                pass
            conn = None
            time.sleep(espera_erro)
            espera_erro = min(espera_erro * 2, 60)
    log("parada")
