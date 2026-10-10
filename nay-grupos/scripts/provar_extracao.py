"""Prova da leitura com a IA de verdade: as mensagens de teste do Pedro (09/10/2026) e o JSON de cada pedido.

    cd /root/nay-grupos && set -a && . ./.env && set +a
    .venv/bin/python scripts/provar_extracao.py                 as 4 mensagens dele
    .venv/bin/python scripts/provar_extracao.py --conta          e, para cada pedido, o melhor imóvel nosso (só leitura)
    .venv/bin/python scripts/provar_extracao.py "texto qualquer"

Não grava nada e não envia nada: chama a IA, e com --conta LÊ o catálogo.
"""
import datetime
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from grupos import config, extrair, regras  # noqa: E402

DO_PEDRO = [
    "Preciso para ALUGUEL: Apartamento 2 Quartos, Adrianópolis ou Vieiralves, Mobiliado, Até R$ 4.000,00",
    "Busco aluguel Primer cidada nova, cru. Valor máximo 2 mil",
    "Procuro apartamento para alugar no condomínio Parque Vile, 2 quartos até 1.800, Térreo ou 1 andar. "
    "Favor me enviar no PV. Att Tatiana Conde",
    "Procuro Eliza Miranda para venda com 3 quartos e suite, Térreo",
]


def main() -> None:
    conta = "--conta" in sys.argv
    mensagens = [a for a in sys.argv[1:] if not a.startswith("--")] or DO_PEDRO
    r, _ = regras.carregar(config.ARQUIVO_DE_REGRAS)
    conn = imoveis = vizinhos = nomes = None
    if conta:
        from grupos import banco, catalogo, lugares, pontuar
        conn = banco.conectar()
        conn.set_session(readonly=True)
        imoveis, vizinhos = catalogo.carregar(conn)
        nomes = lugares.Lugares(conn)
        limite = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=r["confirmado_dias"])
        confirmados = sum(1 for i in imoveis if i["confirmado_em"] and i["confirmado_em"] >= limite)
        print(f"catálogo: {len(imoveis)} imóveis nossos disponíveis; {confirmados} confirmados nos últimos {r['confirmado_dias']} dias\n")
    for n, texto in enumerate(mensagens, start=1):
        print(f"═══ mensagem {n}: {texto}")
        motivo = extrair.nao_precisa_ler(texto)
        if motivo:
            print(f"    nem vai para a IA: {motivo}\n")
            continue
        fichas = extrair.extrair(texto)
        if not fichas:
            print("    a IA leu e disse que NÃO é pedido de imóvel\n")
        for k, ficha in enumerate(fichas, start=1):
            print(f"--- pedido {k} de {len(fichas)}")
            print(json.dumps(ficha, ensure_ascii=False, indent=2))
            if conta:
                pedido, local, duvidosos = lugares.resolver(ficha, None, nomes)
                res = pontuar.melhores(pedido, imoveis, r, vizinhos, limite)
                print("    lugar reconhecido:", json.dumps({k2: local[k2] for k2 in ("bairros", "condominios")}, ensure_ascii=False),
                      "| itens:", "; ".join(f"{i['escrito']} -> {i['como'] or 'não reconheci'}"
                                             + (f" (sugestão: {i['sugestao']})" if i.get("sugestao") else "") for i in local["itens"]))
                if duvidosos:
                    print("    duvidoso no lugar:", ", ".join(duvidosos))
                print("    funil:", json.dumps(res.get("funil"), ensure_ascii=False))
                if not res["pares"]:
                    print("    SEM IMÓVEL COMPATÍVEL:", res["motivo"])
                for p in res["pares"]:
                    im = p["imovel"]
                    valor = im.get("valor_aluguel") if pedido["operacao"] == "aluguel" else im.get("valor_venda")
                    print(f"    {'MELHOR' if p['posicao'] == 1 else 'alternativa'}: {im['codigo']} · {im.get('condominio') or im.get('tipo_cadastro')}"
                          f" · {im.get('bairro')} · {im.get('quartos')}q · R$ {valor:,.0f} · nota {p['nota']} ({pontuar.faixa_da(p['nota'], r)})")
                    if p["posicao"] == 1:
                        for d in p["detalhe"]:
                            print(f"        {d['criterio']}: peso {d['peso']}, rendeu {d['rendimento']}% = {d['pontos']} pontos · {d['texto']}")
        print()
    if conn:
        conn.close()


if __name__ == "__main__":
    main()
