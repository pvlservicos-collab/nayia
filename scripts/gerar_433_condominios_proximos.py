"""Gera Arquivos/nai/433_condominios_proximos.sql a partir de condominios_proximos.xlsx (planilha.json)."""
import json
import pathlib

S = pathlib.Path(__file__).parent
R = pathlib.Path(r"C:\Users\pedro\Desktop\TEL SOBREIRA\Nay IA\Arquivos\nai")
P = json.loads((S / "planilha.json").read_text(encoding="utf-8"))


def q(s):
    return "'" + str(s).replace("'", "''") + "'"


def arr(xs):
    return "ARRAY[" + ", ".join(q(x) for x in xs) + "]::text[]" if xs else "'{}'::text[]"


linhas = ",\n".join(
    f"  ({q(c['nome'])}, {q(c['bairro'])}, {'true' if c['recente'] else 'false'}, {arr(c['normal'])}, {arr(c['novo'])})"
    for c in P["condominios"])

sql = f"""-- 433: CONDOMÍNIOS PRÓXIMOS (Pedro, 20/10/2026: "coloquei uma planilha ... para que quando a Nay for buscar imóveis em
-- condomínios próximos ela possa consultar ... se o cara pede condomínio normal ela relaciona primariamente os normais,
-- se o cara pede um imóvel em um condomínio que é novo, ou seja feito nos últimos 5 anos, ela deve priorizar enviar os
-- imóveis em condomínios novos ... implemente em todas as Nays que buscam imóveis; caso ela não ache nos condomínios
-- novos ou normais ela pode buscar em um ou em outro, mas a prioridade é assim").
--
-- A planilha (condominios_proximos.xlsx, 338 condomínios, 22 recentes) entra como está em `condominio_proximo`:
-- o nome, o bairro, se é recente e a lista dos próximos (na ordem da planilha). Cada nome é ligado a um condomínio do
-- cadastro (`condominios`): pela chave do nome (nay_chave_condominio) ou, quando não bate, pela semelhança (>= 0,55)
-- com os MESMOS números no nome (o "São Judas Tadeu 3" não vira o 1; o "Villa Verde II" não vira o 1).
-- Quem lê:
--   condominio_proximo_nomes   todos os jeitos de escrever cada condomínio da planilha (o da planilha, o do cadastro e
--                              o dos imóveis ligados a ele), normalizados como o nay-core e o radar comparam;
--   condominio_proximo_lista   para cada condomínio, os próximos na ordem, com o recente de cada um.
-- Atualizar a planilha = scripts/ler_planilha_condominios_proximos.py e este gerador num 433b: a tabela é apagada e
-- refeita; depois rodar `SELECT privado.condominio_proximo_anos();` (436) para os recentes pelo ano.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS public.condominio_proximo (
  id          serial PRIMARY KEY,
  nome        text NOT NULL UNIQUE,
  bairro      text,
  recente     boolean NOT NULL DEFAULT false,
  proximos    text[] NOT NULL DEFAULT '{{}}',
  condo_id    integer REFERENCES condominios(id),
  ligado_como text,
  recente_planilha boolean NOT NULL DEFAULT false,   -- 436
  ano          integer,                            -- 436
  origem       text NOT NULL DEFAULT 'planilha',   -- 436
  carregado_em timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.condominio_proximo IS '433: a planilha condominios_proximos.xlsx do Pedro (20/10): os condomínios próximos de cada um e se é recente (últimos 5 anos).';

DELETE FROM public.condominio_proximo;
INSERT INTO public.condominio_proximo (nome, bairro, recente, recente_planilha, proximos)
SELECT nome, bairro, recente, recente, normal FROM (VALUES
{linhas}
) v(nome, bairro, recente, normal, novo);

-- os números do nome (romanos viram arábicos): o par só casa por semelhança se eles forem os mesmos
CREATE OR REPLACE FUNCTION privado.condominio_numeros(p text) RETURNS text
LANGUAGE sql IMMUTABLE AS $f$
  SELECT coalesce(string_agg(n, ',' ORDER BY n), '') FROM (
    SELECT CASE m[1] WHEN 'i' THEN '1' WHEN 'ii' THEN '2' WHEN 'iii' THEN '3' WHEN 'iv' THEN '4' WHEN 'v' THEN '5'
                     ELSE ltrim(m[1], '0') END AS n
      FROM regexp_matches(lower(coalesce(p, '')), '\\m(\\d+|i{{1,3}}|iv|v)\\M', 'g') m) x
$f$;

UPDATE public.condominio_proximo p SET condo_id = c.id, ligado_como = 'nome'
  FROM (SELECT DISTINCT ON (nay_chave_condominio(nome)) id, nay_chave_condominio(nome) ch FROM condominios
         ORDER BY nay_chave_condominio(nome), id) c
 WHERE c.ch = nay_chave_condominio(p.nome) AND c.ch <> '';

UPDATE public.condominio_proximo p SET condo_id = b.id, ligado_como = 'parecido ' || round(b.sim::numeric, 2)
  FROM (SELECT p2.id AS pid, x.id, x.sim FROM public.condominio_proximo p2
         CROSS JOIN LATERAL (SELECT c.id, similarity(nay_chave_condominio(c.nome), nay_chave_condominio(p2.nome)) sim
                               FROM condominios c
                              WHERE privado.condominio_numeros(c.nome) = privado.condominio_numeros(p2.nome)
                              ORDER BY 2 DESC LIMIT 1) x
         WHERE p2.condo_id IS NULL AND x.sim >= 0.55
           -- conferidos à mão em 20/10: parecidos no texto, outro condomínio
           AND p2.nome NOT IN ('Le Gran Ponta Negra', 'La Maison Adrianópolis', 'Ed Palácio Adrianópolis',
                               'Condominio Leda Vieiralves', 'Altos Das Laranjeiras', 'Moradas do Parque Laranjeiras',
                               'Cond Villagio Del Fiori', 'Edificio Cristal', 'Edifício Lírios',
                               'Vila das Flores', 'Amazon Boulevard Life e Garden')) b
 WHERE p.id = b.pid;

-- todos os jeitos de escrever cada um (minúsculo e sem acento, como o nay-core: core_imovel_busca.condominio_norm)
CREATE OR REPLACE VIEW public.condominio_proximo_nomes AS
SELECT DISTINCT p.id, n.norma
  FROM public.condominio_proximo p
  CROSS JOIN LATERAL (
    SELECT lower(unaccent(p.nome)) AS norma
    UNION SELECT lower(unaccent(c.nome)) FROM condominios c WHERE c.id = p.condo_id
    UNION SELECT lower(unaccent(i.condominio_nome)) FROM imoveis i
           WHERE i.condo_id = p.condo_id AND p.condo_id IS NOT NULL AND coalesce(i.condominio_nome, '') <> ''
  ) n
 WHERE coalesce(n.norma, '') <> '';

-- para cada condomínio, os próximos na ordem da planilha, com o recente de cada um. A lista da planilha vem em dois
-- blocos (os do mesmo bairro, depois os da região, cada um em ordem alfabética): `mesmo_bairro` diz de qual bloco
CREATE OR REPLACE VIEW public.condominio_proximo_lista AS
SELECT p.id AS de_id, p.nome AS de_nome, p.recente AS de_recente, l.ordem, q.id AS para_id, q.nome AS para_nome,
       q.recente AS para_recente,
       privado.bairros_iguais(p.bairro, q.bairro) AS mesmo_bairro       -- 438
  FROM public.condominio_proximo p
  CROSS JOIN LATERAL unnest(p.proximos) WITH ORDINALITY l(nome, ordem)
  JOIN public.condominio_proximo q ON q.nome = l.nome;

-- 436/438: os recentes pelo ano da ficha e os do cadastro com os próximos do mesmo bairro
SELECT privado.condominio_proximo_anos();

GRANT SELECT ON public.condominio_proximo, public.condominio_proximo_nomes, public.condominio_proximo_lista
  TO nay_core, nay_leitura, nay_site_leitura;
COMMIT;
"""
(R / "433_condominios_proximos.sql").write_text(sql, encoding="utf-8")
(R / "teste_433.sql").write_text(r"""\pset pager off
SELECT count(*) condominios, count(*) FILTER (WHERE recente) recentes, count(condo_id) ligados,
       count(*) FILTER (WHERE ligado_como LIKE 'parecido%') por_semelhanca FROM condominio_proximo;
SELECT nome, (SELECT c.nome FROM condominios c WHERE c.id = p.condo_id) cadastro, ligado_como
  FROM condominio_proximo p WHERE ligado_como LIKE 'parecido%' ORDER BY ligado_como LIMIT 70;
SELECT count(*) pares, count(DISTINCT de_id) com_lista FROM condominio_proximo_lista;
-- quantos imóveis disponíveis nossos caem num condomínio da planilha (pelo nome normalizado)
SELECT count(*) disponiveis, count(*) FILTER (WHERE EXISTS (SELECT 1 FROM condominio_proximo_nomes n
                                         WHERE n.norma = lower(unaccent(i.condominio_nome)))) na_planilha
  FROM imoveis i WHERE i.status = 'Disponível' AND NOT coalesce(i.e_parceiro, false) AND i.condominio_nome IS NOT NULL;
-- o Jardim das Cerejeiras (recente): os próximos, recentes primeiro
SELECT para_nome, para_recente, mesmo_bairro, ordem FROM condominio_proximo_lista WHERE de_nome ILIKE '%Cerejeiras%'
 ORDER BY para_recente DESC, NOT mesmo_bairro, ordem LIMIT 8;
SELECT count(*) FILTER (WHERE mesmo_bairro) mesmo, count(*) FILTER (WHERE NOT mesmo_bairro) regiao FROM condominio_proximo_lista;
SET ROLE nay_core; SELECT count(*) o_core_le FROM condominio_proximo_nomes; RESET ROLE;
""", encoding="utf-8")
print("ok")
