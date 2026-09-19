"""
Captura a DESCRIÇÃO de cada imóvel no anúncio individual e grava em
`imoveis.descricao`.

O PROBLEMA (medido em 31/08): `descricao` estava vazia nos **1.206**
imóveis. É onde o Tel escreve o que a ficha estruturada não cabe -- o que
está mobiliado e o que falta, se aceita pet, se tem ponto comercial. Sem
isso a Nay só sabia dizer "semi-mobiliado" e não sabia o que faltava, que
é exatamente o que o corretor pergunta.

Dois casos reais que estavam no site e não no banco:
  * o 4098 diz "100% mobiliado. Aceita pet." -- o Tel teve que responder
    isso à mão numa pendência;
  * o 1327 diz "Linda Casa em Via Pública com Ponto Comercial" -- é a
    resposta da pergunta do Leonan sobre "o ponto da lateral faz parte da
    casa?", que ficou dois dias em aberto.

POR QUE A VARREDURA NORMAL NÃO PEGA: ela lê as páginas de LISTAGEM (12
anúncios por página), que não trazem descrição. Só o anúncio individual
tem. São ~1.206 requisições, com pausa -- roda em ~40 minutos.

ONDE A DESCRIÇÃO MORA NO HTML: num `div.form-group` **sem `<label>`**.
Aparecem dois blocos sem rótulo:
  1. um resumo AUTO-GERADO dos campos ("Apartamento localizado no
     condomínio X" + linhas "- 2 quartos"), que não interessa;
  2. o texto escrito à mão, que é o que se quer.
Quando só existe o primeiro, o imóvel não tem descrição.

Uso:
    .venv/bin/python varrer_descricoes.py              # simulação, 20 imóveis
    .venv/bin/python varrer_descricoes.py --tudo       # simulação, todos
    .venv/bin/python varrer_descricoes.py --tudo --escrever
"""
import re
import sys
import time

import requests
from bs4 import BeautifulSoup

import db

BASE_URL = "https://imobeasy.com/anuncios"
PAUSA = 1.5          # regra do projeto: não martelar o site
LIMITE_AMOSTRA = 20

# O bloco que o site pré-preenche NÃO é descartável inteiro: ele é
# EDITÁVEL, e o Tel acrescenta coisa dentro dele. Medido em imóveis reais:
#   1125 tem "- 3 quartos" (eco) junto de "- Varanda; - Climatizado" (dele)
#   887  tem "com 4 quartos e 5 banheiros." (eco) e "valor fora a taxa" (dele)
# Então o que se remove é LINHA a linha, não bloco a bloco. Descartar o
# bloco perderia informação que só existe ali.

# Bullet que só repete um número da ficha: "- 3 quartos", "- 98 m2".
ECO_BULLET = re.compile(
    r"^-\s*\d+\s*(quartos?|banheiros?|m2|vagas?)\b"
    r"(\s*\(\s*sendo\s+\d+\s+su[ií]tes?\s*\))?\s*[.;]?\s*$", re.I)

# Abertura gerada: "Apartamento localizado no condomínio X".
ECO_ABERTURA = re.compile(
    r"^[\wÀ-ÿ/]+(\s+[\wÀ-ÿ/]+)*,?\s*localizado\s+n[oa]\s+condom[ií]nio\b[^\n]*$", re.I)

# Linha que e SO o tipo do imovel -- o 1327 abre com "Casa" sozinho, que
# tambem esta na ficha. Exige a linha inteira: "Casa triplex, interfone..."
# (descricao de verdade do 205) nao pode cair aqui.
ECO_TIPO = re.compile(
    r"^(casa|apartamento|apto|cobertura|pr[ée]dio|lote|terreno|sala|flat|"
    r"ch[áa]cara|s[íi]tio|galp[ãa]o|kitnet|studio)"
    r"(\s+(de|em)\s+condom[ií]nio)?\s*[.;,]?\s*$", re.I)

# Frase gerada, que pode vir seguida de texto do Tel na mesma linha:
# "Casa com 3 quartos (sendo 1 suite) e 1 banheiro." -> remove só a frase.
ECO_FRASE = re.compile(
    r"^[^\n]{0,90}?\bcom\s+\d+\s+(quartos?|su[ií]tes?)\b[^\n]*?\be\s+\d+\s+banheiros?\.?", re.I)


def extrair_descricao(html):
    """Devolve o texto escrito à mão, ou None.

    Não confia na ORDEM dos blocos: identifica o auto-gerado pelo formato
    e devolve o resto. Se a página mudar e o auto-gerado sumir, o pior que
    acontece é entrar um texto a mais -- nunca gravar lixo por silêncio.
    """
    soup = BeautifulSoup(html, "html.parser")
    blocos = []
    for div in soup.select("div.form-group"):
        if div.find("label"):
            continue
        val = div.find("span", class_="form-control")
        if not val:
            continue
        texto = val.get_text("\n", strip=True).replace("\r", "")
        if texto:
            blocos.append(texto)

    linhas = []
    for bloco in blocos:
        for linha in bloco.split("\n"):
            l = linha.strip()
            if not l:
                continue
            if ECO_BULLET.match(l) or ECO_ABERTURA.match(l) or ECO_TIPO.match(l):
                continue
            l = ECO_FRASE.sub("", l).strip(" .;,-")
            if l:
                linhas.append(l)

    # Sem duplicar: o mesmo texto pode aparecer nos dois blocos.
    vistas, limpo = set(), []
    for l in linhas:
        chave = l.lower()
        if chave not in vistas:
            vistas.add(chave)
            limpo.append(l)

    texto = "\n".join(limpo).strip()
    return texto or None


def buscar_descricao(codigo, sessao):
    resp = sessao.get(
        f"{BASE_URL}/{codigo}",
        timeout=20,
        headers={"User-Agent": "Mozilla/5.0 (varredura Imob Easy)"},
    )
    if resp.status_code != 200:
        return None, f"http {resp.status_code}"
    return extrair_descricao(resp.text), None


def codigos_do_banco(conexao, tudo):
    with conexao.cursor() as cur:
        cur.execute(
            "SELECT codigo FROM imoveis WHERE publicado_no_site "
            "ORDER BY codigo" + ("" if tudo else f" LIMIT {LIMITE_AMOSTRA}")
        )
        return [str(l["codigo"]) for l in cur.fetchall()]


def gravar(conexao, codigo, descricao):
    with conexao.cursor() as cur:
        cur.execute(
            "UPDATE imoveis SET descricao = %s, sincronizado_em = now() "
            "WHERE codigo::text = %s",
            (descricao, str(codigo)),
        )
    conexao.commit()


def main():
    tudo = "--tudo" in sys.argv
    escrever = "--escrever" in sys.argv

    conexao = db.conectar()
    sessao = requests.Session()
    try:
        codigos = codigos_do_banco(conexao, tudo)
        print(f"{len(codigos)} imóveis a visitar"
              f"{'' if escrever else ' (SIMULAÇÃO -- nada será gravado)'}\n")

        com, sem, erros = 0, 0, 0
        for i, codigo in enumerate(codigos, 1):
            try:
                descricao, erro = buscar_descricao(codigo, sessao)
            except Exception as exc:
                descricao, erro = None, str(exc)[:60]

            if erro:
                erros += 1
                print(f"  [{i}/{len(codigos)}] {codigo}: ERRO {erro}")
            elif descricao:
                com += 1
                if escrever:
                    gravar(conexao, codigo, descricao)
                print(f"  [{i}/{len(codigos)}] {codigo}: "
                      f"{descricao[:70].replace(chr(10), ' / ')}")
            else:
                sem += 1

            time.sleep(PAUSA)

        print(f"\ncom descrição: {com} | sem: {sem} | erro: {erros}")
        if not escrever:
            print("(simulação -- rode com --escrever para gravar)")
    finally:
        conexao.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
