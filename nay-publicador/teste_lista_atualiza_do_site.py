"""
Prova que a lista relê os valores no SITE antes de sair.

O PEDIDO (Tel, 27/09): "o 3210 do morada dos passaros não atualizou na lista
de disparo de casas de condomínio, coloca para atualizar sempre a lista quando
atualizar os valores do site também".

A CAUSA DO QUE ELE VIU: a lista lê a TABELA, e quem põe o site na tabela é a
varredura -- que estava com a linha do cron COMENTADA desde 26/09. O cron
voltou, mas "de hora em hora" não é "sempre": ele muda um preço no admin e
dispara em seguida.

O QUE IMPORTA PROVAR, e o que cada coisa custa se quebrar:

  * A LEITURA VEM ANTES DE MONTAR O TEXTO. Depois não adiantaria nada -- a
    mensagem já estaria pronta com o valor velho.

  * SÓ GRAVA O QUE MUDOU. Sem a comparação, seriam 85 UPDATEs e 85 linhas
    carimbadas com `sincronizado_em` a cada disparo, e o carimbo deixaria de
    significar "mudou".

  * ANÚNCIO FORA DO AR NÃO ZERA VALOR. `buscar_imovel` devolve um dict TRUTHY
    com tudo None quando o anúncio sai (a armadilha já registrada). Gravar a
    partir dele poria o imóvel de graça na lista que vai para 13 grupos.

  * `None` DO SITE NÃO É ZERO. Imóvel só de locação não tem valor de venda; o
    site cala e a tabela tem que continuar como está.

  * FALHA ISOLADA: um anúncio que não abre não pode impedir o disparo
    inteiro. A lista sai com o que se sabe.

  * OS CÓDIGOS VÊM DA MESMA REGRA QUE MONTA O TEXTO (`nay_codigos_da_lista`).
    Reler um conjunto e mandar outro deixaria o valor recém-corrigido de fora
    -- que é exatamente a queixa dele.

Uso:
    .venv/bin/python teste_lista_atualiza_do_site.py
"""
import publicador

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
        self.linha = None

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def execute(self, sql, params=None):
        s = " ".join(sql.split())
        if "UPDATE imoveis SET" in s:
            self.conn.gravados.append((params[-1], s, params[:-1]))
            self.linha = None
        elif "FROM imoveis" in s and "SELECT" in s:
            coluna = s.split("SELECT ")[1].split(" AS v")[0].strip()
            self.linha = {"v": self.conn.tabela.get(params[0], {}).get(coluna)}
        else:
            self.linha = None

    def fetchone(self):
        return self.linha


class ConnFake:
    def __init__(self, tabela):
        self.tabela = tabela
        self.gravados = []

    def cursor(self):
        return CursorFake(self)

    def commit(self):
        pass


def rodar(tabela, do_site):
    conn = ConnFake(tabela)
    mud = publicador._atualizar_valores_do_site(
        conn, list(tabela), pausa=lambda s: None,
        buscar=lambda c: do_site.get(c, {}))
    return conn, mud


print("--- o valor que mudou no site entra na tabela ---")
conn, mud = rodar(
    {"3210": {"valor_venda": 900000.0, "valor_aluguel": 8000.0}},
    {"3210": {"tipo": "Casa de condomínio", "valor_venda": 900000.0,
              "valor_aluguel": 9000.0}})
checar("grava uma vez", len(conn.gravados), 1)
checar("no imóvel certo", conn.gravados[0][0], "3210")
checar("só a coluna que mudou", "valor_aluguel = %s" in conn.gravados[0][1], True)
checar("e NÃO a que ficou igual", "valor_venda" in conn.gravados[0][1], False)
checar("com o valor novo", conn.gravados[0][2], [9000.0])
checar("carimba o sincronizado_em",
       "sincronizado_em = now()" in conn.gravados[0][1], True)
checar("e relata a mudança", mud, [{"codigo": "3210", "valor_aluguel": 9000.0}])

print()
print("--- o que não mudou não é gravado ---")
# Sem isto seriam 85 UPDATEs por disparo, e o `sincronizado_em` deixaria de
# significar "mudou".
conn, mud = rodar(
    {"3210": {"valor_venda": 900000.0, "valor_aluguel": 9000.0}},
    {"3210": {"tipo": "Casa", "valor_venda": 900000.0, "valor_aluguel": 9000.0}})
checar("nenhuma gravação", len(conn.gravados), 0)
checar("nenhuma mudança relatada", mud, [])

print()
print("--- ANÚNCIO FORA DO AR não zera valor ---")
# dict TRUTHY com tudo None. Gravar a partir dele poria o imóvel de graça
# numa lista que vai para 13 grupos, e grupo não desfaz.
conn, mud = rodar(
    {"3210": {"valor_venda": 900000.0, "valor_aluguel": 9000.0}},
    {"3210": {"tipo": None, "valor_venda": None, "valor_aluguel": None}})
checar("não grava nada", len(conn.gravados), 0)

print()
print("--- None do site não é zero ---")
# Imóvel só de locação não tem valor de venda: o site cala, e calar não é
# dizer "zero". Sem isto o 3210 perderia os 900k a cada disparo da lista de
# locação.
conn, mud = rodar(
    {"3210": {"valor_venda": 900000.0, "valor_aluguel": 8000.0}},
    {"3210": {"tipo": "Casa", "valor_venda": None, "valor_aluguel": 9000.0}})
checar("o aluguel entra", conn.gravados[0][2], [9000.0])
checar("e a venda não é tocada",
       "valor_venda" in conn.gravados[0][1], False)

print()
print("--- valor que ESTAVA vazio na tabela entra ---")
conn, mud = rodar(
    {"5763": {"valor_venda": None, "valor_aluguel": None}},
    {"5763": {"tipo": "Loja", "valor_aluguel": 10000.0}})
checar("grava o que faltava", conn.gravados[0][2], [10000.0])

print()
print("--- um anúncio que explode não derruba o disparo ---")
tabela = {"3210": {"valor_aluguel": 8000.0}, "5749": {"valor_aluguel": 6000.0}}


def _meio_quebrado(c):
    if c == "3210":
        raise RuntimeError("timeout")
    return {"tipo": "Sala", "valor_aluguel": 6500.0}


conn = ConnFake(tabela)
mud = publicador._atualizar_valores_do_site(
    conn, list(tabela), pausa=lambda s: None, buscar=_meio_quebrado)
checar("o que deu certo grava", [g[0] for g in conn.gravados], ["5749"])
checar("e o erro não vira exceção", [m["codigo"] for m in mud], ["5749"])

print()
print("--- a PAUSA entre leituras é respeitada (regra 5 do projeto) ---")
pausas = []
publicador._atualizar_valores_do_site(
    ConnFake({"1": {}, "2": {}, "3": {}}), ["1", "2", "3"],
    pausa=pausas.append, buscar=lambda c: {})
# Entre as três leituras, duas pausas -- nunca antes da primeira.
checar("duas pausas para três leituras", len(pausas), 2)
checar("de 1,5s cada", set(pausas), {publicador.PAUSA_ENTRE_LEITURAS})

print()
print("--- no disparo: relê ANTES de montar o texto ---")
# Depois não adiantaria: a mensagem já estaria pronta com o valor velho.
ordem = []
_a, _c = (publicador._atualizar_valores_do_site, publicador._codigos_da_lista)
publicador._atualizar_valores_do_site = (
    lambda conn, cods, pausa=None, buscar=None: ordem.append("releu") or [])
publicador._codigos_da_lista = lambda *a, **k: ordem.append("pediu codigos") or []


class ConnLista:
    def cursor(self):
        conn = self

        class C:
            def __enter__(s):
                return s

            def __exit__(s, *a):
                return False

            def execute(s, sql, params=None):
                if "nay_lista_de_imoveis" in sql:
                    ordem.append("montou o texto")
                s.r = {"texto_pronto": None, "quantos": 0}

            def fetchone(s):
                return s.r

            def fetchall(s):
                return []
        return C()

    def commit(self):
        pass


try:
    publicador._disparar_lista(
        {"categoria": "casa_condominio", "negocio": "locacao"},
        ConnLista(), pausa=lambda s: None)
finally:
    publicador._atualizar_valores_do_site, publicador._codigos_da_lista = _a, _c
checar("pede os códigos, relê, e só então monta",
       ordem[:3], ["pediu codigos", "releu", "montou o texto"])

print()
if falhas:
    print(f"{falhas} CASOS FALHARAM")
    raise SystemExit(1)
print("TODOS OS CASOS DA ATUALIZAÇÃO DA LISTA PASSARAM")
