"""
Testes do cron de alertas da agenda de visitas.

  .venv/bin/python teste_alertar_visitas.py
"""
import datetime
from zoneinfo import ZoneInfo

import alertar_visitas

FUSO = ZoneInfo("America/Manaus")


class CursorFake:
    def __init__(self, conn):
        self.conn = conn
        self.linhas = []
        self.ultimo_sql = ""
        self.ultimo_params = None

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def execute(self, sql, params=None):
        self.ultimo_sql = sql
        self.ultimo_params = params
        self.linhas = []
        if "hora_a_definir OR NOT confirmada" in sql:
            # A CONSULTA DAS 08:00, filtrada de verdade -- o falho generico
            # devolveria a lista inteira e o teste "nao manda quando esta tudo
            # resolvido" passaria com a consulta errada.
            assert "America/Manaus" in sql, "perdeu o fuso de Manaus"
            hoje = params[0].astimezone(FUSO).date()
            self.linhas = [v for v in self.conn.visitas
                           if v["data_hora"].astimezone(FUSO).date() == hoje
                           and (v.get("hora_a_definir") or not v.get("confirmada"))]
        elif "visita_falta_alinhar_em" in sql and sql.strip().upper().startswith("SELECT"):
            self.linhas = ([{"valor": self.conn.alinhar_em}]
                           if self.conn.alinhar_em else [])
        elif "confirmacao_pedida_em IS NULL" in sql:
            # A CONSULTA DA CONFIRMACAO DAS 07:00, filtrada de verdade. O
            # falho generico abaixo devolve a lista inteira para qualquer
            # pergunta -- e ai "visita de amanha nao e perguntada hoje"
            # passaria mesmo com a consulta sem o filtro de data.
            assert "NOT confirmada" in sql, "perdeu o filtro de confirmada"
            assert "America/Manaus" in sql, "perdeu o fuso de Manaus"
            assert "corretor_telefone" in sql, "perdeu o filtro de telefone"
            agora = params[0]
            hoje = agora.astimezone(FUSO).date()
            self.linhas = [
                v for v in self.conn.visitas
                if not v.get("confirmada")
                and v.get("confirmacao_pedida_em") is None
                and (v.get("corretor_telefone") or "").strip()
                and v["data_hora"].astimezone(FUSO).date() == hoje
                and (v.get("hora_a_definir") or v["data_hora"] > agora)]
        elif "FROM visita" in sql:
            self.linhas = self.conn.visitas
        elif "FROM config" in sql:
            self.linhas = [self.conn.config_row] if self.conn.config_row else []
        elif "DELETE FROM visita" in sql:
            self.conn.deletadas += 1
        elif "UPDATE visita" in sql:
            self.conn.atualizadas += 1
            if "confirmacao_pedida_em" in sql:
                self.conn.carimbos.append(params[1])
                for v in self.conn.visitas:
                    if v.get("id") == params[1]:
                        v["confirmacao_pedida_em"] = params[0]
        elif "UPDATE config" in sql:
            self.conn.config_atualizada = True
        elif "visita_falta_alinhar_em" in sql:
            self.conn.alinhar_em = params[0]

    def fetchall(self):
        return self.linhas

    def fetchone(self):
        return self.linhas[0] if self.linhas else None


class ConnFake:
    def __init__(self, visitas=None, config_row=None):
        self.visitas = visitas or []
        self.config_row = config_row
        self.deletadas = 0
        self.atualizadas = 0
        self.config_atualizada = False
        self.commits = 0
        self.carimbos = []
        self.alinhar_em = None

    def cursor(self):
        return CursorFake(self)

    def commit(self):
        self.commits += 1

    def close(self):
        pass


def _visita(horas_delta=2, confirmada=True, alerta_pendencia_em=None,
            alerta_90min_em=None, criada_em=None, **kwargs):
    agora = datetime.datetime.now(FUSO)
    defaults = {
        "id": 1,
        "codigo": "5095",
        "descricao": "casa Cidade Nova 3k",
        "corretor": "Lincoln",
        "data_hora": agora + datetime.timedelta(hours=horas_delta),
        "confirmada": confirmada,
        "alerta_pendencia_em": alerta_pendencia_em,
        "alerta_90min_em": alerta_90min_em,
        "criada_em": criada_em or (agora - datetime.timedelta(hours=2)),
        "corretor_telefone": None,
        "confirmacao_pedida_em": None,
        "hora_a_definir": False,
    }
    defaults.update(kwargs)
    return defaults


def teste_limpa_visitas_passadas():
    print("--- visitas passadas são apagadas ---")
    conn = ConnFake()
    alertar_visitas._limpar_passadas(conn, datetime.datetime.now(FUSO))
    assert conn.deletadas > 0 or conn.commits > 0
    print("OK\n")


def teste_alerta_pendencia_1h():
    print("--- pedido sem resposta há 1h → avisa ---")
    agora = datetime.datetime.now(FUSO)
    visita = _visita(horas_delta=4, confirmada=False,
                     criada_em=agora - datetime.timedelta(hours=2))
    conn = ConnFake(visitas=[visita])
    enviados = []
    alertar_visitas._alertar_pendencias(
        conn, agora, "tel_id", lambda d, t: enviados.append(t))
    assert len(enviados) == 1, f"devia enviar 1: {enviados}"
    assert "sem resposta" in enviados[0].lower() or "1 hora" in enviados[0]
    assert conn.atualizadas > 0
    print(f"  enviou: {enviados[0][:100]}")
    print("OK\n")


def teste_nao_repete_alerta_pendencia():
    print("--- não repete alerta de pendência ---")
    agora = datetime.datetime.now(FUSO)
    visita = _visita(horas_delta=4, confirmada=False,
                     alerta_pendencia_em=agora - datetime.timedelta(hours=1),
                     criada_em=agora - datetime.timedelta(hours=2))
    conn = ConnFake(visitas=[])  # query retorna vazio porque já alertou
    enviados = []
    alertar_visitas._alertar_pendencias(
        conn, agora, "tel_id", lambda d, t: enviados.append(t))
    assert len(enviados) == 0
    print("OK\n")


def teste_lembrete_90min():
    print("--- 90 min antes de visita confirmada → lembrete ---")
    agora = datetime.datetime.now(FUSO)
    visita = _visita(horas_delta=1, confirmada=True)
    visita["data_hora"] = agora + datetime.timedelta(minutes=60)
    conn = ConnFake(visitas=[visita])
    enviados = []
    alertar_visitas._lembrete_90min(
        conn, agora, "tel_id", lambda d, t: enviados.append(t))
    assert len(enviados) == 1
    assert "1h30" in enviados[0] or "próximas" in enviados[0]
    assert conn.atualizadas > 0
    print(f"  enviou: {enviados[0][:100]}")
    print("OK\n")


def teste_nao_lembra_se_ja_lembrou():
    print("--- não repete lembrete de 90 min ---")
    conn = ConnFake(visitas=[])
    enviados = []
    agora = datetime.datetime.now(FUSO)
    alertar_visitas._lembrete_90min(
        conn, agora, "tel_id", lambda d, t: enviados.append(t))
    assert len(enviados) == 0
    print("OK\n")


def teste_briefing_manha_as_6h():
    print("--- briefing da manhã às 06:00 ---")
    agora = datetime.datetime(2026, 9, 12, 6, 0, tzinfo=FUSO)
    visita = _visita(horas_delta=4)
    visita["data_hora"] = datetime.datetime(2026, 9, 12, 14, 0, tzinfo=FUSO)
    conn = ConnFake(visitas=[visita], config_row={"valor": ""})
    enviados = []
    alertar_visitas._briefing_manha(
        conn, agora, "tel_id", lambda d, t: enviados.append(t))
    assert len(enviados) == 1
    assert "HOJE" in enviados[0]
    assert conn.config_atualizada
    print(f"  enviou: {enviados[0][:120]}")
    print("OK\n")


def teste_briefing_nao_repete_no_mesmo_dia():
    print("--- briefing não repete no mesmo dia ---")
    agora = datetime.datetime(2026, 9, 12, 6, 30, tzinfo=FUSO)
    conn = ConnFake(visitas=[], config_row={"valor": "2026-09-12"})
    enviados = []
    alertar_visitas._briefing_manha(
        conn, agora, "tel_id", lambda d, t: enviados.append(t))
    assert len(enviados) == 0
    print("OK\n")


def teste_briefing_fora_das_6h_nao_dispara():
    print("--- briefing fora das 06:00 não dispara ---")
    agora = datetime.datetime(2026, 9, 12, 7, 0, tzinfo=FUSO)
    conn = ConnFake(visitas=[_visita()])
    enviados = []
    alertar_visitas._briefing_manha(
        conn, agora, "tel_id", lambda d, t: enviados.append(t))
    assert len(enviados) == 0
    print("OK\n")


def teste_alerta_vespera_as_18h():
    print("--- alerta véspera às 18:00 ---")
    agora = datetime.datetime(2026, 9, 12, 18, 0, tzinfo=FUSO)
    visita = _visita()
    visita["data_hora"] = datetime.datetime(2026, 9, 13, 14, 0, tzinfo=FUSO)
    conn = ConnFake(visitas=[visita], config_row={"valor": ""})
    enviados = []
    alertar_visitas._alerta_vespera(
        conn, agora, "tel_id", lambda d, t: enviados.append(t))
    assert len(enviados) == 1
    assert "AMANHÃ" in enviados[0]
    assert conn.config_atualizada
    print(f"  enviou: {enviados[0][:120]}")
    print("OK\n")


def teste_vespera_nao_repete():
    print("--- véspera não repete no mesmo dia ---")
    agora = datetime.datetime(2026, 9, 12, 18, 30, tzinfo=FUSO)
    conn = ConnFake(visitas=[], config_row={"valor": "2026-09-12"})
    enviados = []
    alertar_visitas._alerta_vespera(
        conn, agora, "tel_id", lambda d, t: enviados.append(t))
    assert len(enviados) == 0
    print("OK\n")


def teste_agenda_de_visitas_vazia():
    print("--- agenda de visitas vazia ---")
    import publicador
    conn = ConnFake(visitas=[])
    r = publicador._agenda_de_visitas(conn)
    assert "Nenhuma visita" in r
    print(f"  {r}")
    print("OK\n")


def teste_agenda_de_visitas_com_itens():
    print("--- agenda de visitas com itens ---")
    import publicador
    agora = datetime.datetime.now(FUSO)
    visitas = [
        {"id": 1, "codigo": "5095", "descricao": "casa Cidade Nova 3k",
         "corretor": "Lincoln", "confirmada": True,
         "data_hora": agora + datetime.timedelta(hours=3)},
        {"id": 2, "codigo": None, "descricao": "Acquarelle 3.5k",
         "corretor": "Marlúcia", "confirmada": False,
         "data_hora": agora + datetime.timedelta(days=1, hours=2)},
    ]
    conn = ConnFake(visitas=visitas)
    r = publicador._agenda_de_visitas(conn)
    assert "Agenda de visitas" in r
    assert "Lincoln" in r
    assert "Marlúcia" in r
    assert "✓" in r and "⏳" in r
    print(f"  {r}")
    print("OK\n")


def _rodar(conn, quando):
    """Roda o cron inteiro e devolve o que teria sido enviado."""
    enviados = []
    alertar_visitas.alertar_visitas(
        conexao=conn, agora=quando, tel_whatsapp="tel",
        enviar=lambda d, t: enviados.append((d, t)))
    return enviados


def _hoje_as(h, m=0):
    return datetime.datetime(2026, 9, 24, h, m, tzinfo=FUSO)


def teste_confirma_com_o_corretor_as_07():
    """07:00 -- pergunta AO CORRETOR se a visita de hoje esta de pe.

    O PEDIDO (Tel, 23/09), depois do caso da Waldyrene: ela combinou uma visita
    para 17h30 na noite anterior, a Nay nao entendeu o "Amanha" e ninguem
    confirmou nada. Palavra dele: "se ela nao mandou mensagem pede para enviar
    agora para verificar logo se esta confirmada a visita para alinhar com a
    locadora".

    E a UNICA das seis regras que fala com o CORRETOR -- as outras cinco falam
    so com o Tel --, e por isso e a que tem mais parede.
    """
    print("--- 07:00: confirma com o corretor ---")

    def visita(**kw):
        return _visita(confirmada=False, **kw)

    # SEM TELEFONE nao manda. `corretor_telefone` nulo existe de verdade -- a
    # visita da Renata foi registrada a mao sem ele -- e enviar para None
    # mandaria para lugar nenhum.
    conn = ConnFake([visita(id=1, data_hora=_hoje_as(17, 30),
                            corretor="Waldyrene Oliveira")])
    # `_rodar` roda o cron INTEIRO, e as outras cinco regras tambem mandam --
    # para o Tel. O que nao pode existir e mensagem para QUALQUER OUTRO
    # destino, que seria o corretor recebendo sem telefone cadastrado.
    fora = [e for e in _rodar(conn, _hoje_as(7)) if e[0] != "tel"]
    assert not fora, f"sem telefone nao pode mandar a ninguem: {fora}"
    print("  OK  sem telefone do corretor, nao manda")

    conn = ConnFake([visita(id=1, data_hora=_hoje_as(17, 30),
                            corretor="Waldyrene Oliveira",
                            corretor_telefone="559293072954")])
    enviados = _rodar(conn, _hoje_as(7))
    dela = [e for e in enviados if e[0] == "559293072954"]
    assert len(dela) == 1, f"tinha que mandar uma: {enviados}"
    for pedaco in ("Waldyrene, bom dia!", "17h30", "confirmada", "locadora"):
        assert pedaco in dela[0][1], f"falta {pedaco!r}: {dela[0][1]}"
    print("  OK  pergunta ao corretor: hora, confirmacao e o porque")
    assert any(e[0] == "tel" for e in enviados), "o Tel precisa saber"
    print("  OK  e avisa o Tel de quem foi perguntado")

    # UMA VEZ SO -- o carimbo e POR VISITA, nao por dia.
    assert not [e for e in _rodar(conn, _hoje_as(7, 5))
                if e[0] == "559293072954"], "perguntou duas vezes"
    print("  OK  nao pergunta duas vezes")

    # DUAS visitas no mesmo dia, DUAS perguntas. Um carimbo global em
    # `config` -- que e o que o briefing e a vespera usam -- mandaria so a
    # primeira.
    conn = ConnFake([visita(id=1, data_hora=_hoje_as(10), corretor="Ana",
                            corretor_telefone="559200000001"),
                     visita(id=2, data_hora=_hoje_as(16), corretor="Bruno",
                            corretor_telefone="559200000002")])
    enviados = _rodar(conn, _hoje_as(7))
    assert len([e for e in enviados if e[0].startswith("5592000")]) == 2, enviados
    print("  OK  duas visitas no mesmo dia, duas perguntas")

    # FORA DA JANELA. Sem o teto, o cron que comecasse a rodar a tarde
    # dispararia a pergunta da manha fora de hora.
    for h in (6, 12, 16):
        conn = ConnFake([visita(id=1, data_hora=_hoje_as(17, 30), corretor="Ana",
                                corretor_telefone="559200000001")])
        assert not [e for e in _rodar(conn, _hoje_as(h))
                    if e[0] == "559200000001"], f"{h}h nao podia mandar"
    print("  OK  so entre 07h e 12h")

    conn = ConnFake([visita(id=1, data_hora=_hoje_as(17) + datetime.timedelta(days=1),
                            corretor="Ana", corretor_telefone="559200000001")])
    assert not [e for e in _rodar(conn, _hoje_as(7)) if e[0] == "559200000001"]
    print("  OK  visita de amanha nao e perguntada hoje")

    # HORA JA PASSADA: "confirma a visita de hoje" em cima da hora nao serve
    # para alinhar com a locadora.
    conn = ConnFake([visita(id=1, data_hora=_hoje_as(7), corretor="Ana",
                            corretor_telefone="559200000001")])
    assert not [e for e in _rodar(conn, _hoje_as(7, 30)) if e[0] == "559200000001"]
    print("  OK  visita cuja hora ja passou nao e perguntada")

    conn = ConnFake([_visita(id=1, data_hora=_hoje_as(17), confirmada=True,
                             corretor="Ana", corretor_telefone="559200000001")])
    assert not [e for e in _rodar(conn, _hoje_as(7)) if e[0] == "559200000001"]
    print("  OK  visita ja confirmada nao e perguntada")

    # NOME SEM LETRA nao vira vocativo -- a mesma parede do corretor "..".
    conn = ConnFake([visita(id=1, data_hora=_hoje_as(17), corretor="..",
                            corretor_telefone="559200000001")])
    msg = [e for e in _rodar(conn, _hoje_as(7)) if e[0] == "559200000001"][0][1]
    assert msg.startswith("Bom dia!"), msg
    print("  OK  nome sem letra nao vira vocativo")

    # ENVIO QUE FALHA NAO CARIMBA: tem que tentar de novo no minuto seguinte.
    conn = ConnFake([visita(id=1, data_hora=_hoje_as(17), corretor="Ana",
                            corretor_telefone="559200000001")])

    def quebrar(d, t):
        if d == "559200000001":
            raise RuntimeError("z-api fora do ar")

    alertar_visitas.alertar_visitas(conexao=conn, agora=_hoje_as(7),
                                    tel_whatsapp="tel", enviar=quebrar)
    assert not conn.carimbos, f"carimbou o que nao saiu: {conn.carimbos}"
    print("  OK  envio que falha nao carimba")
    print("OK\n")


def teste_falta_alinhar_as_08():
    """08:00 -- o que ainda FALTA nas visitas de hoje, para ele alinhar com a
    locadora.

    O PEDIDO (Tel, 23/09), no caso do Mario Feitosa: "logo pela manha as 08:00
    a Nay me notifica dessa visita para eu ver o horario e agendar com a
    locadora".

    NAO E O BRIEFING DE NOVO. As 06:00 ele ja recebe TODAS as visitas do dia;
    repetir a lista duas horas depois vira ruido, e lista que vira ruido deixa
    de ser lida. Este so sai quando FALTA alguma coisa, e diz o que.
    """
    print("--- 08:00: o que falta alinhar ---")
    oito = datetime.datetime(2026, 9, 25, 8, 0, tzinfo=FUSO)

    # SEM HORA: entra, e diz que falta a hora.
    conn = ConnFake([_visita(id=1, confirmada=False, hora_a_definir=True,
                             data_hora=oito.replace(hour=12),
                             corretor="Mario Feitosa")])
    e = [t for d, t in _rodar(conn, oito) if "faltam alinhar" in t]
    assert len(e) == 1, f"tinha que avisar: {e}"
    assert "hora a definir" in e[0], e[0]
    assert "sem hora" in e[0], e[0]
    assert "Mario Feitosa" in e[0], e[0]
    print("  OK  visita sem hora entra, dizendo que falta a hora")

    # UMA VEZ POR DIA -- o cron roda a cada minuto.
    assert not [t for d, t in _rodar(conn, oito.replace(minute=30))
                if "faltam alinhar" in t], "mandou duas vezes"
    print("  OK  não repete no mesmo dia")

    # NAO CONFIRMADA, com hora: entra dizendo isso.
    conn = ConnFake([_visita(id=1, confirmada=False, hora_a_definir=False,
                             data_hora=oito.replace(hour=15), corretor="Ana")])
    e = [t for d, t in _rodar(conn, oito) if "faltam alinhar" in t]
    assert "15h00" in e[0] and "não confirmada" in e[0], e[0]
    print("  OK  visita não confirmada entra, com a hora")

    # TUDO RESOLVIDO: silêncio. É o que dá sentido ao aviso -- o silêncio
    # passa a significar "pode alinhar com a locadora".
    conn = ConnFake([_visita(id=1, confirmada=True, hora_a_definir=False,
                             data_hora=oito.replace(hour=15), corretor="Ana")])
    assert not [t for d, t in _rodar(conn, oito) if "faltam alinhar" in t]
    print("  OK  com tudo resolvido, não manda nada")

    # FORA DAS 08 nao manda.
    for h in (7, 9, 14):
        conn = ConnFake([_visita(id=1, confirmada=False, hora_a_definir=True,
                                 data_hora=oito.replace(hour=12), corretor="Ana")])
        assert not [t for d, t in _rodar(conn, oito.replace(hour=h))
                    if "faltam alinhar" in t], f"{h}h não podia"
    print("  OK  só às 08h")

    # VISITA DE OUTRO DIA nao entra.
    conn = ConnFake([_visita(id=1, confirmada=False, hora_a_definir=True,
                             data_hora=oito + datetime.timedelta(days=1),
                             corretor="Ana")])
    assert not [t for d, t in _rodar(conn, oito) if "faltam alinhar" in t]
    print("  OK  visita de outro dia não entra")
    print("OK\n")


if __name__ == "__main__":
    teste_limpa_visitas_passadas()
    teste_confirma_com_o_corretor_as_07()
    teste_falta_alinhar_as_08()
    teste_alerta_pendencia_1h()
    teste_nao_repete_alerta_pendencia()
    teste_lembrete_90min()
    teste_nao_lembra_se_ja_lembrou()
    teste_briefing_manha_as_6h()
    teste_briefing_nao_repete_no_mesmo_dia()
    teste_briefing_fora_das_6h_nao_dispara()
    teste_alerta_vespera_as_18h()
    teste_vespera_nao_repete()
    teste_agenda_de_visitas_vazia()
    teste_agenda_de_visitas_com_itens()
    print("\nTODOS OS TESTES PASSARAM")
