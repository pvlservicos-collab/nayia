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


def montar_lista_destinos(imovel, grupos):
    tem_venda = imovel.get("valor_venda") is not None
    tem_locacao = imovel.get("valor_aluguel") is not None
    return [
        g for g in grupos
        if not g.get("todas_fotos")
        and ((tem_venda and g["aceita_venda"]) or (tem_locacao and g["aceita_locacao"]))
    ]


def carregar_grupos_db(conn):
    """Fonte de verdade em produção -- só grupos ativos."""
    with conn.cursor() as cur:
        cur.execute(
            "SELECT id_grupo, nome, aceita_venda, aceita_locacao, todas_fotos "
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
