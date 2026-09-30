"""
Postar pelo NOME DO CONDOMÍNIO, e a resposta que escolhe (Tel, 15/09).

A conversa que fez isto existir:

    Tel:  Posta o jardim das cerejeiras
    Nay:  Não entendi o comando "Posta o jardim das cerejeiras". Exemplos
          que eu reconheço: "posta o 5750", ...

Literal dele: *"eu nunca lembro por código e preciso que neste caso quando eu
pedir pelo nome do condomínio, ela procure e me pergunte se é para venda ou
locação"*, *"se estiver mais de uma opção ela vai me mandar o jardim das
cerejeiras com o valor e código para eu decidir e respondo com ela pelo valor
ou código que ela me enviou"*.

O QUE IMPORTA PROVAR, e o que custa se quebrar:

  * AS TRÊS FORMAS QUE ELE ESCREVEU funcionam -- "posta o X", "posta o X para
    locação", "posta PARA LOCAÇÃO o X". A do meio caía em "POSTA manda para os
    grupos e nao sei mandar para uma pessoa com esse verbo", porque o "para"
    fazia a cauda virar nome de corretor;

  * NÃO POSTA SEM ELE ESCOLHER. Postagem em 14 grupos não desfaz: com mais de
    uma opção, ou com o negócio não dito, ela PERGUNTA e não manda nada;

  * SÓ POSTA O QUE ELA OFEREU. Um código fora da pergunta não posta nada --
    ele pode estar falando de outro imóvel;

  * O LADO ESCOLHIDO É O LADO QUE SAI. "para locação" num imóvel que também
    tem venda mostra o card de locação, e só nos grupos que aceitam locação;

  * A PERGUNTA É TOMADA UMA VEZ: dois "locação" seguidos não postam duas vezes;

  * E A JANELA: resposta fora do prazo não posta -- pode ser outra conversa.

Uso:
    .venv/bin/python teste_postar_por_nome.py
"""
import io
import json
from unittest.mock import patch

import publicador
from interpretar_comando import interpretar_comando as ic
from montar_destinos import negocios_do_grupo

falhas = 0


def checar(titulo, obtido, esperado):
    global falhas
    ok = obtido == esperado
    falhas += 0 if ok else 1
    print(f"  {'OK  ' if ok else 'FALHOU'} {titulo}")
    if not ok:
        print(f"         esperava {esperado!r}, veio {obtido!r}")


def checar_que(titulo, condicao, detalhe=""):
    checar(titulo, bool(condicao), True)
    if not condicao and detalhe:
        print(f"         {detalhe}")


print("--- as formas que o Tel escreve ---")
for frase, nome, negocio in [
    ("Posta o jardim das cerejeiras", "jardim cerejeiras", None),
    ("Nay publica o jardim das cerejeiras para locação", "jardim cerejeiras", "locacao"),
    ("posta o jardim das cerejeiras para locação", "jardim cerejeiras", "locacao"),
    ("posta para locação o jardim das cerejeiras", "jardim cerejeiras", "locacao"),
    ("posta o morada dos pássaros para venda", "morada pássaros", "venda"),
    ("publica o vision residence", "vision residence", None),
    ("Nay posta o acquarelle", "acquarelle", None),
]:
    r = ic(frase)
    checar(f"{frase[:44]!r}", r["acao"], "postar_por_nome")
    checar("  o nome", r.get("nome"), nome)
    checar("  o negócio", r.get("negocio"), negocio)

print()
print("--- e o que NÃO pode virar busca por nome ---")
for frase, acao in [
    ("Nay posta o 5750", "postar_agora"),
    ("posta no grupo anunciar easy 1885", "postar_easy"),
    ("posta a lista de apartamentos para locação", "disparar_lista"),
    ("posta o 5750 todo dia às 14h", "criar_vaga"),
    ("posta ai", "nao_reconhecido"),
    ("posta agora", "nao_reconhecido"),
    # sem nome de verdade não vira busca: viraria "não achei o condomínio 'o'"
    ("posta o", "nao_reconhecido"),
]:
    checar(f"{frase!r}", ic(frase)["acao"], acao)

print()
print("--- a resposta curta dele ---")
for frase, chave, valor in [
    ("locação", "negocio", "locacao"), ("locacao", "negocio", "locacao"),
    ("é locação", "negocio", "locacao"), ("para locação", "negocio", "locacao"),
    ("aluguel", "negocio", "locacao"), ("venda", "negocio", "venda"),
    ("é venda", "negocio", "venda"), ("para venda", "negocio", "venda"),
    ("5725", "codigo", "5725"), ("o 5725", "codigo", "5725"),
    ("3.6k", "valor", "3.6k"), ("o de 3.6k", "valor", "3.6k"),
    ("R$ 3.600", "valor", "3.600"), ("750k", "valor", "750k"),
]:
    r = ic(frase)
    checar(f"{frase!r}", r["acao"], "escolha_do_posta")
    checar(f"  {chave}", r.get(chave), valor)

# "1" e "2" são o que ele escreveria contando as opções na tela -- e a pergunta
# imprime CÓDIGO, não número de ordem. Virar "R$ 1" seria responder qualquer coisa.
for frase in ["1", "2", "12", "bom dia", "posta o 5750", "5750 alugado"]:
    checar_que(f"{frase!r} não é escolha", ic(frase)["acao"] != "escolha_do_posta")

print()
print("--- os MESMOS casos do portão do n8n (casos_escolha_do_posta.json) ---")
# O portão (`regex_escolha_do_posta.js`) decide se a frase CHEGA ao publicador;
# aqui se prova que, chegando, o Python entende a mesma coisa. Os dois lados
# lendo o mesmo arquivo é o que impede um andar sem o outro.
CASOS = json.loads(
    io.open("casos_escolha_do_posta.json", encoding="utf-8").read())["casos"]
for caso in CASOS:
    checar(f"{caso['texto']!r}", ic(caso["texto"])["acao"], caso["acao"])
checar("o arquivo de casos não encolheu", len(CASOS) >= 37, True)


# --------------------------------------------------------------------
# O banco de mentira: só as consultas que este caminho faz.
CONDOMINIOS = [("Jardim das Cerejeiras", "jardim das cerejeiras"),
               ("Condomínio Acquarelle", "acquarelle")]

IMOVEIS = {
    # o do Tel: locação e venda no mesmo imóvel
    "5725": {"codigo": "5725", "no_ar": True, "parceiro": False,
             "valor_aluguel": 3600, "valor_venda": 750000, "cheio_locacao": 3600,
             "linha_locacao": "Jardim das Cerejeiras / 2 quartos / 3.6k",
             "linha_venda": "Jardim das Cerejeiras / 2 quartos / 750k"},
    "5731": {"codigo": "5731", "no_ar": True, "parceiro": False,
             "valor_aluguel": 2800, "valor_venda": None, "cheio_locacao": 2800,
             "linha_locacao": "Jardim das Cerejeiras / 3 quartos / 2.8k",
             "linha_venda": None},
}


class Cursor:
    def __init__(self, conn):
        self.conn, self.linhas = conn, []

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def execute(self, sql, params=None):
        q = " ".join(sql.split())
        self.conn.consultas.append((q, params))
        self.linhas = []
        if "FROM pergunta_ao_tel" in q and q.startswith("SELECT"):
            self.linhas = [self.conn.pergunta] if self.conn.pergunta else []
        elif "INSERT INTO pergunta_ao_tel" in q:
            self.conn.pergunta = {"id": 1, "acao": "postar_por_nome",
                                  "nome": params[0], "candidatos": params[1],
                                  "negocio": params[2], "codigo": None}
        elif "UPDATE pergunta_ao_tel" in q and "respondida_em = now()" in q:
            # só toma se ainda estiver aberta
            self.linhas = [{"id": 1}] if self.conn.pergunta else []
            self.conn.pergunta = None
        elif "UPDATE pergunta_ao_tel SET candidatos" in q:
            self.conn.pergunta["candidatos"] = params[0]
            self.conn.pergunta["negocio"] = params[1]
        elif "nay_condominio_de_verdade(tipo, condominio_nome) AS nome" in q:
            self.linhas = [{"nome": n, "chave": c} for n, c in CONDOMINIOS]
        elif "nay_linha_da_lista" in q and "FROM imoveis i WHERE i.codigo::text = ANY" in q:
            self.linhas = [IMOVEIS[c] for c in params[0] if c in IMOVEIS]
        elif "FROM imoveis i WHERE" in q:
            linhas = list(IMOVEIS.values())
            if "coalesce(i.valor_aluguel,0) > 0" in q:
                linhas = [i for i in linhas if i["valor_aluguel"]]
            if "coalesce(i.valor_venda,0) > 0" in q:
                linhas = [i for i in linhas if i["valor_venda"]]
            self.linhas = linhas
        elif "nay_custo_cheio" in q:
            im = IMOVEIS[params[0]]
            self.linhas = [{"v": im["cheio_locacao"], "bruto": im["valor_aluguel"]}]
        elif "SELECT valor_venda AS v" in q:
            self.linhas = [{"v": IMOVEIS[params[0]]["valor_venda"]}]
        elif "nay_valor_escrito" in q:
            self.linhas = [{"v": self.conn.valores.get((params[0] or "").strip())}]

    def fetchall(self):
        return self.linhas

    def fetchone(self):
        return self.linhas[0] if self.linhas else None


class Conn:
    def __init__(self, pergunta=None):
        self.pergunta, self.consultas, self.commits = pergunta, [], 0
        self.valores = {"3.6k": 3600, "2.8k": 2800, "750k": 750000,
                        "3.600": 3600, "5k": 5000}

    def cursor(self):
        return Cursor(self)

    def commit(self):
        self.commits += 1


def rodar(texto, conn, postados):
    with patch("publicador._postar_agora",
               side_effect=lambda c, k, n=None: postados.append((c, n)) or "Pronto"):
        return publicador.processar_comando(texto, conexao=conn)


print()
print("--- NÃO POSTA SEM ELE ESCOLHER ---")
conn, postados = Conn(), []
r = rodar("Posta o jardim das cerejeiras", conn, postados)
print("   " + r.replace("\n", "\n   "))
checar("nada foi postado", postados, [])
checar_que("a pergunta lista as três opções (2 do 5725 + 1 do 5731)",
           r.count("5725") == 2 and "5731" in r, r)
checar_que("com o valor de cada uma", "3.6k" in r and "750k" in r and "2.8k" in r, r)
checar_que("e diz como responder", "código" in r and "valor" in r, r)
checar("a pergunta ficou guardada com os pares",
       sorted(conn.pergunta["candidatos"]),
       ["5725:locacao", "5725:venda", "5731:locacao"])

print()
print("--- 'para locação' já filtra o lado ---")
conn, postados = Conn(), []
r = rodar("posta o jardim das cerejeiras para locação", conn, postados)
checar("continua sem postar (são dois de locação)", postados, [])
checar("e os candidatos são só os de locação",
       sorted(conn.pergunta["candidatos"]), ["5725:locacao", "5731:locacao"])

print()
print("--- a resposta pelo CÓDIGO posta, com o lado certo ---")
conn, postados = Conn(), []
rodar("posta o jardim das cerejeiras para locação", conn, postados)
r = rodar("5731", conn, postados)
checar("postou o 5731", postados, [(["5731"], "locacao")])
checar("e a pergunta foi fechada", conn.pergunta, None)
# e a segunda vez não posta de novo
r2 = rodar("5731", conn, postados)
checar("responder duas vezes não posta duas vezes", len(postados), 1)
checar_que("e ela diz que não tem pergunta aberta", "não postei nada" in r2, r2)

print()
print("--- a resposta pelo VALOR posta, e o valor decide o lado ---")
conn, postados = Conn(), []
rodar("Posta o jardim das cerejeiras", conn, postados)
rodar("750k", conn, postados)
checar("750k é a VENDA do 5725", postados, [(["5725"], "venda")])

conn, postados = Conn(), []
rodar("Posta o jardim das cerejeiras", conn, postados)
rodar("3.6k", conn, postados)
checar("3.6k é a LOCAÇÃO do mesmo imóvel", postados, [(["5725"], "locacao")])

print()
print("--- 'locação' quando ainda sobram dois: pergunta de novo ---")
conn, postados = Conn(), []
rodar("Posta o jardim das cerejeiras", conn, postados)
r = rodar("locação", conn, postados)
checar("não postou", postados, [])
checar_que("e mostra os dois que sobraram", "5725" in r and "5731" in r, r)
checar("com os candidatos estreitados",
       sorted(conn.pergunta["candidatos"]), ["5725:locacao", "5731:locacao"])
r = rodar("5725", conn, postados)
checar("aí o código posta a locação", postados, [(["5725"], "locacao")])

print()
print("--- SÓ POSTA O QUE ELA OFERECEU ---")
conn, postados = Conn(), []
rodar("Posta o jardim das cerejeiras", conn, postados)
r = rodar("4159", conn, postados)
checar("código de fora não posta", postados, [])
checar_que("e ela diz por quê", "não estava nas opções" in r, r)

conn, postados = Conn(), []
rodar("Posta o jardim das cerejeiras", conn, postados)
r = rodar("5k", conn, postados)
checar("valor que não é de nenhuma opção não posta", postados, [])
checar_que("e ela diz que nenhuma custa isso", "custa 5k" in r, r)
# e o 2.8k, que É o valor de uma opção, posta a dela
conn, postados = Conn(), []
rodar("Posta o jardim das cerejeiras", conn, postados)
rodar("2.8k", conn, postados)
checar("2.8k posta o 5731", postados, [(["5731"], "locacao")])

print()
print("--- sem pergunta aberta, a resposta curta não posta nada ---")
conn, postados = Conn(), []
r = rodar("locação", conn, postados)
checar("nada postado", postados, [])
checar_que("e ela explica", "não tenho nenhuma pergunta" in r, r)

print()
print("--- a lista de categoria que nomeia um condomínio (15/09) ---")
# "envia as casas do morada dos pássaros para aluguel" tem a palavra "casas" e
# caía no disparo da lista INTEIRA de casas de locação, em TODOS os grupos
# parceiros -- por uma frase que fala de um condomínio só.
CONDOMINIOS.append(("Morada dos Pássaros", "morada dos passaros"))
conn = Conn()
r = publicador._disparar_lista(
    {"categoria": "casa_condominio", "negocio": "locacao", "destino": "parceiros",
     "texto": "envia as casas do morada dos pássaros para aluguel"}, conn)
checar_que("não disparou", "não disparei nada" in r, r)
checar_que("e diz qual lugar ela viu", "Morada dos Pássaros" in r, r)
checar_que("e ensina os dois caminhos", "Nay posta o" in r and "para <nome ou número>" in r, r)
# a lista de verdade não pode ser travada por isto
r = publicador._disparar_lista(
    {"categoria": "casa_condominio", "negocio": "locacao", "destino": "parceiros",
     "texto": "Nay dispara lista de casas em condomínio para locação"}, conn)
checar_que("a lista sem nome de lugar segue o caminho normal",
           "não disparei nada" not in r or "você nomeou" not in r, r)

# E PELO CAMINHO INTEIRO, não só chamando a função: a parede acima existia,
# este mesmo teste passava chamando `_disparar_lista` direto com o texto no
# dicionário -- e a lista saiu nos 15 grupos porque `processar_comando` não
# repassava a frase. Testar o módulo não é testar o caminho.
disparos = []
with patch("publicador._disparar_lista",
           side_effect=lambda c, k, **kw: disparos.append(c.get("texto")) or "ok"):
    publicador.processar_comando(
        "envia as casas do morada dos pássaros para aluguel", conexao=Conn())
checar("a frase original chega em quem decide", disparos,
       ["envia as casas do morada dos pássaros para aluguel"])

print()
print("--- o LADO escolhido é o lado que sai no card ---")
# `_so_esse_negocio` é o que faz isso: some com o valor do outro lado, e a
# regra única (`negocios_do_grupo`) passa a ver um imóvel de um negócio só.
imovel = {"valor_aluguel": 3600, "valor_venda": 750000}
grupo_tudo = {"aceita_venda": True, "aceita_locacao": True}
checar("sem escolha, o grupo vê os dois",
       negocios_do_grupo(imovel, grupo_tudo), {"venda", "locacao"})
checar("escolhendo locação, o grupo vê só locação",
       negocios_do_grupo(publicador._so_esse_negocio(imovel, "locacao"), grupo_tudo),
       {"locacao"})
checar("escolhendo venda, só venda",
       negocios_do_grupo(publicador._so_esse_negocio(imovel, "venda"), grupo_tudo),
       {"venda"})
checar("e o grupo que só aceita venda não recebe a locação escolhida",
       negocios_do_grupo(publicador._so_esse_negocio(imovel, "locacao"),
                         {"aceita_venda": True, "aceita_locacao": False}),
       set())

print()
if falhas:
    print(f"{falhas} CASO(S) FALHARAM")
    raise SystemExit(1)
print("TODOS OS CASOS DO POSTAR POR NOME PASSARAM")
