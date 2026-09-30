"""
Doc 28, passo 4: dado um imóvel, devolve em quais grupos ele pode entrar.

Regra: cruza aceita_venda/aceita_locacao de cada grupo com o que o imóvel
tem (valor_venda e/ou valor_aluguel). Um grupo entra se aceita pelo menos
um dos tipos que o imóvel tem. Isso cobre sozinho o caso do imóvel com
venda E locação (doc 28): como ele "tem venda", qualquer grupo com
aceita_venda=true entra -- inclusive o grupo restrito só-venda.

A trava do grupo restrito não é instrução de prompt -- é este cruzamento
em código. Mesma lição do doc 27, Parte 4.3.

Decisão do Tel: o(s) grupo(s) com todas_fotos=true (hoje só "IMÓVEIS
PARA ANUNCIAR EASY") saem do fluxo normal -- postar_agora e vaga
agendada nunca incluem esse grupo automaticamente. Ele só é alcançado
pelo comando dedicado (postar_easy, publicador.py), que filtra por
todas_fotos diretamente, sem passar por aqui.

Fonte dos grupos: em produção, sempre carregar_grupos_db(conn) -- a
tabela `grupos` é a fonte de verdade. carregar_grupos_csv() continua
existindo só para teste offline, sem precisar de conexão com o banco;
não é um caminho de produção alternativo.

Uso (com um CSV exportado da tabela grupos, só para teste offline):
    .venv/bin/python montar_destinos.py 5644 --grupos-csv grupos.csv
"""
import argparse
import csv
import sys

from buscar_imovel import buscar_imovel
from comparar_catalogo import _bool_csv


# Palavras que a importação de agosto pôs no campo do condomínio de imóvel de
# RUA. É a mesma lista de `nay_condominio_de_verdade` (lista_de_imoveis.sql), que
# governa a lista: o card e a lista precisam concordar sobre o que é condomínio,
# senão o Alto Padrão receberia no card um imóvel que a lista dele esconde.
_ROTULO_NAO_E_CONDOMINIO = {
    "apartamento", "casa", "casas", "lote", "loja", "loja/ponto", "sala",
    "sala/andar", "predio", "prédio", "terreno", "kitnet", "flat", "cobertura",
    "chacara", "chácara", "sobrado", "galpao", "galpão",
}


def tem_condominio_de_verdade(imovel):
    nome = (imovel.get("condominio") or "").strip().lower()
    if not nome:
        return False
    if nome == (imovel.get("tipo") or "").strip().lower():
        return False
    if nome in _ROTULO_NAO_E_CONDOMINIO or "identificado" in nome:
        return False
    return True


# O QUE É IMÓVEL COMERCIAL, pelo tipo do cadastro (15/09, grupo "🟢 Comercial").
# Medido: os tipos comerciais que existem são Sala, Sala/Andar, Loja/Ponto,
# Galpão/Depósito e Prédio -- e PRÉDIO ENTRA por decisão do Tel, sabendo que o
# cadastro não separa prédio comercial de residencial. Os outros termos cobrem
# grafias que o cadastro pode ganhar ("Ponto Comercial", "Galpão", "Andar").
#
# NÃO é a mesma coisa que a categoria "sala" da lista (`nay_categoria_do_imovel`):
# aquela exige condomínio, por decisão de 09/09. Aqui é o uso do imóvel.
_TIPO_COMERCIAL = ("sala", "loja", "ponto", "galp", "deposito", "depósito",
                   "predio", "prédio", "andar", "comercial")


def e_comercial(imovel):
    tipo = (imovel.get("tipo") or "").strip().lower()
    return bool(tipo) and any(t in tipo for t in _TIPO_COMERCIAL)


# E RESIDENCIAL É MORADIA -- nem comércio, nem terra nua (15/09, o filtro por
# descrição: "a mesma coisa vale para imóvel comercial e residencial").
# Medido no catálogo: sobram Apartamento, Apartamento em Via Pública, Casa,
# Casa de condomínio, Cobertura, Flat e Chácara. LOTE FICA DE FORA de
# propósito -- lote não é imóvel residencial, é terreno; quem quer lote pede
# lote, e a categoria `lote` já existe para isso.
_TIPO_RESIDENCIAL = ("casa", "sobrado", "apartament", "cobertura", "flat",
                     "kitnet", "kit", "chacara", "chácara")


def e_residencial(imovel):
    tipo = (imovel.get("tipo") or "").strip().lower()
    if not tipo or e_comercial(imovel):
        return False
    return any(t in tipo for t in _TIPO_RESIDENCIAL)


def negocios_do_grupo(imovel, grupo):
    """Quais negócios DESTE imóvel este grupo aceita: {'venda', 'locacao'}.

    UM LUGAR SÓ para a regra, porque são três as perguntas que dependem dela:
    o imóvel entra no grupo? (`montar_lista_destinos`), que valor o card mostra
    lá? (`montar_mensagem`) e que lista o grupo recebe? (`_disparar_lista`).
    Três respostas escritas em três lugares divergiriam, e aí o Alto Padrão
    receberia um card com o aluguel de 5 mil que ele não aceita.

    ATÉ 15/09 bastava `aceita_venda`/`aceita_locacao`. O grupo Alto Padrão
    trouxe piso de valor e "só condomínio" (colunas `aluguel_minimo`,
    `venda_minima`, `so_condominio`). Chave ausente ou nula é SEM regra: os
    grupos antigos e o envio privado ao corretor, que passa um dicionário
    sem essas chaves, seguem exatamente como eram.
    """
    if grupo.get("so_condominio") and not tem_condominio_de_verdade(imovel):
        return set()
    # "nada de imóvel residencial neste grupo" -- o Tel, 15/09. Tipo vazio NÃO
    # passa: sem saber o que é, não se afirma que é comercial.
    if grupo.get("so_comercial") and not e_comercial(imovel):
        return set()
    aceitos = set()
    for negocio, valor_chave, aceita_chave, piso_chave in (
            ("venda", "valor_venda", "aceita_venda", "venda_minima"),
            ("locacao", "valor_aluguel", "aceita_locacao", "aluguel_minimo")):
        valor = imovel.get(valor_chave)
        if valor is None or not grupo.get(aceita_chave):
            continue
        piso = grupo.get(piso_chave)
        # 1.000.000 EM DIANTE, decisão do Tel: o piso entra.
        if piso is not None and float(valor) < float(piso):
            continue
        aceitos.add(negocio)
    return aceitos


def montar_lista_destinos(imovel, grupos):
    return [
        g for g in grupos
        if not g.get("todas_fotos") and negocios_do_grupo(imovel, g)
    ]


def carregar_grupos_db(conn):
    """Fonte de verdade em produção -- só grupos ativos.

    As três colunas de regra entraram em 15/09 (`grupos_regra_de_valor.sql`) e
    o `apelido` em 25/09 (`grupo_alto_padrao_easy.sql`). Esses arquivos rodam
    ANTES deste código: consulta nova em tabela velha derruba todo `posta`.
    """
    with conn.cursor() as cur:
        cur.execute(
            "SELECT id_grupo, nome, aceita_venda, aceita_locacao, todas_fotos, "
            "       aluguel_minimo, venda_minima, so_condominio, so_comercial, "
            "       apelido "
            "FROM grupos WHERE ativo ORDER BY nome"
        )
        return cur.fetchall()


def carregar_grupos_csv(caminho):
    """Só para teste offline -- produção usa carregar_grupos_db()."""
    with open(caminho, encoding="utf-8") as f:
        grupos = []
        for linha in csv.DictReader(f):
            grupos.append({
                "id_grupo": linha["id_grupo"],
                "nome": linha["nome"],
                "aceita_venda": _bool_csv(linha["aceita_venda"]),
                "aceita_locacao": _bool_csv(linha["aceita_locacao"]),
            })
        return grupos


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("codigo")
    parser.add_argument("--grupos-csv", required=True)
    args = parser.parse_args()

    imovel = buscar_imovel(args.codigo)
    grupos = carregar_grupos_csv(args.grupos_csv)
    destinos = montar_lista_destinos(imovel, grupos)

    print(f"Imóvel {imovel['codigo']} ({imovel['condominio']}): "
          f"valor_venda={imovel['valor_venda']} valor_aluguel={imovel['valor_aluguel']}")
    print(f"\nGrupos elegíveis ({len(destinos)} de {len(grupos)}):")
    for g in destinos:
        print(f"  {g['nome']} ({g['id_grupo']})")


if __name__ == "__main__":
    main()
