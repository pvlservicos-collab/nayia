-- =====================================================================
-- NAI -- 78: ano em data nao e codigo de imovel (Tel, 22/09/2026)
--
-- Achado no treino, rodada 5, caso 140. A pessoa escreveu "ate maio 2028"
-- (o fim de um contrato de locacao) e a Nay mandou ao Tel: "o corretor
-- pediu fotos do 2028 e nao achei foto". Ninguem pediu nada: o extrator
-- `nay_codigos_citados` pegou 2028 como codigo. O Tel mandou corrigir.
--
-- POR QUE NAO DA PARA IGNORAR TODO NUMERO COM CARA DE ANO: existem imoveis
-- com codigo 2014 e 2024. "Me manda o 2024" tem que continuar funcionando.
-- Entao sai so o ano em CONTEXTO DE DATA:
--   * depois do nome do mes, por extenso: "maio 2028", "maio de 2028",
--     "marco/2027" (so nome inteiro: "dez" e numero e e o Parque Dez);
--   * data com barra: "05/2028", "10/05/2028", "10/05/28".
--
-- A troca e no `nay_tirar_valores`, o limpador que o extrator ja usa para
-- tirar valor, area e faixa de preco -- o mesmo lugar onde o resto do que
-- "nao e codigo" ja mora. Funcao viva copiada do pg_proc e remendada.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
  v_def  text;
  v_novo text;
  a      text := $a$lower(coalesce(p_texto,''))$a$;
BEGIN
  SELECT pg_get_functiondef('nay_tirar_valores'::regproc) INTO v_def;
  IF position('ANO EM DATA' IN v_def) > 0 THEN
    RAISE NOTICE 'ja aplicado'; RETURN;
  END IF;
  IF (length(v_def) - length(replace(v_def, a, ''))) / length(a) <> 1 THEN
    RAISE EXCEPTION 'o ponto de troca mudou -- confira nay_tirar_valores';
  END IF;
  v_novo := replace(v_def, a,
$b$regexp_replace(regexp_replace(
    lower(coalesce(p_texto,'')),
    -- ANO EM DATA nao e codigo (78): "maio 2028", "maio de 2028", "marco/2027".
    '\m(janeiro|fevereiro|mar[cç]o|abril|maio|junho|julho|agosto|setembro|outubro|novembro|dezembro)\M[ \t]*(de[ \t]+|/[ \t]*)?(19|20)[0-9]{2}\M', ' ', 'g'),
    -- e data com barra: "05/2028", "10/05/2028", "10/05/28"
    '\m[0-9]{1,2}[ \t]*/[ \t]*([0-9]{1,2}[ \t]*/[ \t]*)?((19|20)[0-9]{2}|[0-9]{2})\M', ' ', 'g')$b$);
  EXECUTE v_novo;
END $$;

-- Prova: cada linha tem que dar o que diz a coluna "esperado".
CREATE TEMP TABLE prova(texto text, esperado text[]);
INSERT INTO prova VALUES
  ('até maio 2028',                     '{}'),
  ('até maio de 2028',                  '{}'),
  ('contrato vai até março/2027',       '{}'),
  ('vence em 05/2028',                  '{}'),
  ('assinado 10/05/2028',               '{}'),
  ('me manda o 2024',                   '{2024}'),
  ('apto no parque dez 2024',           '{2024}'),
  ('o 5733 e o 2024',                   '{2024,5733}'),
  ('Código: 2014',                      '{2014}'),
  ('me manda o card do 5727',           '{5727}'),
  ('tem de 2 quartos até 3000?',        '{}'),
  ('me manda o 3500, 3210 e 2943',      '{2943,3210,3500}');

DO $$
DECLARE r record; v text[]; n int := 0;
BEGIN
  FOR r IN SELECT * FROM prova LOOP
    SELECT coalesce(array_agg(x ORDER BY x), '{}') INTO v FROM unnest(nay_codigos_citados(r.texto)) x;
    IF v IS DISTINCT FROM r.esperado THEN
      RAISE EXCEPTION 'falhou: "%" deu % e devia dar %', r.texto, v, r.esperado;
    END IF;
    n := n + 1;
  END LOOP;
  RAISE NOTICE 'prova: % de % casos certos', n, n;
END $$;

COMMIT;
