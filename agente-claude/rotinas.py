#!/usr/bin/env python3
"""As rotinas dos outros agentes do painel (Pedro, 21/10/2026):

  "Quero que toda visita nova no crm seja enviada para a ia visitas no agentes.imobeasy"
      VISITAS: a cada 5 min, as visitas que entraram na agenda do CRM desde a última olhada (o evento
      'agendada_no_crm' que crm_visita_agendar grava: agendada à mão, pedido da Nay posto na agenda, ou registro
      de visita que já passou) vão, com os dados de cada uma, para o projeto "visitas".
  "Quero que envie todos os dias as métricas do dia para a ia Métricas ... fim da noite 23 hrs"
      MÉTRICAS: às 23:00 de Brasília, os números do dia (o dia de Manaus) do Painel do negócio do site
      (site_painel_metricas + site_painel_visitas) vão para projetos/metricas/dados/metricas/AAAA-MM-DD.json e a
      mensagem para o projeto "metricas".
  "Quero que pela manhã seja enviado as métricas para o Estratégia ... às 7 hrs"
      ESTRATÉGIA: às 07:00 de Brasília, os números de ONTEM e dos últimos 7 dias, do mesmo jeito, para o projeto
      "estrategia".

A mensagem entra na conversa do projeto em que a equipe escreveu por último (fila_nay.conversa_da_equipe), marcada
"rotina". Agente ocupado = tenta de novo na próxima olhada: a visita fica pendente; o horário vale até o fim da hora
(23:59 / 07:59) e depois, naquele dia, não sai mais. O painel chama `laco()` numa thread.
Estado em metricas.db: rotina_visita (as visitas e quando foram) e rotinas_estado (marcadores).
Desligar uma rotina sem mexer no código: /opt/agente-claude/rotinas.json, ex. {"visitas": false}.

  rotinas.py        o estado (só leitura)
"""
import json, os, threading, time
from datetime import datetime, timedelta, timezone

import agente, fila_nay, importar_nay, projetos

BRASILIA = timezone(timedelta(hours=-3))
MANAUS = timezone(timedelta(hours=-4))
CONFIG = os.path.join(agente.BASE, "rotinas.json")
VISITAS_A_CADA_S = 300
TRAVA = threading.Lock()
# rotina de horário: projeto, janela (Brasília), quantos dias para trás termina o período, quantos dias ele tem
HORARIOS = {
    "metricas": {"projeto": "metricas", "de": "23:00", "ate": "23:59", "fim_dias_atras": 0, "dias": 1},
    "estrategia": {"projeto": "estrategia", "de": "07:00", "ate": "07:59", "fim_dias_atras": 1, "dias": 7},
}

SQL_ULTIMO_EVENTO = "SELECT json_build_object('id', coalesce(max(id), 0))::text FROM nai_visita_evento WHERE tipo = 'agendada_no_crm';"
SQL_VISITAS = """
SELECT json_build_object(
         'evento', e.id, 'visita', v.id, 'codigo', v.codigo, 'imovel', nai_ref_imovel(v.codigo),
         'quando', to_char(v.quando AT TIME ZONE 'America/Manaus', 'DD/MM/YYYY HH24:MI'),
         'dia_semana', extract(isodow FROM v.quando AT TIME ZONE 'America/Manaus')::int,
         'duracao', v.duracao_min, 'estado', v.estado, 'resultado', v.resultado,
         'corretor', coalesce(c.nome_completo, c.nome_whatsapp), 'corretor_tel', c.telefone,
         'proprietario', v.proprietario_nome, 'visitante', v.visitante_nome, 'quem', v.criada_no_crm_por,
         'detalhe', e.detalhe, 'em', to_char(e.quando AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI'),
         'ja_passou', v.quando < now())::text
  FROM nai_visita_evento e JOIN nai_visita v ON v.id = e.visita_id LEFT JOIN nai_contato c ON c.id = v.corretor_id
 WHERE e.tipo = 'agendada_no_crm' AND e.id > {cursor}
 ORDER BY e.id;
"""
SQL_METRICAS = """
SELECT json_build_object('de', '{de}', 'ate', '{ate}',
         'painel', site_painel_metricas('{de}'::date, '{ate}'::date, 'dia'),
         'visitas', site_painel_visitas('{de}'::date, '{ate}'::date))::text;
"""
DIAS = ["segunda", "terça", "quarta", "quinta", "sexta", "sábado", "domingo"]


def ligada(nome):
    try:
        with open(CONFIG, encoding="utf-8") as f:
            return json.load(f).get(nome, True) is not False
    except (FileNotFoundError, ValueError):
        return True


def banco():
    con = projetos.banco()
    con.execute("""CREATE TABLE IF NOT EXISTS rotina_visita (
        evento INTEGER PRIMARY KEY, visita INTEGER NOT NULL, dados TEXT NOT NULL, entrou_em TEXT NOT NULL, enviado_em TEXT)""")
    con.execute("CREATE TABLE IF NOT EXISTS rotinas_estado (chave TEXT PRIMARY KEY, valor TEXT)")
    return con


def _estado(con, k):
    r = con.execute("SELECT valor FROM rotinas_estado WHERE chave = ?", (k,)).fetchone()
    return r["valor"] if r else None


def _gravar(con, k, v):
    con.execute("INSERT INTO rotinas_estado (chave, valor) VALUES (?, ?) ON CONFLICT(chave) DO UPDATE SET valor = excluded.valor",
                (k, v))


def _mandar(pid, texto):
    """True quando saiu; False quando o agente ainda responde a mensagem anterior."""
    try:
        projetos.enviar(fila_nay.conversa_da_equipe(pid), texto, origem="rotina")
        return True
    except ValueError:
        return False


# ---------------------------------------------------------------- visitas
def _linha_visita(v):
    dia = DIAS[v["dia_semana"] - 1] if v.get("dia_semana") else ""
    partes = [f"#{v['visita']} · {v.get('imovel') or 'imóvel ' + str(v['codigo'])}",
              f"{dia} {v.get('quando') or 'sem data'} (Manaus)" + (f", {v['duracao']} min" if v.get("duracao") else ""),
              f"corretor {v.get('corretor') or '?'} (…{importar_nay.tel4(v.get('corretor_tel'))})"]
    if v.get("proprietario"):
        partes.append(f"proprietário {v['proprietario']}")
    if v.get("visitante"):
        partes.append(f"visitante {v['visitante']}")
    partes.append(f"estado {v.get('estado')}" + (f", resultado {v['resultado']}" if v.get("resultado") else ""))
    partes.append(f"{importar_nay.mascarar(v.get('detalhe') or '')} ({v.get('em')})")
    if v.get("ja_passou"):
        partes.append("registro de visita que já passou")
    return "- " + " · ".join(p for p in partes if p.strip())


def visitas():
    """Enfileira as visitas novas da agenda do CRM e manda as pendentes ao projeto. Devolve um resumo."""
    con = banco()
    cursor = _estado(con, "visita_evento")
    if cursor is None:
        # primeira vez: começa do último evento (as visitas de antes o agente lê no banco quando quiser)
        _gravar(con, "visita_evento", str(fila_nay._naydb(SQL_ULTIMO_EVENTO)[0]["id"]))
        con.commit()
        con.close()
        return "visitas: marcador posto, começa a partir de agora"
    novas = fila_nay._naydb(SQL_VISITAS.format(cursor=int(cursor)))
    t = projetos.agora()
    for v in novas:
        con.execute("INSERT OR IGNORE INTO rotina_visita (evento, visita, dados, entrou_em) VALUES (?, ?, ?, ?)",
                    (v["evento"], v["visita"], json.dumps(v, ensure_ascii=False), t))
    if novas:
        _gravar(con, "visita_evento", str(max(v["evento"] for v in novas)))
    con.commit()
    pend = con.execute("SELECT evento, dados FROM rotina_visita WHERE enviado_em IS NULL ORDER BY evento").fetchall()
    con.close()
    if not pend:
        return "visitas: nenhuma nova"
    vs = [json.loads(p["dados"]) for p in pend]
    texto = ((f"Visita nova no CRM:\n" if len(vs) == 1 else f"{len(vs)} visitas novas no CRM:\n")
             + "\n".join(_linha_visita(v) for v in vs) + "\n\nAnalise conforme o seu contexto.")
    if not _mandar("visitas", texto):
        return f"visitas: agente ocupado, {len(vs)} na espera"
    con = banco()
    con.executemany("UPDATE rotina_visita SET enviado_em = ? WHERE evento = ?", [(projetos.agora(), p["evento"]) for p in pend])
    con.commit()
    con.close()
    return f"visitas: {len(vs)} enviada(s)"


# ---------------------------------------------------------------- métricas (horário)
def horario(nome):
    """A rotina de horário, uma vez por dia. True quando saiu (ou já tinha saído hoje)."""
    cfg = HORARIOS[nome]
    hoje_b = datetime.now(BRASILIA).strftime("%Y-%m-%d")
    con = banco()
    if _estado(con, "horario:" + nome) == hoje_b:
        con.close()
        return True
    con.close()
    fim = datetime.now(MANAUS).date() - timedelta(days=cfg["fim_dias_atras"])
    ini = fim - timedelta(days=cfg["dias"] - 1)
    dados = fila_nay._naydb(SQL_METRICAS.format(de=ini.isoformat(), ate=fim.isoformat()))[0]
    rel = os.path.join("dados", "metricas", f"{fim.isoformat()}.json" if cfg["dias"] == 1
                       else f"{ini.isoformat()}_a_{fim.isoformat()}.json")
    caminho = os.path.join(projetos.pasta(cfg["projeto"]), rel)
    os.makedirs(os.path.dirname(caminho), exist_ok=True)
    with open(caminho, "w", encoding="utf-8", newline="\n") as f:
        json.dump(dados, f, ensure_ascii=False, indent=1)
    t = (dados.get("painel") or {}).get("totais") or {}
    resumo = ", ".join(f"{k}: {v}" for k, v in list(t.items())[:12] if isinstance(v, (int, float)))
    if nome == "metricas":
        texto = (f"Métricas de hoje, {fim:%d/%m} ({DIAS[fim.weekday()]}), no dia de Manaus.\n"
                 f"Os números do Painel do negócio do site estão em {rel}: totais, série, funil da OLX, fechamentos, "
                 "coortes dos disparos e as visitas do dia. As pessoas por número de WhatsApp estão no crmdb.\n"
                 + (f"Totais: {resumo}.\n" if resumo else "")
                 + "\nFaça as métricas do dia conforme o seu contexto.")
    else:
        texto = (f"Bom dia. As métricas de ontem, {fim:%d/%m} ({DIAS[fim.weekday()]}), e dos últimos 7 dias "
                 f"({ini:%d/%m} a {fim:%d/%m}), no dia de Manaus.\n"
                 f"Os números do Painel do negócio do site estão em {rel} (a série traz um ponto por dia: o último é "
                 "ontem). As pessoas por número de WhatsApp estão no crmdb.\n"
                 + (f"Totais dos 7 dias: {resumo}.\n" if resumo else "")
                 + "\nUse para a estratégia do dia conforme o seu contexto.")
    if not _mandar(cfg["projeto"], texto):
        return False
    con = banco()
    _gravar(con, "horario:" + nome, hoje_b)
    con.commit()
    con.close()
    return True


# ---------------------------------------------------------------- o laço
def laco():
    """A thread do painel: as visitas a cada 5 min; as rotinas de horário dentro da janela de cada uma."""
    ultima_visita = 0.0
    while True:
        try:
            with TRAVA:
                if ligada("visitas") and time.monotonic() - ultima_visita >= VISITAS_A_CADA_S:
                    ultima_visita = time.monotonic()
                    r = visitas()
                    if "nenhuma" not in r:
                        print("rotinas:", r, flush=True)
                agora = datetime.now(BRASILIA).strftime("%H:%M")
                for nome, cfg in HORARIOS.items():
                    if ligada(nome) and cfg["de"] <= agora <= cfg["ate"] and not horario(nome):
                        pass   # agente ocupado: tenta de novo na próxima olhada, até o fim da janela
        except Exception as e:  # noqa: BLE001 - uma rotina com erro não derruba o painel; tenta na próxima volta
            print("rotinas:", type(e).__name__, e, flush=True)
        time.sleep(20)


def estado():
    con = banco()
    r = {"ligadas": {n: ligada(n) for n in ["visitas", *HORARIOS]},
         "marcadores": {x["chave"]: x["valor"] for x in con.execute("SELECT chave, valor FROM rotinas_estado")},
         "visitas_na_espera": con.execute("SELECT count(*) n FROM rotina_visita WHERE enviado_em IS NULL").fetchone()["n"],
         "ultimas_visitas": con.execute("SELECT evento, visita, entrou_em, enviado_em FROM rotina_visita "
                                        "ORDER BY evento DESC LIMIT 5").fetchall()}
    con.close()
    return r


if __name__ == "__main__":
    print(json.dumps(estado(), ensure_ascii=False, indent=2))
