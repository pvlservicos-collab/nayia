"""A fila do `varrer_tipos` não pode ser eterna.

O CASO (09/09, à tarde): a primeira rodada de verdade preencheu o tipo de 63
imóveis e a área de **um**. O anúncio dos outros 62 diz, com todas as letras,
`Área Construída: 0.0 m2` -- o cadastro está vazio na origem, conferido no HTML
do 3210. Como a busca era "área igual a zero", os mesmos 62 voltariam para a
fila a cada hora, para sempre: ~1.500 requisições por dia ao site que nunca
trariam nada. A regra 5 do projeto é não martelar o site.

    .venv/bin/python teste_varrer_tipos.py
"""
import varrer_tipos

falhas = 0


def _checar(nome, condicao, detalhe=""):
    global falhas
    if condicao:
        print(f"  OK   {nome}")
    else:
        falhas += 1
        print(f"  FALHOU {nome} {detalhe}")


class CursorFalso:
    """Responde pelo SQL, não pela ordem."""

    def __init__(self, conexao):
        self.c = conexao
        self.linhas = []

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def execute(self, sql, params=None):
        self.c.sql.append((sql, params))
        self.linhas = []
        if sql.startswith("SELECT codigo FROM imoveis"):
            self.linhas = [{"codigo": c} for c in self.c.fila]

    def fetchall(self):
        return self.linhas


class ConexaoFalsa:
    def __init__(self, fila=()):
        self.fila = list(fila)
        self.sql = []
        self.commits = 0

    def cursor(self):
        return CursorFalso(self)

    def commit(self):
        self.commits += 1


print("--- a busca exclui quem já disse que o anúncio não tem a área ---")
conn = ConexaoFalsa(fila=[3210])
varrer_tipos.sem_tipo(conn)
consulta = conn.sql[0][0]
_checar("pergunta pelo marcador na busca",
        "area_no_anuncio" in consulta and "<> 'ausente'" in consulta, consulta)
# A ordem importa: o marcador só pode valer ENQUANTO a área continuar vazia.
# Se alguém preencher no admin, o imóvel tem que sair da fila pelo valor, não
# ficar dependendo de apagar o marcador.
_checar("o marcador vem colado na condição de área",
        consulta.index("coalesce(area_util,0) = 0")
        < consulta.index("area_no_anuncio"), consulta)
_checar("continua exigindo publicado e disponível",
        "publicado_no_site" in consulta and "disponivel" in consulta)


print("\n--- área ausente vira MARCADOR, não linha repetida ---")
conn = ConexaoFalsa()
varrer_tipos.gravar(conn, 3210, "Casa de condomínio", 0)
sql, params = conn.sql[0]
_checar("marca 'ausente' quando a área não veio", params[2] is True, params)
_checar("grava o tipo mesmo assim", params[0] == "Casa de condomínio", params)
_checar("o marcador entra por || sobre o extras que já existe",
        "coalesce(extras,'{}'::jsonb)" in sql and "jsonb_build_object" in sql, sql)
_checar("não escreve área nenhuma", params[1] is None, params)

conn = ConexaoFalsa()
varrer_tipos.gravar(conn, 4159, "Apartamento", 70)
_checar("com área de verdade NÃO marca ausente", conn.sql[0][1][2] is False,
        conn.sql[0][1])
_checar("e escreve a área", conn.sql[0][1][1] == 70, conn.sql[0][1])


print("\n--- página que não diz NADA também sai da fila ---")
# Era o outro caminho eterno: sem tipo e sem área, o script não gravava nada
# e o mesmo código voltava na hora seguinte.
conn = ConexaoFalsa(fila=[9999])
varrer_tipos.buscar_imovel = lambda c: {"tipo": None, "area": None}
resultados = varrer_tipos.varrer(conn, escrever=True, pausa=lambda s: None,
                                 log=lambda *a: None)
updates = [(s, p) for s, p in conn.sql if s.startswith("UPDATE imoveis")]
_checar("gravou o marcador", len(updates) == 1, conn.sql)
_checar("e o marcador é 'ausente'", updates and updates[0][1][2] is True, updates)
_checar("relata que o anúncio não diz",
        resultados and resultados[0][3] == "o anuncio nao diz", resultados)

# Simulação não pode escrever NADA -- regra 4 do projeto.
conn = ConexaoFalsa(fila=[9999])
varrer_tipos.varrer(conn, escrever=False, pausa=lambda s: None,
                    log=lambda *a: None)
_checar("simulação não escreve",
        not [s for s, _ in conn.sql if s.startswith("UPDATE")], conn.sql)


print()
print("TODOS OS TESTES PASSARAM" if falhas == 0 else f"{falhas} FALHARAM")
raise SystemExit(1 if falhas else 0)
