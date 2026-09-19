"""
A varredura inteira num comando só, contra o banco -- para poder virar cron.

POR QUE ISTO EXISTE: a varredura já funcionava, mas em três passos manuais
com uma exportação de CSV no meio (`varrer_catalogo` -> exportar CSV ->
`comparar_catalogo`/`gerar_sql_atualizacao` -> rodar o .sql à mão). Por
isso nunca virou cron, e por isso a última rodou em 28/08 -- três dias
antes desta linha ser escrita. Imóvel cadastrado depois disso não existe
para o cérebro da Nay, e ela responde "não encontrei o imóvel pelo código
X" de um imóvel que está no site. Foi assim com o 2943 e o 5750.

O QUE ELE NÃO MUDA: as regras continuam as mesmas do CLAUDE.md --

  * NUNCA apaga linha de `imoveis`. Só insere e atualiza;
  * o que está no banco e sumiu do site vira `publicado_no_site = false`,
    e NÃO vira indisponível: pode estar ativo no admin sem anúncio;
  * grava `sincronizado_em = now()` em tudo que tocou;
  * simulação por padrão -- só escreve com `--escrever`;
  * pausa de 1 a 2 segundos entre requisições.

O QUE ELE NÃO TOCA, de propósito: `imovel_privado` (como funciona a
visita, proprietário acompanha), `disponivel`, e qualquer coluna que o
site não fornece. O site não sabe dessas coisas e sobrescrever com nada
apagaria o que o Tel ensinou à Nay.

    .venv/bin/python sincronizar_catalogo.py                 # simula
    .venv/bin/python sincronizar_catalogo.py --escrever      # grava
    .venv/bin/python sincronizar_catalogo.py --paginas-venda 3 --paginas-aluguel 1
"""
import argparse
import sys

import db
from comparar_catalogo import CAMPOS_CONSISTENCIA
from varrer_catalogo import varrer

# O que o site fornece e por isso pode atualizar. Nada fora desta lista é
# tocado -- ver o cabeçalho.
#
# `area` NÃO ESTÁ AQUI, e a simulação é quem mostrou por quê: a coluna
# "Área" do card mistura duas medidas. No 5698 (Vitta Club House) ela diz
# 300 e o banco tem 72 de área útil; no 5693 e 5694 (Vivenda das Marinas)
# ela diz 250 -- são terrenos, e 250 é o lote. Escrever isso em `area_util`
# trocaria o dado bom por um número de outra grandeza, em 18 dos 48
# imóveis olhados no teste de 3 páginas.
#
# `vagas` também não está, e a razão é mais clara ainda: medido nos 39
# imóveis do teste que trazem garagem, 39 de 39 batem com
# `vagas + vagas_cobertas` do banco e NENHUM bate só com `vagas`. O banco
# guarda a vaga descoberta numa coluna e a coberta noutra; o card mostra o
# total. Escrever o total em `vagas` dobraria a garagem de todo imóvel com
# vaga coberta -- o 5706 viraria 4 descobertas mais 2 cobertas.
COLUNAS_DO_SITE = {
    "condominio":   "condominio_nome",
    "bairro":       "bairro",
    "endereco":     "logradouro",
    "complemento":  "complemento",
    "quartos":      "quartos",
    "suites":       "suites",
    "banheiros":    "banheiros",
    "valor_venda":  "valor_venda",
    "valor_aluguel": "valor_aluguel",
    "e_parceiro":   "e_parceiro",
}

# Falha maior que isto significa site fora do ar ou mudança de layout, não
# imóvel removido. Marcar 1.200 imóveis como despublicados por causa de uma
# queda de rede seria pior que não rodar.
MAX_FALHAS_TOLERADAS = 3

# 12 anúncios por página é o que o site entrega. Vindo muito menos que o
# pedido, alguma coisa quebrou -- e o piso é proporcional ao que se pediu,
# não um número fixo, senão o teste de 3 páginas que a regra do projeto
# exige nunca poderia rodar.
PAGINAS_VENDA = 67
PAGINAS_ALUGUEL = 8
ANUNCIOS_POR_PAGINA = 12
FRACAO_MINIMA = 0.7


def indexar_por_codigo(anuncios):
    """Um código pode aparecer na listagem de venda e na de aluguel. Se os
    dois cartões discordarem, o site está inconsistente: melhor parar do que
    escolher um valor em silêncio -- é o mesmo critério do comparar_catalogo."""
    por_codigo = {}
    for a in anuncios:
        codigo = str(a["codigo"])
        anterior = por_codigo.get(codigo)
        if anterior is None:
            por_codigo[codigo] = dict(a)
            continue
        for campo in CAMPOS_CONSISTENCIA:
            if anterior.get(campo) != a.get(campo) and a.get(campo) is not None \
               and anterior.get(campo) is not None:
                raise ValueError(
                    f"código {codigo} aparece duas vezes no site com {campo} "
                    f"diferente: {anterior.get(campo)!r} e {a.get(campo)!r}")
        # o cartão de aluguel traz valor_aluguel, o de venda traz valor_venda
        for campo in ("valor_venda", "valor_aluguel"):
            if anterior.get(campo) is None:
                anterior[campo] = a.get(campo)
    return por_codigo


def ler_banco(conexao):
    with conexao.cursor() as cur:
        cur.execute(
            "SELECT codigo::text AS codigo, condominio_nome, bairro, logradouro, "
            "complemento, area_util, quartos, suites, banheiros, vagas, "
            "valor_venda, valor_aluguel, e_parceiro, publicado_no_site "
            "  FROM imoveis")
        return {linha["codigo"]: linha for linha in cur.fetchall()}


# Zero num destes campos não é "zero", é "o card não disse". O extrator
# devolve `suites=0` sempre que não encontra a palavra "suíte" no texto --
# um zero inventado, não lido. E o card de terreno traz quartos, banheiros
# e vagas todos em zero. NULL é a resposta honesta para "não sei", e a
# busca por perfil já trata NULL como "não filtra por isso".
CONTAGENS = {"quartos", "suites", "banheiros", "vagas"}

# Contagem de três dígitos é número de SALA, não contagem. O card do 2564
# (Millenium Shopping) traz literalmente "1601" na coluna Quartos -- é a
# sala 1601, erro de cadastro no site deles, e a Nay repetiria "1601
# quartos" ao corretor. O maior valor real do banco inteiro é 8 quartos e
# 12 banheiros; o maior do site é um Prédio com 27 quartos em 1.330m2, que
# é de verdade e precisa passar.
TETO_CONTAGEM = 100


def _contagem_plausivel(valor, area):
    if valor >= TETO_CONTAGEM:
        return False
    # E nenhum imóvel tem mais cômodos que metros quadrados. Física, não
    # palpite: 1601 quartos em 79m2 é impossível; 27 em 1.330m2 não é.
    return not (area and valor > area)


def limpar_texto(valor):
    """Tira o lixo de digitação do cadastro antes de comparar E de gravar.

    Sem isto, 15 dos 37 updates da varredura completa eram só ruído:
    "Avenida André Araújo" viraria "Avenida André Araújo -", e
    "Avenida do Cetur" viraria "Avenida  do Cetur". Gravar isso não muda
    informação nenhuma, só piora o texto e marca o imóvel como alterado a
    cada varredura, para sempre.
    """
    if valor is None:
        return None
    texto = " ".join(str(valor).split())          # espaço duplo vira um só
    return texto.strip(" -–—,;:").strip() or None  # traço e vírgula soltos


def valor_para_gravar(valor):
    return limpar_texto(valor) if isinstance(valor, str) else valor


def _mudou(atual, novo, coluna=None, area=None):
    if novo is None:
        return False          # site sem o dado nunca apaga o que o banco tem
    if coluna in CONTAGENS:
        if not novo:
            return False      # zero aqui é ausência de dado, não informação
        if not _contagem_plausivel(novo, area):
            return False      # número de sala vindo no campo errado
    if isinstance(novo, str):
        novo = limpar_texto(novo)
        if novo is None:
            return False
    if atual is None:
        return True
    if isinstance(atual, bool) or isinstance(novo, bool):
        return bool(atual) != bool(novo)
    try:
        return float(atual) != float(novo)
    except (TypeError, ValueError):
        return limpar_texto(atual) != limpar_texto(novo)


def planejar(site, banco, varredura_completa=True):
    """Decide o que fazer sem tocar em nada. Devolve as três listas.

    `varredura_completa=False` desliga o despublicar, e isso é a proteção
    mais importante daqui: numa varredura de 3 páginas o site tem 48
    anúncios e o banco tem 1.206 -- os 1.158 que não foram olhados
    *pareceriam* ter sumido do site. Ausência só significa alguma coisa
    depois de olhar o site inteiro.
    """
    inserir, atualizar, despublicar = [], [], []

    for codigo, anuncio in site.items():
        linha = banco.get(codigo)
        if linha is None:
            inserir.append((codigo, anuncio))
            continue

        # `limpar_texto` também no que vai ser GRAVADO, não só no que é
        # comparado: senão o traço solto entra no banco na primeira vez.
        campos = {destino: valor_para_gravar(anuncio.get(origem))
                  for origem, destino in COLUNAS_DO_SITE.items()
                  if _mudou(linha.get(destino), anuncio.get(origem), destino,
                            anuncio.get("area"))}
        # está no site: se o banco dizia que não estava, corrige
        if not linha.get("publicado_no_site"):
            campos["publicado_no_site"] = True
        if campos:
            atualizar.append((codigo, campos))

    if varredura_completa:
        for codigo, linha in banco.items():
            # Sumiu do site: despublica, NUNCA marca indisponível nem apaga.
            if codigo not in site and linha.get("publicado_no_site") is not False:
                despublicar.append(codigo)

    return inserir, atualizar, despublicar


def marcar_que_rodou(conexao):
    """Carimba que a varredura terminou bem, mesmo sem ter mudado nada.

    `max(sincronizado_em)` NÃO serve para isso: ele só avança nas linhas
    tocadas, então catálogo estável parece varredura parada. Foi o falso
    alarme das 03h20 de 01/09 -- a varredura tinha rodado às 00h17, 01h17,
    02h17 e 03h17, todas em silêncio porque nada mudou.
    """
    with conexao.cursor() as cur:
        cur.execute(
            "INSERT INTO config (chave, valor) VALUES ('varredura_rodou_em', "
            "  to_char(now(), 'YYYY-MM-DD\"T\"HH24:MI:SSOF:00')) "
            "ON CONFLICT (chave) DO UPDATE SET valor = EXCLUDED.valor")
    conexao.commit()


def aplicar(conexao, inserir, atualizar, despublicar):
    with conexao.cursor() as cur:
        for codigo, anuncio in inserir:
            colunas = ["codigo", "publicado_no_site", "sincronizado_em"]
            valores = [codigo, True]
            marcas = ["%s", "%s", "now()"]
            for origem, destino in COLUNAS_DO_SITE.items():
                if _mudou(None, anuncio.get(origem), destino, anuncio.get("area")):
                    colunas.append(destino)
                    valores.append(valor_para_gravar(anuncio[origem]))
                    marcas.append("%s")
            cur.execute(
                f"INSERT INTO imoveis ({', '.join(colunas)}) "
                f"VALUES ({', '.join(marcas)}) ON CONFLICT (codigo) DO NOTHING",
                valores)

        for codigo, campos in atualizar:
            sets = ", ".join(f"{c} = %s" for c in campos)
            cur.execute(
                f"UPDATE imoveis SET {sets}, sincronizado_em = now() "
                f" WHERE codigo::text = %s",
                list(campos.values()) + [codigo])

        if despublicar:
            cur.execute(
                "UPDATE imoveis SET publicado_no_site = false, "
                "sincronizado_em = now() WHERE codigo::text = ANY(%s)",
                (despublicar,))
    conexao.commit()


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--paginas-venda", type=int, default=PAGINAS_VENDA)
    p.add_argument("--paginas-aluguel", type=int, default=PAGINAS_ALUGUEL)
    p.add_argument("--escrever", action="store_true")
    p.add_argument("--silencioso", action="store_true",
                   help="só fala quando muda algo ou dá erro (para o cron)")
    args = p.parse_args()

    log = (lambda *a: None) if args.silencioso else print

    venda, falhas_v = varrer("Venda", args.paginas_venda, log=log)
    aluguel, falhas_a = varrer("Aluguel", args.paginas_aluguel, log=log)
    anuncios = venda + aluguel
    falhas = falhas_v + falhas_a

    # PORTÃO FECHADO: sem prova de que a varredura foi inteira, não escreve.
    # Site fora do ar despublicaria o catálogo todo de uma vez.
    if len(falhas) > MAX_FALHAS_TOLERADAS:
        print(f"ABORTADO: {len(falhas)} páginas falharam. Nada foi escrito.",
              file=sys.stderr)
        return 2
    paginas = args.paginas_venda + args.paginas_aluguel
    minimo = int(paginas * ANUNCIOS_POR_PAGINA * FRACAO_MINIMA)
    if len(anuncios) < minimo:
        print(f"ABORTADO: só {len(anuncios)} anúncios em {paginas} páginas, "
              f"esperava ao menos {minimo}. Nada foi escrito.", file=sys.stderr)
        return 2

    # Só uma varredura do site inteiro pode concluir que algo sumiu dele.
    completa = (args.paginas_venda >= PAGINAS_VENDA
                and args.paginas_aluguel >= PAGINAS_ALUGUEL)

    site = indexar_por_codigo(anuncios)
    conexao = db.conectar()
    try:
        banco = ler_banco(conexao)
        inserir, atualizar, despublicar = planejar(site, banco, completa)

        if not args.escrever:
            parcial = "" if completa else \
                "  (varredura parcial: despublicar desligado)"
            print(f"[simulação] {len(inserir)} novos, {len(atualizar)} alterados, "
                  f"{len(despublicar)} a despublicar.{parcial} Rode com --escrever.")
            for codigo, _ in inserir[:10]:
                print(f"  novo: {codigo}")
            return 0

        aplicar(conexao, inserir, atualizar, despublicar)
        # Depois de aplicar: a varredura chegou ao fim sem abortar.
        marcar_que_rodou(conexao)
    finally:
        conexao.close()

    if inserir or atualizar or despublicar:
        print(f"{len(inserir)} novos, {len(atualizar)} alterados, "
              f"{len(despublicar)} despublicados.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
