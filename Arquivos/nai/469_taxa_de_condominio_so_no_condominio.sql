-- 469: a taxa de condomínio mora no CONDOMÍNIO (uma por número de quartos) e o imóvel só a recebe
--
-- Pedro, 22/10/2026: "não quero que o preço do condomínio fique dando para digitar no editar imóvel, o preço de
-- condomínio é padrão igual no mesmo condomínio para todos, a depender da quantidade de quartos ... quero migrar esse
-- preço para dentro da aba condomínio e editar condomínio. Analise todos os valores e mude isso, botando para
-- condomínio, e já altere nos imóveis que esse valor vem do condomínio".
--
-- O que estava (22/10): só 11 linhas de taxa tinham sido DIGITADAS nos condomínios; 90 tinham sido DEDUZIDAS dos
-- imóveis por uma migração antiga ("fonte": "imóveis") e só preenchiam imóvel sem taxa; 277 imóveis com taxa não
-- tinham linha para os quartos deles; 77 grupos (condomínio + quartos) tinham valores diferentes entre os imóveis
-- (ex.: Acquarelle 3 quartos 892 nos antigos e 1.250 no 1125 disponível; Estilo Golf 2 quartos 280, 290 e 300).
-- E o editar imóvel deixava digitar a taxa, que o gatilho da 448 respeitava (o imóvel podia ficar diferente do
-- condomínio).
--
-- Como fica:
--   1. Para cada condomínio + quartos, UM valor, na linha do condomínio:
--      a) a linha DIGITADA no condomínio fica como está (foi a equipe que escreveu);
--      b) sem ela, o valor dos imóveis: primeiro o de um imóvel Disponível, depois Alugado, depois os outros; no
--         empate, o escrito mais recentemente (taxa_condominio_em), depois o mais repetido, depois o maior.
--         Não contam como prova as 672 taxas que a própria 448 copiou da linha deduzida em 20/10 às 17:06 (Manaus);
--      c) sem imóvel nenhum com taxa, a linha deduzida fica, agora como do condomínio.
--      Toda linha perde o "fonte": a partir de agora a do condomínio manda sempre. O IPTU fixo da linha continua.
--   2. O gatilho da 448 (condominio_taxa_aos_imoveis_tg) leva o valor a todo imóvel do condomínio com aqueles quartos.
--   3. imoveis_taxa_do_condominio (o gatilho do imóvel) passa a impor a linha SEMPRE: quem gravar outra taxa num imóvel
--      que tem linha no condomínio (tela, importador, OLX, site antigo) fica com a do condomínio. Sem linha, fica o que
--      foi gravado. Também reconhece o condomínio pelos "nomes no imóvel", como a função da 448.
--   4. A tela (imovel-editar.js) mostra a taxa como vinda do condomínio, sem campo para digitar.
-- O de antes: privado.taxa_condominio_antes_469 (as linhas de cada condomínio) e privado.taxa_imovel_antes_469 (a taxa
-- e o IPTU de cada imóvel). Desfazer: voltar as taxas das fichas e depois as dos imóveis a partir dessas tabelas, e o
-- gatilho do imóvel pelo backup /root/backups-funcoes/imoveis_taxa_do_condominio-20261022-469.sql.

BEGIN;
SET LOCAL lock_timeout = '3s';
SET LOCAL statement_timeout = '120s';

CREATE TABLE IF NOT EXISTS privado.taxa_condominio_antes_469 (
  ficha integer PRIMARY KEY, taxas jsonb NOT NULL, em timestamptz NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS privado.taxa_imovel_antes_469 (
  codigo integer PRIMARY KEY, taxa numeric, iptu numeric, taxa_em timestamptz, em timestamptz NOT NULL DEFAULT now());
INSERT INTO privado.taxa_condominio_antes_469 (ficha, taxas) SELECT id, taxas FROM condominio_ficha ON CONFLICT DO NOTHING;
INSERT INTO privado.taxa_imovel_antes_469 (codigo, taxa, iptu, taxa_em)
SELECT codigo, taxa_condominio, iptu, taxa_condominio_em FROM imoveis ON CONFLICT DO NOTHING;

-- 3. o gatilho do imóvel: a linha do condomínio manda sempre
CREATE OR REPLACE FUNCTION public.imoveis_taxa_do_condominio()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE l record; v_nome text := lower(btrim(coalesce(NEW.condominio_nome, '')));
BEGIN
  -- 469 (Pedro, 22/10): a taxa é a do condomínio para aqueles quartos; o que vier escrito no imóvel não vale mais
  IF NEW.quartos IS NULL OR coalesce(NEW.status, '') = 'Excluído' THEN RETURN NEW; END IF;
  SELECT (t->>'condominio')::numeric AS condominio, (t->>'iptu')::numeric AS iptu INTO l
    FROM condominio_ficha f LEFT JOIN condominios c ON c.id = f.condominio_id,
         jsonb_array_elements(f.taxas) WITH ORDINALITY x(t, o)
   WHERE t->>'quartos' = NEW.quartos::text AND t->>'condominio' IS NOT NULL
     AND (f.condominio_id = NEW.condo_id
          OR (NEW.condo_id IS NULL AND v_nome <> ''
              AND (v_nome IN (lower(btrim(f.nome)), lower(btrim(c.nome)))
                   OR v_nome IN (SELECT lower(btrim(x)) FROM unnest(f.nomes_no_imovel) x))))
   ORDER BY (f.condominio_id = NEW.condo_id) DESC NULLS LAST, f.id, o
   LIMIT 1;
  IF l.condominio IS NOT NULL AND NEW.taxa_condominio IS DISTINCT FROM l.condominio THEN
    NEW.taxa_condominio := l.condominio;
    NEW.taxa_condominio_em := now();   -- o carimbo é UPDATE OF taxa_condominio e não vê o que este gatilho escreve
  END IF;
  IF l.iptu IS NOT NULL THEN
    NEW.iptu := l.iptu;
  END IF;
  RETURN NEW;
END $function$;

-- 1. um valor por condomínio + quartos
CREATE TEMP TABLE t469 ON COMMIT DROP AS
WITH cf AS (
  SELECT f.id, f.condominio_id,
         array_remove(ARRAY[lower(btrim(f.nome)), lower(btrim(c.nome))]
                      || coalesce((SELECT array_agg(lower(btrim(x))) FROM unnest(f.nomes_no_imovel) x), '{}'), NULL) AS nomes
    FROM condominio_ficha f LEFT JOIN condominios c ON c.id = f.condominio_id
), prova AS (   -- as taxas dos imóveis que valem como prova
  SELECT cf.id AS ficha, i.quartos, i.taxa_condominio AS taxa, i.taxa_condominio_em AS em,
         CASE i.status WHEN 'Disponível' THEN 0 WHEN 'Alugado' THEN 1 ELSE 2 END AS ordem
    FROM imoveis i
    JOIN LATERAL (SELECT cf.* FROM cf
                   WHERE cf.condominio_id = i.condo_id
                      OR (i.condo_id IS NULL AND lower(btrim(coalesce(i.condominio_nome, ''))) = ANY (cf.nomes))
                   ORDER BY (cf.condominio_id = i.condo_id) DESC NULLS LAST, cf.id LIMIT 1) cf ON true
   WHERE coalesce(i.status, '') <> 'Excluído' AND i.quartos IS NOT NULL AND i.taxa_condominio > 0
     AND (i.taxa_condominio_em IS NULL    -- sem carimbo é prova antiga, mas é prova (NOT de NULL daria NULL e sumiria)
          OR NOT (i.taxa_condominio_em >= '2026-10-20 21:06:00+00' AND i.taxa_condominio_em < '2026-10-20 21:07:00+00'))
), voto AS (
  SELECT ficha, quartos, taxa, min(ordem) AS ordem, max(em) AS ultimo, count(*) AS n FROM prova GROUP BY 1, 2, 3
), dos_imoveis AS (
  SELECT DISTINCT ON (ficha, quartos) ficha, quartos, taxa
    FROM voto ORDER BY ficha, quartos, ordem, ultimo DESC NULLS LAST, n DESC, taxa DESC
), linhas AS (
  SELECT f.id AS ficha, (t->>'quartos')::int AS quartos, (t->>'condominio')::numeric AS condominio,
         (t->>'iptu')::numeric AS iptu, t ? 'fonte' AS deduzida
    FROM condominio_ficha f, jsonb_array_elements(f.taxas) t WHERE t->>'quartos' ~ '^\d+$'
)
SELECT coalesce(l.ficha, d.ficha) AS ficha, coalesce(l.quartos, d.quartos) AS quartos,
       CASE WHEN l.condominio IS NOT NULL AND NOT l.deduzida THEN l.condominio
            ELSE coalesce(d.taxa, l.condominio) END AS condominio,
       l.iptu, l.condominio AS antes,
       CASE WHEN l.condominio IS NOT NULL AND NOT l.deduzida THEN 'digitada'
            WHEN d.taxa IS NOT NULL THEN 'dos imóveis' ELSE 'deduzida' END AS de_onde
  FROM linhas l FULL JOIN dos_imoveis d ON d.ficha = l.ficha AND d.quartos = l.quartos;

UPDATE condominio_ficha f SET taxas = n.taxas
  FROM (SELECT ficha, jsonb_agg(jsonb_strip_nulls(jsonb_build_object('quartos', quartos, 'condominio', condominio, 'iptu', iptu))
                                ORDER BY quartos) AS taxas
          FROM t469 WHERE condominio IS NOT NULL GROUP BY ficha) n
 WHERE f.id = n.ficha AND f.taxas IS DISTINCT FROM n.taxas;

-- o resumo (sai no psql)
SELECT de_onde, count(*) AS linhas, count(*) FILTER (WHERE antes IS NULL) AS novas,
       count(*) FILTER (WHERE antes IS NOT NULL AND antes <> condominio) AS mudaram
  FROM t469 GROUP BY 1 ORDER BY 1;
SELECT count(*) AS imoveis_com_taxa_mudada
  FROM imoveis i JOIN privado.taxa_imovel_antes_469 a USING (codigo) WHERE i.taxa_condominio IS DISTINCT FROM a.taxa;

COMMIT;
