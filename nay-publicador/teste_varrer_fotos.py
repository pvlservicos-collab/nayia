"""
Prova a CONFERÊNCIA das fotos que já existem na tabela.

O QUE O TEL VIU (28/09): "Código: 964, na hora de disparar ainda está com as
fotos antigas". Conferido: o site tinha 4 fotos (de 25/09) e a tabela guardava
5, de uma carga bem mais velha. Quem lê a TABELA -- a resposta da Nay sobre
imagem -- mandava as antigas.

A CAUSA: `sem_fotos` só olha imóvel com ZERO foto. Uma vez que o imóvel ganha
qualquer foto, nunca mais é visitado, e trocar as fotos no admin não chegava ao
banco. É o MESMO padrão da mobília e dos lances de escada, achados no mesmo
dia: preenchedor que só preenche vazio e nunca atualiza.

O QUE IMPORTA PROVAR, e o que cada coisa custa se quebrar:

  * IGUAIS NÃO TROCAM, mas CARIMBAM. Sem o carimbo o rodízio voltaria sempre
    aos mesmos e o resto do catálogo nunca seria conferido.

  * ANÚNCIO SEM FOTO NÃO APAGA AS QUE TEMOS. Página que não abriu, ou servida
    pela metade, devolve lista vazia -- e o imóvel iria ao disparo SEM FOTO
    NENHUMA. É a armadilha do dict truthy, de novo.

  * APAGA E REGRAVA numa transação só: a ordem importa (a primeira é a capa), e
    troca parcial deixaria metade novas e metade velhas -- pior que os dois.

  * Falha isolada e pausa entre leituras (regras 5 do projeto).

Uso:
    .venv/bin/python teste_varrer_fotos.py
"""
from varrer_fotos import conferir, trocar, _fotos_do_banco

falhas = 0


def checar(titulo, obtido, esperado):
    global falhas
    ok = obtido == esperado
    falhas += 0 if ok else 1
    print(f"  {'OK  ' if ok else 'FALHOU'} {titulo}")
    if not ok:
        print(f"         esperava {esperado!r}, veio {obtido!r}")


print()
print("--- a CONFERÊNCIA das fotos que já existem (Tel, 28/09) ---")
# "Código: 964, na hora de disparar ainda está com as fotos antigas."
# Conferido: o site tinha 4 fotos de 25/09 e a tabela guardava 5, de uma carga
# bem mais velha.
#
# A CAUSA: `sem_fotos` só olha quem tem ZERO foto. Uma vez que o imóvel ganha
# qualquer foto, nunca mais é visitado -- trocar as fotos no admin não chegava
# ao banco. É o MESMO padrão da mobília e dos lances de escada, achados no
# mesmo dia: preenchedor que só preenche vazio e nunca atualiza.


class ConnFotos:
    def __init__(self, fotos, fila):
        self.fotos = {c: list(u) for c, u in fotos.items()}
        self.fila = list(fila)
        self.carimbados = []
        self.apagados = []

    def cursor(self):
        conn = self

        class C:
            def __enter__(s):
                return s

            def __exit__(s, *a):
                return False

            def execute(s, sql, params=None):
                if "fotos_conferidas_em = now()" in sql:
                    conn.carimbados.append(params[0]); s.r = []
                elif "DELETE FROM imovel_fotos" in sql:
                    conn.apagados.append(params[0])
                    conn.fotos[params[0]] = []; s.r = []
                elif "INSERT INTO imovel_fotos" in sql:
                    conn.fotos.setdefault(params[0], []).append(params[2]); s.r = []
                elif "FROM imovel_fotos" in sql:
                    s.r = [{"url": u} for u in conn.fotos.get(params[0], [])]
                elif "FROM imoveis i" in sql:
                    s.r = [{"codigo": c} for c in conn.fila]
                else:
                    s.r = []

            def fetchall(s):
                return s.r
        return C()

    def commit(self):
        pass


print("  o caso do 964: site com 4, banco com 5")
conn = ConnFotos({964: ["v1", "v2", "v3", "v4", "v5"]}, [964])
trocados = conferir(conn, escrever=True, pausa=lambda s: None,
                    buscar=lambda c: {"fotos": ["n1", "n2", "n3", "n4"]})
checar("acusa a troca", trocados, [(964, 4)])
checar("e o banco fica com as do site", conn.fotos[964], ["n1", "n2", "n3", "n4"])
checar("apagou as velhas antes", conn.apagados, [964])

print()
print("--- o que NÃO pode acontecer ---")
# IGUAIS NÃO TROCAM: reescrever à toa perderia a ordem e encheria o log.
conn2 = ConnFotos({964: ["a", "b"]}, [964])
checar("fotos iguais não trocam",
       conferir(conn2, escrever=True, pausa=lambda s: None,
                buscar=lambda c: {"fotos": ["a", "b"]}), [])
# MAS CARIMBA: sem isso o rodízio voltaria sempre aos mesmos e o resto do
# catálogo nunca seria conferido.
checar("mas carimba assim mesmo", conn2.carimbados, [964])

# ANÚNCIO SEM FOTO NÃO APAGA AS QUE TEMOS. Página que não abriu, ou servida
# pela metade, devolveria lista vazia -- e o imóvel iria ao disparo SEM FOTO
# NENHUMA. É a armadilha do dict truthy, de novo.
conn3 = ConnFotos({964: ["a", "b"]}, [964])
conferir(conn3, escrever=True, pausa=lambda s: None, buscar=lambda c: {"fotos": []})
checar("site sem foto não apaga as nossas", conn3.fotos[964], ["a", "b"])
checar("e nem apagou", conn3.apagados, [])

# SIMULAÇÃO NÃO GRAVA (regra 4).
conn4 = ConnFotos({964: ["v1"]}, [964])
checar("simulação acusa", conferir(conn4, escrever=False, pausa=lambda s: None,
                                   buscar=lambda c: {"fotos": ["n1"]}), [(964, 1)])
checar("mas não troca", conn4.fotos[964], ["v1"])
checar("nem carimba", conn4.carimbados, [])

# UM ANÚNCIO QUE EXPLODE não derruba a rodada.
conn5 = ConnFotos({1: ["a"], 2: ["b"]}, [1, 2])


def _meio_quebrado(c):
    if str(c) == "1":
        raise RuntimeError("timeout")
    return {"fotos": ["novo"]}


checar("o que deu certo troca",
       conferir(conn5, escrever=True, pausa=lambda s: None, buscar=_meio_quebrado),
       [(2, 1)])

# A PAUSA entre leituras (regra 5), nunca antes da primeira.
pausas = []
conferir(ConnFotos({1: [], 2: [], 3: []}, [1, 2, 3]), escrever=False,
         pausa=pausas.append, buscar=lambda c: {"fotos": ["x"]})
checar("duas pausas para três leituras", len(pausas), 2)

print()
print("--- PÁGINA MORTA não é 'sem foto' (Tel, 29/09) ---")
# O 2133 (Life Ponta Negra) foi oferecido a uma corretora, o card saiu da
# TABELA e as fotos nunca foram -- não existia nenhuma. O anúncio dele
# redireciona para `nao-encontrado`: veio da planilha do site antigo
# (importação de 26/09), apareceu na LISTAGEM, e a varredura o marcou
# publicado. A página do anúncio é a autoridade; a listagem pode trazer card
# velho.
from varrer_fotos import varrer


class ConnVarrer:
    """Banco de mentira para o `varrer`: fila de códigos sem foto."""

    def __init__(self, fila):
        self.fila = list(fila)
        self.despublicados = []
        self.gravados = []

    def cursor(self):
        conn = self

        class C:
            def __enter__(s):
                return s

            def __exit__(s, *a):
                return False

            def execute(s, sql, params=None):
                if "publicado_no_site = false" in sql:
                    conn.despublicados.append(params[0])
                elif "INSERT INTO imovel_fotos" in sql:
                    conn.gravados.append((params[0], params[2]))
                s.r = [{"codigo": c} for c in conn.fila] if "FROM imoveis i" in sql else []

            def fetchall(s):
                return s.r
        return C()

    def commit(self):
        pass


# `buscar_imovel` devolve dict TRUTHY com tudo None quando o anúncio saiu do
# ar -- a armadilha já registrada. Sem a conferência, isto virava só
# "o anuncio nao tem foto" e o imóvel seguia sendo oferecido para sempre.
conn = ConnVarrer([2133])
r = varrer(conn, escrever=True, pausa=lambda s: None)
import varrer_fotos as _vf
_b = _vf.buscar_imovel
_vf.buscar_imovel = lambda c: {"tipo": None, "fotos": []}
try:
    conn = ConnVarrer([2133])
    r = varrer(conn, escrever=True, pausa=lambda s: None)
    checar("acusa página morta", [x[2] for x in r],
           ["anuncio fora do ar -- despubliquei"])
    checar("e despublica", conn.despublicados, [2133])
    checar("sem gravar foto nenhuma", conn.gravados, [])

    # ANÚNCIO VIVO E SEM FOTO é outra coisa: continua publicado.
    _vf.buscar_imovel = lambda c: {"tipo": "Apartamento", "fotos": []}
    conn2 = ConnVarrer([999])
    r2 = varrer(conn2, escrever=True, pausa=lambda s: None)
    checar("anúncio vivo sem foto NÃO despublica", conn2.despublicados, [])
    checar("e diz que não tem foto", [x[2] for x in r2], ["o anuncio nao tem foto"])

    # E O CAMINHO NORMAL continua gravando.
    _vf.buscar_imovel = lambda c: {"tipo": "Apartamento", "fotos": ["a", "b"]}
    conn3 = ConnVarrer([888])
    varrer(conn3, escrever=True, pausa=lambda s: None)
    checar("anúncio com foto grava", [u for _, u in conn3.gravados], ["a", "b"])
    checar("e não despublica", conn3.despublicados, [])
finally:
    _vf.buscar_imovel = _b

# FOTOS EDITADAS À MÃO (283, 03/10): as duas listas pulam quem está em
# imovel_fotos_manual -- senão a conferência desfaz a ordem e as fotos que o
# Pedro subiu na biblioteca do cadastro.
print("\n  fotos editadas à mão ficam fora das duas listas")


class ConnSql:
    def __init__(self):
        self.sqls = []

    def cursor(self):
        conn = self

        class C:
            def __enter__(s):
                return s

            def __exit__(s, *a):
                return False

            def execute(s, sql, params=None):
                conn.sqls.append(sql)

            def fetchall(s):
                return []
        return C()


from varrer_fotos import a_conferir, sem_fotos  # noqa: E402
for nome, f in (("a_conferir", a_conferir), ("sem_fotos", sem_fotos)):
    c = ConnSql()
    f(c)
    checar(f"{nome} pula os editados à mão",
           "NOT EXISTS (SELECT 1 FROM public.imovel_fotos_manual m WHERE m.codigo = i.codigo)" in c.sqls[0], True)

print()
if falhas:
    print(f"{falhas} CASOS FALHARAM")
    raise SystemExit(1)
print("TODOS OS CASOS DA CONFERÊNCIA DE FOTOS PASSARAM")
