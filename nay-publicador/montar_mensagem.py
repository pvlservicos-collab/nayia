"""
Doc 28, passo 5: monta o texto da mensagem, por grupo.

Regra do Tel: no grupo restrito ("SÓ TERCEIROS COMPRA, VEN"), a
mensagem sai só com a parte de venda -- a linha de locação nunca
aparece, mesmo que o imóvel tenha aluguel. Nos outros 9 grupos, sai
completa, com venda e locação juntos quando o imóvel tiver os dois.

A função não olha o id do grupo -- olha aceita_venda/aceita_locacao,
os mesmos campos que montar_destinos.py usa para decidir quem recebe o
imóvel. Assim a mesma trava decide "esse grupo recebe?" e "o que
aparece no texto?", sem duas cópias da regra (doc 27, Parte 4.3): se
amanhã existir um segundo grupo restrito (só aluguel, por exemplo),
funciona sem precisar mexer aqui.

Uso:
    .venv/bin/python montar_mensagem.py 5644 --grupos-csv grupos.csv
"""
import argparse

from buscar_imovel import buscar_imovel
from montar_destinos import carregar_grupos_csv, negocios_do_grupo


def _fmt_valor(v):
    return f"{v:,.0f}".replace(",", ".")


def _plural(n, singular, plural=None):
    """"1 vaga", "2 vagas". O card saía "1 vagas" e o Tel corrigiu no exemplo
    dele ("sendo 1 vaga coberta")."""
    return f"{n} {singular if n == 1 else (plural or singular + 's')}"


def _e_via_publica(imovel):
    """Imóvel de rua é o que NÃO tem condomínio.

    POR QUE ASSIM E NÃO POR UMA LISTA DE TIPOS: os tipos vêm em pares
    (`Casa` x `Casa de condomínio`, `Apartamento em Via Pública` x
    `Apartamento`, `Lote` x `Lote em Condomínio`), e uma lista fixa envelhece
    no dia em que o cadastro ganhar um tipo novo. Medido em 02/09 contra 10
    anúncios reais: os quatro sem condomínio eram exatamente os de via pública
    (duas casas, um apartamento em via pública, um prédio) e os seis com
    condomínio eram os de dentro."""
    return not (imovel.get("condominio") or "").strip()


def _titulo(imovel):
    """A primeira linha do card.

    Com condomínio, o nome dele basta. SEM condomínio o card dizia só "Casa",
    que não identifica nada -- o Tel pediu em 02/09: "casa em via pública,
    colocar assim: Casa bairro Flores ou casa conjunto Dom Pedro".

    Quando o próprio nome do bairro já começa com "Conjunto", a palavra
    "bairro" não entra: sairia "Casa bairro Conjunto Dom Pedro".
    """
    condominio = (imovel.get("condominio") or "").strip()
    if condominio:
        return condominio
    tipo = (imovel.get("tipo") or "").strip() or f"Imóvel {imovel['codigo']}"
    bairro = (imovel.get("bairro") or "").strip()
    if not bairro:
        return tipo
    if bairro.lower().startswith(("conjunto", "conj.", "cj")):
        return f"{tipo} {bairro}"
    return f"{tipo} bairro {bairro}"


def _linha_de_area(imovel):
    """"265m2 de área construída" para casa, "49m2" para apartamento.

    Quem decide é o RÓTULO que o site usou ("Área Construída" x "Área"), não
    o tipo do imóvel -- tipo novo no cadastro quebraria a adivinhação.
    """
    area = imovel.get("area")
    if not area:                 # area=0 é dado incompleto, não "sem área"
        return None
    if imovel.get("area_e_construida"):
        return f"• {area}m2 de área construída"
    return f"• {area}m2"


def _linha_de_vagas(imovel):
    """"2 vagas sendo 1 vaga coberta", como o Tel escreveu.

    `vagas` já vem somado (descobertas + cobertas) do `buscar_imovel`.
    Quando o site não traz o rótulo "Vagas Cobertas", `vagas_cobertas` é None
    -- e None é "não sei", não "nenhuma": nesse caso a linha não afirma nada
    sobre cobertura. Dizer "descobertas" de uma vaga coberta é o tipo de erro
    que o corretor descobre na visita.
    """
    total = imovel.get("vagas")
    cobertas = imovel.get("vagas_cobertas")

    if not total:
        if cobertas:
            return "• " + _plural(cobertas, "vaga coberta", "vagas cobertas")
        return None
    if cobertas is None:
        return "• " + _plural(total, "vaga")
    if cobertas == 0:
        return "• " + _plural(total, "vaga descoberta", "vagas descobertas")
    if cobertas >= total:
        return "• " + _plural(total, "vaga coberta", "vagas cobertas")
    return ("• " + _plural(total, "vaga") + " sendo "
            + _plural(cobertas, "vaga coberta", "vagas cobertas"))


def _linha_de_sol(imovel):
    """Nascente ou poente -- o corretor pergunta sempre, e muda o preço."""
    sol = (imovel.get("sol") or "").strip().lower()
    if sol.startswith("nascente"):
        return "• nascente"
    if sol.startswith("poente"):
        return "• poente"
    return None


def _linha_de_mobilia(imovel):
    """"mobiliado", "semi-mobiliado" ou "climatizado".

    O cadastro tem três redações e só três (medido: 234 semi, 140 mobiliado,
    40 só ar-condicionado). "so ar-condicionado" vira "climatizado", que é a
    palavra que o Tel usou.

    Desde 14/09 vem PRIMEIRO da página (a característica "Semi-Mobiliado" ou
    "Mobiliado" marcada no admin), e só na falta dela da nossa tabela.
    """
    m = (imovel.get("mobilia") or "").strip().lower()
    if not m:
        return None
    # 344 (11/10): o cadastro tem 4 níveis -- "com modulados e ar" é o antigo semi-mobiliado; lê as duas redações
    if m.startswith("semi") or "modulad" in m:
        return "• com modulados e ar"
    if m.startswith("mobiliad"):
        return "• mobiliado"
    if "ar-condicionado" in m or "ar condicionado" in m or "climatiz" in m:
        return "• só climatizado"
    if m.startswith("sem"):
        return "• sem mobília"
    return None


def _linhas_de_caracteristicas(imovel):
    """"• edícula", "• escritório"... -- o que o Tel marcou no admin (14/09).

    Semi-Mobiliado e Mobiliado NÃO saem aqui: já saem na linha de mobília, que
    agora lê a mesma marcação da página. Imprimir nos dois lugares repetiria a
    informação no mesmo card.

    Minúsculo, como o exemplo que ele escreveu ("• piscina", "• closet") e como
    as outras linhas do card ("• nascente", "• semi-mobiliado").
    """
    return ["• " + c.lower() for c in (imovel.get("caracteristicas") or [])
            if c not in ("Semi-Mobiliado", "Mobiliado")]


def _linha_de_escada(imovel):
    """"• 3 lances de escada", quando o cadastro diz quantos.

    O PEDIDO (Tel, 14/09), com o exemplo dele: a linha vem logo depois do
    bairro, antes da metragem. Para quem sobe com cliente idoso ou com
    criança, é a informação que decide a visita -- e não está em lugar nenhum
    da página do anúncio.

    ZERO NÃO É AUSÊNCIA, e por isso não vira linha: 616 dos 626 imóveis que
    têm a chave trazem "0", que quer dizer "não tem escada". Imprimir
    "0 lances de escada" em 616 cards seria ruído, e o que ele pediu foi ver
    QUANDO tem.
    """
    bruto = str(imovel.get("lances_de_escada") or "").strip()
    if not bruto.isdigit() or int(bruto) <= 0:
        return None
    return "• " + _plural(int(bruto), "lance") + " de escada"


def _sufixo_do_aluguel(imovel):
    """"(incluso a tx)" quando a taxa de condomínio já está no aluguel.

    Também não existe na página: vem da nossa tabela. O cadastro escreve de
    várias formas ("Taxa de Condomínio", "Água, Taxa de Gás, Taxa de
    Condomínio"), por isso a busca é por "condom" dentro do texto.
    """
    incluso = (imovel.get("incluso_no_aluguel") or "")
    return " (incluso a tx)" if "condom" in incluso.lower() else ""


def _linha_de_financiamento(imovel):
    """Aceita financiamento, sempre que houver venda e o dado existir.

    O Tel pediu em 02/09 para SEMPRE sair -- começou como pedido só para
    imóvel de rua e ele ampliou: "quero deixar que sempre saia se aceita
    financiamento ou não".

    Valor ausente NÃO vira "não financia": o site não traz o campo em todo
    anúncio (o 2943 é um desses), e afirmar que não financia um imóvel que
    financia derruba negócio. Sem o dado, a linha não sai.
    """
    bruto = (imovel.get("aceita_financiamento") or "").strip().lower()
    if bruto.startswith("s"):
        return "• aceita financiamento"
    if bruto.startswith("n"):
        return "• não aceita financiamento"
    return None


def _linha_de_quartos(imovel):
    """"• 3 quartos sendo 1 suíte". UMA função para o card e para o aviso de
    que o imóvel saiu -- as duas mensagens vão para o mesmo grupo, e a mesma
    frase escrita de dois jeitos divergiria na primeira edição."""
    if imovel.get("quartos") is None:
        return None
    suites = imovel.get("suites") or 0
    sufixo = f" sendo {_plural(suites, 'suíte')}" if suites else ""
    return "• " + _plural(imovel["quartos"], "quarto") + sufixo


# O tipo como o Tel escreve na frente do sol: "apto nascente". A ordem importa
# -- "Apartamento em Via Pública" e "Casa de condomínio" começam pela chave.
_TIPO_CURTO = (("apartamento", "apto"), ("cobertura", "cobertura"),
               ("flat", "flat"), ("kitnet", "kitnet"), ("studio", "studio"),
               ("casa", "casa"), ("sobrado", "sobrado"), ("sala", "sala"),
               ("loja", "loja"), ("galp", "galpão"), ("terreno", "terreno"),
               ("lote", "lote"), ("pr", "prédio"))


def _linha_de_tipo_e_sol(imovel):
    """"• apto nascente". Sem o sol a linha não sai: "• apto" sozinho não diz
    nada que o título já não diga, e inventar o sol é informação errada."""
    sol = (imovel.get("sol") or "").strip().lower()
    if not sol:
        return None
    tipo = sem_acento_simples((imovel.get("tipo") or "").strip())
    curto = next((c for chave, c in _TIPO_CURTO if tipo.startswith(chave)),
                 tipo.split()[0] if tipo else "")
    return "• " + " ".join(p for p in (curto, sol) if p)


def sem_acento_simples(texto):
    import unicodedata
    return "".join(c for c in unicodedata.normalize("NFD", texto or "")
                   if unicodedata.category(c) != "Mn").lower()


def montar_aviso_de_saida(imovel, motivo):
    """O aviso que vai para o grupo Easy quando o imóvel sai do mercado.

    ATÉ 15/09 era uma linha: "🛑 acquarelle alugado cod: 5611". O Tel pediu que
    passasse a ser um card resumido, com o exemplo dele:

        🛑 condomínio acquarelle alugado
        • Bairro: Ponta Negra
        • apto nascente
        • 88m2
        • 3 quartos sendo 1 suíte
        locação: 4.600 (incluso a TX)
        Código: 5611

    O grupo Easy é de corretores que PEGARAM o imóvel para anunciar. Com a linha
    antiga eles precisavam lembrar qual era o "acquarelle" -- o condomínio tem
    vários. Com o card resumido reconhecem o anúncio que têm na mão.

    O título é o do card (`_titulo`) em minúsculo, e não o `_nome_curto` da
    lista: ele escreveu "condomínio acquarelle", o nome inteiro.

    O VALOR É O DO NEGÓCIO QUE ACABOU: "alugado" mostra a locação, "vendido" a
    venda. Um imóvel com os dois valores que foi alugado continua à venda --
    mostrar a venda no aviso de "alugado" confundiria justamente isso.

    "(incluso a TX)" com TX em maiúsculo, como ele escreveu aqui -- no card e na
    lista é "tx". Seguido ao pé da letra.
    """
    linhas = [f"🛑 {_titulo(imovel).lower()} {motivo}"]

    bairro = (imovel.get("bairro") or "").strip()
    if bairro and bairro.lower() not in linhas[0]:
        linhas.append(f"• Bairro: {bairro}")

    for linha in (_linha_de_tipo_e_sol(imovel), _linha_de_area(imovel),
                  _linha_de_quartos(imovel)):
        if linha:
            linhas.append(linha)

    if motivo == "alugado":
        valor = imovel.get("valor_aluguel")
        if valor:
            incluso = (imovel.get("incluso_no_aluguel") or "").lower()
            linhas.append(f"locação: {_fmt_valor(valor)}"
                          + (" (incluso a TX)" if "condom" in incluso else ""))
    else:
        valor = imovel.get("valor_venda")
        if valor:
            linhas.append(f"venda: {_fmt_valor(valor)}")

    linhas.append(f"Código: {imovel['codigo']}")
    return "\n".join(linhas)


def montar_mensagem(imovel, grupo):
    titulo = _titulo(imovel)
    linhas = [f"📍 {titulo}"]

    # O bairro só vira linha própria quando o título não o diz -- senão o card
    # repete a mesma palavra duas vezes seguidas.
    bairro = (imovel.get("bairro") or "").strip()
    if bairro and bairro not in titulo:
        linhas.append(f"• Bairro: {bairro}")

    for linha in (_linha_de_escada(imovel), _linha_de_area(imovel)):
        if linha:
            linhas.append(linha)

    linha = _linha_de_quartos(imovel)
    if linha:
        linhas.append(linha)
    if imovel.get("banheiros") is not None:
        linhas.append("• " + _plural(imovel["banheiros"], "banheiro"))

    # As características marcadas vêm DEPOIS dos quartos e ANTES das vagas --
    # a posição do exemplo do Tel (14/09).
    linhas.extend(_linhas_de_caracteristicas(imovel))

    for linha in (_linha_de_vagas(imovel), _linha_de_sol(imovel),
                  _linha_de_mobilia(imovel)):
        # "climatizado" pode vir das duas fontes -- a característica marcada na
        # página e o "só ar-condicionado" da mobília do banco. Uma vez só.
        if linha and linha not in linhas:
            linhas.append(linha)

    # A TAXA DE CONDOMÍNIO, LOGO ANTES DOS VALORES -- a posição do card que ele
    # escreveu em 03/10 ("• poente / • taxa de condomínio 1092,10 / Venda: ...").
    #
    # A LINHA VEM PRONTA DO BANCO e aqui não se decide nada. Quem decide se a
    # taxa pode sair (ela tem validade: 45 dias desde que foi escrita, pedido
    # dele) e como se escreve o número é `nay_linha_da_taxa`. O motivo de estar
    # lá e não aqui: `nai_card_do_banco` monta ESTE MESMO card em SQL, e uma
    # regra de validade em duas cópias divergiria na primeira edição --
    # é o padrão 4.3 do HISTORICO, que este projeto já pagou cinco vezes.
    #
    # Taxa sem data NÃO SAI, e é o estado de 124 dos 149 imóveis no mercado que
    # têm taxa (o import da planilha de 26/09). Elas voltam quando alguém
    # reescrever o valor -- o trigger carimba. `taxa_do_card.sql`.
    if imovel.get("linha_da_taxa"):
        linhas.append(imovel["linha_da_taxa"])

    # Os valores que ESTE grupo aceita (piso e condomínio incluídos) -- a mesma
    # regra que decidiu que o imóvel entra aqui. Sem isso, o Alto Padrão
    # receberia o card de um imóvel de venda 1,2 milhão com o aluguel de 5 mil
    # que ele não aceita.
    negocios = negocios_do_grupo(imovel, grupo)
    if "venda" in negocios:
        linhas.append(f"Venda: R$ {_fmt_valor(imovel['valor_venda'])}")
        financia = _linha_de_financiamento(imovel)
        if financia:
            linhas.append(financia)
    if "locacao" in negocios:
        linhas.append(f"Locação: R$ {_fmt_valor(imovel['valor_aluguel'])}"
                      + _sufixo_do_aluguel(imovel))

    # A OBS DO ADMIN, SEMPRE LOGO ACIMA DO CÓDIGO (Tel, 14/09): "OBS: ap
    # porteira fechada". É texto dele, publicado como ele escreveu.
    obs = (imovel.get("observacao") or "").strip()
    if obs:
        linhas.append(f"OBS: {obs}")

    linhas.append(f"Código: {imovel['codigo']}")
    return "\n".join(linhas)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("codigo")
    parser.add_argument("--grupos-csv", required=True)
    args = parser.parse_args()

    imovel = buscar_imovel(args.codigo)
    grupos = carregar_grupos_csv(args.grupos_csv)

    for g in grupos:
        print(f"=== {g['nome']} ===")
        print(montar_mensagem(imovel, g))
        print()


if __name__ == "__main__":
    main()
