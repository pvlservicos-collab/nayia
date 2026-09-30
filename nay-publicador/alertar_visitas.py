"""
Cron de alertas da agenda de visitas.

O PEDIDO (Tel, 11/09): cinco regras de alerta, mais limpeza automática.

  1. Pedido sem resposta há 1h → avisa o Tel.
  2. 06:00  → briefing das visitas de HOJE.
  3. 18:00  → aviso das visitas de AMANHÃ.
  4. 90 min antes de uma visita confirmada → lembrete.
  5. Passou a hora → DELETE.  Cancelada → DELETE.
  7. 08:00  → o que ainda FALTA para as visitas de hoje, para o Tel alinhar
     com a locadora. Só sai quando falta alguma coisa.

O PEDIDO NOVO (Tel, 23/09): 07:00 → pergunta AO CORRETOR se a visita de hoje
está confirmada. É a única das seis que fala com o corretor; as outras cinco
falam só com o Tel. Palavra dele: "se ela não mandou mensagem pede para enviar
agora para verificar logo se está confirmada a visita para alinhar com a
locadora" -- o valor é ele conseguir avisar a locadora a tempo.

Roda a cada minuto, como os outros crons. Silencioso quando não há nada.

  .venv/bin/python alertar_visitas.py
"""
import datetime
import os
from zoneinfo import ZoneInfo

import db
from enviar_zapi import enviar_texto
from tel_whatsapp import enviar_ao_tel

FUSO_MANAUS = ZoneInfo("America/Manaus")


def alertar_visitas(conexao=None, agora=None, tel_whatsapp=None,
                    enviar=None):
    destino = tel_whatsapp or os.environ.get("TEL_WHATSAPP")
    if not destino:
        raise RuntimeError("TEL_WHATSAPP não configurada no ambiente.")

    enviar = enviar or enviar_texto
    # O LEQUE DOS DOIS NÚMEROS (28/09) é embrulhado AQUI, uma vez, e não em
    # cada chamada: são vários pontos de envio neste arquivo, e um deles
    # esquecido mandaria o alerta só para um número -- falha silenciosa, do
    # tipo que só aparece quando alguém repara que não recebeu.
    _enviar_um = enviar
    enviar = lambda d, t: enviar_ao_tel(d, t, _enviar_um)
    fechar_ao_sair = conexao is None
    conn = conexao or db.conectar()
    try:
        momento = agora or datetime.datetime.now(FUSO_MANAUS)
        _limpar_passadas(conn, momento)
        _alertar_pendencias(conn, momento, destino, enviar)
        _lembrete_90min(conn, momento, destino, enviar)
        _briefing_manha(conn, momento, destino, enviar)
        _alerta_vespera(conn, momento, destino, enviar)
        _confirmar_com_o_corretor(conn, momento, destino, enviar)
        _falta_alinhar(conn, momento, destino, enviar)
    finally:
        if fechar_ao_sair:
            conn.close()


def _limpar_passadas(conn, agora):
    """Visita cuja hora passou sai da agenda (decisão do Tel, 11/09).

    COM HORA A DEFINIR, o critério é o DIA, não a hora: o `data_hora` ali
    guarda 12:00 de marcador, e apagar por ele tiraria da agenda às 12h01 uma
    visita que ainda vai acontecer à tarde. Quem não sabe a hora não sabe se
    já passou -- então espera o dia inteiro.
    """
    with conn.cursor() as cur:
        cur.execute(
            "DELETE FROM visita "
            " WHERE (NOT hora_a_definir AND data_hora <= %s) "
            "    OR (hora_a_definir "
            "        AND (data_hora AT TIME ZONE 'America/Manaus')::date "
            "          < (%s AT TIME ZONE 'America/Manaus')::date)",
            (agora, agora))
    conn.commit()


def _alertar_pendencias(conn, agora, destino, enviar):
    """Pedido de visita sem resposta há mais de 1 hora."""
    with conn.cursor() as cur:
        cur.execute(
            "SELECT id, codigo, descricao, corretor, data_hora, criada_em "
            "FROM visita "
            "WHERE NOT confirmada "
            "  AND alerta_pendencia_em IS NULL "
            "  AND criada_em + interval '1 hour' <= %s "
            "ORDER BY criada_em",
            (agora,))
        pendentes = cur.fetchall()

    if not pendentes:
        return

    linhas = ["⏰ Visitas pedidas há mais de 1 hora sem resposta:"]
    for v in pendentes:
        dh = v["data_hora"]
        hora = dh.strftime("%d/%m %Hh%M") if dh else "?"
        cod = f' cod:{v["codigo"]}' if v.get("codigo") else ""
        linhas.append(f"- {v['descricao']}{cod} para {hora} ({v['corretor']})")

    enviar(destino, "\n".join(linhas))

    ids = [v["id"] for v in pendentes]
    with conn.cursor() as cur:
        cur.execute(
            "UPDATE visita SET alerta_pendencia_em = %s "
            "WHERE id = ANY(%s)", (agora, ids))
    conn.commit()


def _lembrete_90min(conn, agora, destino, enviar):
    # HORA A DEFINIR NAO TEM 90 MINUTOS ANTES. O `data_hora` ali e marcador
    # (12:00), e o lembrete sairia as 10h30 para uma visita que talvez seja as
    # 16h -- pior que nao lembrar, porque parece informacao.
    """90 minutos antes de uma visita confirmada."""
    limite = agora + datetime.timedelta(minutes=90)
    with conn.cursor() as cur:
        cur.execute(
            "SELECT id, codigo, descricao, corretor, data_hora "
            "FROM visita "
            "WHERE confirmada "
            "  AND NOT hora_a_definir "
            "  AND alerta_90min_em IS NULL "
            "  AND data_hora > %s "
            "  AND data_hora <= %s "
            "ORDER BY data_hora",
            (agora, limite))
        proximas = cur.fetchall()

    if not proximas:
        return

    linhas = ["🔔 Visitas nas próximas 1h30:"]
    for v in proximas:
        dh = v["data_hora"]
        hora = dh.strftime("%Hh%M")
        cod = f' cod:{v["codigo"]}' if v.get("codigo") else ""
        linhas.append(f"- {hora} — {v['descricao']}{cod} ({v['corretor']})")

    enviar(destino, "\n".join(linhas))

    ids = [v["id"] for v in proximas]
    with conn.cursor() as cur:
        cur.execute(
            "UPDATE visita SET alerta_90min_em = %s "
            "WHERE id = ANY(%s)", (agora, ids))
    conn.commit()


def _briefing_manha(conn, agora, destino, enviar):
    """06:00 — visitas agendadas para HOJE."""
    if agora.hour != 6:
        return

    hoje = agora.date()
    with conn.cursor() as cur:
        cur.execute(
            "SELECT valor FROM config WHERE chave = 'visita_briefing_manha_em'")
        row = cur.fetchone()
        ultimo = row["valor"] if row else ""
        if ultimo == str(hoje):
            return

        cur.execute(
            "SELECT id, codigo, descricao, corretor, data_hora, confirmada "
            "FROM visita "
            "WHERE data_hora::date = %s "
            "ORDER BY data_hora",
            (hoje,))
        visitas = cur.fetchall()

    if not visitas:
        return

    linhas = [f"☀️ Visitas de HOJE ({hoje.strftime('%d/%m')}):"]
    for v in visitas:
        dh = v["data_hora"]
        hora = dh.strftime("%Hh%M")
        status = "✓" if v["confirmada"] else "⏳"
        cod = f' cod:{v["codigo"]}' if v.get("codigo") else ""
        linhas.append(f"- {status} {hora} — {v['descricao']}{cod} ({v['corretor']})")

    enviar(destino, "\n".join(linhas))

    with conn.cursor() as cur:
        cur.execute(
            "UPDATE config SET valor = %s "
            "WHERE chave = 'visita_briefing_manha_em'",
            (str(hoje),))
    conn.commit()


def _alerta_vespera(conn, agora, destino, enviar):
    """18:00 — visitas de AMANHÃ (que foram agendadas com 2+ dias)."""
    if agora.hour != 18:
        return

    hoje = agora.date()
    amanha = hoje + datetime.timedelta(days=1)
    with conn.cursor() as cur:
        cur.execute(
            "SELECT valor FROM config WHERE chave = 'visita_alerta_vespera_em'")
        row = cur.fetchone()
        ultimo = row["valor"] if row else ""
        if ultimo == str(hoje):
            return

        cur.execute(
            "SELECT id, codigo, descricao, corretor, data_hora, confirmada "
            "FROM visita "
            "WHERE data_hora::date = %s "
            "ORDER BY data_hora",
            (amanha,))
        visitas = cur.fetchall()

    if not visitas:
        return

    linhas = [f"📋 Visitas de AMANHÃ ({amanha.strftime('%d/%m')}):"]
    for v in visitas:
        dh = v["data_hora"]
        hora = dh.strftime("%Hh%M")
        status = "✓" if v["confirmada"] else "⏳"
        cod = f' cod:{v["codigo"]}' if v.get("codigo") else ""
        linhas.append(f"- {status} {hora} — {v['descricao']}{cod} ({v['corretor']})")

    enviar(destino, "\n".join(linhas))

    with conn.cursor() as cur:
        cur.execute(
            "UPDATE config SET valor = %s "
            "WHERE chave = 'visita_alerta_vespera_em'",
            (str(hoje),))
    conn.commit()


def _confirmar_com_o_corretor(conn, agora, destino, enviar):
    """07:00 -- pergunta AO CORRETOR se a visita de hoje está de pé.

    O PEDIDO (Tel, 23/09). As outras cinco regras falam com ele; esta fala com
    o corretor, e é por isso que tem mais parede que as outras.

    AS PAREDES, e cada uma tem motivo:

      * SÓ VISITA DE HOJE. A pergunta é "está confirmada?" -- mandada na
        véspera ela chega antes de o corretor saber, e mandada depois não
        serve para alinhar com a locadora.

      * UMA VEZ POR VISITA, carimbada em `confirmacao_pedida_em`. Um carimbo
        global em `config` -- que é o que o briefing e a véspera usam -- só
        mandaria a primeira, e duas visitas no mesmo dia precisam de duas
        perguntas.

      * SÓ DEPOIS DAS 07:00 E ANTES DAS 12:00. Sem o teto, o cron que
        começasse a rodar à tarde dispararia a pergunta da manhã fora de hora
        -- e "confirma a visita de hoje" às 16h para uma visita das 17h30 é
        tarde para avisar a locadora.

      * NUNCA DEPOIS DA HORA DA VISITA. Visita das 07:30 com o cron rodando
        07:31 receberia "a visita de hoje está confirmada?" já em cima.

      * SÓ QUEM TEM TELEFONE. `corretor_telefone` nulo existe (a visita da
        Renata foi registrada à mão sem ele) e `enviar_texto(None, ...)`
        mandaria para lugar nenhum.

    A visita JÁ CONFIRMADA não recebe pergunta -- mas hoje nada marca
    `confirmada = true` (medido em 23/09: 0 de 8), então na prática todas
    recebem. Fechar esse laço é trabalho à parte, e está dito no relatório.
    """
    hora = agora.astimezone(FUSO_MANAUS)
    if not (7 <= hora.hour < 12):
        return

    with conn.cursor() as cur:
        cur.execute(
            "SELECT id, codigo, descricao, corretor, corretor_telefone, "
            "       data_hora, hora_a_definir "
            "  FROM visita "
            " WHERE NOT confirmada "
            "   AND confirmacao_pedida_em IS NULL "
            "   AND coalesce(btrim(corretor_telefone),'') <> '' "
            "   AND (data_hora AT TIME ZONE 'America/Manaus')::date "
            "     = (%s AT TIME ZONE 'America/Manaus')::date "
            "   AND (hora_a_definir OR data_hora > %s) "
            " ORDER BY data_hora",
            (agora, agora))
        visitas = cur.fetchall()

    for v in visitas:
        # SEM HORA, A PERGUNTA E OUTRA. Confirmar "a visita das 12h00" quando
        # 12:00 e so marcador seria afirmar um horario que ninguem combinou --
        # e o corretor responderia "sim" a coisa errada.
        if v["hora_a_definir"]:
            quando = None
        else:
            quando = v["data_hora"].astimezone(FUSO_MANAUS).strftime("%Hh%M")
        primeiro = (v["corretor"] or "").split()[0] if (v["corretor"] or "").strip() else ""
        # Nome sem letra não vira vocativo -- é a mesma parede do envio
        # privado, posta pelo caso do corretor cadastrado como "..".
        if not any(c.isalpha() for c in primeiro):
            primeiro = ""
        oi = f"{primeiro}, bom dia! " if primeiro else "Bom dia! "
        oque = v["descricao"] or (f'imóvel {v["codigo"]}' if v["codigo"] else "a visita")
        try:
            enviar(v["corretor_telefone"],
                   (f'{oi}a visita de hoje às {quando} está confirmada?'
                    if quando else
                    f'{oi}sobre a visita de hoje — que horas fica melhor '
                    'para você?')
                   + f'\n\n{oque}\n\n'
                   + 'Me confirma agora, por favor, que eu já alinho com a locadora.')
        except Exception:
            continue          # não carimba o que não saiu: tenta no minuto seguinte
        with conn.cursor() as cur:
            cur.execute("UPDATE visita SET confirmacao_pedida_em = %s WHERE id = %s",
                        (agora, v["id"]))
        conn.commit()

    if visitas:
        linhas = "\n".join(
            f'- {v["data_hora"].astimezone(FUSO_MANAUS).strftime("%Hh%M")} '
            f'{v["corretor"]}' for v in visitas)
        enviar(destino,
               f'perguntei a {len(visitas)} corretor(es) se a visita de hoje '
               f'está de pé:\n{linhas}\n\nte aviso o que responderem.')


def _falta_alinhar(conn, agora, destino, enviar):
    """08:00 -- o que ainda falta nas visitas de HOJE, para ele alinhar com a
    locadora.

    O PEDIDO (Tel, 23/09), no caso do Mario: "logo pela manha as 08:00 a Nay
    me notifica dessa visita para eu ver o horario e agendar com a locadora".

    POR QUE NAO E O BRIEFING DE NOVO: as 06:00 ele ja recebe TODAS as visitas
    do dia. Repetir a mesma lista duas horas depois vira ruido, e lista que
    vira ruido deixa de ser lida -- foi o que aconteceu com o log da varredura.
    Este sai SO quando falta alguma coisa, e diz O QUE falta:

      * hora a definir  -- o corretor confirmou o dia e nao a hora
      * nao confirmada  -- ninguem disse ainda se esta de pe

    Quando tudo esta resolvido ele nao recebe nada, e o silencio passa a
    significar "pode alinhar com a locadora sem medo".
    """
    hora = agora.astimezone(FUSO_MANAUS)
    if hora.hour != 8:
        return

    with conn.cursor() as cur:
        cur.execute(
            "SELECT valor FROM config WHERE chave = 'visita_falta_alinhar_em'")
        linha = cur.fetchone()
    # UMA VEZ POR DIA. O cron roda a cada minuto, e sem o carimbo ele mandaria
    # sessenta vezes entre 08:00 e 08:59.
    if linha and str(linha["valor"] or "")[:10] == hora.date().isoformat():
        return

    with conn.cursor() as cur:
        cur.execute(
            "SELECT id, codigo, descricao, corretor, data_hora, confirmada, "
            "       hora_a_definir "
            "  FROM visita "
            " WHERE (data_hora AT TIME ZONE 'America/Manaus')::date "
            "     = (%s AT TIME ZONE 'America/Manaus')::date "
            "   AND (hora_a_definir OR NOT confirmada) "
            " ORDER BY data_hora",
            (agora,))
        visitas = cur.fetchall()

    if visitas:
        linhas = []
        for v in visitas:
            falta = []
            if v["hora_a_definir"]:
                falta.append("sem hora")
            if not v["confirmada"]:
                falta.append("não confirmada")
            quando = ("hora a definir" if v["hora_a_definir"]
                      else v["data_hora"].astimezone(FUSO_MANAUS).strftime("%Hh%M"))
            linhas.append(f'- {quando} — {v["descricao"] or v["codigo"] or "visita"} '
                          f'({v["corretor"]}) — {", ".join(falta)}')
        enviar(destino,
               "🔑 Visitas de HOJE que ainda faltam alinhar:\n"
               + "\n".join(linhas)
               + "\n\nsó alinhe com a locadora depois de fechar isso.")

    with conn.cursor() as cur:
        cur.execute(
            "INSERT INTO config (chave, valor) VALUES "
            "  ('visita_falta_alinhar_em', %s) "
            "ON CONFLICT (chave) DO UPDATE SET valor = EXCLUDED.valor",
            (hora.date().isoformat(),))
    conn.commit()


if __name__ == "__main__":
    alertar_visitas()
