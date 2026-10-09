"""A ficha do dono, analisada e posta nos campos certos do cadastro (327).

Pedro, 09/10/2026, no Cadastro rápido: "se o dono mandou as fotos elas já têm que aparecer lá, o mais automático
possível para eu só aprovar; analisa as informações e põe elas nos campos certinhos".

A ficha (captacao_cadastro) guarda o que o dono disse nas palavras dele. Aqui o modelo lê a ficha e a conversa e devolve
os campos do cadastro; o resultado vai para captacao_ficha_campos, e a tela abre o cadastro já preenchido. Nada é
criado em `imoveis`: quem cadastra é a pessoa, com um clique.

    python -m captacao.preparar            as fichas sem análise, ou que mudaram depois dela (até 10 por vez)
    python -m captacao.preparar --ficha 51 uma ficha só (refaz)
    python -m captacao.preparar --tudo     todas as pendentes, de novo

Roda de 5 em 5 minutos pelo cron (/etc/cron.d/captacao-preparar-fichas).
"""
from __future__ import annotations

import argparse
import json
import re
import sys

from captacao import banco, config
from captacao.modelo import FalhaDoModelo, _chamar, _texto_da

PENDENTES = """
SELECT c.id FROM captacao_cadastro c LEFT JOIN captacao_ficha_campos a ON a.ficha_id = c.id
 WHERE c.estado IN ('coletando', 'pronto') AND c.codigo IS NULL AND c.tipo <> 'atualizar'
   AND (%(tudo)s OR a.ficha_id IS NULL OR a.ficha_atualizada_em IS DISTINCT FROM c.atualizado_em)
 ORDER BY c.atualizado_em LIMIT %(limite)s
"""

ENTRADA = """
SELECT c.id, c.dados, c.atualizado_em, jsonb_array_length(CASE WHEN jsonb_typeof(c.fotos) = 'array' THEN c.fotos ELSE '[]' END) AS fotos,
       l.nome, l.tratamento, l.imovel_desc, l.condominio AS condo_da_campanha, l.bairro AS bairro_da_campanha,
       (SELECT string_agg(to_char(m.criada_em AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI') || ' '
                          || CASE m.direcao WHEN 'recebida' THEN 'DONO' ELSE 'NOS' END || ': '
                          || left(regexp_replace(m.texto, '\\s+', ' ', 'g'), 600), E'\\n' ORDER BY m.id)
          FROM (SELECT * FROM captacao_mensagens x
                 WHERE x.lead_id = c.lead_id AND coalesce(btrim(x.texto), '') <> ''
                 ORDER BY x.id DESC LIMIT 80) m) AS conversa,
       (SELECT json_agg(json_build_object('ficha', o.id, 'estado', o.estado, 'dados', o.dados) ORDER BY o.id)
          FROM captacao_cadastro o
         WHERE o.lead_id = c.lead_id AND o.id <> c.id AND o.estado IN ('coletando', 'pronto', 'aplicado')) AS outras_fichas
  FROM captacao_cadastro c LEFT JOIN captacao_leads l ON l.id = c.lead_id
 WHERE c.id = %s
"""

GUARDAR = """
INSERT INTO captacao_ficha_campos (ficha_id, campos, observacao, pronto, duplicado_de, ficha_atualizada_em, analisado_em, modelo)
VALUES (%(id)s, %(campos)s::jsonb, %(obs)s, %(pronto)s, %(dup)s, %(atu)s, now(), %(modelo)s)
ON CONFLICT (ficha_id) DO UPDATE
   SET campos = EXCLUDED.campos, observacao = EXCLUDED.observacao, pronto = EXCLUDED.pronto,
       duplicado_de = EXCLUDED.duplicado_de, ficha_atualizada_em = EXCLUDED.ficha_atualizada_em,
       analisado_em = now(), modelo = EXCLUDED.modelo
"""

INSTRUCAO = """Você prepara o CADASTRO de um imóvel a partir do que o proprietário contou no WhatsApp.
Recebe a FICHA (o que ele disse, nas palavras dele, sobre UM imóvel) e a CONVERSA. Preencha cada campo com o que ele
DISSE sobre ESTE imóvel. Não invente: sem informação, o campo é null. Use a conversa só para o que é deste imóvel
(o imóvel da campanha, já cadastrado conosco, é OUTRO -- não misture).

Responda SÓ um objeto JSON com estas chaves:
  tipo            "Apartamento", "Casa", "Casa de condomínio", "Sobrado", "Cobertura", "Kitnet", "Flat", "Sala comercial",
                  "Loja", "Prédio comercial", "Galpão", "Terreno", "Lote", "Chácara" ou outro, com inicial maiúscula
  condominio      nome do condomínio ou edifício como ele disse (ex.: "Forest Hill", "Reserva Inglesa Soho"), ou null
  bairro          bairro de Manaus, ou null
  logradouro      rua/avenida (ex.: "Rua 14"), número em "numero"; complemento: quadra, lote, bloco, apto (texto)
  numero, complemento, andar
  quartos, suites, banheiros, vagas         inteiros ("Três suítes" -> suites 3; se ele só falou de suítes, quartos = suítes;
                                             "Garagem 4 carros" -> vagas 4; "banheiro social, lavabo, lavabo" -> banheiros 3)
  area_util, area_total                     números em m² ("220 m²" -> 220; "entre 65 e 70" -> 65)
  valor_aluguel, valor_venda                números em reais ("R$ 1.290.000,00" -> 1290000; "650 mil" -> 650000; "2.500" -> 2500).
                                            Venda vai em valor_venda; aluguel em valor_aluguel
  taxa_condominio, iptu                     números em reais por mês, ou null
  mobilia         um destes textos ou null: "mobiliado (moveis + cama + tudo)", "semi-mobiliado (moveis planejados + ar)",
                  "so ar-condicionado", "sem mobilia"
  caracteristicas lista curta do que o imóvel tem (ex.: ["Piscina", "Varanda", "Lavabo", "Área de serviço"])
  descricao       2 a 4 frases de anúncio, em português simples, sem nome, telefone, preço ou "excelente oportunidade"
  negocio         "venda", "locacao" ou "ambos"
  pronto_para_anunciar  true se é um imóvel vago e descrito; false se ele disse que está alugado, em obra, que vai avisar
                  depois, ou só citou sem dados
  observacao      uma frase curta para a equipe conferir (ex.: "disse que está alugado até fev/2028"), ou null
  duplicado_de    o número de OUTRA ficha deste mesmo dono que descreve o MESMO imóvel, ou null"""

INTEIROS = ("quartos", "suites", "banheiros", "vagas")
NUMEROS = ("area_util", "area_total", "valor_aluguel", "valor_venda", "taxa_condominio", "iptu")
TEXTOS = ("tipo", "condominio", "bairro", "logradouro", "numero", "complemento", "andar", "mobilia", "descricao", "negocio")


def _numero(v):
    if v is None or isinstance(v, bool):
        return None
    if isinstance(v, (int, float)):
        return v
    m = re.search(r"\d[\d.]*(?:,\d+)?", str(v))
    if not m:
        return None
    n = float(m.group(0).replace(".", "").replace(",", ".")) if "," in m.group(0) or m.group(0).count(".") > 1 \
        else float(m.group(0).replace(".", "") if re.fullmatch(r"\d{1,3}(\.\d{3})+", m.group(0)) else m.group(0))
    if re.search(r"milh", str(v), re.I):
        n *= 1_000_000
    elif re.search(r"\bmil\b", str(v), re.I):
        n *= 1000
    return n


def limpar(bruto: dict) -> dict:
    """O JSON do modelo nos tipos que o cadastro aceita; o que não serve vira None."""
    c: dict = {}
    for k in INTEIROS:
        n = _numero(bruto.get(k))
        c[k] = int(round(n)) if n is not None and 0 <= n <= 50 else None
    for k in NUMEROS:
        n = _numero(bruto.get(k))
        c[k] = n if n is not None and n > 0 else None
    for k in TEXTOS:
        v = bruto.get(k)
        c[k] = str(v).strip()[:2000] if v not in (None, "") and str(v).strip().lower() not in ("null", "none") else None
    car = bruto.get("caracteristicas")
    c["caracteristicas"] = [str(x).strip()[:60] for x in car if str(x).strip()][:20] if isinstance(car, list) else None
    if c["descricao"]:   # telefone e e-mail não entram no anúncio
        c["descricao"] = re.sub(r"\(?\d{2}\)?\s*9?\d{4}[-. ]?\d{4}", "", c["descricao"]).strip()
    return c


def analisar(conn, ficha: int) -> dict:
    e = banco.linhas(conn, ENTRADA, (ficha,))
    if not e:
        raise ValueError(f"a ficha {ficha} não existe")
    e = e[0]
    entrada = {
        "ficha": e["id"], "o_que_ele_disse": e["dados"], "fotos_que_ele_mandou": e["fotos"],
        "dono": " ".join(x for x in (e["tratamento"], e["nome"]) if x),
        "imovel_da_campanha_ja_cadastrado": " · ".join(x for x in (e["imovel_desc"], e["condo_da_campanha"], e["bairro_da_campanha"]) if x),
        "outras_fichas_deste_dono": e["outras_fichas"] or [],
    }
    corpo = {"model": config.MODELO, "text": {"format": {"type": "json_object"}},
             "input": [{"role": "system", "content": INSTRUCAO},
                       {"role": "user", "content": "FICHA:\n" + json.dumps(entrada, ensure_ascii=False, default=str) +
                                                   "\n\nCONVERSA (a mais recente no fim):\n" + (e["conversa"] or "(sem texto)")}]}
    bruto = json.loads(_texto_da(_chamar(corpo)) or "{}")
    campos = limpar(bruto)
    dup = bruto.get("duplicado_de")
    dup = int(dup) if isinstance(dup, (int, float)) or (isinstance(dup, str) and dup.isdigit()) else None
    pronto = bruto.get("pronto_para_anunciar")
    banco.linhas(conn, GUARDAR, {"id": ficha, "campos": json.dumps(campos, ensure_ascii=False), "obs": (bruto.get("observacao") or None),
                                 "pronto": pronto if isinstance(pronto, bool) else None, "dup": dup if dup != ficha else None,
                                 "atu": e["atualizado_em"], "modelo": config.MODELO})
    return {"ficha": ficha, "campos": {k: v for k, v in campos.items() if v not in (None, [])}, "pronto": pronto,
            "observacao": bruto.get("observacao"), "duplicado_de": dup}


def main() -> None:
    a = argparse.ArgumentParser(description="Analisa as fichas do dono e prepara os campos do cadastro.")
    a.add_argument("--ficha", type=int)
    a.add_argument("--tudo", action="store_true")
    a.add_argument("--limite", type=int, default=10)
    args = a.parse_args()
    conn = banco.conectar()
    try:
        ids = [args.ficha] if args.ficha else [r["id"] for r in banco.linhas(
            conn, PENDENTES, {"tudo": args.tudo, "limite": 500 if args.tudo else args.limite})]
        for f in ids:
            try:
                r = analisar(conn, f)
                print(json.dumps(r, ensure_ascii=False, default=str)[:600])
            except (FalhaDoModelo, ValueError, json.JSONDecodeError) as erro:
                print(f"ficha {f}: não analisei ({erro})", file=sys.stderr)
        # 332: depois das fichas, o palpite de cada item da fila do Cadastro rápido ("O que a IA supõe que é")
        if not args.ficha:
            from captacao import palpite
            for r in palpite.rodar(conn):
                print("palpite " + json.dumps(r, ensure_ascii=False)[:300])
    finally:
        conn.close()


if __name__ == "__main__":
    main()
