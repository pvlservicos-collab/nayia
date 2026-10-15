"""O MEU catálogo, como a conta precisa dele: só imóvel nosso, disponível, com o que o cadastro sabe.

Só entram imóveis NOSSOS (parceiro nunca é oferecido: regra antiga da casa) com situação "Disponível".

A DATA DE CONFIRMAÇÃO não existe como campo (avisado a ele em 09/10). Vale a mais recente entre:
  - o anúncio visto no ar pelo leitor da ficha (`imovel_ficha`, a cada 3 h);
  - o dono dizendo "disponível" na captação (`captacao_aplicado`);
  - a situação decidida à mão (`travado_em`) e o cadastro novo (`criado_em`).
`fotos_conferidas_em` NÃO conta: é carimbo de rotina automática das fotos, não diz que o imóvel está disponível.
Medido em 09/10: dos 311 nossos, 252 pelo anúncio, 57 à mão, 15 pelo dono, 86 cadastros do último mês.
"""
from __future__ import annotations

from grupos.texto import normal

SQL = """
SELECT i.codigo, i.tipo, i.bairro, i.condominio_nome, i.quartos, i.suites, i.vagas, i.andar, i.mobilia,
       i.valor_aluguel, i.valor_venda, i.taxa_condominio, i.area_util, i.logradouro,
       nay_chave_condominio(coalesce(i.condominio_nome, '')) AS condominio_chave,
       (array_to_string(coalesce(i.caracteristicas, '{}'), ' ') ~* '(aceita|permite)\\s+(pet|anima)|pet\\s*friendly'
        OR coalesce(i.extras::text, '') ~* '(aceita|permite)[^"]{0,12}(pet|anima)') AS pet,
       nullif(btrim(i.extras->>'aceita financiamento'), '') AS financiamento,
       f.visto, a.dono, CASE WHEN i.travado THEN i.travado_em END AS a_mao, i.criado_em
  FROM imoveis i
  LEFT JOIN LATERAL (SELECT max(x.lido_em) AS visto FROM imovel_ficha x
                      WHERE x.codigo = i.codigo AND x.encontrado AND x.erro IS NULL) f ON true
  LEFT JOIN LATERAL (SELECT max(x.aplicado_em) AS dono FROM captacao_aplicado x
                      WHERE x.codigo::text = i.codigo::text AND x.situacao = 'disponivel') a ON true
 WHERE coalesce(i.disponivel, true) AND i.status = 'Disponível'
   AND NOT coalesce(i.e_parceiro, false) AND NOT coalesce(i.bloqueado, false)
"""

# OS BAIRROS PRÓXIMOS, com o que se sabe de cada par: se fazem divisa e a distância entre os centros (km).
#   geo_bairro_vizinho  o mapa: 576 pares (quem faz divisa, e quem fica a até ~7 km sem fazer)
#   bairro_vizinho      a tabela editável dele: par posto à mão vale como "faz divisa" (km do mapa, se houver)
SQL_VIZINHOS = """
SELECT a, b, bool_or(divisa) AS divisa, min(km) AS km FROM (
  SELECT coalesce(n1.nome_cadastro, g.bairro) AS a, coalesce(n2.nome_cadastro, g.vizinho) AS b, g.divisa, g.km
    FROM geo_bairro_vizinho g
    LEFT JOIN geo_bairro_nome n1 ON n1.bairro = g.bairro
    LEFT JOIN geo_bairro_nome n2 ON n2.bairro = g.vizinho
  UNION ALL SELECT bairro, vizinho, true, NULL FROM bairro_vizinho
  UNION ALL SELECT vizinho, bairro, true, NULL FROM bairro_vizinho
) x
 GROUP BY a, b
"""


def tipo_do(t: str | None) -> str:
    n = normal(t)
    if n.startswith(("apartamento", "flat", "cobertura", "kitnet", "studio", "loft", "duplex")):
        return "apartamento"
    if n.startswith("casa") or "sobrado" in n:
        return "casa"
    if n.startswith(("sala", "loja", "ponto", "andar")):
        return "sala"
    return "outro"


def mobilia_do(m: str | None) -> str | None:
    n = normal(m)
    if not n:
        return None
    if n.startswith("semi"):
        return "semi"
    if n.startswith(("mobiliado", "porteira")):
        return "mobiliado"
    if n.startswith(("so ar", "sem mob", "vazio", "nao mobiliado", "cru")):
        return "vazio"
    return None


def financiamento_do(f: str | None) -> bool | None:
    n = normal(f)
    if n.startswith(("sim", "aceita")):
        return True
    if n.startswith(("nao", "não")):
        return False
    return None


def andar_do(a: str | None) -> int | None:
    n = normal(a)
    if not n:
        return None
    if "terr" in n:
        return 0
    digitos = "".join(c for c in n.split()[0] if c.isdigit())
    if digitos:
        return int(digitos)
    return 99 if "alto" in n else None


def carregar(conn) -> tuple[list[dict], dict]:
    """(os imóveis, {bairro: {vizinho: {"divisa": bool, "km": float | None}}}); nomes como chave (texto.normal)."""
    with conn.cursor() as cur:
        cur.execute(SQL)
        colunas = [d[0] for d in cur.description]
        linhas = [dict(zip(colunas, l)) for l in cur.fetchall()]
        cur.execute(SQL_VIZINHOS)
        pares = cur.fetchall()
    imoveis = []
    for l in linhas:
        datas = {"anúncio visto no ar": l["visto"], "dono confirmou na captação": l["dono"],
                 "situação decidida à mão": l["a_mao"], "cadastro novo": l["criado_em"]}
        datas = {k: v for k, v in datas.items() if v is not None}
        como = max(datas, key=datas.get) if datas else None
        imoveis.append({
            "codigo": l["codigo"], "tipo": tipo_do(l["tipo"]), "tipo_cadastro": l["tipo"],
            "bairro": (l["bairro"] or "").strip() or None, "bairro_chave": normal(l["bairro"]),
            "condominio": (l["condominio_nome"] or "").strip() or None, "condominio_chave": l["condominio_chave"] or "",
            "quartos": l["quartos"], "suites": l["suites"], "vagas": l["vagas"],
            "andar": andar_do(l["andar"]), "andar_cadastro": (l["andar"] or "").strip() or None,
            "mobilia": mobilia_do(l["mobilia"]), "mobilia_cadastro": (l["mobilia"] or "").strip() or None,
            "pet": True if l["pet"] else None,
            # o "aceita financiamento" do cadastro (Sim / Não / vazio = não informado)
            "financiamento": financiamento_do(l["financiamento"]),
            "valor_aluguel": float(l["valor_aluguel"]) if l["valor_aluguel"] else None,
            "valor_venda": float(l["valor_venda"]) if l["valor_venda"] else None,
            "taxa_condominio": float(l["taxa_condominio"]) if l["taxa_condominio"] else None,
            "area": float(l["area_util"]) if l["area_util"] else None,
            "logradouro": (l["logradouro"] or "").strip() or None,
            "confirmado_em": datas[como] if como else None, "confirmado_como": como,
        })
    vizinhos: dict[str, dict[str, dict]] = {}
    for a, b, divisa, km in pares:
        if a and b and normal(a) != normal(b):
            vizinhos.setdefault(normal(a), {})[normal(b)] = {"divisa": bool(divisa), "km": float(km) if km is not None else None}
    return imoveis, vizinhos


def para_a_tela(imovel: dict) -> dict:
    """O retrato do imóvel que fica guardado com o par (só o que a tela mostra, em JSON)."""
    r = {k: imovel.get(k) for k in ("codigo", "tipo_cadastro", "bairro", "condominio", "quartos", "suites", "vagas",
                                    "andar_cadastro", "mobilia_cadastro", "valor_aluguel", "valor_venda",
                                    "taxa_condominio", "area", "logradouro", "confirmado_como", "financiamento")}
    r["confirmado_em"] = imovel["confirmado_em"].isoformat() if imovel.get("confirmado_em") else None
    return r
