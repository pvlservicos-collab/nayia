"""
Prova que a lista ESCRITA À MÃO no site sai como foi escrita, menos o que não pode sair.

O PEDIDO (Pedro, 03/10): "quero também lá na página de agenda que crie, no criar
mensagem, lista de imóveis, e editar essa mensagem fisicamente: hoje tu só edita
horários". A vaga de lista ganhou `texto_fixo` (migrações 285/286): preenchido,
é ESSE texto que vai para os grupos.

O QUE IMPORTA PROVAR, e o que cada coisa custa se quebrar:

  * SAI O TEXTO DELE: o título, a ordem e a frase que ele acrescentou. Se a
    lista montada na hora tomasse o lugar, editar não serviria para nada.

  * IMÓVEL QUE SAIU DO MERCADO SOME DA LISTA NA HORA. Texto parado com imóvel
    alugado ontem, em 16 grupos, é o erro que a lista automática nunca comete.

  * SEM NENHUM IMÓVEL NO AR, NADA SAI, e o Tel recebe o motivo. Mandar só o
    título para os grupos seria ruído.

  * GRUPO COM REGRA (o piso do Alto Padrão) recebe só as linhas que aceita, e
    nada se nenhuma passa -- a mesma regra da lista automática.

  * O ID DE CADA PEDAÇO É REGISTRADO (281), para o corretor marcar a lista.

  * A LISTA AUTOMÁTICA (sem texto_fixo) continua exatamente como era.

Uso:
    .venv/bin/python teste_lista_escrita_a_mao.py
"""
import publicador
from publicador import _lista_escrita_a_mao

falhas = 0


def checar(titulo, obtido, esperado):
    global falhas
    ok = obtido == esperado
    falhas += 0 if ok else 1
    print(f"  {'OK  ' if ok else 'FALHOU'} {titulo}")
    if not ok:
        print(f"         esperava {esperado!r}, veio {obtido!r}")


TEXTO = ("🔥 SELEÇÃO DO PEDRO 🔥\n\n"
         "✅Conquista rio negro cod 5724 / 2 quartos / mobiliado / 2.6k\n"
         "✅Saiu do mercado cod 1111 / 1 quarto / 1.5k\n"
         "✅Saint Martin cod 5757 / 3 quartos / 6.9k\n\n"
         "Quem tiver cliente me chama!")

print("  a função que filtra o texto")
t, n = _lista_escrita_a_mao(TEXTO, {5724, 5757})
checar("tira só a linha do imóvel que não pode sair", "cod 1111" in t, False)
checar("e mantém as outras, o título e a frase dele",
       ["SELEÇÃO DO PEDRO" in t, "cod 5724" in t, "cod 5757" in t, "me chama" in t], [True] * 4)
checar("conta as linhas de imóvel que ficaram", n, 2)
checar("nenhum permitido: zero imóvel", _lista_escrita_a_mao(TEXTO, set())[1], 0)
checar("texto sem código nenhum: zero imóvel", _lista_escrita_a_mao("só um aviso", {5724})[1], 0)


class CursorFake:
    def __init__(self, conn):
        self.conn = conn
        self.linhas = []

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def execute(self, sql, params=None):
        s = " ".join(sql.split())
        self.conn.sqls.append(s)
        if "FROM imoveis i WHERE i.codigo = ANY" in s:
            self.linhas = [{"codigo": c} for c in params[0] if c in self.conn.no_ar]
        elif "nay_codigos_da_lista" in s:        # os que passam na regra do grupo (piso, só condomínio)
            self.linhas = [{"codigo": c} for c in self.conn.do_piso]
        elif "nay_reservar_disparo_de_lista" in s:
            self.linhas = [{"id": 77, "ja_foi_em": None}]
        elif "nay_lista_de_imoveis" in s:
            self.linhas = [{"texto_pronto": "🔥 AUTOMÁTICA 🔥\n\n✅Auto cod 5724 / 2.6k", "quantos": 1}]
        else:
            self.linhas = []

    def executemany(self, sql, linhas):
        self.conn.registrados.extend(linhas)

    def fetchone(self):
        return self.linhas[0] if self.linhas else None

    def fetchall(self):
        return self.linhas


class ConnFake:
    def __init__(self, no_ar, do_piso=()):
        self.no_ar, self.do_piso = set(no_ar), list(do_piso)
        self.sqls, self.registrados = [], []

    def cursor(self):
        return CursorFake(self)

    def commit(self):
        pass

    def rollback(self):
        pass


GRUPOS = [
    {"id_grupo": "g1", "nome": "Parceiros 1", "ativo": True, "todas_fotos": False,
     "aceita_venda": True, "aceita_locacao": True},
    {"id_grupo": "g2", "nome": "Alto Padrão", "ativo": True, "todas_fotos": False,
     "aceita_venda": True, "aceita_locacao": True, "aluguel_minimo": 6500, "so_condominio": True},
]

_originais = (publicador.enviar_texto, publicador.carregar_grupos_db, publicador._atualizar_valores_do_site)
enviados = []
seq = [0]


def _envia(destino, texto):
    seq[0] += 1
    enviados.append((destino, texto))
    return {"messageId": f"MSG{seq[0]}"}


def _nao_era_para_reler(*a, **k):
    raise AssertionError("a lista escrita à mão não relê o site")


try:
    publicador.enviar_texto = _envia
    publicador.carregar_grupos_db = lambda conn: GRUPOS
    comando = {"categoria": "apartamento", "negocio": "locacao", "destino": "parceiros", "texto_fixo": TEXTO}

    print("\n  o disparo com o texto dele")
    publicador._atualizar_valores_do_site = _nao_era_para_reler
    conn = ConnFake(no_ar={5724, 5757}, do_piso=[5757])
    resposta = publicador._disparar_lista(dict(comando), conn, pausa=lambda s: None)
    por_grupo = dict(enviados)
    checar("o grupo comum recebe o texto dele, sem o imóvel fora do mercado",
           ["SELEÇÃO DO PEDRO" in por_grupo.get("g1", ""), "cod 5724" in por_grupo.get("g1", ""),
            "cod 1111" in por_grupo.get("g1", ""), "me chama" in por_grupo.get("g1", "")],
           [True, True, False, True])
    checar("não é a lista automática", "AUTOMÁTICA" in por_grupo.get("g1", ""), False)
    checar("o Alto Padrão recebe só a linha que passa no piso",
           ["cod 5757" in por_grupo.get("g2", ""), "cod 5724" in por_grupo.get("g2", "")], [True, False])
    checar("os ids ficam registrados, um por imóvel de cada pedaço",
           sorted((r[0], r[1]) for r in conn.registrados), [("MSG1", 5724), ("MSG1", 5757), ("MSG2", 5757)])
    checar("a resposta ao Tel diz que mandou", "enviada" in resposta, True)

    print("\n  nenhum imóvel do texto está no ar")
    enviados.clear()
    conn = ConnFake(no_ar=set())
    resposta = publicador._disparar_lista(dict(comando), conn, pausa=lambda s: None)
    checar("nada sai", enviados, [])
    checar("e o Tel fica sabendo o motivo", "escrita à mão" in resposta and "não mandei nada" in resposta, True)
    checar("sem reservar o disparo", any("nay_reservar_disparo_de_lista" in s for s in conn.sqls), False)

    print("\n  a lista automática continua como era")
    enviados.clear()
    publicador._atualizar_valores_do_site = lambda conn, codigos, pausa=None, buscar=None: []
    conn = ConnFake(no_ar={5724})
    publicador._disparar_lista({"categoria": "apartamento", "negocio": "locacao", "destino": "parceiros"},
                               conn, pausa=lambda s: None)
    checar("sai o texto montado na hora", "AUTOMÁTICA" in dict(enviados).get("g1", ""), True)
    checar("sem perguntar pelos códigos escritos", any("i.codigo = ANY" in s for s in conn.sqls), False)
finally:
    publicador.enviar_texto, publicador.carregar_grupos_db, publicador._atualizar_valores_do_site = _originais

print()
if falhas:
    print(f"{falhas} CASOS FALHARAM")
    raise SystemExit(1)
print("TODOS OS CASOS DA LISTA ESCRITA À MÃO PASSARAM")
