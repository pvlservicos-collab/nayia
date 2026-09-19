"""
Doc 28, passo 7: dado o horário atual, decide quais vagas da grade
devem disparar agora.

Função pura -- recebe o horário como parâmetro, nunca lê o relógio do
sistema direto (datetime.now()). Isso é o que permite testar qualquer
horário/dia sem esperar o relógio real chegar lá.

Ponto de atenção deliberado: a coluna dias_semana usa a convenção do
Postgres (EXTRACT(DOW): 0=domingo ... 6=sábado), mas o Python
(date.weekday()) usa 0=segunda ... 6=domingo. As duas convenções têm
"0" significando dias diferentes -- é exatamente o tipo de bug que não
dá erro nenhum, só dispara a vaga no dia errado. _dow_postgres() faz a
conversão, e é testada isoladamente antes de qualquer outra coisa.
"""
import calendar
import datetime


def _dow_postgres(data):
    """Converte date.weekday() do Python (0=segunda) para a convenção
    do Postgres EXTRACT(DOW) (0=domingo), usada em vagas.dias_semana."""
    return (data.weekday() + 1) % 7


def vaga_deve_disparar(vaga, agora):
    """vaga: dict com horario (datetime.time), tipo_recorrencia,
    dias_semana (list[int] ou None), data_unica (date ou None),
    codigos (list[str]). agora: datetime.datetime."""
    if not vaga["codigos"]:
        return False  # vaga livre, nada pra postar

    if (vaga["horario"].hour, vaga["horario"].minute) != (agora.hour, agora.minute):
        return False

    tipo = vaga["tipo_recorrencia"]
    if tipo == "diaria":
        return True
    if tipo == "semanal":
        return _dow_postgres(agora.date()) in (vaga["dias_semana"] or [])
    if tipo == "unica":
        return vaga["data_unica"] == agora.date()
    return False


def vagas_para_disparar(vagas, agora):
    return [v for v in vagas if vaga_deve_disparar(v, agora)]


# --- autoteste --------------------------------------------------------
# Tabela verdade da conversão, tirada direto da documentação de cada
# sistema (não é calculada por nenhuma das duas funções sob teste, para
# não virar um teste que confirma a si mesmo):
#   Python date.weekday():   0=segunda 1=terça 2=quarta 3=quinta 4=sexta 5=sábado 6=domingo
#   Postgres EXTRACT(DOW):   0=domingo 1=segunda 2=terça 3=quarta 4=quinta 5=sexta 6=sábado
ESPERADO_WEEKDAY_PARA_DOW_POSTGRES = {
    0: 1,  # segunda
    1: 2,  # terça
    2: 3,  # quarta
    3: 4,  # quinta
    4: 5,  # sexta
    5: 6,  # sábado
    6: 0,  # domingo
}


def testar_conversao_dow():
    print("--- teste isolado: _dow_postgres() ---")
    base = datetime.date(2026, 1, 1)  # data qualquer -- 7 dias seguidos cobrem a semana inteira
    falhas = 0
    for i in range(7):
        data = base + datetime.timedelta(days=i)
        nome = calendar.day_name[data.weekday()]  # só para o print, não usado na checagem
        esperado = ESPERADO_WEEKDAY_PARA_DOW_POSTGRES[data.weekday()]
        obtido = _dow_postgres(data)
        ok = obtido == esperado
        falhas += 0 if ok else 1
        print(
            f"{data} ({nome}): weekday()={data.weekday()} -> "
            f"dow_postgres esperado={esperado} obtido={obtido} "
            f"{'OK' if ok else 'FALHOU'}"
        )
    if falhas:
        raise AssertionError(f"{falhas} conversão(ões) errada(s)")
    print("todas as 7 conversões corretas\n")


def testar_vagas_para_disparar():
    print("--- teste: vagas_para_disparar() ---")

    vaga_diaria = {
        "id": 1, "horario": datetime.time(14, 0), "tipo_recorrencia": "diaria",
        "dias_semana": None, "data_unica": None, "codigos": ["5644"],
    }
    vaga_semanal = {
        # terça (2) e quinta (4), convenção Postgres
        "id": 2, "horario": datetime.time(9, 0), "tipo_recorrencia": "semanal",
        "dias_semana": [2, 4], "data_unica": None, "codigos": ["5750", "5751"],
    }
    vaga_unica = {
        "id": 3, "horario": datetime.time(10, 30), "tipo_recorrencia": "unica",
        "dias_semana": None, "data_unica": datetime.date(2026, 8, 25), "codigos": ["5643"],
    }
    vaga_livre = {
        "id": 4, "horario": datetime.time(14, 0), "tipo_recorrencia": "diaria",
        "dias_semana": None, "data_unica": None, "codigos": [],
    }
    vagas = [vaga_diaria, vaga_semanal, vaga_unica, vaga_livre]

    casos = [
        # (descrição, agora, ids esperados)
        ("diaria no horário certo, qualquer dia",
         datetime.datetime(2026, 8, 24, 14, 0), [1]),  # 24/08/2026 = segunda
        ("diaria um minuto depois do horário -- não dispara",
         datetime.datetime(2026, 8, 24, 14, 1), []),
        ("semanal numa terça no horário certo",
         datetime.datetime(2026, 8, 25, 9, 0), [2]),  # 25/08/2026 = terça
        ("semanal numa quarta no mesmo horário -- não dispara",
         datetime.datetime(2026, 8, 26, 9, 0), []),  # 26/08/2026 = quarta
        ("unica na data certa e horário certo",
         datetime.datetime(2026, 8, 25, 10, 30), [3]),  # só a única -- a semanal é às 9h, não às 10h30
        ("unica um dia depois da data -- não dispara",
         datetime.datetime(2026, 8, 26, 10, 30), []),
        ("vaga livre nunca dispara, mesmo no horário certo",
         datetime.datetime(2026, 8, 24, 14, 0), [1]),  # já coberto acima, livre (id 4) fica de fora
    ]

    falhas = 0
    for descricao, agora, esperado_ids in casos:
        resultado = vagas_para_disparar(vagas, agora)
        ids = sorted(v["id"] for v in resultado)
        ok = ids == sorted(esperado_ids)
        falhas += 0 if ok else 1
        print(f"{descricao}: agora={agora} -> ids={ids} esperado={sorted(esperado_ids)} {'OK' if ok else 'FALHOU'}")

    if falhas:
        raise AssertionError(f"{falhas} caso(s) de vagas_para_disparar() errado(s)")
    print("todos os casos de vagas_para_disparar() corretos")


if __name__ == "__main__":
    testar_conversao_dow()
    testar_vagas_para_disparar()
