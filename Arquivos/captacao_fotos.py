"""
Baixa as fotos do anúncio do OLX para o disco do servidor, sem gravar lixo.

POR QUE ESTE ARQUIVO EXISTE. Na captação, o imóvel é NOSSO -- o Tel fecha com o
proprietário e o anúncio do OLX é do próprio dono. Para cadastrar no site da
Imob Easy é preciso ter as fotos em mãos, e elas moram no CDN da OLX. Ler o
ANÚNCIO precisa de um IP liberado (o servidor está bloqueado pelo Cloudflare da
OLX; ver `extrair_olx.py` e `33-OLX-Para-o-Site.md`), mas **baixar a FOTO roda no
servidor hoje** -- medido de novo em 02/09/2026, a partir de 179.198.121.171:

    curl --fail -o /tmp/f.jpg -w '%{http_code} %{size_download} %{content_type}'
        https://img.olx.com.br/images/48/481626791965796.jpg
    -> 200 192231 image/jpeg     (JPEG 1280x960, `curl` comum, sem curl_cffi)

O CASO QUE DITA O CÓDIGO INTEIRO, e é uma armadilha silenciosa: **a OLX devolve
404 COM UM JPEG DE VERDADE DENTRO**. Medido no mesmo minuto, no mesmo servidor,
com uma URL inventada:

    -> 404 49639 image/jpeg      (JPEG 640x640 -- um quadrado cinza)

Ou seja: quem grava o corpo sem olhar o status enche a pasta de quadrados
cinzas e acha que deu certo. E note o tamanho: **49.639 bytes**. Não adianta
tentar pegar o placeholder por "arquivo pequeno demais" -- ele é MAIOR que
muita foto legítima. Quem pega o placeholder é o **status**, e só ele. As outras
conferências (tipo de conteúdo, assinatura dos primeiros bytes, piso de
tamanho) existem para outra coisa: página de erro em HTML, resposta truncada,
conexão que caiu no meio.

AS OUTRAS DECISÕES, e o motivo de cada uma:

* **Retomada.** Foto já baixada não baixa de novo. Uma captação tem ~16 fotos e
  qualquer erro no meio faz o Tel rodar de novo; sem isso ele martelaria o CDN
  repetindo o que já está no disco. A conferência é pelo ARQUIVO em disco, não
  por memória do processo.
* **Grava com nome temporário e renomeia.** Processo morto no meio da escrita
  deixaria um arquivo pela metade -- e a retomada da próxima vez confiaria nele.
  `os.replace` é atômico: ou o arquivo final existe inteiro, ou não existe.
* **Uma foto ruim não derruba a captação.** Registra a falha e segue; o chamador
  vê exatamente o que faltou. Mas falha SEGUIDA é outra coisa (CDN fora, IP
  bloqueado) e aí para -- insistir em 16 fotos só empilha erro. Isso vale
  também para erro de DISCO: depois que o laço começa, `baixar` não levanta
  exceção nenhuma, sempre devolve o relatório. Até 02/09 a gravação ficava
  fora do `try` e um `No space left on device` na foto 12 estourava um
  traceback que levava junto o registro das 11 que já tinham vindo. A única
  exceção que `baixar` ainda deixa subir é não conseguir CRIAR a pasta, e
  essa acontece antes de qualquer download: não há relatório a perder.
* **Pausa entre downloads**, como no resto do projeto: não martelar o CDN.
* **`baixador` injetável** para o teste não tocar a rede (`teste_captacao_fotos.py`).

A primeira URL da lista é a CAPA -- `extrair_olx.py` devolve na ordem do
anúncio, e essa ordem é a do proprietário. Se a foto 1 falhar, NENHUMA foto vem
marcada como capa: promover a segunda em silêncio esconderia a falha.

QUEM CHAMA ISTO LÊ A LISTA DEVOLVIDA, NUNCA A PASTA. O prefixo no nome do
arquivo ajuda o humano que abre o diretório, mas não é o registro da ordem:
    * com 100 fotos ou mais, `100-` vem antes de `99-` na ordem alfabética;
    * se a OLX devolver as mesmas fotos em outra ordem numa segunda rodada, a
      retomada não as reconhece e a pasta fica com as duas numerações -- 4
      arquivos para 2 fotos. Nenhuma se perde, mas quem listar o diretório
      conta o dobro e sobe a mesma foto duas vezes para o site.
Ordem, capa e identidade estão em `fotos` (`ordem`, `e_capa`, `arquivo`).

    .venv/bin/python captacao_fotos.py /root/captacoes/1526572128 https://img.olx.com.br/...jpg
"""
import argparse
import glob
import hashlib
import os
import random
import re
import sys
import time
from urllib.parse import urlsplit

# Piso contra resposta truncada/vazia -- NÃO contra o placeholder do 404, que
# tem 49.639 bytes e passaria por qualquer piso razoável. Ver o cabeçalho.
PESO_MINIMO = 2 * 1024

# Acima disto não é foto de anúncio: é engano ou resposta envenenada, e vai
# inteiro para a memória do processo.
PESO_MAXIMO = 15 * 1024 * 1024

PAUSA_MIN = 0.5
PAUSA_MAX = 1.5

# CDN fora do ar ou IP bloqueado falha em TODAS. Continuar pedindo as 16 só
# empilha erro e demora.
MAX_FALHAS_SEGUIDAS = 5

TEMPO_LIMITE = 30

# O que o servidor DIZ (Content-Type) pode estar errado; os primeiros bytes são
# o que de fato veio. Página de erro em HTML servida como image/jpeg morre aqui.
ASSINATURAS = (
    (b"\xff\xd8\xff", ".jpg"),
    (b"\x89PNG\r\n\x1a\n", ".png"),
    (b"GIF87a", ".gif"),
    (b"GIF89a", ".gif"),
)


class FotoRecusada(RuntimeError):
    """A resposta chegou, mas não é uma foto que se possa gravar."""


class DiscoRecusado(RuntimeError):
    """A foto veio boa, mas não deu para gravar: pasta sem espaço ou sem
    permissão. É falha da MÁQUINA, não do anúncio -- por isso tem classe
    própria, para o motivo dizer ao Tel o que olhar."""


def _extensao_do_conteudo(conteudo):
    """Extensão pela assinatura real do arquivo, ou None se não for imagem."""
    for assinatura, extensao in ASSINATURAS:
        if conteudo.startswith(assinatura):
            return extensao
    # WEBP é "RIFF" + 4 bytes de tamanho + "WEBP"
    if conteudo[:4] == b"RIFF" and conteudo[8:12] == b"WEBP":
        return ".webp"
    return None


def _cabecalho(resposta, nome):
    cabecalhos = getattr(resposta, "headers", None) or {}
    try:
        return cabecalhos.get(nome) or cabecalhos.get(nome.lower()) or ""
    except AttributeError:                       # pragma: no cover
        return ""


def nome_base(ordem, url):
    """Nome do arquivo SEM extensão: `01-481626791965796`.

    A posição vai no nome de propósito -- é ela que guarda a ordem do anúncio
    (e a capa) no disco, onde a lista original não existe mais. O resto vem do
    último pedaço da URL, saneado: URL é texto de fora, e `../../etc` no nome
    escreveria fora da pasta.
    """
    caminho = urlsplit(str(url)).path
    bruto = os.path.splitext(caminho.rsplit("/", 1)[-1])[0]
    limpo = re.sub(r"[^A-Za-z0-9_-]", "", bruto)[:40]
    if not limpo:
        limpo = hashlib.sha1(str(url).encode("utf-8")).hexdigest()[:12]
    return f"{ordem:02d}-{limpo}"


def _ja_baixada(pasta, base):
    """Caminho da foto já gravada, ou None.

    Aceita qualquer extensão porque quem decide a extensão é o conteúdo, e aqui
    ainda não se baixou nada. Arquivo menor que o piso é sobra de execução
    interrompida: não conta como baixado.

    `glob.escape` na PASTA porque o caminho vem de fora: um `[` no nome da
    pasta é metacaractere de glob e não casaria com nada -- a retomada morreria
    calada e o CDN levaria a captação inteira de novo a cada tentativa. O
    `base` já sai saneado de `nome_base`, sem metacaractere.
    """
    for caminho in sorted(glob.glob(os.path.join(glob.escape(pasta), base + ".*"))):
        if caminho.endswith(".parcial"):
            continue
        try:
            if os.path.getsize(caminho) >= PESO_MINIMO:
                return caminho
        except OSError:                          # pragma: no cover
            continue
    return None


def _conferir(resposta):
    """Devolve (conteúdo, extensão) ou levanta `FotoRecusada` dizendo por quê."""
    status = getattr(resposta, "status_code", None)
    if status != 200:
        # O 404 da OLX vem com um JPEG cinza de 49.639 bytes dentro. É por isso
        # que esta é a PRIMEIRA conferência, e a única que pega esse caso.
        # A pista só entra no 404: colada em todo status ela mentia -- um 302
        # aparecia no log como "status 302 (a OLX manda JPEG cinza no 404)".
        pista = " -- a OLX manda um JPEG cinza dentro do 404" if status == 404 else ""
        raise FotoRecusada(f"status {status}{pista}")

    tipo = (_cabecalho(resposta, "Content-Type") or "").split(";")[0].strip().lower()
    if tipo and not tipo.startswith("image/"):
        raise FotoRecusada(f"não é imagem: Content-Type {tipo!r}")

    conteudo = getattr(resposta, "content", None) or b""
    if len(conteudo) > PESO_MAXIMO:
        raise FotoRecusada(f"{len(conteudo)} bytes: grande demais para uma foto")
    if len(conteudo) < PESO_MINIMO:
        raise FotoRecusada(f"só {len(conteudo)} bytes: resposta truncada ou vazia")

    extensao = _extensao_do_conteudo(conteudo)
    if extensao is None:
        raise FotoRecusada("os primeiros bytes não são de imagem nenhuma")
    return conteudo, extensao


def _gravar(pasta, base, conteudo, extensao):
    """Escreve num nome temporário e renomeia -- morrer no meio da escrita não
    pode deixar um arquivo pela metade que a retomada aceite como pronto."""
    caminho = os.path.join(pasta, base + extensao)
    parcial = caminho + ".parcial"
    try:
        with open(parcial, "wb") as saida:
            saida.write(conteudo)
        os.replace(parcial, caminho)
    except OSError as erro:
        # Disco cheio estoura no meio da escrita e deixa o `.parcial` ali. A
        # retomada já o ignora, mas cada nova tentativa largaria mais um --
        # numa pasta que encheu o disco, justamente.
        try:
            os.remove(parcial)
        except OSError:
            pass
        raise DiscoRecusado(
            f"não deu para gravar em disco (confira espaço e permissão de "
            f"{pasta}): {erro}") from erro
    return caminho


def _baixador_padrao(url):
    """`requests` puro basta: o CDN de foto não exige a impressão digital TLS
    do Chrome que `extrair_olx.py` precisa para ler o anúncio (medido: `curl`
    comum devolve 200 no servidor)."""
    import requests
    return requests.get(url, timeout=TEMPO_LIMITE)


def _urls_uteis(urls):
    """Descarta vazio e repetido, preservando a ordem.

    Repetido não é uma segunda foto: baixaria o mesmo bytes duas vezes e daria
    duas linhas em `imovel_fotos`. A lista da OLX já veio com repetição em
    outras partes do site (ver `33-OLX-Para-o-Site.md`).
    """
    vistas = set()
    saida = []
    for url in urls or []:
        url = (str(url).strip() if url else "")
        if not url or url in vistas:
            continue
        vistas.add(url)
        saida.append(url)
    return saida


def baixar(urls, pasta, baixador=None, pausa=time.sleep, log=None):
    """Baixa as fotos na ordem e devolve o que deu certo e o que falhou.

    Devolve:
        {"pasta": str,
         "fotos":  [{"ordem", "url", "arquivo", "bytes", "e_capa", "estado"}],
         "falhas": [{"ordem", "url", "motivo"}]}

    `estado` é "baixada" ou "ja_estava" (retomada). `e_capa` só é verdadeiro na
    ordem 1 -- se a foto 1 falhar, nada vem marcado como capa, de propósito.
    """
    baixador = baixador or _baixador_padrao
    log = log or (lambda *a: None)
    lista = _urls_uteis(urls)
    os.makedirs(pasta, exist_ok=True)

    fotos, falhas = [], []
    falhas_seguidas = 0
    baixou_algo = False

    for indice, url in enumerate(lista):
        ordem = indice + 1
        base = nome_base(ordem, url)

        existente = _ja_baixada(pasta, base)
        if existente:
            fotos.append({"ordem": ordem, "url": url, "arquivo": existente,
                          "bytes": os.path.getsize(existente),
                          "e_capa": ordem == 1, "estado": "ja_estava"})
            continue

        # A pausa é do CDN, não do laço: só depois de ter ido à rede de fato.
        # Foto já em disco não pediu nada a ninguém e não deve custar espera.
        if baixou_algo:
            pausa(random.uniform(PAUSA_MIN, PAUSA_MAX))

        try:
            resposta = baixador(url)
            baixou_algo = True
            conteudo, extensao = _conferir(resposta)
            # Gravar mora DENTRO do `try` de propósito. Ficava fora, e aí uma
            # OSError de disco cheio subia por `baixar` inteiro: o Tel perdia o
            # relatório das fotos que JÁ tinham vindo e via um traceback no
            # lugar. Disco cheio também falha nas próximas, então isto conta em
            # `falhas_seguidas` e a captação para sozinha em vez de insistir.
            caminho = _gravar(pasta, base, conteudo, extensao)
        except (FotoRecusada, DiscoRecusado) as erro:
            motivo = str(erro)
        except Exception as erro:                # rede é imprevisível de mais
            baixou_algo = True                   # formas para listar uma a uma
            motivo = f"{type(erro).__name__}: {erro}"
        else:
            falhas_seguidas = 0
            fotos.append({"ordem": ordem, "url": url, "arquivo": caminho,
                          "bytes": len(conteudo), "e_capa": ordem == 1,
                          "estado": "baixada"})
            continue

        falhas.append({"ordem": ordem, "url": url, "motivo": motivo})
        falhas_seguidas += 1
        log(f"foto {ordem}: {motivo}")
        if falhas_seguidas >= MAX_FALHAS_SEGUIDAS:
            log(f"parei em {falhas_seguidas} falhas seguidas -- CDN fora, "
                f"IP bloqueado ou anúncio removido.")
            for resto, url_resto in enumerate(lista[ordem:], start=ordem + 1):
                falhas.append({"ordem": resto, "url": url_resto,
                               "motivo": "não tentada: parei nas falhas seguidas"})
            break

    return {"pasta": pasta, "fotos": fotos, "falhas": falhas}


def main():
    p = argparse.ArgumentParser(description="Baixa as fotos de um anúncio.")
    p.add_argument("pasta")
    p.add_argument("urls", nargs="+")
    args = p.parse_args()

    r = baixar(args.urls, args.pasta, log=print)
    for f in r["fotos"]:
        capa = " (capa)" if f["e_capa"] else ""
        print(f"[{f['estado']}] {f['ordem']}: {f['arquivo']} "
              f"-- {f['bytes']} bytes{capa}")
    for f in r["falhas"]:
        print(f"[FALHOU] {f['ordem']}: {f['url']} -- {f['motivo']}")
    print(f"\n{len(r['fotos'])} foto(s) em disco, {len(r['falhas'])} falha(s).")
    return 1 if r["falhas"] else 0


if __name__ == "__main__":
    sys.exit(main())
