"""Lê condominios_proximos.xlsx e gera um SQL só de leitura que mede quantos nomes casam com o cadastro."""
import json
import pathlib
import re
import sys

import openpyxl

sys.stdout.reconfigure(encoding="utf-8")
RAIZ = pathlib.Path(r"C:\Users\pedro\Desktop\TEL SOBREIRA\Nay IA")
S = pathlib.Path(__file__).parent
wb = openpyxl.load_workbook(RAIZ / "condominios_proximos.xlsx", data_only=True)
ws = wb.worksheets[0]
linhas = []
for r in ws.iter_rows(min_row=2, values_only=True):
    if not r[0]:
        continue
    lista = lambda s: [re.sub(r"\s*\(recente\)\s*$", "", x.strip(), flags=re.I) for x in (s or "").split(";") if x.strip()]
    linhas.append({"nome": r[0].strip(), "bairro": (r[1] or "").strip(), "recente": str(r[2] or "").strip().lower() == "sim",
                   "normal": lista(r[3]), "novo": lista(r[4])})
bairros = {}
for r in wb.worksheets[1].iter_rows(min_row=2, values_only=True):
    if r[0]:
        bairros[r[0].strip()] = [x.strip() for x in (r[1] or "").split(",") if x.strip()]
(S / "planilha.json").write_text(json.dumps({"condominios": linhas, "bairros": bairros}, ensure_ascii=False, indent=1),
                                 encoding="utf-8")
nomes = sorted({x["nome"] for x in linhas} | {n for x in linhas for n in x["normal"] + x["novo"]})
fora = sorted({n for x in linhas for n in x["normal"] + x["novo"]} - {x["nome"] for x in linhas})
print(len(linhas), "linhas;", len(nomes), "nomes;", len(fora), "nomes de lista que não têm linha própria:", fora[:15])
q = lambda s: "'" + s.replace("'", "''") + "'"
vals = ",\n".join(f"({q(n)})" for n in nomes)
(S / "casar.sql").write_text(f"""WITH p(nome) AS (VALUES {vals}),
c AS (SELECT DISTINCT ON (nay_chave_condominio(nome)) id, nome, bairro, nay_chave_condominio(nome) ch FROM condominios),
i AS (SELECT nay_chave_condominio(condominio_nome) ch, count(*) n FROM imoveis
       WHERE status = 'Disponível' AND NOT coalesce(e_parceiro, false) AND condominio_nome IS NOT NULL GROUP BY 1)
SELECT count(*) nomes, count(c.id) casam_cadastro, count(i.ch) com_imovel_disponivel,
       sum(coalesce(i.n,0)) imoveis_disponiveis
  FROM p LEFT JOIN c ON c.ch = nay_chave_condominio(p.nome) LEFT JOIN i ON i.ch = nay_chave_condominio(p.nome);
WITH p(nome) AS (VALUES {vals}),
c AS (SELECT nay_chave_condominio(nome) ch FROM condominios)
SELECT p.nome FROM p WHERE nay_chave_condominio(p.nome) NOT IN (SELECT ch FROM c) ORDER BY 1 LIMIT 40;
WITH i AS (SELECT nay_chave_condominio(condominio_nome) ch, min(condominio_nome) nome, count(*) n FROM imoveis
       WHERE status = 'Disponível' AND NOT coalesce(e_parceiro, false) AND condominio_nome IS NOT NULL GROUP BY 1),
p(nome) AS (VALUES {vals})
SELECT count(*) condominios_com_oferta, count(*) FILTER (WHERE ch IN (SELECT nay_chave_condominio(nome) FROM p)) na_planilha,
       sum(n) imoveis, sum(n) FILTER (WHERE ch IN (SELECT nay_chave_condominio(nome) FROM p)) imoveis_na_planilha FROM i;
""", encoding="utf-8")
print("ok")
