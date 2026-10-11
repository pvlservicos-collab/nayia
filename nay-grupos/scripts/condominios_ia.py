"""Pede ao modelo o que ele souber de cada condomínio e guarda como SUGESTÃO (condominio_ficha.ia_sugestao, 348).

    python -m scripts.condominios_ia              # os condomínios com imóvel nosso e ficha incompleta
    python -m scripts.condominios_ia --todos      # todos os condomínios do cadastro
    python -m scripts.condominios_ia --limite 20  # só os 20 primeiros (para testar)

Nada entra na ficha por aqui: a sugestão aparece no cadastro do condomínio (Imóveis › Adicionar condomínio) com o
botão "Usar o que está vazio". O modelo é o mesmo do serviço (gpt-6-luna), no formato rígido; o que ele não sabe
vem nulo, e a confiança baixa é descartada. Roda no servidor, com o .env do nay-grupos (OPENAI_API_KEY, DATABASE_URL).
"""
from __future__ import annotations

import argparse
import json
import sys
import time

import psycopg2
import psycopg2.extras
import requests

from grupos import config

URL = "https://api.openai.com/v1/responses"
TEXTO = ("Você levanta dados de condomínios residenciais de Manaus (AM). PESQUISE na web o condomínio pedido (sites de "
         "imobiliárias, construtoras, anúncios) e responda SÓ o que encontrar; o que não encontrar, deixe nulo. Nunca "
         "invente construtora, ano ou número de torres. Em `confianca`, 'alta' quando duas fontes batem, 'media' com uma "
         "fonte, 'baixa' quando for palpite. Lazer/segurança/comodidades: use os nomes como os anúncios escrevem "
         "(Piscina, Academia, Salão de festas, Playground, Guarita 24 Horas, Elevador, Gás Encanado...).")
ESQUEMA = {
    "type": "object", "additionalProperties": False,
    "properties": {
        "confianca": {"type": "string", "enum": ["alta", "media", "baixa"]},
        "construtora": {"type": ["string", "null"]},
        "ano_construcao": {"type": ["string", "null"], "description": "ano de entrega, ex.: 2012"},
        "torres": {"type": ["integer", "null"]},
        "andares": {"type": ["integer", "null"]},
        "aptos_por_andar": {"type": ["integer", "null"]},
        "elevador": {"type": ["boolean", "null"]},
        "logradouro": {"type": ["string", "null"], "description": "rua ou avenida, sem o número"},
        "lazer": {"type": "array", "items": {"type": "string"}},
        "seguranca": {"type": "array", "items": {"type": "string"}},
        "comodidades": {"type": "array", "items": {"type": "string"}},
        "observacao": {"type": ["string", "null"], "description": "uma frase do que mais vale saber"},
    },
    "required": ["confianca", "construtora", "ano_construcao", "torres", "andares", "aptos_por_andar", "elevador",
                 "logradouro", "lazer", "seguranca", "comodidades", "observacao"],
}

SQL_FILA = """
SELECT c.id, c.nome, coalesce(c.bairro, f.bairro) AS bairro, f.id AS ficha_id, f.ia_em,
       f.construtora, coalesce(f.ano_construcao, f.ano_lancamento::text) AS ano, f.torres, f.andares, f.aptos_por_andar, f.lazer
  FROM condominios c LEFT JOIN condominio_ficha f ON f.condominio_id = c.id
 WHERE c.nome !~* '(nao|não) identificad|^(casa|apartamento|predio|prédio|livre|sala|loja|lote|flat)s?$'
   AND (%(todos)s OR EXISTS (SELECT 1 FROM imoveis i WHERE i.condo_id = c.id AND NOT coalesce(i.e_parceiro, false)
                                                      AND coalesce(i.status, '') <> 'Excluído'))
   AND (%(todos)s OR f.id IS NULL OR coalesce(f.construtora, '') = '' OR coalesce(f.ano_construcao, f.ano_lancamento::text, '') = ''
        OR coalesce(f.torres, '') = '' OR coalesce(f.andares, '') = '')
   AND (f.ia_em IS NULL OR f.ia_em < now() - interval '30 days')
 ORDER BY (SELECT count(*) FROM imoveis i WHERE i.condo_id = c.id) DESC, c.id
"""


def perguntar(nome: str, bairro: str | None) -> dict | None:
    entrada = [{"role": "system", "content": TEXTO},
               {"role": "user", "content": f"Condomínio: {nome}" + (f"\nBairro: {bairro}" if bairro else "") + "\nCidade: Manaus, AM"}]
    # "completar com o Google" (Pedro, 11/10): o modelo PESQUISA na web antes de responder; sem isso ele só sabia
    # dizer "confiança baixa" até do Acqua (Tecnisa) e do Maison Rochelle
    corpo = {"model": config.MODELO, "input": entrada, "tools": [{"type": "web_search"}],
             "text": {"format": {"type": "json_schema", "name": "condominio", "strict": True, "schema": ESQUEMA}}}
    for tentativa in range(3):
        try:
            r = requests.post(URL, json=corpo, timeout=90,
                              headers={"Authorization": f"Bearer {config.OPENAI_API_KEY}", "Content-Type": "application/json"})
            if r.status_code == 429 or r.status_code >= 500:
                time.sleep(5 * (tentativa + 1))
                continue
            r.raise_for_status()
            d = r.json()
            texto = "".join(p.get("text", "") for item in d.get("output", []) for p in item.get("content", []) if p.get("type") == "output_text")
            return json.loads(texto)
        except (requests.RequestException, ValueError) as e:
            print(f"  erro ({e.__class__.__name__}), tentativa {tentativa + 1}", file=sys.stderr)
            time.sleep(3)
    return None


def limpar(s: dict) -> dict | None:
    """Só o que vale: confiança alta ou média; textos curtos; listas sem repetição."""
    if not s or s.get("confianca") == "baixa":
        return None

    def t(k, n=120):
        v = s.get(k)
        return str(v).strip()[:n] if v not in (None, "") else None

    def lista(k):
        vistos, saida = set(), []
        for x in s.get(k) or []:
            x = str(x).strip()[:60]
            if x and x.lower() not in vistos:
                vistos.add(x.lower())
                saida.append(x)
        return saida[:30]

    limpo = {"confianca": s.get("confianca"), "construtora": t("construtora"), "ano_construcao": t("ano_construcao", 20),
             "torres": s.get("torres"), "andares": s.get("andares"), "aptos_por_andar": s.get("aptos_por_andar"),
             "elevador": s.get("elevador"), "logradouro": t("logradouro", 160),
             "lazer": lista("lazer"), "seguranca": lista("seguranca"), "comodidades": lista("comodidades"),
             "observacao": t("observacao", 300)}
    tem_algo = any(limpo[k] for k in ("construtora", "ano_construcao", "torres", "andares", "lazer", "logradouro"))
    return limpo if tem_algo else None


def main() -> None:
    a = argparse.ArgumentParser()
    a.add_argument("--todos", action="store_true")
    a.add_argument("--limite", type=int, default=0)
    args = a.parse_args()
    conn = psycopg2.connect(config.DATABASE_URL)
    conn.autocommit = True
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute(SQL_FILA, {"todos": args.todos})
    fila = cur.fetchall()
    if args.limite:
        fila = fila[:args.limite]
    print(f"{len(fila)} condomínios para perguntar")
    com, sem = 0, 0
    for c in fila:
        s = limpar(perguntar(c["nome"], c["bairro"]) or {})
        if s is None:
            sem += 1
            cur.execute("UPDATE condominio_ficha SET ia_em = now() WHERE condominio_id = %s", (c["id"],))
            continue
        com += 1
        if c["ficha_id"] is None:
            cur.execute("""INSERT INTO condominio_ficha (condominio_id, nome, bairro, fonte, ia_sugestao, ia_em)
                           VALUES (%s, %s, %s, 'sugestão da IA (conferir)', %s, now())
                           ON CONFLICT (nome) DO NOTHING""",
                        (c["id"], c["nome"], c["bairro"], psycopg2.extras.Json(s)))
            if cur.rowcount == 0:     # nome repetido em outra ficha: o id entre parênteses
                cur.execute("""INSERT INTO condominio_ficha (condominio_id, nome, bairro, fonte, ia_sugestao, ia_em)
                               VALUES (%s, %s, %s, 'sugestão da IA (conferir)', %s, now()) ON CONFLICT DO NOTHING""",
                            (c["id"], f"{c['nome']} ({c['id']})", c["bairro"], psycopg2.extras.Json(s)))
        else:
            cur.execute("UPDATE condominio_ficha SET ia_sugestao = %s, ia_em = now() WHERE id = %s",
                        (psycopg2.extras.Json(s), c["ficha_id"]))
        print(f"  {c['id']} {c['nome'][:40]}: {s['confianca']}, "
              f"{', '.join(k for k in ('construtora', 'ano_construcao', 'torres', 'andares') if s.get(k))}")
    print(f"com sugestão: {com}; sem nada que preste: {sem}")


if __name__ == "__main__":
    main()
