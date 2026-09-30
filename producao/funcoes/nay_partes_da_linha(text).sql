CREATE OR REPLACE FUNCTION public.nay_partes_da_linha(p_linha text)
 RETURNS TABLE(nome text, quartos integer, suites integer, area integer, valor numeric)
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
  t      text;
  v_nome text;
  v_q    int;
  v_s    int;
  v_a    int;
  v_val  numeric;
  tok    text;
BEGIN
  t := btrim(coalesce(p_linha,''));
  t := regexp_replace(t, '^\s*([-*•·✅✔☑]|\d+[.)])\s*', '');
  t := regexp_replace(t, '\(\s*incluso\s+a\s+tx\s*\)', ' ', 'gi');
  t := regexp_replace(t, '[/,]?\s*\+\s*tx\s+de\s+[0-9.,]+', ' ', 'gi');
  -- O CÓDIGO sai aqui (28/09), antes de tudo: ele não identifica o NOME, e
  -- o número dele competiria com o valor na busca do último token numérico.
  t := nay_linha_sem_codigo(t);
  t := btrim(regexp_replace(t, '\s+', ' ', 'g'));
  IF t = '' THEN RETURN; END IF;

  v_q := (regexp_match(t, '([0-9]+)\s*quartos?', 'i'))[1]::int;
  v_s := (regexp_match(t, '([0-9]+)\s*su[íi]tes?', 'i'))[1]::int;
  v_a := (regexp_match(t, '([0-9]+)\s*m(?:2|²)\M', 'i'))[1]::int;

  IF v_q IS NULL AND v_s IS NOT NULL THEN v_q := v_s; END IF;

  t := regexp_replace(t, '[0-9]+\s*quartos?', ' ', 'gi');
  t := regexp_replace(t, '[0-9]+\s*su[íi]tes?', ' ', 'gi');
  t := regexp_replace(t, '[0-9]+\s*m(?:2|²)\M', ' ', 'gi');

  SELECT z.achado INTO tok FROM (
    SELECT x[1] AS achado, row_number() OVER () AS n
      FROM regexp_matches(t || ' ', '([0-9]+(?:[.,][0-9]+)?\s*[kmKM]?)(?:\s|/)', 'g') x
     ORDER BY n DESC LIMIT 1) z;
  v_val := nay_valor_escrito(tok);

  -- O NOME: antes da primeira barra; sem barra, antes do primeiro número.
  -- LÊ DE `p_linha`, não de `t` -- é assim desde 11/09, porque `t` já perdeu
  -- os pedaços que ajudam a cortar. Por isso o código sai DE NOVO aqui: a
  -- limpeza lá em cima não alcança esta variável.
  v_nome := nay_linha_sem_codigo(split_part(btrim(coalesce(p_linha,'')), '/', 1));
  v_nome := regexp_replace(v_nome, '^\s*([-*•·✅✔☑]|\d+[.)])\s*', '');
  IF position('/' in coalesce(p_linha,'')) = 0 THEN
    v_nome := (regexp_match(v_nome, '^([^0-9]*)'))[1];
  END IF;
  -- palavras de ligação penduradas no fim: "acquarelle de" -> "acquarelle"
  v_nome := regexp_replace(v_nome, '\s+(de|da|do|com|a|o|e|para|pra)\s*$', '', 'i');
  v_nome := btrim(regexp_replace(v_nome, '\s+', ' ', 'g'));

  IF v_nome = '' THEN RETURN; END IF;
  RETURN QUERY SELECT v_nome, v_q, v_s, v_a, v_val;
END;
$function$;
