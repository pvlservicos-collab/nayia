"""
Testa disparar_grade.py: decide o que disparar agora (reaproveitando
vagas_para_disparar de agendador.py, já testado à parte) e executa via
_postar_codigo (publicador.py -- a mesma função que
processar_comando("posta ...") usa por código). Nenhuma chamada real ao
Postgres, ao site da Imob Easy nem à Z-API.

Uso:
    .venv/bin/python teste_disparar_grade.py
"""
import datetime
from unittest.mock import Mock, patch

import disparar_grade


class FakeCursor:
    def __init__(self, fetchall_resultado=None):
        self.fetchall_resultado = fetchall_resultado or []

    def execute(self, query, params=None):
        pass

    def fetchall(self):
        return self.fetchall_resultado

    def __enter__(self):
        return self

    def __exit__(self, *exc_info):
        return False


class FakeConn:
    def __init__(self, vagas):
        self._cursor = FakeCursor(fetchall_resultado=vagas)
        self.fechada = False

    def cursor(self):
        return self._cursor

    def close(self):
        self.fechada = True


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

TEL = "5592999999999"
AGORA = datetime.datetime(2026, 8, 25, 14, 0)  # terça, 25/08/2026


def _vaga(id_, horario, codigos, tipo="diaria", dias_semana=None, data_unica=None,
          categoria=None, negocio=None, destino=None):
    return {
        "id": id_, "horario": horario, "tipo_recorrencia": tipo,
        "dias_semana": dias_semana, "data_unica": data_unica, "codigos": codigos,
        "categoria": categoria, "negocio": negocio, "destino": destino,
    }


def teste_vaga_dispara_e_confirma():
    print("--- vaga no horário certo: dispara e manda confirmação ---")
    vaga = _vaga(1, datetime.time(14, 0), ["5644"])
    conn = FakeConn([vaga])
    confirmacoes = []

    with patch("disparar_grade.carregar_grupos_db", return_value=[GRUPO_FAKE]), \
         patch("publicador.buscar_imovel", return_value=IMOVEL_FAKE), \
         patch("publicador.enviar_imovel"), \
         patch("disparar_grade.enviar_texto",
               side_effect=lambda destino, texto: confirmacoes.append((destino, texto))):
        disparar_grade.disparar_grade(conexao=conn, agora=AGORA, tel_whatsapp=TEL)

    assert len(confirmacoes) == 1, f"esperava 1 confirmação, teve {len(confirmacoes)}"
    destino, texto = confirmacoes[0]
    print(texto)
    assert destino == TEL
    assert "todo dia às 14h" in texto
    assert "5644" in texto and "1 grupo(s)" in texto
    assert "FALHOU" not in texto
    print("OK\n")


def teste_vaga_de_lista_dispara_pelo_mesmo_caminho_do_comando():
    print("--- vaga de LISTA: dispara a lista, não imóvel ---")
    # Pedido do Tel em 10/09: "preciso disparar a lista de imóveis todo dia".
    # A vaga de lista tem `codigos` vazio -- antes disso ela seria uma "vaga
    # livre" que não faz nada.
    vaga = _vaga(12, datetime.time(14, 0), [], categoria="apartamento",
                 negocio="locacao", destino="parceiros")
    conn = FakeConn([vaga])
    confirmacoes = []
    chamadas = []

    def _lista_falsa(comando, conexao):
        chamadas.append(comando)
        return "lista de 18 imóvel(is) enviada em 13 grupo(s): A, B."

    with patch("disparar_grade.carregar_grupos_db", return_value=[GRUPO_FAKE]), \
         patch("disparar_grade._disparar_lista", side_effect=_lista_falsa), \
         patch("disparar_grade._postar_codigo") as postar, \
         patch("disparar_grade.enviar_texto",
               side_effect=lambda d, t: confirmacoes.append((d, t))):
        disparar_grade.disparar_grade(conexao=conn, agora=AGORA, tel_whatsapp=TEL)

    # É o MESMO caminho do comando na mão -- inclusive a trava de repetição, o
    # corte por aceita_locacao e a quebra em pedaços. Montar a mensagem num
    # segundo lugar faria os dois divergirem.
    assert chamadas == [{"categoria": "apartamento", "negocio": "locacao",
                         "destino": "parceiros", "texto_fixo": None}], chamadas
    assert not postar.called, "vaga de lista não posta imóvel"

    # A LISTA ESCRITA À MÃO NO SITE (03/10): o texto da vaga viaja no comando.
    # Sem isto a edição feita na agenda ficaria só no banco e sairia a lista
    # montada na hora.
    chamadas.clear()
    escrita = dict(vaga, texto_fixo="🔥 MINHA LISTA 🔥\n\n✅Conquista cod 5724 / 2.6k")
    with patch("disparar_grade.carregar_grupos_db", return_value=[GRUPO_FAKE]), \
         patch("disparar_grade._disparar_lista", side_effect=_lista_falsa), \
         patch("disparar_grade._postar_codigo"), \
         patch("disparar_grade.enviar_texto"):
        disparar_grade.disparar_grade(conexao=FakeConn([escrita]), agora=AGORA,
                                      tel_whatsapp=TEL)
    assert [c["texto_fixo"] for c in chamadas] == [escrita["texto_fixo"]], chamadas

    assert len(confirmacoes) == 1
    destino, texto = confirmacoes[0]
    print(texto)
    assert destino == TEL
    assert "todo dia às 14h" in texto
    assert "lista de apartamento para locação nos grupos de parceiro" in texto
    assert "13 grupo(s)" in texto
    print("OK\n")



def teste_vaga_fora_do_horario_fica_em_silencio():
    print("--- vaga fora do horário: não faz nada, não manda mensagem ---")
    vaga = _vaga(1, datetime.time(9, 0), ["5644"])  # AGORA é 14h
    conn = FakeConn([vaga])

    with patch("disparar_grade.carregar_grupos_db") as mock_grupos, \
         patch("publicador.buscar_imovel") as mock_buscar, \
         patch("publicador.enviar_imovel") as mock_enviar, \
         patch("disparar_grade.enviar_texto") as mock_texto:
        disparar_grade.disparar_grade(conexao=conn, agora=AGORA, tel_whatsapp=TEL)

    mock_grupos.assert_not_called()
    mock_buscar.assert_not_called()
    mock_enviar.assert_not_called()
    mock_texto.assert_not_called()
    print("OK -- nenhuma chamada de site, envio ou mensagem\n")


def teste_vaga_vazia_no_horario_certo_fica_em_silencio():
    print("--- vaga livre (codigos=[]) no horário certo: não dispara, fica em silêncio ---")
    # caso real: VENDEU 5644 esvaziou a vaga id=1 (liberar_vaga.py). No
    # horário certo, vaga_deve_disparar (agendador.py) já filtra
    # codigos=[] antes de checar horário -- essa vaga nunca chega em
    # devidas, então disparar_grade.py nunca tenta montar confirmação
    # nenhuma pra ela.
    vaga_vazia = _vaga(1, datetime.time(14, 0), [])
    conn = FakeConn([vaga_vazia])

    with patch("disparar_grade.carregar_grupos_db") as mock_grupos, \
         patch("publicador.buscar_imovel") as mock_buscar, \
         patch("disparar_grade.enviar_texto") as mock_texto:
        disparar_grade.disparar_grade(conexao=conn, agora=AGORA, tel_whatsapp=TEL)

    mock_grupos.assert_not_called()
    mock_buscar.assert_not_called()
    mock_texto.assert_not_called()
    print("OK -- vaga vazia filtrada por vagas_para_disparar, nenhuma mensagem\n")


def teste_multiplos_codigos_um_falha():
    print("--- vaga com 2 códigos: um falha, o outro continua, falha é reportada ---")
    vaga = _vaga(1, datetime.time(14, 0), ["5644", "9999"])
    conn = FakeConn([vaga])
    confirmacoes = []

    def buscar_com_falha(codigo):
        if codigo == "9999":
            raise RuntimeError("timeout no site")
        return IMOVEL_FAKE

    with patch("disparar_grade.carregar_grupos_db", return_value=[GRUPO_FAKE]), \
         patch("publicador.buscar_imovel", side_effect=buscar_com_falha), \
         patch("publicador.enviar_imovel") as mock_enviar, \
         patch("disparar_grade.enviar_texto",
               side_effect=lambda destino, texto: confirmacoes.append((destino, texto))):
        disparar_grade.disparar_grade(conexao=conn, agora=AGORA, tel_whatsapp=TEL)

    assert len(confirmacoes) == 1, f"esperava 1 confirmação (mesmo com falha parcial), teve {len(confirmacoes)}"
    _, texto = confirmacoes[0]
    print(texto)
    assert "5644" in texto and "1 grupo(s)" in texto
    assert "9999: FALHOU -- não consegui buscar no site (timeout no site)" in texto
    assert mock_enviar.call_count == 1, "só o código que deu certo deveria ter tentado enviar"
    print("OK\n")


def teste_falha_parcial_no_envio_mostra_grupos_reais_na_confirmacao():
    print("--- vaga com falha no MEIO do envio: confirmação mostra os grupos que já receberam ---")
    grupo_1 = dict(GRUPO_FAKE, id_grupo="grupo-1")
    grupo_2 = dict(GRUPO_FAKE, id_grupo="grupo-2")
    vaga = _vaga(1, datetime.time(14, 0), ["5644"])
    conn = FakeConn([vaga])
    confirmacoes = []

    def enviar_com_falha_no_meio(destino, *a):
        if destino == "grupo-2":
            raise RuntimeError("Z-API respondeu 500")

    with patch("disparar_grade.carregar_grupos_db", return_value=[grupo_1, grupo_2]), \
         patch("publicador.buscar_imovel", return_value=IMOVEL_FAKE), \
         patch("publicador.enviar_imovel", side_effect=enviar_com_falha_no_meio), \
         patch("disparar_grade.enviar_texto",
               side_effect=lambda destino, texto: confirmacoes.append((destino, texto))):
        disparar_grade.disparar_grade(conexao=conn, agora=AGORA, tel_whatsapp=TEL)

    assert len(confirmacoes) == 1
    _, texto = confirmacoes[0]
    print(texto)
    assert "postou em 1 grupo(s) antes de falhar -- falha ao enviar (Z-API respondeu 500)" in texto
    print("OK\n")


def teste_tel_whatsapp_ausente_falha_cedo_antes_do_banco():
    print("--- TEL_WHATSAPP ausente: falha cedo, antes de consultar a tabela de vagas ---")
    conn = Mock()

    with patch("disparar_grade.os.environ.get", return_value=None):
        try:
            disparar_grade.disparar_grade(conexao=conn, agora=AGORA, tel_whatsapp=None)
            raise AssertionError("deveria ter levantado RuntimeError")
        except RuntimeError as exc:
            assert "TEL_WHATSAPP" in str(exc)

    conn.cursor.assert_not_called()
    print("OK -- levantou RuntimeError sem tocar no banco\n")


def teste_nenhuma_vaga_valida_e_silencio_total():
    print("--- nenhuma vaga válida no minuto atual: silêncio total ---")
    conn = FakeConn([])  # tabela vazia

    with patch("disparar_grade.carregar_grupos_db") as mock_grupos, \
         patch("disparar_grade.enviar_texto") as mock_texto:
        disparar_grade.disparar_grade(conexao=conn, agora=AGORA, tel_whatsapp=TEL)

    mock_grupos.assert_not_called()
    mock_texto.assert_not_called()
    assert not conn.fechada, "conexão injetada não deveria ser fechada por disparar_grade"
    print("OK\n")



def teste_vaga_com_grupos_marcados_vai_so_neles():
    print("--- 415: a vaga com grupos marcados posta só neles (o apelido pelo caminho dele) ---")
    vaga = _vaga(9, datetime.time(14, 0), ["5644"])
    vaga["grupos_ids"] = ["g-a", "g-easy"]
    grupos = [dict(GRUPO_FAKE, id_grupo="g-a", nome="A", apelido=None),
              dict(GRUPO_FAKE, id_grupo="g-b", nome="B (não marcado)", apelido=None),
              dict(GRUPO_FAKE, id_grupo="g-easy", nome="Easy", apelido="easy")]
    conn = FakeConn([vaga])
    with patch("disparar_grade.carregar_grupos_db", return_value=grupos),          patch("disparar_grade._postar_codigo", return_value={"codigo": "5644", "sucesso": True, "nome_imovel": "x",
                                                            "grupos_atingidos": 1, "avisos": []}) as postar,          patch("disparar_grade._postar_da_vaga", return_value={"codigo": "5644", "resposta": "postado no Easy"}) as pela_vaga,          patch("disparar_grade.enviar_texto"):
        disparar_grade.disparar_grade(conexao=conn, agora=AGORA, tel_whatsapp=TEL)
    assert postar.call_count == 1
    assert [g["id_grupo"] for g in postar.call_args[0][1]] == ["g-a"], "só o grupo marcado sem apelido"
    assert pela_vaga.call_count == 1 and pela_vaga.call_args[0][3] == "easy"
    print("OK")


if __name__ == "__main__":
    teste_vaga_dispara_e_confirma()
    teste_vaga_de_lista_dispara_pelo_mesmo_caminho_do_comando()
    teste_vaga_fora_do_horario_fica_em_silencio()
    teste_vaga_vazia_no_horario_certo_fica_em_silencio()
    teste_multiplos_codigos_um_falha()
    teste_falha_parcial_no_envio_mostra_grupos_reais_na_confirmacao()
    teste_tel_whatsapp_ausente_falha_cedo_antes_do_banco()
    teste_nenhuma_vaga_valida_e_silencio_total()
    teste_vaga_com_grupos_marcados_vai_so_neles()
    print("TODOS OS TESTES DE DISPARAR_GRADE PASSARAM")
