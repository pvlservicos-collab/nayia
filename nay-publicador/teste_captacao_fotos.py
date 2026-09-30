"""
Prova o baixador de fotos da captação sem tocar na rede.

O DUBLÊ REPRODUZ O QUE FOI MEDIDO NO SERVIDOR em 02/09/2026, e é isso que dá
valor a este teste: URL que não existe devolve **404 com um JPEG de verdade
dentro** -- 49.639 bytes, `Content-Type: image/jpeg`, um quadrado cinza 640x640.
O placeholder é MAIOR que muita foto legítima, então nenhum piso de tamanho o
pega; quem pega é o status. Se alguém um dia "simplificar" o `_conferir` e tirar
a checagem de status, o caso 2 fica vermelho.

Os outros casos guardam o resto do que faz esta pasta encher de lixo: HTML de
erro servido como imagem, resposta truncada, arquivo pela metade de uma execução
morta no meio, foto repetida na lista, e o CDN fora do ar (falha seguida).

    .venv/bin/python teste_captacao_fotos.py
"""
import builtins
import os
import shutil
import sys
import tempfile

import captacao_fotos as cf

falhas = 0


def checar(rotulo, condicao, detalhe=""):
    global falhas
    if condicao:
        print(f"  OK   {rotulo}")
    else:
        falhas += 1
        print(f"  FALHOU {rotulo} {detalhe}")


# --- os corpos, com os tamanhos medidos de verdade ---------------------------
JPEG = b"\xff\xd8\xff\xe0"
FOTO = JPEG + b"conteudo de foto" * 12000              # ~192 KB, como a real
# Exatamente os 49.639 bytes do quadrado cinza que a OLX manda no 404.
PLACEHOLDER = JPEG + b"\x20" * (49639 - 4)
PNG = b"\x89PNG\r\n\x1a\n" + b"0" * 60000
HTML = b"<!doctype html><html><body>erro</body></html>" * 200


class Resposta:
    def __init__(self, status_code, content, tipo="image/jpeg"):
        self.status_code = status_code
        self.content = content
        self.headers = {"Content-Type": tipo}


class Baixador:
    """URL não mapeada responde como o CDN da OLX responde de verdade:
    404 com o JPEG cinza dentro."""

    def __init__(self, mapa=None):
        self.mapa = mapa or {}
        self.chamadas = []

    def __call__(self, url):
        self.chamadas.append(url)
        r = self.mapa.get(url)
        if r is None:
            return Resposta(404, PLACEHOLDER)
        if isinstance(r, Exception):
            raise r
        return r


U1 = "https://img.olx.com.br/images/48/481626791965796.jpg"
U2 = "https://img.olx.com.br/images/50/505613799054848.jpg"
U3 = "https://img.olx.com.br/images/51/517777799054848.jpg"

pasta_raiz = tempfile.mkdtemp(prefix="teste_captacao_fotos_")


def nova_pasta(nome):
    caminho = os.path.join(pasta_raiz, nome)
    os.makedirs(caminho, exist_ok=True)
    return caminho


def arquivos(pasta):
    return sorted(os.listdir(pasta))


try:
    print("--- 1. as três fotos, na ordem, a primeira é a capa ---")
    pasta = nova_pasta("feliz")
    b = Baixador({U1: Resposta(200, FOTO), U2: Resposta(200, FOTO),
                  U3: Resposta(200, PNG)})
    pausas = []
    r = cf.baixar([U1, U2, U3], pasta, baixador=b, pausa=pausas.append)
    checar("3 fotos e nenhuma falha", len(r["fotos"]) == 3 and not r["falhas"], r)
    checar("ordem preservada", [f["ordem"] for f in r["fotos"]] == [1, 2, 3])
    checar("só a primeira é capa",
           [f["e_capa"] for f in r["fotos"]] == [True, False, False])
    checar("os arquivos existem em disco",
           all(os.path.exists(f["arquivo"]) for f in r["fotos"]))
    checar("o nome guarda a posição e o id da OLX",
           os.path.basename(r["fotos"][0]["arquivo"]) == "01-481626791965796.jpg",
           os.path.basename(r["fotos"][0]["arquivo"]))
    checar("extensão vem do conteúdo, não da URL (.jpg na URL, PNG dentro)",
           r["fotos"][2]["arquivo"].endswith(".png"),
           r["fotos"][2]["arquivo"])
    checar("bytes conferem", r["fotos"][0]["bytes"] == len(FOTO))
    checar("pausou entre downloads, não antes do primeiro", len(pausas) == 2, pausas)
    checar("nenhum .parcial ficou para trás",
           not [a for a in arquivos(pasta) if a.endswith(".parcial")], arquivos(pasta))

    print("\n--- 2. O CASO: 404 com JPEG de verdade dentro (medido) ---")
    pasta = nova_pasta("placeholder")
    b = Baixador({U1: Resposta(200, FOTO)})      # U2 não existe -> 404 + cinza
    r = cf.baixar([U1, U2], pasta, baixador=b, pausa=lambda s: None)
    checar("o placeholder tem 49.639 bytes, como o medido", len(PLACEHOLDER) == 49639)
    checar("o placeholder é maior que o piso de tamanho -- piso não o pegaria",
           len(PLACEHOLDER) > cf.PESO_MINIMO)
    checar("a foto do 404 NÃO foi gravada", arquivos(pasta) == ["01-481626791965796.jpg"],
           arquivos(pasta))
    checar("entrou em falhas com o status no motivo",
           len(r["falhas"]) == 1 and "404" in r["falhas"][0]["motivo"], r["falhas"])
    checar("a foto boa passou mesmo assim", len(r["fotos"]) == 1)

    print("\n--- 3. resposta que não é foto ---")
    pasta = nova_pasta("nao_e_foto")
    b = Baixador({U1: Resposta(200, HTML, tipo="text/html; charset=utf-8"),
                  U2: Resposta(200, HTML, tipo="image/jpeg"),
                  U3: Resposta(200, JPEG + b"x" * 100)})
    r = cf.baixar([U1, U2, U3], pasta, baixador=b, pausa=lambda s: None)
    checar("HTML declarado como HTML é recusado pelo Content-Type",
           "Content-Type" in r["falhas"][0]["motivo"], r["falhas"][0])
    checar("HTML MENTINDO que é image/jpeg morre na assinatura dos bytes",
           "primeiros bytes" in r["falhas"][1]["motivo"], r["falhas"][1])
    checar("resposta truncada é recusada pelo piso",
           "truncada" in r["falhas"][2]["motivo"], r["falhas"][2])
    checar("a pasta ficou vazia -- nada de lixo em disco", arquivos(pasta) == [],
           arquivos(pasta))

    print("\n--- 4. retomada: o que já está em disco não baixa de novo ---")
    pasta = nova_pasta("retomada")
    b = Baixador({U1: Resposta(200, FOTO), U2: Resposta(200, FOTO)})
    cf.baixar([U1, U2], pasta, baixador=b, pausa=lambda s: None)
    b2 = Baixador({U1: Resposta(200, FOTO), U2: Resposta(200, FOTO)})
    pausas = []
    r = cf.baixar([U1, U2], pasta, baixador=b2, pausa=pausas.append)
    checar("não foi à rede nenhuma vez", b2.chamadas == [], b2.chamadas)
    checar("nem pausou -- ninguém foi martelado", pausas == [])
    checar("as duas contam como fotos", len(r["fotos"]) == 2)
    checar("estado diz 'ja_estava'",
           all(f["estado"] == "ja_estava" for f in r["fotos"]))
    checar("a capa continua sendo a primeira", r["fotos"][0]["e_capa"] is True)

    print("\n--- 5. retomada NÃO confia em arquivo pela metade ---")
    pasta = nova_pasta("meio_arquivo")
    with open(os.path.join(pasta, "01-481626791965796.jpg"), "wb") as s:
        s.write(b"\xff\xd8\xff\xe0meia foto")     # execução morta no meio
    b = Baixador({U1: Resposta(200, FOTO)})
    r = cf.baixar([U1], pasta, baixador=b, pausa=lambda s: None)
    checar("baixou de novo", b.chamadas == [U1], b.chamadas)
    checar("o arquivo agora está inteiro", r["fotos"][0]["bytes"] == len(FOTO))
    # Um `.parcial` do tamanho de uma foto inteira é exatamente o que sobra de
    # um processo morto DEPOIS de escrever e ANTES do rename: se a retomada o
    # aceitasse, a foto ficaria com o nome errado e nunca seria regravada.
    with open(os.path.join(pasta, "02-505613799054848.jpg.parcial"), "wb") as s:
        s.write(FOTO)
    checar("um .parcial largado no disco não é aceito como foto",
           cf._ja_baixada(pasta, "02-505613799054848") is None)

    print("\n--- 6. uma foto ruim não derruba as outras ---")
    pasta = nova_pasta("segue")
    b = Baixador({U1: Resposta(200, FOTO),
                  U2: OSError("conexão fechada pelo servidor"),
                  U3: Resposta(200, FOTO)})
    r = cf.baixar([U1, U2, U3], pasta, baixador=b, pausa=lambda s: None)
    checar("as duas boas foram baixadas", len(r["fotos"]) == 2)
    checar("a terceira foi tentada depois da falha",
           [f["ordem"] for f in r["fotos"]] == [1, 3])
    checar("a falha traz o erro da rede, sem explodir",
           "OSError" in r["falhas"][0]["motivo"], r["falhas"])

    print("\n--- 7. CDN fora: para nas falhas seguidas e diz o que não tentou ---")
    pasta = nova_pasta("cdn_fora")
    urls = [f"https://img.olx.com.br/images/48/48162679196{n:04d}.jpg"
            for n in range(8)]
    b = Baixador({})                              # tudo 404, como CDN bloqueado
    r = cf.baixar(urls, pasta, baixador=b, pausa=lambda s: None)
    checar(f"parou depois de {cf.MAX_FALHAS_SEGUIDAS} tentativas",
           len(b.chamadas) == cf.MAX_FALHAS_SEGUIDAS, b.chamadas)
    checar("as 8 aparecem como falha -- nenhuma some do relatório",
           len(r["falhas"]) == 8, len(r["falhas"]))
    checar("as não tentadas dizem que não foram tentadas",
           "não tentada" in r["falhas"][-1]["motivo"], r["falhas"][-1])

    print("\n--- 8. lista suja: repetida, vazia, None ---")
    pasta = nova_pasta("lista_suja")
    b = Baixador({U1: Resposta(200, FOTO), U2: Resposta(200, FOTO)})
    r = cf.baixar([U1, "", U1, None, U2, "  "], pasta, baixador=b,
                  pausa=lambda s: None)
    checar("repetida baixa uma vez só", b.chamadas == [U1, U2], b.chamadas)
    checar("2 fotos, sem falha", len(r["fotos"]) == 2 and not r["falhas"], r)
    checar("lista vazia não quebra e não cria nada",
           cf.baixar([], nova_pasta("vazia"), baixador=b)["fotos"] == [])

    print("\n--- 9. nome de arquivo não escapa da pasta ---")
    pasta = nova_pasta("travessia")
    malicioso = "https://img.olx.com.br/../../../../etc/cron.d/ruim.jpg"
    base = cf.nome_base(1, malicioso)
    checar("sem barra e sem ponto-ponto no nome",
           "/" not in base and ".." not in base, base)
    b = Baixador({malicioso: Resposta(200, FOTO)})
    r = cf.baixar([malicioso], pasta, baixador=b, pausa=lambda s: None)
    checar("gravou dentro da pasta pedida",
           os.path.dirname(os.path.abspath(r["fotos"][0]["arquivo"]))
           == os.path.abspath(pasta), r["fotos"][0]["arquivo"])
    checar("URL sem nome aproveitável ganha nome mesmo assim",
           cf.nome_base(2, "https://img.olx.com.br/").startswith("02-"),
           cf.nome_base(2, "https://img.olx.com.br/"))

    print("\n--- 10. se a foto 1 falha, NADA vem marcado como capa ---")
    pasta = nova_pasta("sem_capa")
    b = Baixador({U2: Resposta(200, FOTO)})       # U1 não existe
    r = cf.baixar([U1, U2], pasta, baixador=b, pausa=lambda s: None)
    checar("a foto 2 não virou capa às escondidas",
           [f["e_capa"] for f in r["fotos"]] == [False], r["fotos"])
    checar("e a falha da capa está registrada",
           r["falhas"][0]["ordem"] == 1)

    print("\n--- 11. tamanho absurdo é recusado ---")
    pasta = nova_pasta("gigante")
    b = Baixador({U1: Resposta(200, JPEG + b"0" * (cf.PESO_MAXIMO + 1))})
    r = cf.baixar([U1], pasta, baixador=b, pausa=lambda s: None)
    checar("recusou o corpo gigante",
           "grande demais" in r["falhas"][0]["motivo"], r["falhas"])
    checar("e não gravou nada", arquivos(pasta) == [], arquivos(pasta))

    # ------------------------------------------------------------------
    # Daqui para baixo: casos levantados na revisão de 02/09/2026.
    # ------------------------------------------------------------------

    print("\n--- 12. disco cheio vira FALHA, não traceback ---")
    # Era um bug de verdade: `_gravar` ficava fora do `try` e a OSError subia
    # por `baixar` inteiro. Na foto 12 de 16, o Tel perdia o registro das 11
    # que já tinham vindo e recebia um traceback no lugar do relatório.
    pasta = nova_pasta("disco_cheio")
    abrir_de_verdade = builtins.open

    def abrir_sem_espaco(caminho, modo="r", *a, **k):
        if str(caminho).endswith(".parcial"):
            raise OSError(28, "No space left on device")
        return abrir_de_verdade(caminho, modo, *a, **k)

    b = Baixador({U1: Resposta(200, FOTO), U2: Resposta(200, FOTO)})
    builtins.open = abrir_sem_espaco
    try:
        r = cf.baixar([U1, U2], pasta, baixador=b, pausa=lambda s: None)
        explodiu = None
    except Exception as erro:                     # é exatamente o que não pode
        r, explodiu = None, f"{type(erro).__name__}: {erro}"
    finally:
        builtins.open = abrir_de_verdade
    checar("não explodiu: o chamador recebeu o relatório", explodiu is None, explodiu)
    checar("as duas viraram falha, nenhuma virou foto",
           r and not r["fotos"] and len(r["falhas"]) == 2, r)
    checar("o motivo é português e diz o que olhar",
           r and "espaço e permissão" in r["falhas"][0]["motivo"], r and r["falhas"])
    checar("não sobrou .parcial na pasta que encheu o disco",
           arquivos(pasta) == [], arquivos(pasta))

    print("\n--- 13. disco cheio para nas falhas seguidas, não tenta as 16 ---")
    pasta = nova_pasta("disco_cheio_para")
    urls16 = [f"https://img.olx.com.br/images/48/48162679196{n:04d}.jpg"
              for n in range(16)]
    b = Baixador({u: Resposta(200, FOTO) for u in urls16})
    builtins.open = abrir_sem_espaco
    try:
        r = cf.baixar(urls16, pasta, baixador=b, pausa=lambda s: None)
    finally:
        builtins.open = abrir_de_verdade
    checar(f"parou depois de {cf.MAX_FALHAS_SEGUIDAS}, não martelou o CDN 16 vezes",
           len(b.chamadas) == cf.MAX_FALHAS_SEGUIDAS, len(b.chamadas))
    checar("as 16 continuam no relatório", len(r["falhas"]) == 16, len(r["falhas"]))

    print("\n--- 14. escrita que morre NO MEIO não deixa .parcial para trás ---")
    pasta = nova_pasta("morreu_escrevendo")

    class SaidaQueMorre:
        def __init__(s, caminho):
            s.arquivo = abrir_de_verdade(caminho, "wb")
        def write(s, dados):
            s.arquivo.write(dados[:10])           # escreveu um pedaço e morreu
            raise OSError(28, "No space left on device")
        def __enter__(s):
            return s
        def __exit__(s, *a):
            s.arquivo.close()
            return False

    def abrir_que_morre(caminho, modo="r", *a, **k):
        if str(caminho).endswith(".parcial"):
            return SaidaQueMorre(caminho)
        return abrir_de_verdade(caminho, modo, *a, **k)

    b = Baixador({U1: Resposta(200, FOTO)})
    builtins.open = abrir_que_morre
    try:
        r = cf.baixar([U1], pasta, baixador=b, pausa=lambda s: None)
    finally:
        builtins.open = abrir_de_verdade
    checar("virou falha, não traceback", len(r["falhas"]) == 1, r)
    checar("o pedaço escrito foi removido -- pasta limpa",
           arquivos(pasta) == [], arquivos(pasta))

    print("\n--- 15. pasta com colchete no nome não mata a retomada ---")
    # `glob` trata `[` como metacaractere. Sem `glob.escape`, a retomada não
    # achava nada e a captação inteira voltava ao CDN a cada tentativa --
    # calada, que é o pior jeito de falhar.
    pasta = nova_pasta("captacao[2026]")
    b = Baixador({U1: Resposta(200, FOTO)})
    cf.baixar([U1], pasta, baixador=b, pausa=lambda s: None)
    b2 = Baixador({U1: Resposta(200, FOTO)})
    r = cf.baixar([U1], pasta, baixador=b2, pausa=lambda s: None)
    checar("não voltou ao CDN pelo que já estava em disco", b2.chamadas == [],
           b2.chamadas)
    checar("e reconheceu como 'ja_estava'",
           r["fotos"][0]["estado"] == "ja_estava", r["fotos"])

    print("\n--- 16. o motivo do status não inventa 404 onde não houve ---")
    pasta = nova_pasta("status_honesto")
    b = Baixador({U1: Resposta(302, FOTO), U2: Resposta(404, PLACEHOLDER)})
    r = cf.baixar([U1, U2], pasta, baixador=b, pausa=lambda s: None)
    checar("o 302 não é explicado como se fosse o 404 da OLX",
           "302" in r["falhas"][0]["motivo"] and "404" not in r["falhas"][0]["motivo"],
           r["falhas"][0]["motivo"])
    checar("o 404 continua explicando o JPEG cinza",
           "cinza" in r["falhas"][1]["motivo"], r["falhas"][1]["motivo"])

    print("\n--- 17. nenhum campo devolvido vira 0 no lugar de vazio ---")
    # A Nay já disse que um apartamento não tinha vaga porque um campo ausente
    # virou 0. Aqui `ordem` começa em 1 e `bytes` é tamanho medido: 0 em
    # qualquer um dos dois seria dado inventado.
    pasta = nova_pasta("sem_zero")
    b = Baixador({U1: Resposta(200, FOTO), U2: Resposta(200, PNG)})
    r = cf.baixar([U1, U2], pasta, baixador=b, pausa=lambda s: None)
    checar("nenhuma ordem é 0", all(f["ordem"] > 0 for f in r["fotos"]), r["fotos"])
    checar("nenhum bytes é 0", all(f["bytes"] > 0 for f in r["fotos"]), r["fotos"])
    checar("e_capa é booleano de verdade, não 0/1",
           all(isinstance(f["e_capa"], bool) for f in r["fotos"]))
    checar("bytes bate com o arquivo em disco",
           all(f["bytes"] == os.path.getsize(f["arquivo"]) for f in r["fotos"]))

    print("\n--- 18. tudo falhou é diferente de anúncio sem foto ---")
    # Quem consome isto (o cadastro no site) não pode ler `fotos == []` como
    # "o anúncio não tinha foto": pode ser o CDN fora. A diferença mora em
    # `falhas`, e é por isso que ela nunca vem vazia por engano.
    pasta = nova_pasta("tudo_falhou")
    r_zero = cf.baixar([], pasta, baixador=Baixador({}), pausa=lambda s: None)
    r_cdn = cf.baixar([U1, U2], pasta, baixador=Baixador({}), pausa=lambda s: None)
    checar("anúncio sem foto: fotos e falhas vazias",
           r_zero["fotos"] == [] and r_zero["falhas"] == [], r_zero)
    checar("CDN fora: fotos vazias MAS falhas cheias",
           r_cdn["fotos"] == [] and len(r_cdn["falhas"]) == 2, r_cdn)

finally:
    shutil.rmtree(pasta_raiz, ignore_errors=True)

print()
if falhas:
    print(f"{falhas} caso(s) FALHARAM.")
    sys.exit(1)
print("todos os casos passaram.")
