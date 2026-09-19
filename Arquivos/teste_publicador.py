"""
Testa a lógica de roteamento de processar_comando() com banco e envio
simulados -- nenhuma chamada real ao Postgres nem à Z-API. O teste
contra o banco real roda no servidor, à parte.

Uso:
    .venv/bin/python teste_publicador.py
"""
import datetime
import threading
import time
from unittest.mock import patch

import publicador


class FakeCursor:
    def __init__(self, fetchall_resultado=None, fetchone_resultado=None):
        self.fetchall_resultado = fetchall_resultado or []
        self.fetchone_resultado = fetchone_resultado
        self.execucoes = []
        # `_marcar_indisponivel` conta linhas afetadas. Zero por padrão =
        # nada a cancelar, que é o caso comum.
        self.rowcount = 0

    def execute(self, query, params=None):
        self.execucoes.append((query, params))

    def fetchall(self):
        return self.fetchall_resultado

    def fetchone(self):
        return self.fetchone_resultado

    def __enter__(self):
        return self

    def __exit__(self, *exc_info):
        return False


class FakeConn:
    def __init__(self, cursores):
        # uma fila de cursores -- cada chamada a conn.cursor() consome o
        # próximo, na ordem em que o código real os pede
        self._cursores = list(cursores)
        self.commits = 0
        self.rollbacks = 0
        self.fechada = False

    def cursor(self):
        return self._cursores.pop(0)

    def commit(self):
        self.commits += 1

    def rollback(self):
        self.rollbacks += 1

    def close(self):
        self.fechada = True


class TabelaEasyFalsa:
    """Simula easy_publicacoes com o MESMO comportamento atômico do
    INSERT ... ON CONFLICT DO NOTHING ... RETURNING do Postgres real,
    usando um lock de verdade -- estado compartilhado entre threads,
    não por instância de conexão. É o que permite provar a proteção
    contra corrida com threads reais, não só chamadas em sequência."""
    def __init__(self):
        self._dados = {}
        self._lock = threading.Lock()

    def tentar_reservar(self, codigo):
        with self._lock:
            if codigo in self._dados:
                return False  # ON CONFLICT DO NOTHING -- não insere
            self._dados[codigo] = datetime.datetime(2026, 8, 25, 12, 0)
            return True  # inseriu de verdade -- RETURNING devolveria a linha

    def publicado_em(self, codigo):
        with self._lock:
            return self._dados.get(codigo)


class CursorEasyFalso:
    """Interpreta só as duas queries que _postar_easy manda, delegando
    pra TabelaEasyFalsa (que é quem tem o lock de verdade)."""
    def __init__(self, tabela):
        self._tabela = tabela
        self._resultado = None

    def execute(self, query, params=None):
        codigo = params[0]
        if "INSERT INTO easy_publicacoes" in query:
            reservou = self._tabela.tentar_reservar(codigo)
            self._resultado = {"codigo": codigo} if reservou else None
        elif "SELECT publicado_em" in query:
            data = self._tabela.publicado_em(codigo)
            self._resultado = {"publicado_em": data} if data is not None else None
        else:
            raise AssertionError(f"query inesperada no teste de concorrência: {query}")

    def fetchone(self):
        return self._resultado

    def __enter__(self):
        return self

    def __exit__(self, *exc_info):
        return False


class ConexaoEasyFalsa:
    """Uma por 'requisição' (como uma conexão psycopg2 de verdade
    seria) -- mas todas compartilham a mesma TabelaEasyFalsa por
    baixo, simulando o banco real compartilhado entre conexões."""
    def __init__(self, tabela):
        self._tabela = tabela
        self.commits = 0
        self.rollbacks = 0

    def cursor(self):
        return CursorEasyFalso(self._tabela)

    def commit(self):
        self.commits += 1

    def rollback(self):
        self.rollbacks += 1

    def close(self):
        pass


def _sem_conexao_real(*a, **k):
    raise AssertionError("db.conectar() não deveria ter sido chamado")


IMOVEL_FAKE = {
    "codigo": "5644", "condominio": "Morada dos Pássaros", "tipo": "Casa de condomínio",
    "bairro": "Ponta Negra", "area": 220, "quartos": 4, "suites": 4, "banheiros": 6,
    "vagas": 4, "vagas_cobertas": 2, "valor_venda": 1990000.0, "valor_aluguel": 15000.0,
    "fotos": ["https://x/foto1.jpg", "https://x/foto2.jpg"],
}

GRUPO_FAKE = {
    "id_grupo": "559281275642-1489427335", "nome": "Top imóveis venda e aluguéis",
    "aceita_venda": True, "aceita_locacao": True, "todas_fotos": False,
}

GRUPO_TODAS_FOTOS_FAKE = {
    "id_grupo": "120363296035090852-group", "nome": "IMÓVEIS PARA ANUNCIAR EASY",
    "aceita_venda": True, "aceita_locacao": True, "todas_fotos": True,
}


def teste_postar_agora():
    print("--- postar_agora: Easy (todas_fotos=true) fica de fora do fluxo normal ---")
    chamadas_envio = []
    with patch("publicador.buscar_imovel", return_value=IMOVEL_FAKE), \
         patch("publicador.carregar_grupos_db", return_value=[GRUPO_FAKE, GRUPO_TODAS_FOTOS_FAKE]), \
         patch("publicador.enviar_imovel", side_effect=lambda *a: chamadas_envio.append(a)):
        conn = FakeConn([])  # postar_agora não usa cursor do banco
        resposta = publicador.processar_comando("posta o 5644", conexao=conn)

    print(resposta)
    # mesmo com os dois grupos disponíveis em carregar_grupos_db, só o
    # comum deveria receber -- o Easy é filtrado em montar_lista_destinos
    assert len(chamadas_envio) == 1, f"esperava 1 envio (Easy fora), teve {len(chamadas_envio)}"
    destino, texto, fotos = chamadas_envio[0]
    assert destino == GRUPO_FAKE["id_grupo"]
    assert destino != GRUPO_TODAS_FOTOS_FAKE["id_grupo"], "Easy nunca deveria ser destino no fluxo normal"
    assert "Locação" in texto  # grupo comum, não o restrito -- mensagem completa
    assert fotos == IMOVEL_FAKE["fotos"][:1], "grupo comum recebe só a capa"

    assert "5644" in resposta and "1 grupo" in resposta
    assert not conn.fechada, "conexão injetada não deveria ser fechada por processar_comando"
    print("OK\n")


def teste_postar_agora_aviso_area_zero():
    print("--- postar_agora: area=0 -- posta normal, mas avisa metragem zerada ---")
    imovel_area_zero = dict(IMOVEL_FAKE, area=0)
    with patch("publicador.buscar_imovel", return_value=imovel_area_zero), \
         patch("publicador.carregar_grupos_db", return_value=[GRUPO_FAKE]), \
         patch("publicador.enviar_imovel"):
        conn = FakeConn([])
        resposta = publicador.processar_comando("posta o 5644", conexao=conn)

    print(resposta)
    assert "postado em 1 grupo" in resposta
    assert "Aviso: o imóvel 5644 está com metragem zerada -- confirme com o proprietário." in resposta
    print("OK\n")


def teste_postar_agora_aviso_vagas_zero():
    print("--- postar_agora: vagas=0 -- posta normal, mas avisa vagas zeradas ---")
    imovel_vagas_zero = dict(IMOVEL_FAKE, vagas=0, vagas_cobertas=0)
    with patch("publicador.buscar_imovel", return_value=imovel_vagas_zero), \
         patch("publicador.carregar_grupos_db", return_value=[GRUPO_FAKE]), \
         patch("publicador.enviar_imovel"):
        conn = FakeConn([])
        resposta = publicador.processar_comando("posta o 5644", conexao=conn)

    print(resposta)
    assert "postado em 1 grupo" in resposta
    assert "Aviso: o imóvel 5644 está com vagas zeradas -- confirme com o proprietário." in resposta
    print("OK\n")


def teste_postar_agora_falha_no_envio_nao_derruba_a_chamada():
    print("--- postar_agora: enviar_imovel falha (Z-API fora) -- vira erro por código, não crasha ---")
    # antes da extração de _postar_codigo, uma falha aqui subia sem
    # controle e derrubava a chamada inteira -- inclusive outros
    # códigos da mesma lista. Comportamento novo, introduzido junto com
    # a extração pra disparar_grade.py (doc 29).
    with patch("publicador.buscar_imovel", return_value=IMOVEL_FAKE), \
         patch("publicador.carregar_grupos_db", return_value=[GRUPO_FAKE]), \
         patch("publicador.enviar_imovel", side_effect=RuntimeError("Z-API respondeu 500")):
        conn = FakeConn([])
        resposta = publicador.processar_comando("posta o 5644", conexao=conn)

    print(resposta)
    assert "5644: falha ao enviar (Z-API respondeu 500)" in resposta
    print("OK\n")


def teste_postar_agora_falha_parcial_no_envio_conta_grupos_reais():
    print("--- postar_agora: falha no MEIO do envio -- não pode zerar quem já recebeu de verdade ---")
    # bug encontrado antes de aprovar: grupos_atingidos vinha 0 mesmo
    # quando o grupo-1 já tinha recebido de verdade, o que arriscava
    # reenvio duplicado pra quem já tinha sido alcançado.
    grupo_1 = dict(GRUPO_FAKE, id_grupo="grupo-1")
    grupo_2 = dict(GRUPO_FAKE, id_grupo="grupo-2")
    grupo_3 = dict(GRUPO_FAKE, id_grupo="grupo-3")
    chamadas_envio = []

    def enviar_com_falha_no_meio(destino, *a):
        chamadas_envio.append(destino)
        if destino == "grupo-2":
            raise RuntimeError("Z-API respondeu 500")

    with patch("publicador.buscar_imovel", return_value=IMOVEL_FAKE), \
         patch("publicador.carregar_grupos_db", return_value=[grupo_1, grupo_2, grupo_3]), \
         patch("publicador.enviar_imovel", side_effect=enviar_com_falha_no_meio):
        conn = FakeConn([])
        resposta = publicador.processar_comando("posta o 5644", conexao=conn)

    print(resposta)
    assert chamadas_envio == ["grupo-1", "grupo-2"], "não deveria ter tentado o grupo-3 depois da falha"
    assert "postado em 1 grupo(s) antes de falhar" in resposta, "grupo-1 já recebeu de verdade -- não pode zerar"
    assert "Z-API respondeu 500" in resposta
    print("OK\n")


def teste_postar_easy_sucesso():
    print("--- postar_easy: código nunca postado -- reserva atômica, posta com todas as fotos, confirma ---")
    # RETURNING devolveu uma linha -- esta chamada reservou de verdade
    cursor_insert = FakeCursor(fetchone_resultado={"codigo": "5644"})
    # O SEGUNDO cursor é o do registro em `envios`. Antes de 01/09 o Easy
    # era o único caminho de envio que postava e NÃO registrava -- e sem
    # linha em `envios` não há message_id, então a citação do card do Easy
    # não resolvia. A Waldyrene respondeu ao card do Smart Tower Itapuranga
    # postado ali e ouviu "de qual imóvel você está falando?".
    cursor_registro = FakeCursor()
    conn = FakeConn([cursor_insert, cursor_registro])
    chamadas_envio = []

    def _envio_fake(*a):
        chamadas_envio.append(a)
        return {"texto": {"messageId": "3EBEASY0001"}, "fotos": []}

    with patch("publicador.buscar_imovel", return_value=IMOVEL_FAKE), \
         patch("publicador.carregar_grupos_db", return_value=[GRUPO_FAKE, GRUPO_TODAS_FOTOS_FAKE]), \
         patch("publicador.enviar_imovel", side_effect=_envio_fake):
        resposta = publicador.processar_comando("publica no nosso grupo anunciar easy o 5644", conexao=conn)

    print(resposta)
    query_insert, params_insert = cursor_insert.execucoes[0]
    assert "INSERT INTO easy_publicacoes" in query_insert
    assert "ON CONFLICT" in query_insert and "RETURNING" in query_insert
    assert params_insert == ("5644",)
    # Dois commits: a reserva (antes de buscar/enviar) e o registro do
    # card em `envios`, depois do envio.
    assert conn.commits == 2, "reserva + registro do card"
    assert conn.rollbacks == 0

    assert len(chamadas_envio) == 1, "só o grupo todas_fotos deveria receber"
    destino, texto, fotos = chamadas_envio[0]
    assert destino == GRUPO_TODAS_FOTOS_FAKE["id_grupo"]
    assert fotos == IMOVEL_FAKE["fotos"], "Easy recebe a lista inteira de fotos, não só a capa"

    # O card do Easy vira linha em `envios` COM o message_id: é por
    # igualdade com ele que a citação do corretor resolve depois.
    query_reg, params_reg = cursor_registro.execucoes[0]
    assert "INSERT INTO envios" in query_reg, query_reg
    assert params_reg[0] == "5644"
    assert params_reg[3] == "3EBEASY0001", "sem o message_id a citação não resolve"

    assert "postado no Easy" in resposta and "5644" in resposta
    print("OK\n")


def teste_postar_easy_falha_no_envio_nao_derruba_a_chamada():
    print("--- postar_easy: enviar_imovel falha -- vira resposta de erro, não sobe exceção ---")
    # Antes deste conserto, este era o ÚNICO laço de envio do projeto sem
    # try/except. A exceção subia até servidor.py, que devolve 500 e
    # retorna ANTES da linha que avisa o Tel pelo WhatsApp: metade da
    # mensagem saía no grupo e ele não recebia nada.
    cursor_insert = FakeCursor(fetchone_resultado={"codigo": "5644"})
    conn = FakeConn([cursor_insert])

    with patch("publicador.buscar_imovel", return_value=IMOVEL_FAKE), \
         patch("publicador.carregar_grupos_db", return_value=[GRUPO_FAKE, GRUPO_TODAS_FOTOS_FAKE]), \
         patch("publicador.enviar_imovel", side_effect=RuntimeError("Z-API respondeu 500")):
        resposta = publicador.processar_comando("publica no anunciar easy o 5644", conexao=conn)

    print(resposta)
    assert "5644" in resposta
    assert "Z-API respondeu 500" in resposta
    assert "parte das fotos" in resposta, "tem que avisar do envio parcial, não só contar grupos inteiros"
    assert "segue marcado como postado" in resposta, "a reserva já foi commitada -- o Tel precisa saber"
    print("OK\n")


def teste_postar_easy_falha_parcial_conta_grupos_inteiros():
    print("--- postar_easy: falha no SEGUNDO grupo -- conta 1 inteiro e avisa do parcial ---")
    easy_1 = dict(GRUPO_TODAS_FOTOS_FAKE, id_grupo="easy-1")
    easy_2 = dict(GRUPO_TODAS_FOTOS_FAKE, id_grupo="easy-2")
    cursor_insert = FakeCursor(fetchone_resultado={"codigo": "5644"})
    conn = FakeConn([cursor_insert])
    chamadas_envio = []

    def enviar_com_falha_no_segundo(destino, *a):
        chamadas_envio.append(destino)
        if destino == "easy-2":
            raise RuntimeError("Z-API respondeu 500")

    with patch("publicador.buscar_imovel", return_value=IMOVEL_FAKE), \
         patch("publicador.carregar_grupos_db", return_value=[GRUPO_FAKE, easy_1, easy_2]), \
         patch("publicador.enviar_imovel", side_effect=enviar_com_falha_no_segundo):
        resposta = publicador.processar_comando("publica no anunciar easy o 5644", conexao=conn)

    print(resposta)
    assert chamadas_envio == ["easy-1", "easy-2"], "não deveria seguir depois da falha"
    assert "1 grupo(s) receberam tudo" in resposta, "o easy-1 recebeu de verdade -- não pode zerar"
    print("OK\n")


def teste_postar_easy_ja_postado():
    print("--- postar_easy: já postado -- reserva falha por conflito (ON CONFLICT DO NOTHING), rejeita sem tentar de novo ---")
    cursor_insert = FakeCursor(fetchone_resultado=None)  # ON CONFLICT DO NOTHING -- ninguém reservou agora
    cursor_select = FakeCursor(fetchone_resultado={"publicado_em": datetime.datetime(2026, 8, 20, 10, 0)})
    conn = FakeConn([cursor_insert, cursor_select])

    chamou_buscar = []
    with patch("publicador.buscar_imovel", side_effect=lambda c: chamou_buscar.append(c)), \
         patch("publicador.enviar_imovel"):
        resposta = publicador.processar_comando("publica no nosso grupo anunciar easy o 5644", conexao=conn)

    print(resposta)
    query_insert, params_insert = cursor_insert.execucoes[0]
    assert "INSERT INTO easy_publicacoes" in query_insert
    assert params_insert == ("5644",)
    assert conn.rollbacks == 1, "reserva sem sucesso deveria dar rollback, não commit"
    assert conn.commits == 0

    query_select, params_select = cursor_select.execucoes[0]
    assert "SELECT publicado_em FROM easy_publicacoes" in query_select
    assert params_select == ("5644",)

    assert not chamou_buscar, "não deveria nem tentar buscar o imóvel se já foi postado"
    assert "já foi postado no Easy em 20/08/2026" in resposta
    assert conn.commits == 0
    print("OK\n")


def teste_postar_easy_concorrencia_real():
    print("--- postar_easy: DUAS chamadas concorrentes (threads reais) pro mesmo código -- só uma posta ---")
    # bug real de produção (25/08): o Tel mandou o mesmo comando duas
    # vezes com ~90s de intervalo; postar no Easy pode levar minutos,
    # e o servidor aceita requisição concorrente (threaded=True) -- as
    # duas passavam pela checagem antes de qualquer uma gravar.
    tabela = TabelaEasyFalsa()
    chamadas_envio = []
    lock_envio = threading.Lock()
    resultados = []
    lock_resultados = threading.Lock()

    def buscar_imovel_lento(codigo):
        # simula "pode levar minutos" -- alarga a janela onde a
        # corrida antiga acontecia (entre checar e gravar). Não causa
        # trava no código novo: só a vencedora da reserva chega aqui.
        time.sleep(0.05)
        return IMOVEL_FAKE

    def enviar_imovel_thread_safe(*a):
        with lock_envio:
            chamadas_envio.append(a)

    def rodar():
        conn = ConexaoEasyFalsa(tabela)
        resposta = publicador.processar_comando(
            "publica no nosso grupo anunciar easy o 5644", conexao=conn
        )
        with lock_resultados:
            resultados.append(resposta)

    with patch("publicador.buscar_imovel", side_effect=buscar_imovel_lento), \
         patch("publicador.carregar_grupos_db", return_value=[GRUPO_TODAS_FOTOS_FAKE]), \
         patch("publicador.enviar_imovel", side_effect=enviar_imovel_thread_safe):
        threads = [threading.Thread(target=rodar) for _ in range(2)]
        for t in threads:
            t.start()
        for t in threads:
            t.join(timeout=5)

    for r in resultados:
        print(r)

    assert len(resultados) == 2, f"as duas chamadas deveriam ter terminado, terminaram {len(resultados)}"
    assert len(chamadas_envio) == 1, (
        f"esperava exatamente 1 envio real sob concorrência, teve {len(chamadas_envio)} -- "
        "corrida não corrigida"
    )
    # substrings mutuamente exclusivas -- "já foi postado no Easy" (rejeição)
    # também contém "postado no Easy", então não dá pra usar essa sozinha
    sucesso = [r for r in resultados if "com todas as fotos" in r]
    rejeitado = [r for r in resultados if "já foi postado no Easy" in r]
    assert len(sucesso) == 1, f"esperava 1 resposta de sucesso, teve {len(sucesso)}: {resultados}"
    assert len(rejeitado) == 1, f"esperava 1 resposta de rejeição, teve {len(rejeitado)}: {resultados}"
    print("OK -- metodologia validada à parte (30/30 corridas no padrão antigo, 0/30 no novo)\n")


def teste_criar_vaga_diaria():
    print("--- criar_vaga (diaria) ---")
    cursor_insert = FakeCursor(fetchone_resultado={"id": 7})
    conn = FakeConn([cursor_insert])

    resposta = publicador.processar_comando("posta o 5750 todo dia às 14h", conexao=conn)
    print(resposta)

    assert conn.commits == 1
    query, params = cursor_insert.execucoes[0]
    assert "INSERT INTO vagas" in query
    assert params == (datetime.time(14, 0), "diaria", None, None, ["5750"])
    assert "#7" in resposta and "todo dia às 14h" in resposta and "5750" in resposta
    print("OK\n")


def teste_criar_vaga_semanal():
    print("--- criar_vaga (semanal) ---")
    cursor_insert = FakeCursor(fetchone_resultado={"id": 8})
    conn = FakeConn([cursor_insert])

    resposta = publicador.processar_comando(
        "posta 5750, 5751 e 5752 terça e quinta às 9h", conexao=conn
    )
    print(resposta)

    query, params = cursor_insert.execucoes[0]
    assert params == (datetime.time(9, 0), "semanal", [2, 4], None, ["5750", "5751", "5752"])
    assert "terça e quinta às 9h" in resposta
    print("OK\n")


def teste_liberar_vaga_fica_vazia():
    print("--- liberar_vaga: vaga de 1 código, fica vazia, dispara aviso ---")
    vaga = {
        "id": 3, "horario": datetime.time(10, 30), "tipo_recorrencia": "unica",
        "dias_semana": None, "data_unica": datetime.date(2026, 8, 25), "codigos": ["5643"],
    }
    cursor_select = FakeCursor(fetchall_resultado=[vaga])
    cursor_update = FakeCursor()
    conn = FakeConn([cursor_select, cursor_update, FakeCursor()])

    resposta = publicador.processar_comando("VENDEU 5643", conexao=conn)
    print(resposta)

    assert conn.commits == 2, "uma pela vaga, outra por tirar da oferta"
    query, params = cursor_update.execucoes[0]
    assert "UPDATE vagas SET codigos" in query
    assert params == ([], 3)
    assert "ficou livre" in resposta
    print("OK\n")


def teste_liberar_vaga_continua_ativa():
    print("--- liberar_vaga: vaga de 3 códigos perde 1, continua ativa, sem aviso ---")
    vaga = {
        "id": 2, "horario": datetime.time(9, 0), "tipo_recorrencia": "semanal",
        "dias_semana": [2, 4], "data_unica": None, "codigos": ["5750", "5751", "5752"],
    }
    cursor_select = FakeCursor(fetchall_resultado=[vaga])
    cursor_update = FakeCursor()
    conn = FakeConn([cursor_select, cursor_update, FakeCursor()])

    resposta = publicador.processar_comando("ALUGOU 5751", conexao=conn)
    print(resposta)

    query, params = cursor_update.execucoes[0]
    assert params == (["5750", "5752"], 2)
    assert "ficou livre" not in resposta
    print("OK\n")


def teste_remover_da_grade():
    print("--- remover_da_grade: tira da grade sem dizer que vendeu ---")
    vaga = {
        "id": 2, "horario": datetime.time(9, 0), "tipo_recorrencia": "semanal",
        "dias_semana": [2, 4], "data_unica": None, "codigos": ["5750", "5751", "5752"],
    }
    cursor_select = FakeCursor(fetchall_resultado=[vaga])
    cursor_update = FakeCursor()
    conn = FakeConn([cursor_select, cursor_update])

    resposta = publicador.processar_comando("tira o 5751", conexao=conn)
    print(resposta)

    # a escrita no banco é idêntica à de liberar_vaga -- é a mesma função
    assert conn.commits == 1
    query, params = cursor_update.execucoes[0]
    assert "UPDATE vagas SET codigos" in query
    assert params == (["5750", "5752"], 2)

    # ...mas a resposta não pode sugerir venda/locação
    assert "removido da grade" in resposta
    assert "vendido" not in resposta.lower() and "alugado" not in resposta.lower()
    assert "vaga(s)" not in resposta, "essa é a frase de liberar_vaga, não desta ação"
    print("OK\n")


def teste_remover_da_grade_esvazia_vaga():
    print("--- remover_da_grade: se a vaga fica vazia, avisa igual liberar_vaga ---")
    vaga = {
        "id": 3, "horario": datetime.time(10, 30), "tipo_recorrencia": "unica",
        "dias_semana": None, "data_unica": datetime.date(2026, 8, 25), "codigos": ["5643"],
    }
    cursor_select = FakeCursor(fetchall_resultado=[vaga])
    cursor_update = FakeCursor()
    conn = FakeConn([cursor_select, cursor_update])

    resposta = publicador.processar_comando("remove o 5643", conexao=conn)
    print(resposta)

    assert "removido da grade" in resposta
    assert "ficou livre" in resposta, "vaga vazia continua precisando de imóvel novo, seja qual for o verbo"
    print("OK\n")


def teste_remover_da_grade_codigo_ausente_nao_escreve():
    print("--- remover_da_grade: código que não está em vaga nenhuma não escreve nada ---")
    cursor_select = FakeCursor(fetchall_resultado=[])
    conn = FakeConn([cursor_select])

    resposta = publicador.processar_comando("tira o 9999", conexao=conn)
    print(resposta)

    assert conn.commits == 0, "sem mudança não deveria commitar"
    assert "não estava na grade" in resposta
    print("OK\n")


def teste_vendeu_tira_da_oferta_e_tira_nao():
    """A diferença entre VENDEU e `tira` tinha que existir no BANCO.

    Até 31/08 os dois faziam a mesma escrita e só a frase mudava. Resultado:
    o Tel dava um imóvel por vendido, ele saía da grade -- e as buscas
    continuavam oferecendo, porque elas olham `imoveis.disponivel` e ninguém
    tinha tocado nele. Corretor montava visita para imóvel que não existia
    mais.
    """
    print("--- VENDEU tira da oferta; `tira` NÃO ---")
    vaga = {"id": 3, "horario": datetime.time(10, 30), "tipo_recorrencia": "unica",
            "dias_semana": None, "data_unica": datetime.date(2026, 8, 25),
            "codigos": ["5643"]}

    def escritas(comando):
        cur_extra = FakeCursor(fetchone_resultado={"codigo": 5643})
        conn = FakeConn([FakeCursor(fetchall_resultado=[dict(vaga)]),
                         FakeCursor(), cur_extra])
        resposta = publicador.processar_comando(comando, conexao=conn)
        return resposta, " ".join(q for q, _ in cur_extra.execucoes)

    resp_vendeu, sql_vendeu = escritas("VENDEU 5643")
    print(resp_vendeu)
    assert "UPDATE imoveis SET disponivel = false" in sql_vendeu, \
        "VENDEU sem isto deixa o imóvel sendo oferecido nas buscas"
    assert "lembrete" in sql_vendeu, "lembrete de imóvel vendido é cobrança à toa"
    assert "entrega_pendente" in sql_vendeu, "não se entrega imóvel que saiu do mercado"
    assert "indisponível" in resp_vendeu, "o Tel precisa VER que saiu da oferta"

    resp_tira, sql_tira = escritas("tira o 5643")
    print(resp_tira)
    assert sql_tira == "", "`tira` é só reorganização de horário: o imóvel segue à venda"
    assert "indisponível" not in resp_tira
    print("OK\n")


def teste_id_da_mensagem():
    """O ID que a Z-API devolve ao enviar é o que fecha o ciclo da citação.

    Quando o corretor MARCA um card nosso, a Z-API manda o ID daquela
    mensagem em `referenceMessageId`. Guardando o ID de cada card que sai,
    a citação vira o código do imóvel por igualdade. Sem guardar, a Nay só
    consegue perguntar "de qual imóvel você fala?" -- foi o que aconteceu
    com o Victor em 01/09.

    O nome do campo varia entre rotas e versões da Z-API, e chutar UM nome
    é como o `referencedMessage` custou um dia: aceita os três conhecidos.
    """
    print("--- id_da_mensagem: aceita as três formas da Z-API ---")
    from enviar_zapi import id_da_mensagem

    assert id_da_mensagem({"messageId": "3EB0ABC"}) == "3EB0ABC"
    assert id_da_mensagem({"id": "XYZ"}) == "XYZ"
    assert id_da_mensagem({"zaapId": "Z1"}) == "Z1"
    # messageId ganha quando vêm juntos: é o ID que volta na citação
    assert id_da_mensagem({"zaapId": "Z1", "messageId": "M1"}) == "M1"
    # e nada quebra quando a resposta não tem nenhum
    assert id_da_mensagem({}) is None
    assert id_da_mensagem({"erro": "x"}) is None
    assert id_da_mensagem(None) is None
    assert id_da_mensagem("texto solto") is None
    # número vira texto: a coluna é text e o casamento é por igualdade
    assert id_da_mensagem({"messageId": 12345}) == "12345"
    print("OK\n")


def teste_registra_o_id_do_card():
    """O ID guardado é o do TEXTO, não o da foto.

    O corretor marca o card -- o texto -- para dizer de qual imóvel fala.
    Guardar o ID de uma das fotos faria a citação não casar com nada.
    """
    print("--- registra o message_id do card, não o da foto ---")
    cur = FakeCursor()
    conn = FakeConn([cur])
    publicador._registrar_envio_corretor(conn, "4946", "559285311259", "M-DO-TEXTO")
    query, params = cur.execucoes[0]
    assert "message_id" in query, "sem a coluna, a citação nunca resolve"
    assert params == ("4946", "559285311259", "M-DO-TEXTO"), params

    # sem id (Z-API não devolveu) continua gravando: o envio aconteceu
    cur2 = FakeCursor()
    publicador._registrar_envio_corretor(FakeConn([cur2]), "4946", "5592", None)
    assert cur2.execucoes[0][1][2] is None
    print("OK\n")


def teste_listar_vagas():
    print("--- listar_vagas ---")
    vagas = [
        {"id": 1, "horario": datetime.time(9, 0), "tipo_recorrencia": "semanal",
         "dias_semana": [2, 4], "data_unica": None, "codigos": ["5750"]},
        {"id": 2, "horario": datetime.time(14, 0), "tipo_recorrencia": "diaria",
         "dias_semana": None, "data_unica": None, "codigos": []},
    ]
    cursor_select = FakeCursor(fetchall_resultado=vagas)
    conn = FakeConn([cursor_select])

    resposta = publicador.processar_comando("VAGAS", conexao=conn)
    print(resposta)

    assert "terça e quinta às 9h: 5750" in resposta
    assert "todo dia às 14h: vaga livre" in resposta
    print("OK\n")


def teste_nao_reconhecido_nao_toca_no_banco():
    print("--- nao_reconhecido: não pode abrir conexão nenhuma ---")
    with patch("publicador.db.conectar", side_effect=_sem_conexao_real):
        resposta = publicador.processar_comando("oi, tudo bem?")
    print(resposta)
    assert "Não entendi" in resposta
    print("OK\n")


if __name__ == "__main__":
    teste_postar_agora()
    teste_postar_agora_aviso_area_zero()
    teste_postar_agora_aviso_vagas_zero()
    teste_postar_agora_falha_no_envio_nao_derruba_a_chamada()
    teste_postar_agora_falha_parcial_no_envio_conta_grupos_reais()
    teste_postar_easy_sucesso()
    teste_postar_easy_falha_no_envio_nao_derruba_a_chamada()
    teste_postar_easy_falha_parcial_conta_grupos_inteiros()
    teste_postar_easy_ja_postado()
    teste_postar_easy_concorrencia_real()
    teste_criar_vaga_diaria()
    teste_criar_vaga_semanal()
    teste_liberar_vaga_fica_vazia()
    teste_liberar_vaga_continua_ativa()
    teste_remover_da_grade()
    teste_remover_da_grade_esvazia_vaga()
    teste_remover_da_grade_codigo_ausente_nao_escreve()
    teste_vendeu_tira_da_oferta_e_tira_nao()
    teste_id_da_mensagem()
    teste_registra_o_id_do_card()
    teste_listar_vagas()
    teste_nao_reconhecido_nao_toca_no_banco()
    print("TODOS OS TESTES DE ROTEAMENTO PASSARAM")
