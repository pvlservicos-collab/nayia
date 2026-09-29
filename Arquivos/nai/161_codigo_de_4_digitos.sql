-- =====================================================================
-- 161 — CÓDIGO DE 4 DÍGITOS NO CADASTRO DO SITE NOVO (28/09/2026)
--
-- Pedro: "fiz um cadastro mas saiu com um número estranho fora dos nossos
-- padrões, tem como tirar isso e pôr um número de 4 dígitos?"
--
-- O cadastro do site novo (à mão ou da OLX) numerava de 900000 em diante para
-- nunca bater com o código que o site antigo dá (sequencial: está no 5765 em
-- 28/09, ~2 por dia). A faixa nova é 9001 a 9999: continua longe do site antigo
-- por anos, tem 4 dígitos como todo código da casa, e a Nay reconhece (o
-- caminho de código puro só dispara para ^\d{3,5}$ -- 900004 não entrava).
-- MAXVALUE 9999 sem CYCLE: acabou a faixa, o cadastro falha alto em vez de
-- virar 5 dígitos em silêncio.
--
-- O 900004 (o primeiro importado da OLX, pelo Pedro) vira 9001: a linha é
-- copiada com o código novo, as 14 fotos passam para ela (URL e pasta
-- /fotos-captacao/olx/9001/), e a linha velha sai. Nada mais citava o 900004.
--
-- E o que veio no anúncio e ficou só no texto: a OLX manda a quebra de linha
-- como <br> (a descrição aparecia com "<br>" no meio); o "incluso no aluguel"
-- vai para o campo dele (é dali que a Nay soma o custo cheio); e as
-- características do condomínio ficam separadas das do imóvel, como na OLX.
-- =====================================================================
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL lock_timeout = '3s';

ALTER SEQUENCE imoveis_crm_codigo_seq MINVALUE 9001 MAXVALUE 9999 START WITH 9001 RESTART WITH 9002 NO CYCLE;

DO $$
DECLARE cols text;
BEGIN
  IF EXISTS (SELECT 1 FROM imoveis WHERE codigo = 9001) THEN
    RAISE EXCEPTION 'o 9001 já existe';
  END IF;
  SELECT string_agg(quote_ident(column_name), ', ' ORDER BY ordinal_position) INTO cols
    FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'imoveis' AND column_name <> 'codigo';
  EXECUTE format('INSERT INTO imoveis (codigo, %s) SELECT 9001, %s FROM imoveis WHERE codigo = 900004', cols, cols);
END $$;
UPDATE imovel_fotos SET codigo = 9001, url = replace(url, '/olx/900004/', '/olx/9001/') WHERE codigo = 900004;
DELETE FROM imoveis WHERE codigo = 900004;

UPDATE imoveis SET
  descricao = btrim(regexp_replace(regexp_replace(regexp_replace(descricao,
                '<br\s*/?>', E'\n', 'gi'),                       -- a quebra de linha da OLX
                '[ \t]+\n', E'\n', 'g'),                         -- espaço sobrando no fim da linha
                '\n\s*Contato para mais informa\S*:\s*$', '')),  -- sobrou sem o telefone
  extras = coalesce(extras, '{}'::jsonb) || jsonb_build_object(
    'incluso no aluguel', 'Água, Internet, Taxa de Condomínio, IPTU',
    'caracteristicas do condominio', 'Condomínio fechado, Piscina, Portaria, Salão de festas, Segurança 24h')
 WHERE codigo = 9001;

\echo '== resultado'
SELECT codigo, origem, status, extras->>'incluso no aluguel' AS incluso, extras->>'caracteristicas do condominio' AS condominio,
       (SELECT count(*) FROM imovel_fotos f WHERE f.codigo = 9001) AS fotos,
       (SELECT count(*) FROM imoveis WHERE codigo = 900004) AS sobrou_900004
  FROM imoveis WHERE codigo = 9001;
SELECT descricao FROM imoveis WHERE codigo = 9001;
SELECT min(url) FROM imovel_fotos WHERE codigo = 9001;

\if :{?ensaio}
  \echo '>>> ENSAIO: desfazendo tudo'
  ROLLBACK;
\else
  COMMIT;
\endif
