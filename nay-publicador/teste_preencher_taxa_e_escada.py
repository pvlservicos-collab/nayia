"""
Testa o preenchimento do "Incluso no Aluguel" e dos "Lances de Escada".

POR QUE EXISTE (14/09): o card já lê os dois da página ao vivo, mas quem lê da
TABELA é outra coisa -- a LISTA (`nay_linha_da_lista`), que é o que o Tel cola
no WhatsApp. Sem preencher, a lista dizia que o 5718 não tem taxa inclusa
enquanto o card dizia que tem: duas respostas diferentes para a mesma pergunta.

O QUE IMPORTA PROVAR, e o que cada coisa custa se quebrar:

  * COMPLEMENTA, nunca sobrescreve. É isso que preserva o que o Tel marcou à
    mão pelo comando `NNNN incluso a tx` -- o 5729 é assim: o site não diz e
    ele marcou. Sobrescrever apagaria decisão dele;

  * o `extras` é FUNDIDO, não trocado. Trocar o objeto apagaria "aceita
    permuta", "aceita financiamento" e o resto que a importação de agosto
    deixou -- e a regra 1 do projeto é não apagar nada;

  * NÃO BAIXA o que já tem. Sem a guarda seriam 85 requisições para escrever
    em 50, e a pausa de 1,5s faz cada uma custar;

  * página vazia não ensina nada. `buscar_imovel` devolve um dict TRUTHY com
    tudo None quando o anúncio saiu do ar (o site redireciona e o
    `raise_for_status` não levanta) -- é a armadilha já registrada, e gravar
    a partir dela encheria a tabela de vazio;

  * simulação por padrão (regra 4): sem `--escrever`, nada é gravado.

Uso:
    .venv/bin/python teste_preencher_taxa_e_escada.py
"""
import preencher_taxa_e_escada as p

falhas = 0


def checar(titulo, obtido, esperado):
    global falhas
    ok = str(obtido) == str(esperado)
    falhas += 0 if ok else 1
    print(f"  {'OK  ' if ok else 'FALHOU'} {titulo}")
    if not ok:
        print(f"         esperava {esperado!r}, veio {obtido!r}")


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
        self.linhas = []
        if "UPDATE imoveis" in s:
            self.conn.gravados.append((params[1], params[0], s))
        elif "extras->>'incluso no aluguel' AS incluso" in s:
            self.linhas = [self.conn.tabela.get(params[0], {})]
        elif "SELECT codigo::text AS codigo" in s:
            if params:
                self.linhas = [{"codigo": str(params[0])}]
            else:
                self.linhas = [{"codigo": c} for c in self.conn.tabela]

    def fetchall(self):
        return self.linhas

    def fetchone(self):
        return self.linhas[0] if self.linhas else None


class ConnFake:
    def __init__(self, tabela):
        self.tabela = tabela
        self.gravados = []

    def cursor(self):
        return CursorFake(self)

    def commit(self):
        pass

    def close(self):
        pass


DA_PAGINA = {
    # o site diz os dois
    "5718": {"tipo": "Apartamento",
             "incluso_no_aluguel": "Água, Taxa de Gás, Taxa de Condomínio, IPTU",
             "lances_de_escada": "3"},
    # o site diz só a escada -- o incluso dele veio do comando do Tel
    "5729": {"tipo": "Apartamento", "incluso_no_aluguel": None,
             "lances_de_escada": "2"},
    # anúncio fora do ar: dict TRUTHY com tudo None
    "5110": {"tipo": None, "incluso_no_aluguel": None, "lances_de_escada": None},
}


def rodar(tabela, escrever=True):
    conn = ConnFake(tabela)
    feitas = p.preencher(conexao=conn, escrever=escrever, todos=True,
                         buscar=lambda c: DA_PAGINA.get(c, {}), ao_vivo=False)
    return conn, feitas


print("--- preenche o que está vazio ---")
conn, feitas = rodar({"5718": {"incluso": None, "escada": None}})
checar("grava uma vez", len(conn.gravados), 1)
_cod, _json, _sql = conn.gravados[0]
checar("no imóvel certo", _cod, "5718")
checar("com a taxa da página", "Taxa de Condomínio" in _json, True)
checar("e com os lances", '"3"' in _json, True)

print()
print("--- COMPLEMENTA, nunca sobrescreve ---")
# O 5729 tem o incluso vindo do comando `5729 incluso a tx` e o site não diz.
# Sobrescrever apagaria a decisão dele.
conn, feitas = rodar({"5729": {"incluso": "Taxa de Condomínio", "escada": None}})
checar("grava só o que faltava", len(conn.gravados), 1)
checar("o incluso NÃO é tocado", "incluso no aluguel" in conn.gravados[0][1], False)
checar("e a escada entra", '"2"' in conn.gravados[0][1], True)

print()
print("--- o que já tem os dois nem é baixado ---")
baixados = []


def _contar(c):
    baixados.append(c)
    return DA_PAGINA.get(c, {})


conn = ConnFake({"5718": {"incluso": "Taxa de Condomínio", "escada": "3"}})
p.preencher(conexao=conn, escrever=True, todos=True, buscar=_contar,
            ao_vivo=False)
checar("nenhuma requisição", len(baixados), 0)
checar("nenhuma gravação", len(conn.gravados), 0)

print()
print("--- página vazia não ensina nada ---")
# `buscar_imovel` devolve dict TRUTHY com tudo None quando o anúncio saiu do
# ar. Gravar a partir dele encheria a tabela de vazio.
conn, feitas = rodar({"5110": {"incluso": None, "escada": None}})
checar("não grava", len(conn.gravados), 0)
checar("e não conta como mudança", len(feitas), 0)

print()
print("--- o extras é FUNDIDO, não trocado ---")
# Trocar o objeto apagaria "aceita permuta", "aceita financiamento" e o resto
# da importação de agosto. A regra 1 do projeto é não apagar nada.
conn, _ = rodar({"5718": {"incluso": None, "escada": None}})
checar("usa o operador de fusão", "extras = coalesce(extras,'{}'::jsonb) || "
       in conn.gravados[0][2], True)
checar("e carimba o sincronizado_em",
       "sincronizado_em = now()" in conn.gravados[0][2], True)

print()
print("--- simulação não grava (regra 4) ---")
conn, feitas = rodar({"5718": {"incluso": None, "escada": None}}, escrever=False)
checar("vê a mudança", len(feitas), 1)
checar("mas não grava", len(conn.gravados), 0)

print()
print("--- erro numa página não derruba o resto ---")
def _quebrar(c):
    if c == "5729":
        raise RuntimeError("timeout")
    return DA_PAGINA.get(c, {})


conn = ConnFake({"5729": {"incluso": None, "escada": None},
                 "5718": {"incluso": None, "escada": None}})
feitas = p.preencher(conexao=conn, escrever=True, todos=True, buscar=_quebrar,
                     ao_vivo=False)
checar("o que deu certo grava", len(conn.gravados), 1)
checar("e o erro é relatado", any(f.get("erro") for f in feitas), True)

print()
print("--- o CRON também guarda os lances de escada (Tel, 28/09) ---")
# "todo imóvel que for escada, sempre na descrição coloque quantos lances de
# escada, caso tenha na descrição do imóvel".
#
# O CARD JÁ MOSTRAVA -- ele lê a página AO VIVO -- e o formato já era o que ele
# pediu (bairro, escada, metragem). O que faltava era a TABELA guardar: é dela
# que sai o card quando o site não responde, e o cron de preenchimento
# (`preencher_do_anuncio`) pegava dez campos e não este.
#
# MEDIDO em 28/09: só 8 imóveis no mercado têm o dado, e numa amostra de 12
# sem ele o SITE também não tinha -- ou seja, a caixa está vazia no admin.
# Coletar não inventa dado; serve para quando ele preencher.
import preencher_do_anuncio as _pda

_html_com = """
<label class="form-control-label">Lances de Escada</label>
<span class="form-control">3</span>
"""
_html_sem = """
<label class="form-control-label">Quartos</label>
<span class="form-control">2</span>
"""
checar("lê o rótulo da página",
       _pda.campos_do_anuncio(_html_com).get("lances de escada"), "3")
checar("e devolve None quando a caixa está vazia",
       _pda.campos_do_anuncio(_html_sem).get("lances de escada"), None)
# ZERO É RESPOSTA, não ausência: quer dizer "não tem escada". Guardar o zero
# evita rebaixar a página toda hora para reaprender que não tem -- e o card
# já sabe não imprimir linha nenhuma nesse caso.
_html_zero = _html_com.replace(">3<", ">0<")
checar("zero é guardado como resposta",
       _pda.campos_do_anuncio(_html_zero).get("lances de escada"), "0")

print()
print("--- VAGAS é CORRIGIDO, não só preenchido (Tel, 29/09) ---")
# O CASO: a Nay disse a um corretor "tem 2 vagas de garagem" sobre o 5739
# (Life Parque Dez) e ele respondeu "tá dizendo aí só 1". O CARD estava certo
# -- lê a página ao vivo; a resposta veio da TABELA, que guardava 2 desde a
# importação de agosto. O anúncio diz 1.
#
# MEDIDO antes de mexer: em 15 imóveis sorteados, quartos, suítes e banheiros
# batiam em TODOS; só `vagas` divergia, e num só. A página traz os dois campos
# separados ("Vagas" e "Vagas Cobertas") e o banco guarda igual -- o 2973
# (2 e 2) e o 2947 (3 e 1) batem certo. Não há total a somar.
_com_duas = """
<label class="form-control-label">Vagas</label><span class="form-control">1</span>
"""
_com_cobertas = """
<label class="form-control-label">Vagas</label><span class="form-control">3</span>
<label class="form-control-label">Vagas Cobertas</label><span class="form-control">1</span>
"""
checar("lê as vagas da página",
       _pda.campos_do_anuncio(_com_duas).get("vagas"), "1")
checar("e as cobertas, quando a página traz",
       _pda.campos_do_anuncio(_com_cobertas).get("vagas cobertas"), "1")
checar("sem o rótulo, não inventa",
       _pda.campos_do_anuncio(_com_duas).get("vagas cobertas"), None)
# ZERO É RESPOSTA: "não tem vaga" é informação, e `inteiro('0')` não pode
# virar None -- senão o campo nunca sairia de um valor velho maior que zero.
checar("zero é lido como zero", _pda.inteiro("0"), 0)
checar("e vazio continua None", _pda.inteiro(""), None)

print()
if falhas:
    print(f"{falhas} CASOS FALHARAM")
    raise SystemExit(1)
print("TODOS OS CASOS DO PREENCHIMENTO PASSARAM")
