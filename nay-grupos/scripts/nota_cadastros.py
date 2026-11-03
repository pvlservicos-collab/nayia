"""571 (Pedro, 03/11/2026): a NOTA de cada cadastro incompleto (captacao_cadastro em 'coletando') pela procura.

"classifique os imóveis que eles estavam cadastrando com uma nota baseada no que nossos clientes estão pedindo".
A conta é a MESMA dos pedidos dos grupos (grupos.pontuar.avaliar), de trás para frente: o imóvel que o dono estava
cadastrando (o que a conversa já sabe: operação, tipo, bairro/condomínio, quartos, valor) é comparado com
  - os pedidos dos grupos dos últimos 30 dias (os clientes dos corretores): conta os de nota 90+ e 70+;
  - as buscas dos clientes da aba Leads que ainda não foram encerradas (privado.busca_cliente.filtros).
Campo que a conversa ainda não trouxe (quartos, valor) NÃO elimina: assume o que o pedido pede (a nota é generosa e a
tela diz o que faltou). Só lê; grava em privado.cadastro_incompleto_nota. Rodar na VPS, na pasta do nay-grupos:

    cd /root/nay-grupos && set -a && . ./.env && set +a && PYTHONPATH=. .venv/bin/python scripts/nota_cadastros.py

A nota (0-100) é RELATIVA: pontos = (1 por pedido 90+ de corretor diferente + 0,4 por pedido 70-89 + 3 por cliente nosso)
x (0,7 + 0,075 por dado conhecido entre tipo, local, quartos e valor); nota = 100 x log(1+pontos) / log(1+maior pontos
dos incompletos). 100 = o imóvel com mais procura entre os cadastros incompletos. (A primeira versão somava e saturava em 100.)
"""
import math
import datetime
import json
import re
import sys

from psycopg2.extras import Json

from grupos import banco, catalogo, config, lugares, pontuar, regras
from grupos.texto import normal

UNIDADES = {"um": 1, "uma": 1, "dois": 2, "duas": 2, "tres": 3, "quatro": 4, "cinco": 5, "seis": 6, "sete": 7, "oito": 8,
            "nove": 9, "dez": 10, "quinze": 15, "vinte": 20}


def valor_de(texto: str | None) -> float | None:
    """O valor dito pelo dono ("1.950", "4mil", "cinco mil o aluguel", "R$ 850 mil"); None se não dá para ler."""
    t = normal(texto or "")
    if not t:
        return None
    m = re.search(r"(\d[\d.,]*)\s*(mil|k|milhao|milhoes)?", t)
    if m:
        n = m.group(1)
        n = n.replace(".", "") if re.fullmatch(r"\d{1,3}(\.\d{3})+", n) else n.replace(",", ".")
        try:
            v = float(n)
        except ValueError:
            return None
        if m.group(2) in ("mil", "k"):
            v *= 1000
        elif m.group(2) in ("milhao", "milhoes"):
            v *= 1_000_000
        return v or None
    m = re.search(r"\b(" + "|".join(UNIDADES) + r")\s+(mil|milhao|milhoes)\b", t)
    if m:
        return UNIDADES[m.group(1)] * (1000 if m.group(2) == "mil" else 1_000_000)
    return None


def quartos_de(dados: dict) -> int | None:
    for campo in ("quartos", "detalhes"):
        t = normal(dados.get(campo) or "")
        m = re.search(r"(\d+)\s*(?:qts?|quartos?|dormitorios?)\b", t) or (re.fullmatch(r"\s*(\d+)\s*", t) if campo == "quartos" else None)
        if m:
            return int(m.group(1))
    return None


def tipo_de(dados: dict, lead: dict) -> str | None:
    t = catalogo.tipo_do(dados.get("tipo") or lead.get("tipo_imovel") or "")
    if t != "outro":
        return t
    d = normal((dados.get("detalhes") or "") + " " + (lead.get("imovel_desc") or ""))
    return "apartamento" if "apart" in d or "apto" in d else "casa" if "casa" in d else None


def operacoes_de(dados: dict) -> list[str]:
    n = normal(dados.get("negocio") or "")
    if "dois" in n or ("venda" in n and "loca" in n) or " e " in n:
        return ["aluguel", "venda"]
    if "venda" in n or "vend" in n:
        return ["venda"]
    if "loca" in n or "alug" in n:
        return ["aluguel"]
    return ["aluguel", "venda"]                     # a conversa ainda não disse: vale o melhor dos dois


def main() -> None:
    conn = banco.conectar()
    r, _ = regras.carregar(config.ARQUIVO_DE_REGRAS)
    _, vizinhos = catalogo.carregar(conn)
    nomes = lugares.Lugares(conn)
    limite = None                                   # o imóvel ainda nem está no catálogo: não há data de confirmação

    with conn.cursor() as cur:
        cur.execute("""SELECT c.id, c.dados, l.bairro, l.condominio, l.tipo_imovel, l.imovel_desc
                         FROM captacao_cadastro c JOIN captacao_leads l ON l.id = c.lead_id WHERE c.estado = 'coletando'""")
        cadastros = cur.fetchall()
        cur.execute("""SELECT DISTINCT ON (q.remetente, md5(q.ficha::text)) q.id, q.ficha, q.grupo_nome, q.remetente, q.remetente_nome
                         FROM privado.grupo_pedido q
                        WHERE q.fonte = 'grupo' AND q.enviada_em > now() - interval '30 days' AND q.remetente IS NOT NULL
                        ORDER BY q.remetente, md5(q.ficha::text), q.enviada_em DESC""")
        pedidos = cur.fetchall()
        cur.execute("""SELECT b.lead, b.filtros, coalesce(l.nome, '') FROM privado.busca_cliente b
                         JOIN privado.olx_lead_whatsapp l ON l.id = b.lead
                        WHERE b.estado <> 'encerrada' AND NOT b.teste AND b.filtros <> '{}'::jsonb""")
        buscas = cur.fetchall()
    print(f"# cadastros: {len(cadastros)}; pedidos (únicos) dos grupos: {len(pedidos)}; buscas de clientes: {len(buscas)}", file=sys.stderr)

    resolvidos = []
    for pid, ficha, grupo, rem, nome in pedidos:
        p, _, _ = lugares.resolver(ficha, grupo, nomes)
        resolvidos.append((p, rem, nome, (ficha or {}).get("trecho") or ""))
    clientes = []
    for lead, f, nome in buscas:
        ficha = {"operacao": {"venda": "venda", "locacao": "aluguel"}.get(f.get("finalidade")),
                 "tipo": "casa" if str(f.get("tipo") or "").startswith("casa") else f.get("tipo"),
                 "quartos": f.get("quartos"), "preco_max": f.get("teto"), "bairros": f.get("bairros") or [],
                 "condominio": f.get("condominio"), "mobiliado": None}
        p, _, _ = lugares.resolver(ficha, None, nomes)
        clientes.append((p, lead, nome))

    saida = []
    for cid, dados, bairro, condominio, tipo_imovel, desc in cadastros:
        lead = {"tipo_imovel": tipo_imovel, "imovel_desc": desc}
        bairro_ = (dados.get("bairro") or bairro or "").strip() or None
        condo_ = (dados.get("condominio") or condominio or "").strip() or None
        tipo = tipo_de(dados, lead)
        quartos = quartos_de(dados)
        valor = valor_de(dados.get("valor"))
        ops = operacoes_de(dados)
        # o bairro/condomínio pelo mesmo reconhecimento dos pedidos
        ficha_local = {"bairros": [bairro_] if bairro_ else [], "condominio": condo_}
        ped_local, _, _ = lugares.resolver(ficha_local, None, nomes)
        bairros_reconhecidos = ped_local["bairro_chaves"]
        faltou = [k for k, v in (("tipo", tipo), ("bairro ou condomínio", bairro_ or condo_), ("quartos", quartos), ("valor", valor)) if not v]

        def serve(pedido: dict) -> float | None:
            melhor = None
            for op in ops:
                for t in ([tipo] if tipo else ["apartamento", "casa"]):
                    q = quartos if quartos is not None else pedido.get("quartos")
                    v = valor if (valor and (len(ops) == 1)) else (pedido.get("preco_max") or 1.0)
                    imovel = {"codigo": cid, "tipo": t, "bairro": bairro_, "bairro_chave": normal(bairro_ or ""),
                              "condominio": condo_, "condominio_chave": normal(condo_ or ""), "planilha_id": None,
                              "quartos": q, "mobilia": None, "andar": None, "elevador": None, "financiamento": None,
                              "valor_aluguel": v if op == "aluguel" else None, "valor_venda": v if op == "venda" else None,
                              "confirmado_em": None}
                    if pedido.get("operacao") not in (op, None):
                        continue
                    ped = {**pedido, "operacao": pedido.get("operacao") or op}
                    etapa, res = pontuar.avaliar(ped, imovel, r, vizinhos, limite)
                    if res and res["nota"] is not None and (melhor is None or res["nota"] > melhor):
                        melhor = res["nota"]
            return melhor

        por_corretor: dict[str, tuple[float, str]] = {}
        for p, rem, nome, trecho in resolvidos:
            nota = serve(p)
            if nota is not None and nota >= 70 and (rem not in por_corretor or nota > por_corretor[rem][0]):
                por_corretor[rem] = (nota, f"{nome or 'corretor'}: {trecho[:90]}")
        n90 = sum(1 for n, _ in por_corretor.values() if n >= 90)
        n70 = sum(1 for n, _ in por_corretor.values() if 70 <= n < 90)
        cli = [(lead_id, nome, s) for p, lead_id, nome in clientes if (s := serve(p)) is not None and s >= 70]
        pontos = (n90 + 0.4 * n70 + 3 * len(cli)) * (0.7 + 0.075 * (4 - len(faltou)))
        melhores = sorted(por_corretor.values(), key=lambda x: -x[0])[:3]
        detalhe = {"faltou": faltou, "assumido": {"tipo": tipo, "bairro": bairro_, "condominio": condo_, "quartos": quartos, "valor": valor, "operacao": ops},
                   "corretores": [{"nota": n, "texto": t} for n, t in melhores],
                   "clientes": [{"nota": s, "nome": (n or "cliente").split()[0]} for _, n, s in cli[:5]]}
        saida.append([cid, pontos, n90, n70, len(cli), detalhe])

    maior = max((x[1] for x in saida), default=0) or 1
    saida = [(cid, int(round(100 * math.log1p(pt) / math.log1p(maior))), n90, n70, ncli, Json({**det, "pontos": round(pt, 1)}))
             for cid, pt, n90, n70, ncli, det in saida]
    with conn.cursor() as cur:
        cur.execute("DELETE FROM privado.cadastro_incompleto_nota WHERE cadastro_id <> ALL(%s)", ([s[0] for s in saida],))
        for cid, nota, n90, n70, ncli, det in saida:
            cur.execute("""INSERT INTO privado.cadastro_incompleto_nota (cadastro_id, nota, pedidos_90, pedidos_70, clientes, melhor, calculada_em)
                           VALUES (%s, %s, %s, %s, %s, %s, now())
                           ON CONFLICT (cadastro_id) DO UPDATE SET nota = EXCLUDED.nota, pedidos_90 = EXCLUDED.pedidos_90,
                             pedidos_70 = EXCLUDED.pedidos_70, clientes = EXCLUDED.clientes, melhor = EXCLUDED.melhor, calculada_em = now()""",
                        (cid, nota, n90, n70, ncli, det))
    conn.commit()
    print(f"# {len(saida)} notas gravadas; com nota > 0: {sum(1 for s in saida if s[1] > 0)}", file=sys.stderr)


if __name__ == "__main__":
    main()
