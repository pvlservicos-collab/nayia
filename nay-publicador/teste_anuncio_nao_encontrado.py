"""
Código que não existe no site NÃO vira card (14/09).

O CASO: o Tel mandou "Posta no grupo anunciar easy 2944". O 2944 não existe:
`/anuncios/2944` redireciona para `/nao-encontrado`, que responde 200. A Nay
postou no grupo "📍 Imóvel 2944 / Código: 2944" e respondeu a ele "2944 (2944)
postado no Easy, com todas as fotos" -- e o código ficou marcado como postado.

O QUE IMPORTA PROVAR, e o que cada coisa custa se quebrar:

  * a página de 404 do site é lida como "não achei" -- senão o card vazio sai;
  * o Easy não envia nada e DESFAZ a reserva -- senão o próximo pedido, com o
    anúncio já no ar, cai em "já foi postado";
  * no "de novo", a data que volta é a ANTERIOR -- apagar a linha faria o
    próximo pedido postar sem perguntar;
  * site fora do ar também desfaz: nada saiu;
  * grupos de parceiro e entrega a corretor recusam pelo mesmo motivo;
  * ao publicar, o Tel é AVISADO que o anúncio deve estar arquivado, para
    consertar no site -- o 2944 estava, e ele só soube pelo card vazio;
  * a resposta ao Tel nunca traz "Código: NNNN", que o nó de fotos leria.

Uso:
    .venv/bin/python teste_anuncio_nao_encontrado.py
"""
import datetime
from unittest.mock import patch

import entregar_pendentes as ep
import publicador
from buscar_imovel import anuncio_encontrado, extrair_imovel

falhas = 0


def checar(titulo, condicao, detalhe=""):
    global falhas
    falhas += 0 if condicao else 1
    print(f"  {'OK  ' if condicao else 'FALHOU'} {titulo}")
    if not condicao and detalhe:
        print(f"         {detalhe}")


# O corpo da página /nao-encontrado, como o site devolveu para o 2944.
PAGINA_404 = """
<html><head><title>Imob Easy</title></head><body>
<div class="container"><h1>404</h1><h2>Não encontrado!</h2>
<p>A página que você tentou acessar não existe.</p><a href="/">Voltar</a></div>
</body></html>
"""

IMOVEL_NO_AR = {
    "codigo": "5738", "tipo": "Apartamento", "condominio": "Estilo Ponta Negra",
    "valor_venda": 499999.0, "valor_aluguel": None, "fotos": ["https://x/1.jpg"],
}

GRUPO_EASY = {
    "id_grupo": "120363296035090852-group", "nome": "IMÓVEIS PARA ANUNCIAR EASY",
    "aceita_venda": True, "aceita_locacao": True, "todas_fotos": True,
}


class Conexao:
    """Grava cada comando SQL e responde à reserva com o que o teste mandar."""

    def __init__(self, reserva):
        self.reserva = reserva
        self.comandos = []
        self.commits = 0

    def cursor(self):
        return Cursor(self)

    def commit(self):
        self.commits += 1

    def rollback(self):
        pass


class Cursor:
    def __init__(self, conexao):
        self.conexao = conexao
        self.resultado = None

    def execute(self, sql, params=None):
        self.conexao.comandos.append((sql, params))
        self.resultado = self.conexao.reserva if "INSERT INTO easy_publicacoes" in sql else None

    def fetchone(self):
        return self.resultado

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


def comandos_com(conexao, trecho):
    return [(s, p) for s, p in conexao.comandos if trecho in s]


print("--- a página de 404 do site ---")
vazio = extrair_imovel(PAGINA_404, "2944")
checar("404 do site: não achei", anuncio_encontrado(vazio) is False)
checar("dict vazio e None: não achei",
       not anuncio_encontrado({"codigo": "4"}) and not anuncio_encontrado(None))
checar("anúncio no ar: achei", anuncio_encontrado(IMOVEL_NO_AR) is True)
# O complemento do banco preenche mobília e sol de imóvel que saiu do site --
# isso não pode fazer o anúncio "existir".
checar("mobília e sol vindos do banco não bastam",
       not anuncio_encontrado(dict(vazio, mobilia="mobiliado", sol="Nascente")))

print("--- Easy: o pedido do 2944 ---")
conexao = Conexao(reserva={"codigo": "2944"})
enviados = []
with patch("publicador.buscar_imovel", return_value=vazio), \
     patch("publicador.carregar_grupos_db", return_value=[GRUPO_EASY]), \
     patch("publicador.enviar_imovel", side_effect=lambda *a: enviados.append(a)), \
     patch("publicador._registrar_publicacao"):
    resposta = publicador.processar_comando("Posta no grupo anunciar easy 2944", conexao=conexao)
print(f"         resposta: {resposta}")
checar("nada foi ao grupo", enviados == [], f"enviou {enviados}")
# O Tel pediu (14/09): avisar que o anúncio está arquivado, para ele
# consertar no site. A página não separa arquivado de inexistente -- a frase
# diz o provável e o que fazer.
checar("avisa: fora do ar, deve estar arquivado, não postou, publica e pede de novo",
       resposta == "⚠️ 2944: o anúncio não está no ar no site -- deve estar arquivado. "
                   "não postei nada no Easy. publica no site e me pede de novo.", resposta)
checar("não diz 'postado no Easy'", "postado no Easy" not in resposta)
checar("não traz 'Código: NNNN'", "ódigo:" not in resposta)
desfeitos = comandos_com(conexao, "DELETE FROM easy_publicacoes")
checar("a reserva nova é apagada", desfeitos and desfeitos[0][1] == ("2944",), desfeitos)
checar("e o desfazer é commitado (reserva + desfazer)", conexao.commits == 2,
       f"commits={conexao.commits}")

print("--- Easy de novo: volta a data anterior ---")
em_01_09 = datetime.datetime(2026, 9, 1, 10, 0, tzinfo=datetime.timezone.utc)
conexao = Conexao(reserva={"codigo": "1885", "antes": em_01_09})
enviados = []
with patch("publicador.buscar_imovel", return_value=dict(vazio, codigo="1885")), \
     patch("publicador.enviar_imovel", side_effect=lambda *a: enviados.append(a)):
    resposta = publicador._postar_easy("1885", conexao, de_novo=True)
reserva = comandos_com(conexao, "INSERT INTO easy_publicacoes")
checar("a reserva do 'de novo' lê a data anterior no mesmo comando",
       reserva and "anterior" in reserva[0][0] and reserva[0][1] == ("1885", "1885"), reserva)
voltou = comandos_com(conexao, "UPDATE easy_publicacoes SET publicado_em")
checar("a data de 01/09 volta", voltou and voltou[0][1] == (em_01_09, "1885"), voltou)
checar("a linha NÃO é apagada", not comandos_com(conexao, "DELETE FROM easy_publicacoes"))
checar("nada foi ao grupo", enviados == [])

print("--- Easy com o site fora do ar ---")
conexao = Conexao(reserva={"codigo": "5738"})
with patch("publicador.buscar_imovel", side_effect=ConnectionError("timeout")), \
     patch("publicador.enviar_imovel") as enviar:
    resposta = publicador._postar_easy("5738", conexao)
checar("desfaz a reserva", bool(comandos_com(conexao, "DELETE FROM easy_publicacoes")))
checar("diz que não postou", "não postei nada" in resposta and not enviar.called, resposta)

print("--- Easy com o anúncio no ar continua postando ---")
conexao = Conexao(reserva={"codigo": "5738"})
enviados = []
with patch("publicador.buscar_imovel", return_value=IMOVEL_NO_AR), \
     patch("publicador.carregar_grupos_db", return_value=[GRUPO_EASY]), \
     patch("publicador.enviar_imovel", side_effect=lambda *a: enviados.append(a)), \
     patch("publicador._registrar_publicacao"):
    resposta = publicador._postar_easy("5738", conexao)
checar("postou", len(enviados) == 1 and "postado no Easy" in resposta, resposta)
checar("e a reserva fica", not comandos_com(conexao, "DELETE FROM easy_publicacoes"))

print("--- grupos de parceiro ---")
with patch("publicador.buscar_imovel", return_value=vazio), \
     patch("publicador.enviar_imovel") as enviar:
    resultado = publicador._postar_codigo("2944", [GRUPO_EASY], conn=None)
checar("recusa avisando que está fora do ar (não 'sem valor')",
       "deve estar arquivado" in resultado["erro"] and not resultado["sucesso"], resultado)
checar("nada foi aos grupos", not enviar.called)
with patch("publicador.buscar_imovel", return_value=vazio), \
     patch("publicador.carregar_grupos_db", return_value=[GRUPO_EASY]), \
     patch("publicador.enviar_imovel") as enviar:
    relato = publicador._postar_agora(["2944"], conn=None)
print(f"         relato: {relato!r}")
checar("o relato ao Tel traz o código uma vez só",
       relato.count("2944") == 1 and "2944: ⚠️ o anúncio não está no ar" in relato, relato)

print("--- entrega a corretor ---")


class ConexaoEntrega:
    def __init__(self):
        self.comandos = []

    def cursor(self):
        conexao = self

        class C:
            def execute(self, sql, params=None):
                conexao.comandos.append((sql, params))

            def fetchone(self):
                return {"n": 1}

            def fetchall(self):
                return [{"telefone": "559286034966", "ids": [1, 2], "codigos": "2944,5738",
                         "abertura": "segue o que fiquei de te enviar 👇"}]

            def __enter__(self):
                return self

            def __exit__(self, *a):
                return False
        return C()

    def commit(self):
        pass


cards = []
agora = datetime.datetime(2026, 9, 15, 10, 0, tzinfo=ep.FUSO_MANAUS)
with patch.object(ep, "buscar_imovel", lambda c: vazio if c == "2944" else IMOVEL_NO_AR), \
     patch.object(ep, "atendimento_pausado", lambda c: False), \
     patch.object(ep, "dentro_do_horario", lambda a: True), \
     patch.object(ep, "enviar_texto", lambda *a: None), \
     patch.object(ep, "montar_mensagem", lambda im, neg: "card do " + im["codigo"]), \
     patch.object(ep, "enviar_imovel", lambda tel, msg, fotos: cards.append(msg)):
    ep.entregar(ConexaoEntrega(), enviar=True, agora=agora)
checar("o 2944 não vai; o 5738 vai", cards == ["card do 5738"], cards)

print()
if falhas:
    print(f"{falhas} FALHARAM")
    raise SystemExit(1)
print("TODOS OS TESTES PASSARAM")
