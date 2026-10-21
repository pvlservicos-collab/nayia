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
  "que seja enviado para ele uma pergunta a cada 2 hrs 3 de manha e 3 a tarde pedindo para ele ver se todas as
  visitas estão do sistema" (21/10, depois de o Visitas dizer que as visitas do dia "não existiam": elas estavam
  nas conversas que a equipe faz à mão pelo número da Nay, tabela mensagens, que ele nunca abriu)
      CONFERÊNCIA: às 07, 09, 11, 13, 15 e 17 h de MANAUS (08 a 18 h de Brasília), as conversas de visita de ontem
      e de hoje (mensagens) e as visitas da agenda (nai_visita) vão para
      projetos/visitas/dados/conferencia/AAAA-MM-DD/HHMM.txt e a pergunta para o projeto "visitas".

A mensagem entra na conversa do projeto em que a equipe escreveu por último (fila_nay.conversa_da_equipe), marcada
"rotina". Agente ocupado = tenta de novo na próxima olhada: a visita fica pendente; o horário vale até o fim da hora
(23:59 / 07:59) e depois, naquele dia, não sai mais. O painel chama `laco()` numa thread.
Estado em metricas.db: rotina_visita (as visitas e quando foram) e rotinas_estado (marcadores).
Desligar uma rotina sem mexer no código: /opt/agente-claude/rotinas.json, ex. {"visitas": false} ou {"conferencia": false}.

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
# a conferência das visitas: horas de MANAUS (onde as visitas acontecem); cada uma vale até o minuto 59 daquela hora
CONFERENCIA_HORAS = ["07", "09", "11", "13", "15", "17"]
CONFERENCIA_TEXTO_MAX = 400   # o card da Nay é longo e repete a ficha: o começo basta para saber de que imóvel é

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
# Conferência. As conversas de visita: quem, desde ontem 00:00 de Manaus, falou de visita (pedido, horário, cancelar,
# remarcar, portaria, chave). A fala da Nay que é card ("Código:", "#1234", "R$") não puxa a conversa sozinha.
# A conversa vai inteira desde ontem, menos as imagens sem legenda que a Nay manda (fotos dos imóveis).
SQL_CONF_CONVERSAS = r"""
WITH desde AS (SELECT (date_trunc('day', now() AT TIME ZONE 'America/Manaus') - interval '1 day')
                      AT TIME ZONE 'America/Manaus' AS t),
rel AS (
  SELECT DISTINCT m.telefone FROM mensagens m, desde
   WHERE m.criada_em > desde.t
     AND m.texto ~* '(visit|agend|remarc|cancel|desmarc|portaria|\mchave|\m\d{1,2} ?(h|hs|hrs|horas)\M|\m\d{1,2}:\d\d)'
     AND (m.direcao = 'recebida' OR m.texto !~* '(c[óo]digo:|#\d{3,5}|R\$)'))
SELECT json_build_object('id', m.id, 'tel', m.telefone, 'nome', m.nome, 'direcao', m.direcao, 'origem', m.origem,
         'texto', m.texto, 'em', to_char(m.criada_em AT TIME ZONE 'America/Manaus', 'YYYY-MM-DD HH24:MI'),
         'contato', (SELECT coalesce(c.nome_completo, c.nome_whatsapp) FROM nai_contato c
                      WHERE c.telefone = m.telefone LIMIT 1))::text
  FROM mensagens m JOIN rel USING (telefone), desde
 WHERE m.criada_em > desde.t
   AND NOT (m.direcao = 'enviada' AND m.origem = 'imagem' AND coalesce(m.texto, '') = '')
 ORDER BY m.telefone, m.id;
"""
# as visitas do sistema (a agenda): de ontem até daqui a 7 dias, inclusive as excluídas e as encerradas
SQL_CONF_VISITAS = """
SELECT json_build_object('visita', v.id, 'codigo', v.codigo, 'imovel', nai_ref_imovel(v.codigo),
         'quando', to_char(v.quando AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI'), 'estado', v.estado,
         'resultado', v.resultado, 'motivo', v.motivo, 'corretor', coalesce(c.nome_completo, c.nome_whatsapp),
         'corretor_tel', c.telefone, 'proprietario', v.proprietario_nome, 'quem', v.criada_no_crm_por,
         'excluida', to_char(v.excluida_em AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI'))::text
  FROM nai_visita v LEFT JOIN nai_contato c ON c.id = v.corretor_id
 WHERE v.quando >= date_trunc('day', now() AT TIME ZONE 'America/Manaus') AT TIME ZONE 'America/Manaus' - interval '1 day'
   AND v.quando <  date_trunc('day', now() AT TIME ZONE 'America/Manaus') AT TIME ZONE 'America/Manaus' + interval '8 days'
 ORDER BY v.quando;
"""
CONFERENCIA_PERGUNTA = """Conferência das visitas das {hora_m} (Manaus), {hora_b} em Brasília. Veja se todas as visitas estão no sistema.

No arquivo {rel} estão, primeiro, as visitas do sistema (a agenda, tabela nai_visita, de ontem até daqui a 7 dias) e, depois, as {n} conversas de WhatsApp de ontem e de hoje em que se falou de visita ({pessoas}). As conversas são da tabela mensagens do naydb: o que a equipe escreve à mão pelo número da Nay também está lá, como "Imob Easy". Se precisar de mais, leia a conversa inteira no banco (como-ler-os-dados).

Toda visita tem de estar no mesmo lugar, a agenda do CRM, para não perdermos dado. Compare as conversas com a agenda e ATUALIZE a agenda pelas funções do CRM, do jeito que está em "Como registrar" (como-ler-os-dados):
1. Visita combinada na conversa (a equipe confirmou o dia e a hora) que NÃO está no sistema: agende (crm_visita_agendar).
2. Visita do sistema que a conversa diz que foi cancelada: exclua (crm_visita_excluir). Remarcada para outro dia ou hora já combinado: mude o horário (crm_visita_mudar_horario).
3. Pendência (ficou de confirmar e não confirmou, pediu visita e ninguém respondeu, remarcação sem hora fechada): não registre, só liste.
Não mande mensagem a ninguém. Responda com o que você fez (o número da visita, corretor com 4 últimos dígitos, imóvel, dia e hora, e a frase da conversa que prova), o que ficou pendente, e o que não fez por dúvida. Se já estava tudo no sistema, diga só isso, em uma linha."""
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


# ---------------------------------------------------------------- conferência das visitas (6 vezes por dia)
def _linha_agenda(v):
    partes = [f"#{v['visita']} · {v.get('imovel') or 'imóvel ' + str(v['codigo'])}", f"{v.get('quando')} (Manaus)",
              f"corretor {v.get('corretor') or '?'} (…{importar_nay.tel4(v.get('corretor_tel'))})",
              f"estado {v.get('estado')}" + (f", resultado {v['resultado']}" if v.get("resultado") else "")]
    if v.get("proprietario"):
        partes.append(f"proprietário {v['proprietario']}")
    partes.append(f"agendada no CRM por {v['quem']}" if v.get("quem") else "pedido da Nay (não aparece na Agenda do CRM)")
    if v.get("motivo"):
        partes.append(f"motivo: {v['motivo']}")
    if v.get("excluida"):
        partes.append(f"EXCLUÍDA em {v['excluida']}")
    return "- " + " · ".join(partes)


def _nome(ms):
    """O nome do cadastro (nai_contato) quando é um nome de verdade; senão, o do WhatsApp."""
    cad = (ms[0].get("contato") or "").strip()
    zap = next((m["nome"] for m in ms if m["direcao"] == "recebida" and m.get("nome")), None)
    return (cad if sum(ch.isalpha() for ch in cad) >= 4 else None) or zap or cad or "sem nome"


def _bloco_conversa(ms):
    nome = _nome(ms)
    tel = ms[0]["tel"]
    linhas = [f"=== {nome} …{importar_nay.tel4(tel)}{' (@lid)' if '@lid' in tel else ''} · {len(ms)} falas · "
              f"{ms[0]['em'][8:10]}/{ms[0]['em'][5:7]} {ms[0]['em'][11:]} a "
              f"{ms[-1]['em'][8:10]}/{ms[-1]['em'][5:7]} {ms[-1]['em'][11:]} ==="]
    dia = None
    for m in ms:
        if m["em"][:10] != dia:
            dia = m["em"][:10]
            linhas.append(f"-- {dia[8:10]}/{dia[5:7]} --")
        texto = importar_nay.mascarar((m.get("texto") or "").strip())
        if len(texto) > CONFERENCIA_TEXTO_MAX:
            texto = texto[:CONFERENCIA_TEXTO_MAX] + "…"
        if not texto:
            texto = f"[{m.get('origem') or 'mídia'}]"
        quem = "Imob Easy" if m["direcao"] == "enviada" else "Ele(a)"
        linhas.append(importar_nay.recuo(f"{m['em'][11:]} {quem}: {texto}"))
    return "\n".join(linhas)


def conferencia(hora_m):
    """A conferência daquela hora de Manaus, uma vez. True quando saiu (ou já tinha saído)."""
    agora_m = datetime.now(MANAUS)
    marca = f"{agora_m:%Y-%m-%d} {hora_m}"
    con = banco()
    if _estado(con, "conferencia") == marca:
        con.close()
        return True
    pronta = _estado(con, "conferencia_texto") or ""
    con.close()
    if pronta.startswith(marca + "\n"):   # o arquivo já foi feito nesta hora; o agente estava ocupado
        return _conferencia_mandar(marca, pronta[len(marca) + 1:])
    agenda = fila_nay._naydb(SQL_CONF_VISITAS)
    msgs = fila_nay._naydb(SQL_CONF_CONVERSAS)
    conversas = {}
    for m in msgs:
        conversas.setdefault(m["tel"], []).append(m)
    blocos = sorted((_bloco_conversa(ms) for ms in conversas.values()), key=lambda b: b.split(" ·")[0].lower())
    rel = os.path.join("dados", "conferencia", f"{agora_m:%Y-%m-%d}", f"{agora_m:%H%M}.txt")
    caminho = os.path.join(projetos.pasta("visitas"), rel)
    os.makedirs(os.path.dirname(caminho), exist_ok=True)
    with open(caminho, "w", encoding="utf-8", newline="\n") as f:
        f.write(f"CONFERÊNCIA DAS VISITAS · {agora_m:%d/%m/%Y %H:%M} em Manaus\n"
                "Telefones só com os 4 últimos dígitos. \"Imob Easy\" = o número da Nay Parceria (a Nay ou alguém da "
                "equipe escrevendo à mão); \"Ele(a)\" = o corretor, o proprietário ou quem for o contato.\n\n"
                f"## VISITAS NO SISTEMA (nai_visita, de ontem até daqui a 7 dias): {len(agenda)}\n"
                + ("\n".join(_linha_agenda(v) for v in agenda) or "- nenhuma") + "\n\n"
                f"## CONVERSAS EM QUE SE FALOU DE VISITA (mensagens, desde ontem 00:00): {len(blocos)}\n\n"
                + "\n\n".join(blocos) + "\n")
    nomes = [_nome(ms) for ms in conversas.values()]
    agora_b = datetime.now(BRASILIA)
    texto = CONFERENCIA_PERGUNTA.format(hora_m=f"{agora_m:%H:%M}", hora_b=f"{agora_b:%H:%M}", rel=rel, n=len(blocos),
                                        pessoas=", ".join(sorted(set(nomes), key=str.lower)[:40]) or "nenhuma")
    con = banco()
    _gravar(con, "conferencia_texto", marca + "\n" + texto)
    con.commit()
    con.close()
    return _conferencia_mandar(marca, texto)


def _conferencia_mandar(marca, texto):
    if not _mandar("visitas", texto):
        return False
    con = banco()
    _gravar(con, "conferencia", marca)
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
                hora_m = datetime.now(MANAUS).strftime("%H")
                if ligada("conferencia") and hora_m in CONFERENCIA_HORAS and not conferencia(hora_m):
                    pass   # agente ocupado: tenta de novo até o fim daquela hora
        except Exception as e:  # noqa: BLE001 - uma rotina com erro não derruba o painel; tenta na próxima volta
            print("rotinas:", type(e).__name__, e, flush=True)
        time.sleep(20)


def estado():
    con = banco()
    r = {"ligadas": {n: ligada(n) for n in ["visitas", *HORARIOS, "conferencia"]},
         "marcadores": {x["chave"]: x["valor"] for x in con.execute("SELECT chave, valor FROM rotinas_estado")},
         "visitas_na_espera": con.execute("SELECT count(*) n FROM rotina_visita WHERE enviado_em IS NULL").fetchone()["n"],
         "ultimas_visitas": con.execute("SELECT evento, visita, entrou_em, enviado_em FROM rotina_visita "
                                        "ORDER BY evento DESC LIMIT 5").fetchall()}
    con.close()
    return r


if __name__ == "__main__":
    print(json.dumps(estado(), ensure_ascii=False, indent=2))
