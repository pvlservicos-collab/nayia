"""
Prova que o publicador guarda o id de cada FOTO que manda (migração 287).

O QUE ACONTECEU (03/10): o Osmar marcou uma mensagem nossa do grupo, escreveu
"Bom dia Colega", e a Nay não soube de que imóvel era. `envios` guarda só o id
do TEXTO do card; a foto (a metadinha, ou todas as fotos no grupo de anunciar)
saía sem registro. Medido: de 2 a 5 marcações por dia apontam para mensagem
nossa que não estava em lugar nenhum.

O QUE IMPORTA PROVAR:

  * UMA LINHA POR FOTO em `envios_foto`, com o código, o destino e o grupo. É
    por esse id que `nay_imovel_da_citacao` e a Nay nova acham o imóvel.

  * `envios` NÃO GANHA LINHA A MAIS. Ela é contada (posts da agenda, métricas,
    um imóvel por corretor por dia): uma linha por foto multiplicaria tudo.

  * SEM FOTO, SEM ID OU COM O BANCO FORA, O ENVIO NÃO CAI. A mensagem já saiu
    quando o registro roda.

Uso:
    .venv/bin/python teste_foto_do_post_guarda_o_id.py
"""
from publicador import _registrar_fotos

falhas = 0


def checar(titulo, obtido, esperado):
    global falhas
    ok = obtido == esperado
    falhas += 0 if ok else 1
    print(f"  {'OK  ' if ok else 'FALHOU'} {titulo}")
    if not ok:
        print(f"         esperava {esperado!r}, veio {obtido!r}")


class CursorFake:
    def __init__(self, conn):
        self.conn = conn

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def execute(self, sql, params=None):
        self.conn.sqls.append(" ".join(sql.split()))

    def executemany(self, sql, linhas):
        if self.conn.quebrado:
            raise RuntimeError("banco fora")
        self.conn.sqls.append(" ".join(sql.split()))
        self.conn.linhas.extend(linhas)


class ConnFake:
    def __init__(self, quebrado=False):
        self.sqls, self.linhas, self.quebrado = [], [], quebrado
        self.commits = self.rollbacks = 0

    def cursor(self):
        return CursorFake(self)

    def commit(self):
        self.commits += 1

    def rollback(self):
        self.rollbacks += 1


RESULTADO = {"texto": {"messageId": "TEXTO1"},
             "fotos": [{"messageId": "FOTO1"}, {"id": "FOTO2"}, {}, None, {"zaapId": "FOTO3"}]}

print("  post num grupo")
conn = ConnFake()
_registrar_fotos(conn, "2944", "grupo", "120363@g.us", "Corretores Parceiros", RESULTADO)
checar("uma linha por foto que tem id (as sem id ficam de fora)",
       conn.linhas, [("FOTO1", 2944, "grupo", "120363@g.us", "Corretores Parceiros"),
                     ("FOTO2", 2944, "grupo", "120363@g.us", "Corretores Parceiros"),
                     ("FOTO3", 2944, "grupo", "120363@g.us", "Corretores Parceiros")])
checar("vai para envios_foto", all("INTO envios_foto" in s for s in conn.sqls) and len(conn.sqls) == 1, True)
checar("e nunca para `envios` (que é contada)", any("INTO envios " in s for s in conn.sqls), False)
checar("o id do TEXTO não entra aqui (ele já está em `envios`)", "TEXTO1" in [l[0] for l in conn.linhas], False)
checar("gravou", conn.commits, 1)

print("\n  envio direto ao corretor")
conn = ConnFake()
_registrar_fotos(conn, 5733, "corretor", "5592999990000", None, {"texto": {}, "fotos": [{"messageId": "F9"}]})
checar("guarda com o telefone e sem grupo", conn.linhas, [("F9", 5733, "corretor", "5592999990000", None)])

print("\n  nada disso derruba o envio")
for titulo, args in (
        ("sem foto", ("2944", "grupo", "g", "G", {"texto": {"messageId": "T"}, "fotos": []})),
        ("sem resultado", ("2944", "grupo", "g", "G", None)),
        ("fotos sem id", ("2944", "grupo", "g", "G", {"fotos": [{}, None]})),
        ("código que não é número", ("lista", "grupo", "g", "G", RESULTADO))):
    conn = ConnFake()
    _registrar_fotos(conn, *args)
    checar(f"{titulo}: não escreve nada", (conn.linhas, conn.sqls), ([], []))
_registrar_fotos(None, "2944", "grupo", "g", "G", RESULTADO)
checar("sem conexão: não levanta erro", True, True)
conn = ConnFake(quebrado=True)
_registrar_fotos(conn, "2944", "grupo", "g", "G", RESULTADO)
checar("banco fora: desfaz e segue, sem levantar erro", (conn.rollbacks, conn.commits), (1, 0))

print()
if falhas:
    print(f"{falhas} CASOS FALHARAM")
    raise SystemExit(1)
print("TODOS OS CASOS DO ID DA FOTO PASSARAM")
