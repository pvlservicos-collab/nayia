"""
Testa o ENVIO POR LISTA COLADA: "Nay envia esses imóveis para <alguém>"
seguido das linhas, e a desambiguação "Nay codigo 5719".

POR QUE ELE EXISTE: o Tel pediu em 11/09 para colar a lista em vez de dar
código a código. A lista que ele cola é a que a PRÓPRIA Nay gerou
(`nay_linha_da_lista`), e essa função não é injetora -- o 5719 e o 5728 são
os dois 2 quartos / 1 suíte / 2.6k no Estilo Golf e rendem a MESMA linha.
Por isso a pergunta de desambiguação não é enfeite: é a única saída correta.

O QUE IMPORTA PROVAR, e o que cada coisa custa se quebrar:

  * a lista NÃO pode virar telefone. O corpo e a cauda do `ENVIO_RE` são
    gulosos e casam `\\n`; sem a parede, `_resolver_corretor` limpa os
    não-dígitos do bloco todo e o "telefone" vira a colagem dos números de
    todas as linhas -- medido com a lista dele: 25 dígitos, e os oito
    últimos NÃO são o número que ele quis. Se algum corretor tiver aquele
    final, a carteira vai para a pessoa errada, e envio não desfaz;

  * SEGURA TUDO até ele responder (decisão dele, 11/09). Mandar metade e
    perguntar o resto faria o corretor receber em duas levas;

  * linha REPETIDA não é engano: são dois imóveis. Deduplicar por texto
    entrega um e esconde o outro;

  * o portão da resposta falha FECHADO. Sem lista em aberto, com a janela
    vencida, ou com código que ela não ofereceu, a resposta é recusa com o
    comando pronto -- nunca envio para o destinatário da lista anterior;

  * imóvel fora do site é recusa DITA, nunca sumiço calado (foi o sumiço
    que escondeu 112 apartamentos de venda em 09/09);

  * parecença de nome (faixa 5) não vira envio, só "você quis dizer?".

Uso:
    .venv/bin/python teste_envio_de_lista.py
"""
import json

import publicador
from interpretar_comando import interpretar_comando as ic

falhas = 0


def checar(titulo, obtido, esperado_em):
    """`esperado_em` é um pedaço que TEM que aparecer na resposta."""
    global falhas
    ok = esperado_em.lower() in str(obtido).lower()
    falhas += 0 if ok else 1
    print(f"  {'OK  ' if ok else 'FALHOU'} {titulo}")
    if not ok:
        print(f"         esperava conter: {esperado_em!r}")
        print(f"         recebeu:         {str(obtido)[:300]!r}")


# --------------------------------------------------------------------
# O banco falso. `nay_imoveis_da_linha` é a única consulta que decide
# código, e ela mora no SQL -- aqui ela é alimentada por um dicionário, e a
# regra de verdade é exercitada por `teste_envio_por_descricao.sql` contra
# o catálogo inteiro. Testar a regra aqui seria uma SEGUNDA cópia dela.
CATALOGO = {
    "Arezzo Residencial / 2 quartos / 2.5k": [
        {"codigo": "5718", "faixa": 0, "negocio": "locacao", "no_mercado": True}],
    "Ariranhas / 2 quartos / 2.6k (incluso a tx)": [
        {"codigo": "5729", "faixa": 0, "negocio": "locacao", "no_mercado": True}],
    "Estilo Golf / 2 quartos sendo 1 suíte / 2.6k": [
        {"codigo": "5719", "faixa": 0, "negocio": "locacao", "no_mercado": True},
        {"codigo": "5728", "faixa": 0, "negocio": "locacao", "no_mercado": True}],
    # reconhecido, mas o anúncio saiu do ar
    "Brisas do Lírio / 2 quartos / 2.4k": [
        {"codigo": "5110", "faixa": 0, "negocio": "locacao", "no_mercado": False}],
    # duas linhas ambíguas na mesma lista
    "Alphaville 2 / 550k": [
        {"codigo": "5282", "faixa": 0, "negocio": "venda", "no_mercado": True},
        {"codigo": "5283", "faixa": 0, "negocio": "venda", "no_mercado": True}],
}


class CursorFake:
    def __init__(self, conn):
        self.conn = conn
        self.linhas = []

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def execute(self, sql, params=None):
        self.linhas = []
        if "nay_imoveis_da_linha" in sql:
            self.linhas = list(CATALOGO.get(params[0], []))
        elif "FROM corretores" in sql:
            self.linhas = list(self.conn.corretores)
        elif "FROM envio_pendente" in sql and sql.strip().upper().startswith("SELECT"):
            self.linhas = [self.conn.pendente] if self.conn.pendente else []
        elif "INSERT INTO envio_pendente" in sql:
            self.conn.pendente = {
                "id": 1, "destino_telefone": params[0], "destino_nome": params[1],
                "codigos": list(params[2]), "ambiguas": params[3],
                "sem_casar": list(params[4]), "fora_do_site": list(params[5])}
        elif "UPDATE envio_pendente SET codigos" in sql:
            self.conn.pendente["codigos"] = list(params[0])
            self.conn.pendente["ambiguas"] = params[1]
        elif "UPDATE envio_pendente SET fechado_em" in sql:
            self.conn.fechados.append(params[0])
            self.conn.pendente = None

    def fetchall(self):
        return self.linhas

    def fetchone(self):
        return self.linhas[0] if self.linhas else None


class ConnFake:
    def __init__(self, corretores=None, pendente=None):
        self.corretores = corretores if corretores is not None else [
            {"telefone": "559294717316", "nome": "Tel Sobreira"}]
        self.pendente = pendente
        self.fechados = []

    def cursor(self):
        return CursorFake(self)

    def commit(self):
        pass

    def close(self):
        pass


# O envio de verdade nunca roda aqui: manda card e TODAS as fotos.
mandados = []


def _fingir_envio(conn, telefone, nome, codigos):
    mandados.append((telefone, nome, list(codigos)))
    return f"mandei {len(codigos)} imovel(is) para {nome}:\n" + "\n".join(codigos)


publicador._mandar_os_codigos = _fingir_envio

LISTA_DELE = """Nay envia esses imóveis para o número 92994717316

Arezzo Residencial / 2 quartos / 2.5k
Ariranhas / 2 quartos / 2.6k (incluso a tx)
Estilo Golf / 2 quartos sendo 1 suíte / 2.6k
Estilo Golf / 2 quartos sendo 1 suíte / 2.6k"""


print("--- a gramática reconhece a lista colada ---")
r = ic(LISTA_DELE)
checar("vira enviar_lista_para_corretor", r["acao"], "enviar_lista_para_corretor")
# Desde 14/09 o destino É o telefone quando ele está escrito -- "para Ana
# 92 9396-5797 os imóveis que ela está pedindo" põe o telefone no MEIO da
# frase, e o resto é pedido. O que este caso protege continua: o destino não
# engole a lista.
checar("o destino é o telefone, sem a lista", r["destino"], "92994717316")
checar("as 4 linhas viram itens", len(r["linhas"]), "4")

print()
print("--- A PAREDE: a lista nunca pode virar telefone ---")
# Sem o corte na quebra de linha, `_resolver_corretor` veria 25 dígitos e
# procuraria o final "21262126", que não é o número dele.
r_env = ic("Nay manda o 5750 pro Sergio\nArezzo Residencial / 2 quartos / 2.5k")
checar("destino sem quebra de linha", "\n" not in r_env.get("destino", ""), "true")
checar("destino é só a pessoa", r_env.get("destino"), "Sergio")

print()
print("--- verbo de GRUPO com lista: recusa que ensina ---")
r_grupo = ic("Nay posta esses imóveis para o Sergio\nArezzo Residencial / 2 quartos / 2.5k")
checar("posta + pessoa + lista = recusa", r_grupo["acao"], "envio_recusado")
checar("a recusa ensina a forma certa", r_grupo["motivo"], "Nay envia esses imoveis pro")

print()
print("--- código no cabeçalho segue o caminho antigo ---")
r_cod = ic("Nay envia o 5718 para o Sergio\nvaleu")
checar("não sequestra o envio por código", r_cod["acao"], "enviar_para_corretor")

print()
print("--- SEGURA TUDO: com ambiguidade, nada sai ---")
mandados.clear()
conn = ConnFake()
resp = publicador.processar_comando(LISTA_DELE, conexao=conn)
checar("diz que não mandou nada ainda", resp, "nao mandei nada ainda")
checar("nenhum envio de verdade saiu", len(mandados), "0")
checar("mostra a linha repetida como 2x", resp, "veio 2x")
checar("manda os dois links", resp, "https://imobeasy.com/imoveis/5719")
checar("e o segundo link", resp, "https://imobeasy.com/imoveis/5728")
checar("ensina a resposta natural PRIMEIRO", resp, 'responde "os dois"')
checar("e ensina a forma de um so", resp, "codigo 5719")
# O nó `Achar codigo na resposta` roda /C[óo]digo:\s*(\d{3,5})/ na resposta
# DELA e manda as fotos para o chat do próprio Tel. Link puro não dispara.
checar("NUNCA escreve 'Código: NNNN'", "ódigo:" not in resp and "odigo:" not in resp, "true")

print()
print("--- ele escolhe UM: sai a lista inteira, de uma vez ---")
mandados.clear()
resp = publicador.processar_comando("Nay codigo 5719", conexao=conn)
checar("saiu um envio só", len(mandados), "1")
checar("com os três imóveis", sorted(mandados[0][2]), "['5718', '5719', '5729']")
checar("para o destinatário da lista", mandados[0][0], "559294717316")

print()
print("--- ele escolhe OS DOIS ---")
mandados.clear()
conn = ConnFake()
publicador.processar_comando(LISTA_DELE, conexao=conn)
publicador.processar_comando("Nay codigo 5719 e 5728", conexao=conn)
checar("os quatro imóveis saem juntos", sorted(mandados[0][2]),
       "['5718', '5719', '5728', '5729']")

print()
print("--- O PORTÃO FALHA FECHADO ---")
mandados.clear()
conn_vazia = ConnFake()
resp = publicador.processar_comando("Nay codigo 5719", conexao=conn_vazia)
checar("sem lista em aberto não envia", len(mandados), "0")
checar("e devolve o comando pronto", resp, "nay envia o 5719 para")

mandados.clear()
conn = ConnFake()
publicador.processar_comando(LISTA_DELE, conexao=conn)
resp = publicador.processar_comando("Nay codigo 9999", conexao=conn)
checar("código que ela não ofereceu não envia", len(mandados), "0")
checar("e explica", resp, "nao esta entre os que eu te ofereci")

print()
print("--- duas linhas ambíguas: uma resposta não libera o envio ---")
mandados.clear()
conn = ConnFake()
duas = ("Nay envia esses imóveis para o número 92994717316\n"
        "Estilo Golf / 2 quartos sendo 1 suíte / 2.6k\n"
        "Alphaville 2 / 550k")
publicador.processar_comando(duas, conexao=conn)
resp = publicador.processar_comando("Nay codigo 5719", conexao=conn)
checar("ainda não envia", len(mandados), "0")
checar("diz o que falta", resp, "ainda falta resolver")
checar("e mostra a outra linha", resp, "Alphaville")
resp = publicador.processar_comando("Nay codigo 5282", conexao=conn)
checar("agora sai", len(mandados), "1")
checar("com os dois escolhidos", sorted(mandados[0][2]), "['5282', '5719']")

print()
print("--- imóvel fora do site: recusa DITA, nunca sumiço ---")
mandados.clear()
conn = ConnFake()
resp = publicador.processar_comando(
    "Nay envia esses imóveis para o número 92994717316\n"
    "Arezzo Residencial / 2 quartos / 2.5k\n"
    "Brisas do Lírio / 2 quartos / 2.4k", conexao=conn)
checar("manda o que pode", len(mandados), "1")
checar("só o que está no ar", mandados[0][2], "['5718']")
checar("e diz qual saiu do site", resp, "saiu do site")
checar("nomeando o código", resp, "5110")

print()
print("--- linha que não casa com nada: dita, não engolida ---")
mandados.clear()
conn = ConnFake()
resp = publicador.processar_comando(
    "Nay envia esses imóveis para o número 92994717316\n"
    "Arezzo Residencial / 2 quartos / 2.5k\n"
    "Xanadu Imperial / 9 quartos / 99k", conexao=conn)
checar("manda o que resolveu", mandados[0][2], "['5718']")
checar("e diz o que não achou", resp, "nao achei imovel para")
checar("mostrando a linha", resp, "Xanadu Imperial")

print()
print("--- nenhuma linha resolve: não envia e explica ---")
mandados.clear()
conn = ConnFake()
resp = publicador.processar_comando(
    "Nay envia esses imóveis para o número 92994717316\n"
    "Xanadu Imperial / 9 quartos / 99k", conexao=conn)
checar("não mandou nada", len(mandados), "0")
checar("e explica", resp, "nao consegui identificar nenhum imovel")

print()
print("--- corretor não cadastrado: não envia ---")
mandados.clear()
conn = ConnFake(corretores=[])
resp = publicador.processar_comando(LISTA_DELE, conexao=conn)
checar("não mandou nada", len(mandados), "0")
checar("pede para cadastrar", resp, "nao esta cadastrado")

print()
print("--- lista nova fecha a anterior ---")
mandados.clear()
conn = ConnFake()
publicador.processar_comando(LISTA_DELE, conexao=conn)
resp = publicador.processar_comando(LISTA_DELE, conexao=conn)
checar("avisa que descartou a anterior", resp, "lista anterior")
checar("e fechou a linha velha", "trocado" in conn.fechados, "true")

print()
print("--- A RESPOSTA NATURAL: o bug de 12/09 ---")
# Ele respondeu "os dois" -- a frase que a PRÓPRIA pergunta dela sugeria -- e
# caiu no agente, que devolveu uma lista de imóveis sem nexo. Pergunta que não
# resolve na volta é laço fechado, não desambiguação.
# "tudo" e "me manda os dois" NÃO estão aqui, e a ausência é deliberada:
# "tudo sim" é o pedaço que ele lembra do "DESCARTAR TUDO SIM", e o "me" de
# "me manda" nomeia OUTRO destinatário (ele mesmo) no vocabulário medido dele.
for frase in ["os dois", "os 2", "ambos", "as duas", "todos",
              "manda os dois", "quero os dois", "pode mandar os dois",
              "sim os dois", "os dois estilo golf", "todos eles",
              "5719 e 5728", "manda o 5719 e o 5728", "Nay os dois"]:
    mandados.clear()
    conn = ConnFake()
    publicador.processar_comando(LISTA_DELE, conexao=conn)
    publicador.processar_comando(frase, conexao=conn)
    checar(f'{frase!r} manda os dois do Estilo Golf',
           sorted(mandados[0][2]) if mandados else "(nada saiu)",
           "['5718', '5719', '5728', '5729']")

print()
print("--- posição na lista ---")
for frase, esperado in [("o primeiro", "['5718', '5719', '5729']"),
                        ("o segundo", "['5718', '5728', '5729']"),
                        ("o ultimo", "['5718', '5728', '5729']")]:
    mandados.clear()
    conn = ConnFake()
    publicador.processar_comando(LISTA_DELE, conexao=conn)
    publicador.processar_comando(frase, conexao=conn)
    checar(f'{frase!r}', sorted(mandados[0][2]) if mandados else "(nada saiu)", esperado)

print()
print("--- 'sim' e 'isso' SOZINHOS não enviam ---")
# Ele usa "isso" como confirmação genérica (medido nas mensagens reais). Com
# uma lista em aberto, um "isso" sobre outro assunto mandaria a carteira sem
# ele ter pedido -- e envio não desfaz.
for frase in ["sim", "isso", "ok", "pode", "manda"]:
    mandados.clear()
    conn = ConnFake()
    publicador.processar_comando(LISTA_DELE, conexao=conn)
    publicador.processar_comando(frase, conexao=conn)
    checar(f'{frase!r} não dispara envio', len(mandados), "0")

print()
print("--- a conta tem que fechar: falha FECHADA ---")
mandados.clear()
conn = ConnFake()
publicador.processar_comando(LISTA_DELE, conexao=conn)
resp = publicador.processar_comando("os tres", conexao=conn)
checar("'os tres' com 2 candidatos não envia", len(mandados), "0")
checar("e explica a conta", resp, "nesta linha são 2")

print()
print("--- duas linhas ambíguas: 'os dois' é ambíguo ---")
mandados.clear()
conn = ConnFake()
duas = ("Nay envia esses imóveis para o número 92994717316\n"
        "Estilo Golf / 2 quartos sendo 1 suíte / 2.6k\n"
        "Alphaville 2 / 550k")
resp = publicador.processar_comando(duas, conexao=conn)
# UMA LINHA POR VEZ: com duas em aberto, toda resposta curta seria ambígua.
# Mostrando uma só, "os dois" tem um referente só -- e as opções vêm
# NUMERADAS, senão "o primeiro" é ordinal contra lista sem ordem escrita.
checar("mostra UMA linha por vez", resp, "ainda tenho 1 linha")
checar("com as opções numeradas", resp, "1) https://imobeasy.com/imoveis/")
checar("ensina 'os dois' para a linha mostrada", resp, 'responde "os dois"')
resp = publicador.processar_comando("os dois", conexao=conn)
checar("'os dois' resolve a linha mostrada", len(mandados), "0")
checar("e ela pergunta a seguinte", resp, "ainda falta resolver")
resp = publicador.processar_comando("os dois", conexao=conn)
checar("resolvida a segunda, o envio sai", len(mandados), "1")
checar("com os quatro códigos", sorted(mandados[0][2]),
       "['5282', '5283', '5719', '5728']")

print()
print("--- 'os dois' sem lista em aberto ---")
mandados.clear()
resp = publicador.processar_comando("os dois", conexao=ConnFake())
checar("não envia", len(mandados), "0")
checar("e diz que não sabe de quais imóveis", resp, "nao sei de quais imoveis")

print()
print()
print("--- o que NUNCA pode virar escolha ---")
# AS PRÓPRIAS LINHAS DA LISTA. Medido: "2 quartos sendo 1 suíte / 2.6k"
# devolvia {quantos: 2}, e o nó do n8n percorre o texto LINHA POR LINHA --
# então uma linha de PREÇO disparava o envio da carteira.
for frase in ["2 quartos sendo 1 suite / 2.6k", "3 quartos / 450k",
              "duas suites", "2 vagas", "2.6k",
              "Estilo Golf / 2 quartos sendo 1 suíte / 2.6k"]:
    mandados.clear()
    conn = ConnFake()
    publicador.processar_comando(LISTA_DELE, conexao=conn)
    publicador.processar_comando(frase, conexao=conn)
    checar(f"linha de imóvel {frase[:28]!r} não envia", len(mandados), "0")

# DÍGITO CRU não é intenção -- a lição do "as 08:00" e do valor 4000. E "2"
# como resposta a "qual?" quer dizer "o segundo", não "dois deles".
for frase in ["1", "2", "3", "tudo", "tudo sim", "me manda os dois"]:
    mandados.clear()
    conn = ConnFake()
    publicador.processar_comando(LISTA_DELE, conexao=conn)
    publicador.processar_comando(frase, conexao=conn)
    checar(f"{frase!r} não envia", len(mandados), "0")

# GRUPO não é pessoa: ele acharia que postou em 14 grupos e não postou.
for frase in ["os dois no grupo", "manda os dois no easy"]:
    mandados.clear()
    conn = ConnFake()
    publicador.processar_comando(LISTA_DELE, conexao=conn)
    publicador.processar_comando(frase, conexao=conn)
    checar(f"{frase!r} não envia", len(mandados), "0")

print()
print("--- a COLISÃO que a primeira versão causou ---")
# Esta frase está citada no próprio interpretar_comando.py como forma viva do
# envio por descrição. Com a escolha natural rodando cedo no dispatch, ela
# virava escolha com o "Sergio" DESCARTADO, e a carteira ia para o
# destinatário da lista em aberto. Envio para a pessoa errada.
for frase in ["Nay envia todos os acquarelle para locacao para o corretor Sergio",
              "manda os dois pro Sergio", "manda todos pro Sergio"]:
    r = ic(frase)
    checar(f"{frase[:42]!r} continua sendo ENVIO", r["acao"],
           "enviar_para_corretor")

print()
print()
print("--- a lista no formato de 15/09, colada INTEIRA ---")
# Ele copia a mensagem da lista do jeito que ela chega: título entre 🔥, linha
# em branco, e os imóveis. O título não pode virar "não achei imóvel para".
mandados.clear()
conn = ConnFake()
resp = publicador.processar_comando(
    "Nay envia esses imóveis para o número 92994717316\n"
    "🔥 APARTAMENTOS PARA LOCAÇÃO DE 1.9k A 10k 🔥\n"
    "\n"
    "Arezzo Residencial / 2 quartos / 2.5k", conexao=conn)
checar("o título não vira 'não achei'", "nao achei" not in resp, "true")
checar("e o imóvel sai", mandados[0][2] if mandados else "(nada)", "['5718']")


print()
print("--- FONTE UNICA: os mesmos casos do teste JS ---")
# `casos_envio_de_lista.json` e lido por este teste E por
# `teste_regex_envio_de_lista.js`, que roda no Node do container. A
# gramatica do Tel vive em quatro copias e ja divergiu sozinha; com a lista
# de casos compartilhada, divergencia vira vermelho em vez de comando morto.
#
# "lista" no arquivo significa "o no tem que mandar o TEXTO INTEIRO ao
# publicador". Do lado Python isso pode virar o envio OU a recusa que ensina
# ("posta esses imoveis pro Sergio") -- as duas precisam do texto todo, e e
# por isso que as duas contam como lista.
with open("casos_envio_de_lista.json", encoding="utf-8") as f:
    casos = json.load(f)

DE_ACAO = {
    "enviar_lista_para_corretor": "lista",
    "envio_recusado": "lista",
    "escolher_codigos": "escolha",
}
for texto, esperado in casos:
    acao = ic(texto)["acao"]
    deu = DE_ACAO.get(acao, "nada")
    curto = texto.replace("\n", " | ")[:52]
    checar(f"{deu:7s} {curto}", deu, esperado)

print()
if falhas:
    print(f"{falhas} CASOS FALHARAM")
    raise SystemExit(1)
print("TODOS OS CASOS DO ENVIO POR LISTA PASSARAM")
