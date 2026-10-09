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


class CursorQuePeek:
    """Responde sozinho a pergunta de PARCERIA e só então consome da fila.

    POR QUE EXISTE (27/09): `_e_de_parceiro` roda ANTES da reserva, então
    passou a pedir um cursor a mais em todo caminho de postagem -- e a fila
    do `FakeConn` é posicional. Sem isto, cada teste de `_postar_easy`
    entregava à parceria o cursor que era da reserva, e a fila inteira
    andava um. É a terceira vez neste projeto que um dublê genérico responde
    à pergunta errada porque não olha a consulta; aqui ele passa a olhar.

    A resposta padrão é "não é parceiro" -- o caso de quase todo teste. Quem
    quiser provar a recusa monta o cenário direto, como
    `teste_parceria_nao_posta.py` faz.
    """

    def __init__(self, conn):
        self.conn = conn
        self.real = None
        self.parceria = False

    def _delegar(self):
        if self.real is None:
            self.real = self.conn._cursores.pop(0)
        return self.real

    def execute(self, query, params=None):
        if "e_parceiro" in query and "FROM imoveis" in query:
            self.parceria = True
            return None
        self.parceria = False
        return self._delegar().execute(query, params)

    def fetchone(self):
        if self.parceria:
            return {"p": False}
        return self._delegar().fetchone()

    def fetchall(self):
        return self._delegar().fetchall()

    def __getattr__(self, nome):
        return getattr(self._delegar(), nome)

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
        return CursorQuePeek(self)

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
        # A recusa grava a pergunta "quer postar de novo?" desde 14/09.
        if "pergunta_ao_tel" in query:
            self._resultado = None
            return
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
    # Desde 14/09 a recusa PERGUNTA se é para postar de novo, e grava a pergunta.
    cursor_pergunta = FakeCursor()
    conn = FakeConn([cursor_insert, cursor_select, cursor_pergunta])

    chamou_buscar = []
    with patch("publicador.buscar_imovel", side_effect=lambda c: chamou_buscar.append(c)), \
         patch("publicador.enviar_imovel"):
        resposta = publicador.processar_comando("publica no nosso grupo anunciar easy o 5644", conexao=conn)

    print(resposta)
    query_insert, params_insert = cursor_insert.execucoes[0]
    assert "INSERT INTO easy_publicacoes" in query_insert
    assert params_insert == ("5644",)
    assert conn.rollbacks == 1, "reserva sem sucesso deveria dar rollback, não commit"

    query_select, params_select = cursor_select.execucoes[0]
    assert "SELECT publicado_em FROM easy_publicacoes" in query_select
    assert params_select == ("5644",)

    assert not chamou_buscar, "não deveria nem tentar buscar o imóvel se já foi postado"
    assert "já foi postado no Easy em 20/08/2026" in resposta
    # A pergunta: fecha a anterior e grava esta. O único commit é o dela --
    # a reserva continua em rollback, nada foi postado.
    assert "quer que eu poste de novo" in resposta
    assert 'responde "sim"' in resposta
    consultas = [q for q, _ in cursor_pergunta.execucoes]
    assert any("UPDATE pergunta_ao_tel" in q and "trocada" in q for q in consultas)
    # O APELIDO VIAJA NA PERGUNTA (27/09). Sem ele, o "sim" postava sempre no
    # Easy -- inclusive quando a pergunta era do Alto Padrão ou do Comercial.
    assert ("repostar_easy", "5644", "easy") in [p for _, p in cursor_pergunta.execucoes]
    assert conn.commits == 1
    # nunca "Código: NNNN" -- o nó de fotos leria e mandaria o álbum
    assert "ódigo:" not in resposta
    print("OK\n")


def teste_sim_reposta_no_easy():
    """O "sim" dele à pergunta posta DE NOVO -- pelo caminho que renova a reserva."""
    print("--- responder_pergunta: 'sim' posta de novo no Easy ---")
    cur_pendencia = FakeCursor(fetchone_resultado=None)      # SELECT pendencia_rascunho + SELECT aberta
    cur_tomar = FakeCursor(fetchone_resultado={"acao": "repostar_easy", "codigo": "1885",
                                   "apelido": "easy"})
    cur_reserva = FakeCursor(fetchone_resultado={"codigo": "1885"})
    conn = FakeConn([cur_pendencia, cur_tomar, cur_reserva])
    enviados = []
    with patch("publicador.buscar_imovel", return_value=dict(IMOVEL_FAKE, codigo="1885")), \
         patch("publicador.carregar_grupos_db", return_value=[GRUPO_TODAS_FOTOS_FAKE]), \
         patch("publicador.enviar_imovel", side_effect=lambda *a: enviados.append(a)), \
         patch("publicador._registrar_publicacao"):
        resposta = publicador.processar_comando("Pode postar novamente", conexao=conn)
    print(resposta)
    q_tomar, p_tomar = cur_tomar.execucoes[0]
    assert "UPDATE pergunta_ao_tel" in q_tomar and "RETURNING" in q_tomar, \
        "a pergunta tem que ser TOMADA num update só, senão dois 'sim' postam duas vezes"
    assert p_tomar == ("sim",)
    q_res, _ = cur_reserva.execucoes[0]
    assert "ON CONFLICT (codigo) DO UPDATE" in q_res and "10 minutes" in q_res
    assert len(enviados) == 1
    assert "postado no Easy" in resposta
    print("OK\n")


def teste_nao_nao_posta():
    print("--- responder_pergunta: 'não' fecha e não posta ---")
    cur_pendencia = FakeCursor(fetchone_resultado=None)
    cur_tomar = FakeCursor(fetchone_resultado={"acao": "repostar_easy", "codigo": "1885",
                                   "apelido": "easy"})
    conn = FakeConn([cur_pendencia, cur_tomar])
    with patch("publicador.enviar_imovel", side_effect=AssertionError("não era para postar")):
        resposta = publicador.processar_comando("não precisa", conexao=conn)
    print(resposta)
    assert cur_tomar.execucoes[0][1] == ("nao",)
    assert "não postei o 1885" in resposta
    print("OK\n")


def teste_sim_sem_pergunta_nao_faz_nada():
    """Falha fechada: sem pergunta aberta dentro da janela, o 'sim' não posta."""
    print("--- responder_pergunta: 'sim' sem pergunta aberta ---")
    cur_pendencia = FakeCursor(fetchone_resultado=None)
    cur_tomar = FakeCursor(fetchone_resultado=None)   # UPDATE não achou pergunta viva
    conn = FakeConn([cur_pendencia, cur_tomar])
    with patch("publicador.enviar_imovel", side_effect=AssertionError("não era para postar")):
        resposta = publicador.processar_comando("sim", conexao=conn)
    print(resposta)
    assert "não tenho nenhuma pergunta" in resposta
    print("OK\n")


def teste_sim_com_pendencia_esperando_nao_posta():
    """O mesmo 'sim' confirma resposta de pendência -- com as duas abertas, não se adivinha."""
    print("--- responder_pergunta: pendência esperando o mesmo 'sim' ---")
    cur = FakeCursor(fetchone_resultado={"acao": "repostar_easy", "codigo": "1885",
                                   "apelido": "easy"})
    conn = FakeConn([cur])
    with patch("publicador.enviar_imovel", side_effect=AssertionError("não era para postar")):
        resposta = publicador.processar_comando("sim", conexao=conn)
    print(resposta)
    assert "posta no anunciar easy de novo o 1885" in resposta
    assert "não postei nada" in resposta
    print("OK\n")


def teste_de_novo_recente_nao_repete():
    """Dois 'sim' seguidos, ou o comando repetido: a reserva renovada há menos de 10 min recusa."""
    print("--- postar_easy de novo: menos de 10 minutos depois, não repete ---")
    cur_reserva = FakeCursor(fetchone_resultado=None)   # DO UPDATE ... WHERE < 10 min: não renovou
    cur_select = FakeCursor(fetchone_resultado={
        "publicado_em": datetime.datetime(2026, 9, 14, 19, 20, tzinfo=datetime.timezone.utc)})
    conn = FakeConn([cur_reserva, cur_select])
    with patch("publicador.enviar_imovel", side_effect=AssertionError("não era para postar")):
        resposta = publicador.processar_comando("posta no anunciar easy de novo o 1885", conexao=conn)
    print(resposta)
    assert "agora há pouco" in resposta and "não postei de novo" in resposta
    assert conn.commits == 0 and conn.rollbacks == 1
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
    # `destino` entrou em 27/09: None = grupos de sempre, como sempre foi.
    assert params == (datetime.time(14, 0), "diaria", None, None, ["5750"], None)
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
    assert params == (datetime.time(9, 0), "semanal", [2, 4], None, ["5750", "5751", "5752"], None)
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
    # O SEGUNDO cursor busca o nome e o valor de cada código. Pedido do Tel em
    # 09/09, com exemplos: `2247 acquarelle 4.6k`, `1192 casa parque dez 5k`.
    imoveis = [{"codigo": "5750", "tipo": "Apartamento",
                "condominio_nome": "Condomínio Acquarelle",
                "bairro": "Ponta Negra", "valor_venda": None,
                "valor_aluguel": 4600.0}]
    conn = FakeConn([FakeCursor(fetchall_resultado=vagas),
                     FakeCursor(fetchall_resultado=imoveis)])

    resposta = publicador.processar_comando("VAGAS", conexao=conn)
    print(resposta)

    assert "terça e quinta às 9h: 5750 acquarelle 4.6k" in resposta, resposta
    # VAGA LIVRE NÃO APARECE MAIS (Tel, 27/09): "vagas vazias porque vendeu ou
    # alugou não precisa estar na lista mostrando, eu já sei que só eu colocar
    # naquele horário". Elas não disparam nada -- eram ruído entre as que
    # disparam. A linha continua no banco: o horário segue reservado.
    assert "vaga livre" not in resposta, resposta
    assert "14h" not in resposta, resposta
    print("OK\n")


def teste_grade_so_com_vaga_livre_nao_sai_pelada():
    """Escondida a vaga livre, uma grade só delas devolvia "Grade atual:" e
    mais nada -- pareceria defeito, e ele mexeria onde não precisa."""
    print("--- grade só de vagas livres diz isso, não um cabeçalho vazio ---")
    vagas = [
        {"id": 1, "horario": datetime.time(8, 0), "tipo_recorrencia": "diaria",
         "dias_semana": None, "data_unica": None, "codigos": []},
        {"id": 2, "horario": datetime.time(14, 0), "tipo_recorrencia": "diaria",
         "dias_semana": None, "data_unica": None, "codigos": []},
    ]
    conn = FakeConn([FakeCursor(fetchall_resultado=vagas),
                     FakeCursor(fetchall_resultado=[])])
    resposta = publicador.processar_comando("VAGAS", conexao=conn)
    print(resposta)
    assert resposta == "Nenhuma vaga com imóvel ou lista agendada no momento.", resposta
    print("OK\n")


def teste_nome_curto_e_valor_na_grade():
    print("--- o nome e o valor de cada código, como o Tel escreveu ---")

    def nome(**imovel):
        return publicador._nome_curto(imovel)

    # Em condomínio, o nome do condomínio sem as palavras que todo condomínio
    # tem. "Parque" NÃO é uma delas: sem ela, "Condomínio Parque Imperial"
    # viraria "imperial", que é outro lugar.
    assert nome(condominio_nome="Condomínio Acquarelle") == "acquarelle"
    assert nome(condominio_nome="Rio Amazonas Residencial") == "rio amazonas"
    assert nome(condominio_nome="Condomínio Parque Imperial") == "parque imperial"
    assert nome(condominio_nome="Smart Tower Itapuranga") == "smart tower itapuranga"
    assert nome(condominio_nome="Morada dos Pássaros") == "morada dos pássaros"

    # Via pública é o imóvel SEM condomínio -- o mesmo critério do card do
    # disparo, medido em 10 anúncios reais.
    assert nome(tipo="Casa", bairro="Parque das Laranjeiras") == "casa parque das laranjeiras"
    assert nome(tipo="Casa", bairro="Dom Pedro") == "casa dom pedro"
    # Sem tipo no cadastro (39 imóveis estão assim), não inventa um.
    assert nome(tipo=None, bairro="Flores") == "imóvel flores"

    # 4600 -> 4.6k, 10000 -> 10k, 900000 -> 900k. Ponto e não vírgula porque
    # foi assim que ele escreveu.
    curto = publicador._valor_curto
    assert curto(4600) == "4.6k"
    assert curto(10000) == "10k"
    assert curto(3600) == "3.6k"
    assert curto(5500) == "5.5k"
    assert curto(900000) == "900k"
    # Não arredonda o aluguel de ninguém: 2750 não vira 2.8k.
    assert curto(2750) == "2.75k"
    assert curto(None) is None
    assert curto(0) is None

    # A PARTIR DO MILHÃO vira "M" (pedido do Tel em 09/09): numa lista lida de
    # relance, "2.1M" não se confunde com nada e "2100k" se confunde com
    # "210k".
    assert curto(1000000) == "1M"
    assert curto(2100000) == "2.1M"
    assert curto(1050000) == "1.05M"
    assert curto(2000000) == "2M"
    assert curto(12500000) == "12.5M"
    # A fronteira: abaixo de um milhão continua em k...
    assert curto(999000) == "999k"
    # ...mas a unidade sai do valor JÁ ARREDONDADO, senão 999.999 viraria
    # "1000k" -- tecnicamente certo e ilegível.
    assert curto(999999) == "1M"

    print("OK\n")


def teste_grade_com_os_dois_valores_e_com_codigo_desconhecido():
    print("--- imóvel com venda E locação mostra os dois; código sem cadastro sai sozinho ---")
    vagas = [{"id": 1, "horario": datetime.time(14, 0), "tipo_recorrencia": "diaria",
              "dias_semana": None, "data_unica": None,
              "codigos": ["3210", "9999"]}]
    imoveis = [{"codigo": "3210", "tipo": "Casa de condomínio",
                "condominio_nome": "Morada dos Pássaros", "bairro": "Ponta Negra",
                "valor_venda": 900000.0, "valor_aluguel": 10000.0}]
    conn = FakeConn([FakeCursor(fetchall_resultado=vagas),
                     FakeCursor(fetchall_resultado=imoveis)])
    resposta = publicador.processar_comando("VAGAS", conexao=conn)
    print(resposta)

    # Escolher um dos dois esconderia do Tel metade do que ele está disparando.
    assert "3210 morada dos pássaros 900k / 10k" in resposta, resposta
    # O 9999 não está na tabela -- sai o código e nada mais, sem nome inventado.
    # É o caso do imóvel cadastrado na última hora, que a varredura ainda não
    # trouxe.
    assert "9999" in resposta and "9999 " not in resposta.replace("9999\n", "")
    print("OK\n")


class CursorPorSQL:
    """Dublê que responde pelo SQL, não pela ORDEM.

    A primeira versão destes testes montava uma FILA de cursores e errou: o
    `_marcar_indisponivel` abre UM cursor e roda QUATRO comandos nele, então a
    fila saía de sincronia e o nome do imóvel vinha vazio -- o teste acusou
    `"alugado cod: 5712"` sem o nome. Dublê que depende da ordem interna da
    função testa a implementação, não o comportamento.
    """

    def __init__(self, conexao):
        self.c = conexao
        self.r = None
        self.linhas = []
        self.rowcount = 0

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def execute(self, sql, params=None):
        self.c.sql.append(sql)
        self.c.chamadas.append((sql, params))
        self.r, self.linhas, self.rowcount = None, [], 0
        if "UPDATE imoveis SET disponivel" in sql:
            self.r = {"codigo": "5712"} if self.c.saiu_agora else None
        elif "nay_esquecer_imovel" in sql:
            self.r = {"n": 0}
        elif "SELECT tipo, condominio_nome, bairro" in sql:
            self.r = self.c.imovel

    def fetchone(self):
        return self.r

    def fetchall(self):
        return self.linhas


class ConexaoPorSQL:
    def __init__(self, saiu_agora=True, imovel=None):
        self.saiu_agora = saiu_agora
        self.imovel = imovel
        self.sql = []
        self.chamadas = []
        self.commits = 0

    def motivo_na_fila(self):
        """A palavra que o comando gravou em `aviso_de_saida` (None = não gravou)."""
        for sql, params in self.chamadas:
            if "UPDATE aviso_de_saida SET motivo" in sql:
                return params
        return None

    def cursor(self):
        return CursorPorSQL(self)

    def commit(self):
        self.commits += 1


from decimal import Decimal

# Com os campos do aviso de 15/09. `area_util` e os valores vêm do banco como
# Decimal de propósito: sem converter, o aviso diria "49.0m2" e "2600.0".
SMART_TOWER = {"tipo": "Apartamento", "condominio_nome": "Smart Tower Itapuranga",
               "bairro": "Ponta Negra", "sol": "Nascente",
               "area_util": Decimal("49.0"), "quartos": 2, "suites": 0,
               "valor_aluguel": Decimal("2600.0"), "valor_venda": None,
               "incluso": "Taxa de Condomínio"}

AVISO_SMART_TOWER = ("🛑 smart tower itapuranga alugado\n"
                     "• Bairro: Ponta Negra\n"
                     "• apto nascente\n"
                     "• 49m2\n"
                     "• 2 quartos\n"
                     "locação: 2.600 (incluso a TX)\n"
                     "Código: 5712")

# O site fora do ar devolve dict vazio; os testes do aviso não abrem rede.
SITE_FORA = patch("publicador.buscar_imovel", return_value={})


def teste_alugado_avisa_no_easy_e_so_uma_vez():
    print("--- `5712 Alugado`: tira da grade e NÃO posta no Easy -- espera o SIM do Tel ---")
    # O Tel pediu em 09/09 o aviso automático no grupo. Em 09/10 o Pedro mudou:
    # "tira essas notificações ... no PV dele a Nay pergunta e só dispara no
    # grupo após o sim dele" (migração 334). O comando só deixa a saída na fila.
    enviados = []

    def _falso(destino, texto):
        enviados.append((destino, texto))

    conn = ConexaoPorSQL(saiu_agora=True, imovel=SMART_TOWER)
    with SITE_FORA, patch("publicador.enviar_texto", side_effect=_falso), \
         patch("publicador.carregar_grupos_db",
               return_value=[GRUPO_FAKE, GRUPO_TODAS_FOTOS_FAKE]):
        resposta = publicador.processar_comando("5712 Alugado", conexao=conn)
    print(resposta)

    assert enviados == [], f"o comando não posta mais em grupo nenhum: {enviados}"
    assert "esperando o seu SIM" in resposta and "avisei no Easy" not in resposta
    assert conn.motivo_na_fila() == ("alugado", "5712"), conn.motivo_na_fila()

    # O AVISO EM SI NÃO MUDOU: é o que o `avisar_saidas.py` chama depois do SIM.
    # Só o grupo Easy recebe, com o card resumido que o Tel pediu em 15/09,
    # palavra por palavra.
    conn = ConexaoPorSQL(saiu_agora=True, imovel=SMART_TOWER)
    with SITE_FORA, patch("publicador.enviar_texto", side_effect=_falso), \
         patch("publicador.carregar_grupos_db",
               return_value=[GRUPO_FAKE, GRUPO_TODAS_FOTOS_FAKE]):
        resposta = publicador._avisar_easy_que_saiu("5712", conn, "alugado")
    assert len(enviados) == 1, f"só o grupo Easy recebe: {enviados}"
    destino, texto = enviados[0]
    assert destino == GRUPO_TODAS_FOTOS_FAKE["id_grupo"]
    assert texto == AVISO_SMART_TOWER, texto
    assert "avisei no Easy" in resposta

    # REPETIR O COMANDO NÃO MEXE NA FILA DE NOVO. O UPDATE de `disponivel` só
    # casa uma vez (`AND coalesce(disponivel, true)`), e é ele que abre a
    # pergunta -- senão o Tel seria perguntado duas vezes do mesmo imóvel.
    enviados.clear()
    conn = ConexaoPorSQL(saiu_agora=False, imovel=SMART_TOWER)
    with SITE_FORA, patch("publicador.enviar_texto", side_effect=_falso), \
         patch("publicador.carregar_grupos_db",
               return_value=[GRUPO_FAKE, GRUPO_TODAS_FOTOS_FAKE]):
        resposta = publicador.processar_comando("5712 Alugado", conexao=conn)
    assert enviados == [], f"repetir o comando não posta: {enviados}"
    assert conn.motivo_na_fila() is None and "SIM" not in resposta, resposta
    print("OK\n")


def teste_vendido_diz_vendido_e_tira_nao_avisa():
    print("--- `5712 Vendido` diz vendido; `tira` não avisa ninguém ---")
    enviados = []

    def _falso(destino, texto):
        enviados.append((destino, texto))

    # Imóvel de rua não tem condomínio: o nome é tipo + bairro, o mesmo
    # critério do card do disparo.
    conn = ConexaoPorSQL(saiu_agora=True,
                         imovel={"tipo": "Casa", "condominio_nome": None,
                                 "bairro": "Flores",
                                 "valor_venda": Decimal("650000")})
    with SITE_FORA, patch("publicador.enviar_texto", side_effect=_falso), \
         patch("publicador.carregar_grupos_db", return_value=[GRUPO_TODAS_FOTOS_FAKE]):
        publicador.processar_comando("5712 Vendido", conexao=conn)
        assert enviados == [], "o comando não posta: a palavra vai para a fila"
        assert conn.motivo_na_fila() == ("vendido", "5712"), conn.motivo_na_fila()
        publicador._avisar_easy_que_saiu("5712", conn, "vendido")
    assert enviados[0][1] == ("🛑 casa bairro flores vendido\n"
                              "venda: 650.000\n"
                              "Código: 5712"), enviados
    print("  ", enviados[0][1])

    # `tira`/`remove` é só reorganização de horário -- não afirma que saiu do
    # mercado e NÃO pode avisar ninguém.
    enviados.clear()
    conn = ConexaoPorSQL(saiu_agora=True, imovel=SMART_TOWER)
    with SITE_FORA, patch("publicador.enviar_texto", side_effect=_falso):
        publicador.processar_comando("tira o 5712", conexao=conn)
    assert enviados == [], "tira/remove não avisa grupo nenhum"

    # E o VERBO NA FRENTE continua funcionando, com a saída na fila.
    enviados.clear()
    conn = ConexaoPorSQL(saiu_agora=True, imovel=SMART_TOWER)
    with SITE_FORA, patch("publicador.enviar_texto", side_effect=_falso), \
         patch("publicador.carregar_grupos_db", return_value=[GRUPO_TODAS_FOTOS_FAKE]):
        publicador.processar_comando("Nay ALUGOU 5712", conexao=conn)
    assert enviados == [] and conn.motivo_na_fila() == ("alugado", "5712"), (enviados, conn.motivo_na_fila())
    print("OK\n")



def teste_aviso_de_saida_le_o_site_por_cima_do_banco():
    print("--- aviso de saída: o site completa o banco, e cai no banco sem site ---")
    enviados = []

    def _falso(destino, texto):
        enviados.append((destino, texto))

    # O banco não sabe o sol nem a taxa; o anúncio ainda no ar sabe. É a mesma
    # fonte do card, então o aviso bate com o card que os corretores viram.
    so_banco = {"tipo": "Apartamento", "condominio_nome": "Condomínio Acquarelle",
                "bairro": "Ponta Negra", "sol": None, "area_util": Decimal("88.0"),
                "quartos": 3, "suites": 1, "valor_aluguel": Decimal("4600.0"),
                "valor_venda": None, "incluso": None}
    do_site = {"tipo": "Apartamento", "condominio": "Condomínio Acquarelle",
               "bairro": "Ponta Negra", "sol": "Nascente", "area": 88,
               "quartos": 3, "suites": 1, "valor_aluguel": 4600.0,
               "incluso_no_aluguel": "Água, Taxa de Gás, Taxa de Condomínio"}
    conn = ConexaoPorSQL(saiu_agora=True, imovel=so_banco)
    with patch("publicador.buscar_imovel", return_value=do_site), \
         patch("publicador.enviar_texto", side_effect=_falso), \
         patch("publicador.carregar_grupos_db", return_value=[GRUPO_TODAS_FOTOS_FAKE]):
        publicador._avisar_easy_que_saiu("5611", conn, "alugado")
    # O exemplo literal do Tel em 15/09.
    esperado = ("🛑 condomínio acquarelle alugado\n"
                "• Bairro: Ponta Negra\n"
                "• apto nascente\n"
                "• 88m2\n"
                "• 3 quartos sendo 1 suíte\n"
                "locação: 4.600 (incluso a TX)\n"
                "Código: 5611")
    assert enviados and enviados[0][1] == esperado, enviados
    print("   com o site:", enviados[0][1].split("\n")[0], "...")

    # Anúncio já fora do ar (o Tel às vezes tira do site antes): fica o banco,
    # e a metragem Decimal NÃO vira "88.0m2".
    enviados.clear()
    conn = ConexaoPorSQL(saiu_agora=True, imovel=so_banco)
    with SITE_FORA, patch("publicador.enviar_texto", side_effect=_falso), \
         patch("publicador.carregar_grupos_db", return_value=[GRUPO_TODAS_FOTOS_FAKE]):
        publicador._avisar_easy_que_saiu("5611", conn, "alugado")
    texto = enviados[0][1]
    assert "• 88m2" in texto and "88.0" not in texto, texto
    assert "locação: 4.600\n" in texto, "sem a taxa sabida, sem o (incluso a TX)"
    assert "apto" not in texto, "sem o sol, a linha 'apto nascente' não sai"

    # O site caindo com exceção também não derruba o aviso.
    enviados.clear()
    conn = ConexaoPorSQL(saiu_agora=True, imovel=so_banco)
    with patch("publicador.buscar_imovel", side_effect=RuntimeError("timeout")), \
         patch("publicador.enviar_texto", side_effect=_falso), \
         patch("publicador.carregar_grupos_db", return_value=[GRUPO_TODAS_FOTOS_FAKE]):
        publicador._avisar_easy_que_saiu("5611", conn, "alugado")
    assert enviados and enviados[0][1].startswith("🛑 condomínio acquarelle alugado")
    print("OK\n")


def teste_abertura_sem_nome_nao_usa_o_telefone():
    print("--- corretor sem nome: a abertura não chama ele de '92' ---")
    # `_resolver_corretor` devolve o número digitado quando o cadastro não tem
    # nome. A abertura saía "92, segue as opções que fiquei de te enviar".
    enviados = []
    with patch("publicador.enviar_texto", side_effect=lambda d, t: enviados.append(t)), \
         patch("publicador.buscar_imovel", return_value={}):
        publicador._mandar_os_codigos(None, "559281133331", "92 8113-3331", ["5718", "5717"])
    assert enviados and enviados[0].startswith("segue as opções"), enviados[:1]
    enviados.clear()
    with patch("publicador.enviar_texto", side_effect=lambda d, t: enviados.append(t)), \
         patch("publicador.buscar_imovel", return_value={}):
        publicador._mandar_os_codigos(None, "559281133331", "Sergio Lima", ["5718"])
    assert enviados[0].startswith("Sergio, segue o imóvel"), enviados[:1]
    print("   ", enviados[0])
    print("OK\n")


# ---------------------------------------------------------------------------
# `Nay dispara lista ...` -- a lista pronta indo para os grupos (09/09)
# ---------------------------------------------------------------------------

GRUPO_SO_VENDA = {
    "id_grupo": "so-terceiros-group", "nome": "SÓ TERCEIROS COMPRA, VEN",
    "aceita_venda": True, "aceita_locacao": False, "todas_fotos": False,
}
GRUPO_LOCACAO_2 = {
    "id_grupo": "parceiros-2-group", "nome": "Parceiros Zona Centro-Sul",
    "aceita_venda": True, "aceita_locacao": True, "todas_fotos": False,
}
TODOS_OS_GRUPOS = [GRUPO_FAKE, GRUPO_LOCACAO_2, GRUPO_SO_VENDA,
                   GRUPO_TODAS_FOTOS_FAKE]

LISTA_PRONTA = ("✅ APARTAMENTOS PARA LOCAÇÃO DE 2.5k A 4.6k\n"
                "acquarelle / 78m2 / 3 qts / 2.5k\n"
                "smart tower / 42m2 / 1 qt / 4.6k")


class CursorDeLista:
    """Responde pelo SQL, não pela ordem -- mesma lição do `CursorPorSQL`."""

    def __init__(self, conexao):
        self.c = conexao
        self.r = None

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def execute(self, sql, params=None):
        self.c.sql.append((sql, params))
        self.r = None
        if "nay_lista_de_imoveis" in sql:
            self.r = {"texto_pronto": self.c.texto, "quantos": self.c.quantos}
        elif "nay_reservar_disparo_de_lista" in sql:
            self.c.forcar_pedido = params[3]
            if self.c.ja_saiu_em is not None and not params[3]:
                self.r = {"id": None, "ja_foi_em": self.c.ja_saiu_em}
            else:
                self.r = {"id": 77, "ja_foi_em": None}

    def fetchone(self):
        return self.r

    def fetchall(self):
        return []


class ConexaoDeLista:
    def __init__(self, texto=LISTA_PRONTA, quantos=2, ja_saiu_em=None):
        self.texto = texto
        self.quantos = quantos
        self.ja_saiu_em = ja_saiu_em
        self.forcar_pedido = None
        self.sql = []
        self.commits = 0

    def cursor(self):
        return CursorDeLista(self)

    def commit(self):
        self.commits += 1

    def sql_com(self, trecho):
        return [s for s, _ in self.sql if trecho in s]


def _disparar(texto, conn, envio=None, grupos=None):
    """Roda o comando com envio e grupos simulados, e SEM pausa de verdade --
    a cadência anti-banimento são 4s por grupo, e o teste não pode dormir."""
    enviados = []

    def _falso(destino, msg):
        enviados.append((destino, msg))
        if envio:
            envio(destino, msg)

    with SITE_FORA, patch("publicador.enviar_texto", side_effect=_falso), \
         patch("publicador.carregar_grupos_db",
               return_value=grupos if grupos is not None else TODOS_OS_GRUPOS), \
         patch("publicador.time.sleep"):
        resposta = publicador.processar_comando(texto, conexao=conn)
    return resposta, enviados


def teste_dispara_lista_nos_parceiros_e_respeita_aceita_locacao():
    print("--- `Nay dispara lista de apartamento para locação` ---")
    conn = ConexaoDeLista()
    resposta, enviados = _disparar(
        "Nay dispara lista de apartamento para locação", conn)
    print(resposta)

    destinos = [d for d, _ in enviados]
    # O grupo do Easy NÃO entra no disparo de parceiros -- é o mesmo corte
    # que `montar_lista_destinos` faz para o card.
    assert GRUPO_TODAS_FOTOS_FAKE["id_grupo"] not in destinos, destinos
    # E o grupo que não aceita locação também não: a trava é o cruzamento em
    # código, não instrução de prompt.
    assert GRUPO_SO_VENDA["id_grupo"] not in destinos, destinos
    assert destinos == [GRUPO_FAKE["id_grupo"], GRUPO_LOCACAO_2["id_grupo"]], destinos

    # O texto que sai é EXATAMENTE o que o `Nay lista de ...` mostra na tela.
    assert all(msg == LISTA_PRONTA for _, msg in enviados), enviados
    assert "2 grupo(s)" in resposta and GRUPO_LOCACAO_2["nome"] in resposta
    print("OK\n")


def teste_dispara_lista_de_venda_alcanca_o_grupo_so_venda():
    print("--- lista de VENDA: o grupo só-venda entra ---")
    conn = ConexaoDeLista(quantos=3)
    resposta, enviados = _disparar(
        "Nay dispara lista de apartamento para venda", conn)
    destinos = [d for d, _ in enviados]
    assert GRUPO_SO_VENDA["id_grupo"] in destinos, destinos
    assert GRUPO_TODAS_FOTOS_FAKE["id_grupo"] not in destinos, destinos
    # E a lista pedida ao banco foi a de venda, não a de locação.
    _, params = [par for par in conn.sql if "nay_lista_de_imoveis" in par[0]][0]
    assert params == ("apartamento", "venda"), params
    print(resposta)
    print("OK\n")


def teste_dispara_lista_no_easy_vai_so_para_o_easy():
    print("--- `... no anunciar easy` vai só para o grupo de todas as fotos ---")
    conn = ConexaoDeLista()
    resposta, enviados = _disparar(
        "Nay dispara lista de sala comercial para locação no anunciar easy", conn)
    print(resposta)
    assert [d for d, _ in enviados] == [GRUPO_TODAS_FOTOS_FAKE["id_grupo"]], enviados
    print("OK\n")


def teste_dispara_sem_categoria_pergunta_e_nao_manda_nada():
    print("--- `Nay dispara lista no imóveis para anunciar easy` (sem categoria) ---")
    # A frase do Tel em 09/09 não diz QUAL lista. Adivinhar mandaria a lista
    # errada para um grupo, e postagem em grupo não desfaz.
    conn = ConexaoDeLista()
    resposta, enviados = _disparar(
        "Nay dispara lista no imóveis para anunciar easy", conn)
    print(resposta)
    assert enviados == [], enviados
    assert conn.sql == [], f"nem consultou o banco: {conn.sql}"
    assert "não disparei nada" in resposta
    for nome in ("apartamento", "casa em condomínio", "sala comercial"):
        assert nome in resposta, resposta
    print("OK\n")


def teste_lista_vazia_nao_vira_mensagem_no_grupo():
    print("--- categoria sem imóvel: não manda nada nos grupos ---")
    conn = ConexaoDeLista(texto="não tenho nenhum imóvel nessa categoria...",
                          quantos=0)
    resposta, enviados = _disparar("Nay dispara lista de lote para locação", conn)
    print(resposta)
    assert enviados == [], enviados
    assert conn.sql_com("nay_reservar_disparo_de_lista") == [], \
        "nem chega a reservar -- não há o que mandar"
    print("OK\n")


def teste_repetir_o_comando_nao_dispara_de_novo():
    print("--- repetir dentro da janela: não manda de novo ---")
    ontem = datetime.datetime(2026, 9, 9, 8, 30)
    conn = ConexaoDeLista(ja_saiu_em=ontem)
    resposta, enviados = _disparar(
        "Nay dispara lista de apartamento para locação", conn)
    print(resposta)
    assert enviados == [], f"a mesma lista não pode sair duas vezes: {enviados}"
    assert "09/09 às 08:30" in resposta, resposta
    assert "de novo" in resposta, "tem que ensinar como forçar"

    # E o escape funciona: "de novo" pede a reserva forçada e manda.
    conn = ConexaoDeLista(ja_saiu_em=ontem)
    resposta, enviados = _disparar(
        "Nay dispara lista de apartamento para locação de novo", conn)
    print(resposta)
    assert conn.forcar_pedido is True, conn.forcar_pedido
    assert len(enviados) == 2, enviados
    print("OK\n")


def teste_falha_em_todos_os_grupos_libera_a_reserva():
    print("--- falhou em TODOS: tira a reserva para ele poder tentar de novo ---")
    def _explode(destino, msg):
        raise RuntimeError("Z-API fora do ar")

    conn = ConexaoDeLista()
    resposta, _ = _disparar("Nay dispara lista de apartamento para locação",
                            conn, envio=_explode)
    print(resposta)
    assert conn.sql_com("DELETE FROM lista_disparada"), conn.sql
    assert "Nada saiu" in resposta and "pode tentar de novo" in resposta
    print("OK\n")


def teste_falha_no_meio_conta_quem_recebeu_e_avisa_para_nao_repetir():
    print("--- falhou no meio: diz quem recebeu e manda NÃO repetir ---")
    def _explode_no_segundo(destino, msg):
        if destino == GRUPO_LOCACAO_2["id_grupo"]:
            raise RuntimeError("timeout")

    conn = ConexaoDeLista()
    resposta, enviados = _disparar(
        "Nay dispara lista de apartamento para locação", conn,
        envio=_explode_no_segundo)
    print(resposta)
    # A reserva FICA (o UPDATE, não o DELETE): um grupo já recebeu, e reenviar
    # daria a lista duas vezes para ele.
    assert conn.sql_com("UPDATE lista_disparada"), conn.sql
    assert not conn.sql_com("DELETE FROM lista_disparada"), conn.sql
    assert GRUPO_FAKE["nome"] in resposta
    assert GRUPO_LOCACAO_2["nome"] not in resposta, "não recebeu, não pode constar"
    assert "NÃO reenvie" in resposta
    print("OK\n")



def teste_lista_sem_negocio_pergunta_em_vez_de_supor():
    print("--- `Nay lista de apartamentos`: pergunta, não supõe locação ---")
    # O Tel em 09/09: *"quando eu mandar assim ela tem que me perguntar se é
    # para venda ou locação, porque quando pedir para venda ela precisa mandar
    # também que vou precisar"*. Supor locação calada fazia a lista de venda
    # nunca chegar -- e ele não tinha como saber que faltava uma palavra.
    conn = ConexaoDeLista()
    resposta = publicador.processar_comando("Nay lista de apartamentos",
                                            conexao=conn)
    print(resposta)
    assert conn.sql == [], f"não pode nem consultar a lista: {conn.sql}"
    assert "LOCAÇÃO" in resposta and "VENDA" in resposta
    # As duas frases prontas, com a categoria que ele já escreveu -- a resposta
    # tem que ser copiar e colar, não outra rodada de adivinhação.
    assert '"Nay lista de apartamento para locação"' in resposta, resposta
    assert '"Nay lista de apartamento para venda"' in resposta, resposta

    # E com o negócio escrito, lista normalmente -- nas duas formas que ele usa.
    for texto in ("Nay lista de apartamentos para locação",
                  "Nay lista de apartamentos locação",
                  "Nay lista de apartamentos de aluguel"):
        conn = ConexaoDeLista()
        r = publicador.processar_comando(texto, conexao=conn)
        assert r == LISTA_PRONTA, f"{texto} -> {r}"
        assert conn.sql[0][1] == ("apartamento", "locacao"), conn.sql[0][1]
    conn = ConexaoDeLista()
    publicador.processar_comando("Nay lista de apartamentos venda", conexao=conn)
    assert conn.sql[0][1] == ("apartamento", "venda"), conn.sql[0][1]
    print("OK\n")


def teste_disparo_sem_negocio_nao_manda_nada():
    print("--- `Nay dispara lista de apartamento` sem negócio: não dispara ---")
    # Na lista de tela supor custaria uma pergunta a mais. Aqui custaria a
    # lista errada em 13 grupos, sem desfazer.
    conn = ConexaoDeLista()
    resposta, enviados = _disparar("Nay dispara lista de apartamento", conn)
    print(resposta)
    assert enviados == [], enviados
    assert conn.sql == [], f"nem consultou o banco: {conn.sql}"
    assert "não disparei nada" in resposta
    assert '"Nay dispara lista de apartamento para venda"' in resposta, resposta

    # No caminho do Easy, as duas sugestões têm que sair COM o destino, senão
    # ele copia a frase e a lista vai para os grupos de parceiro.
    conn = ConexaoDeLista()
    resposta, enviados = _disparar(
        "Nay dispara lista de sala comercial no anunciar easy", conn)
    print(resposta)
    assert enviados == []
    assert resposta.count("no anunciar easy") == 2, resposta
    print("OK\n")



def teste_lista_longa_vai_em_pedacos_sem_perder_linha():
    print("--- lista grande demais para uma mensagem: quebra em LINHA inteira ---")
    # Medido em 09/09 no catálogo real: a lista de apartamento para VENDA tem
    # 118 itens e 6.600 caracteres. Uma mensagem só estoura o limite de várias
    # rotas de WhatsApp -- e o sintoma seria o pior deste projeto: o Tel
    # escreve o comando e nada chega em grupo nenhum.
    titulo = "✅ APARTAMENTOS PARA VENDA DE 180k A 2.4M"
    itens = [f"Condomínio Exemplo {i} / 3 quartos sendo 1 suíte / {i}00k"
             for i in range(118)]
    texto = titulo + "\n" + "\n".join(itens)
    assert len(texto) > publicador.LIMITE_TEXTO_WHATSAPP

    pedacos = publicador._pedacos_da_lista(texto)
    assert len(pedacos) > 1, "tinha que quebrar"
    for p in pedacos:
        assert len(p) <= publicador.LIMITE_TEXTO_WHATSAPP, len(p)

    # Nenhum imóvel some e nenhum se parte no meio -- cortar dentro da linha
    # daria "3 quartos sendo 1" numa mensagem e "suíte / 400k" na outra.
    de_volta = [l for p in pedacos for l in p.split("\n")
                if not l.startswith("✅")]
    assert de_volta == itens, "linha perdida ou partida"

    # Quem chega no meio da rolagem precisa saber do que é a lista.
    assert pedacos[0].startswith(titulo)
    for p in pedacos[1:]:
        assert p.startswith(titulo + " (continuação)"), p[:60]

    # Lista que cabe continua sendo UMA mensagem.
    assert publicador._pedacos_da_lista("um\ndois") == ["um\ndois"]
    print(f"   {len(texto)} caracteres -> {len(pedacos)} mensagens")
    print("OK\n")


def teste_dispara_lista_longa_manda_todos_os_pedacos_em_cada_grupo():
    print("--- lista quebrada: cada grupo recebe a lista INTEIRA ---")
    titulo = "✅ APARTAMENTOS PARA VENDA DE 180k A 2.4M"
    texto = titulo + "\n" + "\n".join(
        f"Condomínio Exemplo {i} / 3 quartos sendo 1 suíte / {i}00k"
        for i in range(118))
    conn = ConexaoDeLista(texto=texto, quantos=118)
    resposta, enviados = _disparar(
        "Nay dispara lista de apartamento para venda", conn)
    print(resposta)

    pedacos = publicador._pedacos_da_lista(texto)
    por_grupo = {}
    for destino, msg in enviados:
        por_grupo.setdefault(destino, []).append(msg)

    # Três grupos aceitam venda (o do Easy fica de fora do disparo de parceiro).
    assert len(por_grupo) == 3, list(por_grupo)
    for destino, msgs in por_grupo.items():
        assert msgs == pedacos, f"{destino} não recebeu a lista inteira"
    assert f"{len(pedacos)} partes" in resposta, resposta
    print("OK\n")


def teste_lista_para_uma_pessoa_e_recusada_sem_postar():
    print("--- `manda a lista pro Sergio`: recusa, nunca dispara ---")
    # Mesma parede do `Nay posta o 5750 pro Rogério`: verbo de grupo com
    # destinatário pessoal vira recusa que ensina, nunca disparo.
    with patch("publicador.db.conectar", side_effect=_sem_conexao_real):
        resposta = publicador.processar_comando(
            "Nay envia a lista de apartamento pro Sergio")
    print(resposta)
    assert "parece uma pessoa" in resposta
    assert "não disparei" in resposta or "só sei mandar para os grupos" in resposta
    print("OK\n")



# ---------------------------------------------------------------------------
# A lista NA GRADE -- "preciso disparar a lista de imóveis todo dia" (10/09)
# ---------------------------------------------------------------------------

class CursorDeVaga:
    def __init__(self, conexao):
        self.c = conexao
        self.r = None
        self.linhas = []

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def execute(self, sql, params=None):
        self.c.sql.append((sql, params))
        self.r, self.linhas = None, []
        if sql.startswith("INSERT INTO vagas"):
            # ON CONFLICT DO NOTHING: devolve nada quando a vaga já existia.
            self.r = None if self.c.ja_existe else {"id": 12}
        elif sql.startswith("DELETE FROM vagas"):
            self.linhas = self.c.a_tirar
        elif "FROM vagas ORDER BY horario" in sql:
            self.linhas = self.c.grade

    def fetchone(self):
        return self.r

    def fetchall(self):
        return self.linhas


class ConexaoDeVaga:
    def __init__(self, ja_existe=False, a_tirar=(), grade=()):
        self.ja_existe = ja_existe
        self.a_tirar = list(a_tirar)
        self.grade = list(grade)
        self.sql = []
        self.commits = 0

    def cursor(self):
        return CursorDeVaga(self)

    def commit(self):
        self.commits += 1


def teste_agenda_a_lista_na_grade():
    print("--- `dispara apartamentos para locação todo dia às 9h` ---")
    conn = ConexaoDeVaga()
    resposta = publicador.processar_comando(
        "dispara apartamentos para locação todo dia às 9h", conexao=conn)
    print(resposta)

    sql, params = [x for x in conn.sql if x[0].startswith("INSERT INTO vagas")][0]
    assert params[1] == "diaria", params
    assert params[3:] == ("apartamento", "locacao", "parceiros"), params
    # `codigos` vazio é o que o CHECK do banco exige de uma vaga de lista.
    assert "'{}'" in sql, sql
    assert "Vaga #12" in resposta and "todo dia" in resposta
    assert "apartamento" in resposta and "locação" in resposta
    print("OK\n")


def teste_agendar_a_mesma_lista_duas_vezes_nao_duplica():
    print("--- repetir o comando não cria uma segunda vaga igual ---")
    # Ele repetiria achando que o primeiro não pegou, e os grupos receberiam a
    # lista DUAS vezes por dia, para sempre, sem ninguém notar.
    conn = ConexaoDeVaga(ja_existe=True)
    resposta = publicador.processar_comando(
        "dispara apartamentos para locação todo dia às 9h", conexao=conn)
    print(resposta)
    assert "já existia" in resposta and "Não criei outra" in resposta
    print("OK\n")


def teste_agendar_sem_negocio_pergunta_e_nao_agenda():
    print("--- agendar sem dizer venda ou locação: pergunta ---")
    # Vaga errada não erra uma vez: erra todo dia.
    conn = ConexaoDeVaga()
    resposta = publicador.processar_comando(
        "dispara apartamentos todo dia às 9h", conexao=conn)
    print(resposta)
    assert conn.sql == [], f"não pode escrever nada: {conn.sql}"
    assert "não agendei nada" in resposta
    assert "todo dia às 9h" in resposta, "a sugestão tem que manter o horário"
    print("OK\n")


def teste_tirar_a_lista_da_grade():
    print("--- `tira a lista de apartamento para locação` ---")
    # Sem o desfazer, a lista sairia todo dia para sempre.
    vaga = {"id": 12, "horario": datetime.time(9, 0),
            "tipo_recorrencia": "diaria", "dias_semana": None,
            "data_unica": None, "categoria": "apartamento",
            "negocio": "locacao", "destino": "parceiros"}
    conn = ConexaoDeVaga(a_tirar=[vaga])
    resposta = publicador.processar_comando(
        "tira a lista de apartamento para locação", conexao=conn)
    print(resposta)
    sql, params = [x for x in conn.sql if x[0].startswith("DELETE FROM vagas")][0]
    assert params[0] == "apartamento" and params[1] == "parceiros", params
    assert "Tirei da grade" in resposta and "todo dia" in resposta

    # Nada agendado: diz isso, não finge que tirou.
    conn = ConexaoDeVaga(a_tirar=[])
    resposta = publicador.processar_comando(
        "tira a lista de lote para venda", conexao=conn)
    print(resposta)
    assert "não havia lista de lote" in resposta
    print("OK\n")


def teste_vagas_mostra_a_lista_agendada():
    print("--- `Nay VAGAS` mostra a lista, não 'vaga livre' ---")
    # Sem este ramo a vaga de lista apareceria como "vaga livre" -- ela não tem
    # código -- e ele acharia que não havia nada agendado ali.
    grade = [
        {"id": 12, "horario": datetime.time(9, 0), "tipo_recorrencia": "diaria",
         "dias_semana": None, "data_unica": None, "codigos": [],
         "categoria": "apartamento", "negocio": "locacao", "destino": "parceiros"},
        {"id": 13, "horario": datetime.time(7, 0), "tipo_recorrencia": "diaria",
         "dias_semana": None, "data_unica": None, "codigos": [],
         "categoria": "sala", "negocio": "venda", "destino": "easy"},
        {"id": 1, "horario": datetime.time(14, 0), "tipo_recorrencia": "diaria",
         "dias_semana": None, "data_unica": None, "codigos": [],
         "categoria": None, "negocio": None, "destino": None},
    ]
    conn = ConexaoDeVaga(grade=grade)
    with patch("publicador._resumo_dos_codigos", return_value={}):
        resposta = publicador.processar_comando("Nay VAGAS", conexao=conn)
    print(resposta)
    assert "lista de apartamento para locação nos grupos de parceiro" in resposta
    assert "lista de sala comercial para venda no anunciar easy" in resposta
    # A VAGA DE IMÓVEL SEM CÓDIGO SOME (Tel, 27/09) -- mas a de LISTA, que
    # também não tem código, TEM que continuar aparecendo. As duas se parecem
    # na tabela e só o `categoria` as separa; esconder a errada faria ele
    # achar que a lista diária não estava agendada.
    assert "vaga livre" not in resposta, resposta
    assert "14h" not in resposta, resposta
    print("OK\n")


def teste_nao_reconhecido_nao_toca_no_banco():
    print("--- nao_reconhecido: não pode abrir conexão nenhuma ---")
    with patch("publicador.db.conectar", side_effect=_sem_conexao_real):
        resposta = publicador.processar_comando("oi, tudo bem?")
    print(resposta)
    assert "Não entendi" in resposta
    print("OK\n")



def teste_avisa_quando_a_taxa_nao_esta_marcada():
    """O card sai sem "(incluso a tx)" porque o DADO falta, não a regra.

    O Tel reclamou em 14/09 que o 5718 saiu sem o sufixo. A regra funcionava --
    provado no 3714, que tem a marca e sai com ele. Medido no mesmo dia: 50 dos
    85 imóveis de locação no mercado não têm NENHUMA informação de taxa, e o
    site não publica o campo em lugar nenhum.

    O aviso fecha o laço: ele já recebe a confirmação a cada disparo, e a frase
    traz o comando pronto. Uma linha por disparo enche a lacuna com o tempo,
    em vez de exigir que ele repasse 50 imóveis de uma vez.
    """
    print("--- aviso da taxa não marcada ---")
    base = dict(codigo="5718", area=54, vagas=1, valor_aluguel=2500)

    avisos = publicador._avisos_dados_incompletos(base)
    assert any("incluso a tx" in a for a in avisos), avisos
    assert any("5718 incluso a tx" in a for a in avisos), "falta o comando pronto"
    print(f"  avisa: {avisos[0][:88]}...")

    # Marcada como inclusa: a informação existe, cobrar seria ruído.
    assert not publicador._avisos_dados_incompletos(
        dict(base, incluso_no_aluguel="Taxa de Condomínio"))
    # Taxa POR FORA com valor também é informação.
    assert not publicador._avisos_dados_incompletos(
        dict(base, taxa_condominio=850))
    # E imóvel só de venda não tem taxa de aluguel para marcar.
    assert not publicador._avisos_dados_incompletos(
        dict(codigo="2539", area=54, vagas=1, valor_venda=450000))
    print("  não avisa quando já se sabe, nem em imóvel só de venda")
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
    teste_sim_reposta_no_easy()
    teste_nao_nao_posta()
    teste_sim_sem_pergunta_nao_faz_nada()
    teste_sim_com_pendencia_esperando_nao_posta()
    teste_de_novo_recente_nao_repete()
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
    teste_grade_so_com_vaga_livre_nao_sai_pelada()
    teste_nome_curto_e_valor_na_grade()
    teste_grade_com_os_dois_valores_e_com_codigo_desconhecido()
    teste_alugado_avisa_no_easy_e_so_uma_vez()
    teste_vendido_diz_vendido_e_tira_nao_avisa()
    teste_aviso_de_saida_le_o_site_por_cima_do_banco()
    teste_abertura_sem_nome_nao_usa_o_telefone()
    teste_dispara_lista_nos_parceiros_e_respeita_aceita_locacao()
    teste_dispara_lista_de_venda_alcanca_o_grupo_so_venda()
    teste_dispara_lista_no_easy_vai_so_para_o_easy()
    teste_dispara_sem_categoria_pergunta_e_nao_manda_nada()
    teste_lista_vazia_nao_vira_mensagem_no_grupo()
    teste_repetir_o_comando_nao_dispara_de_novo()
    teste_falha_em_todos_os_grupos_libera_a_reserva()
    teste_falha_no_meio_conta_quem_recebeu_e_avisa_para_nao_repetir()
    teste_lista_sem_negocio_pergunta_em_vez_de_supor()
    teste_disparo_sem_negocio_nao_manda_nada()
    teste_lista_longa_vai_em_pedacos_sem_perder_linha()
    teste_dispara_lista_longa_manda_todos_os_pedacos_em_cada_grupo()
    teste_lista_para_uma_pessoa_e_recusada_sem_postar()
    teste_agenda_a_lista_na_grade()
    teste_agendar_a_mesma_lista_duas_vezes_nao_duplica()
    teste_agendar_sem_negocio_pergunta_e_nao_agenda()
    teste_tirar_a_lista_da_grade()
    teste_vagas_mostra_a_lista_agendada()
    teste_nao_reconhecido_nao_toca_no_banco()
    teste_avisa_quando_a_taxa_nao_esta_marcada()
    print("TODOS OS TESTES DE ROTEAMENTO PASSARAM")
