"""
Prova que imóvel de PARCERIA não sai nos grupos.

O PEDIDO (Tel, 16/09: "esses imoveis de parceiros nao e pra enviar"; 27/09:
"não quero imóvel de parceiro, só nosso direto, pode retirar o de parceiro da
lista").

O QUE JÁ ESTAVA CERTO, medido em 27/09 antes de escrever uma linha: as quatro
funções da Nay que leem `imoveis` (`nay_lista_de_imoveis`,
`nay_buscar_por_perfil`, `nay_disponibilidade_no_condominio` e a do envio) já
traziam `AND NOT coalesce(i.e_parceiro, false)`. Nenhuma lista, nenhuma busca
e nenhum envio a corretor jamais ofereceu parceria.

O QUE FALTAVA: a POSTAGEM EM GRUPO. `_postar_codigo` lê o site ao vivo e nunca
consultou `e_parceiro` -- são 561 imóveis de parceiro no ar hoje, e qualquer um
deles saía nos 17 grupos com um `Nay posta o NNNN`. Grupo não desfaz.

O QUE IMPORTA PROVAR, e o que cada coisa custa se quebrar:

  * A RECUSA VEM ANTES DA REQUISIÇÃO AO SITE no caminho de vários códigos: a
    resposta é a mesma com ou sem ela, e ele manda até 6 códigos de uma vez.

  * E ANTES DA RESERVA no caminho do Easy/Alto Padrão/Comercial. Reservar e
    depois recusar deixaria o código marcado como postado sem nada ter saído,
    e o pedido seguinte cairia em "já foi" -- o buraco que o Easy teve até
    14/09.

  * IMÓVEL NOVO CONTINUA POSTANDO. Este portão NÃO falha fechado, contra a
    regra geral do projeto, e é decisão consciente: o caso comum de "não sei"
    é imóvel recém-cadastrado, que não tem linha na tabela ainda. O CLAUDE.md
    é explícito -- "imóvel cadastrado agora já pode ser postado agora". O 5763
    passou 27/09 inteiro assim. Fechar aqui faria a varredura virar
    pré-requisito do comando que ele mais usa.

Uso:
    .venv/bin/python teste_parceria_nao_posta.py
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

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def execute(self, sql, params=None):
        if self.conn.explodir:
            raise RuntimeError("banco fora do ar")
        self.conn.perguntou.append(params[0])
        self.linha = self.conn.tabela.get(params[0])

    def fetchone(self):
        return self.linha


class ConnFake:
    def __init__(self, tabela, explodir=False):
        self.tabela = tabela
        self.explodir = explodir
        self.perguntou = []
        self.rollbacks = 0

    def cursor(self):
        return CursorFake(self)

    def commit(self):
        pass

    def rollback(self):
        self.rollbacks += 1


TABELA = {"5745": {"p": True},    # de parceiro
          "5749": {"p": False}}   # nosso


print("--- a parede em si ---")
checar("parceiro é recusado",
       bool(publicador._e_de_parceiro(ConnFake(TABELA), "5745")), True)
checar("  e a recusa nomeia o código e diz que não postou",
       "5745" in publicador._e_de_parceiro(ConnFake(TABELA), "5745")
       and "não postei nada" in publicador._e_de_parceiro(ConnFake(TABELA), "5745"),
       True)
checar("nosso passa", publicador._e_de_parceiro(ConnFake(TABELA), "5749"), None)
# IMÓVEL NOVO: sem linha na tabela. É o caso do 5763 em 27/09 -- estava no
# site e não no banco. Recusar aqui faria a varredura virar pré-requisito.
checar("imóvel NOVO (sem linha) passa",
       publicador._e_de_parceiro(ConnFake(TABELA), "5999"), None)
# Banco fora do ar não pode travar o comando -- e tem que desfazer a
# transação, senão a conexão fica suja para a próxima consulta.
conn = ConnFake(TABELA, explodir=True)
checar("banco fora do ar não trava", publicador._e_de_parceiro(conn, "5745"), None)
checar("  e faz rollback", conn.rollbacks, 1)


print()
print("--- no caminho dos grupos: recusa ANTES de ir ao site ---")
buscou = []
_b = publicador.buscar_imovel
publicador.buscar_imovel = lambda c: buscou.append(c) or {}
try:
    r = publicador._postar_codigo("5745", [{"id_grupo": "g", "nome": "G"}],
                                  conn=ConnFake(TABELA))
    checar("não posta", r["sucesso"], False)
    checar("diz que é parceria", "PARCERIA" in r["erro"], True)
    checar("e NÃO gastou requisição no site", buscou, [])
finally:
    publicador.buscar_imovel = _b

# `conn=None` (o teste do anúncio fora do ar chama assim) não pode explodir.
_b = publicador.buscar_imovel
publicador.buscar_imovel = lambda c: {}
try:
    r = publicador._postar_codigo("5745", [{"id_grupo": "g", "nome": "G"}],
                                  conn=None)
    checar("sem conexão, segue o caminho antigo", r["sucesso"], False)
finally:
    publicador.buscar_imovel = _b


print()
print("--- no Easy/Alto Padrão/Comercial: recusa ANTES da reserva ---")
# Reservar e depois recusar deixaria o código marcado como postado sem nada
# ter saído, e o próximo pedido cairia em "já foi postado".
class ConnEasy(ConnFake):
    def __init__(self, tabela):
        super().__init__(tabela)
        self.reservou = False

    def cursor(self):
        cur = CursorFake(self)
        pai = cur.execute

        def espiar(sql, params=None):
            if "INSERT INTO" in sql:
                self.reservou = True
                return
            return pai(sql, params)
        cur.execute = espiar
        return cur


for apelido, rotulo in [("easy", "Easy"), ("alto_padrao", "Alto Padrão"),
                        ("comercial", "Comercial")]:
    conn = ConnEasy(TABELA)
    r = publicador._postar_easy("5745", conn, apelido=apelido)
    checar(f"{rotulo}: recusa", "PARCERIA" in str(r), True)
    checar(f"  e NÃO reservou o código", conn.reservou, False)

print()
if falhas:
    print(f"{falhas} CASOS FALHARAM")
    raise SystemExit(1)
print("TODOS OS CASOS DA PARCERIA PASSARAM")
