CREATE OR REPLACE FUNCTION public.nay_maior_valor(p_texto text)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
  s text := lower(unaccent(coalesce(p_texto, '')));
  m text[];
  v numeric;
  v_max numeric := NULL;
BEGIN
  -- FORA DA CONTA primeiro: telefone, CEP, data, hora, CPF/CNPJ. Sao numeros
  -- grandes que nao sao preco -- e um deles sozinho jogaria a conversa toda
  -- para "venda".
  s := regexp_replace(s, '\(?\d{2}\)?\s*9?\d{4}[-. ]?\d{4}', ' ', 'g');  -- telefone
  s := regexp_replace(s, '\d{5}-?\d{3}\M', ' ', 'g');                     -- CEP
  s := regexp_replace(s, '\d{1,2}/\d{1,2}(/\d{2,4})?', ' ', 'g');         -- data
  s := regexp_replace(s, '\d{1,2}:\d{2}', ' ', 'g');                      -- hora
  s := regexp_replace(s, '\d{3}\.\d{3}\.\d{3}-\d{2}', ' ', 'g');          -- CPF
  s := regexp_replace(s, '\d{10,}', ' ', 'g');                            -- numerao solto

  -- "700 mil", "700k", "1,5 mil"
  FOR m IN SELECT regexp_matches(s, '(\d{1,4}(?:[.,]\d{1,3})?)\s*(mil|k)\M', 'g') LOOP
    v := replace(m[1], ',', '.')::numeric * 1000;
    IF v_max IS NULL OR v > v_max THEN v_max := v; END IF;
  END LOOP;

  -- "1 milhao", "1.2 mi"
  FOR m IN SELECT regexp_matches(s, '(\d{1,3}(?:[.,]\d{1,2})?)\s*(milhao|milhoes|mi)\M', 'g') LOOP
    v := replace(m[1], ',', '.')::numeric * 1000000;
    IF v_max IS NULL OR v > v_max THEN v_max := v; END IF;
  END LOOP;

  -- "750.000", "R$ 2.600", "R$ 700000"
  FOR m IN SELECT regexp_matches(s, '(\d{1,3}(?:\.\d{3})+)(?:,\d{2})?', 'g') LOOP
    v := replace(m[1], '.', '')::numeric;
    IF v_max IS NULL OR v > v_max THEN v_max := v; END IF;
  END LOOP;
  FOR m IN SELECT regexp_matches(s, 'r\$\s*(\d{4,9})', 'g') LOOP
    v := m[1]::numeric;
    IF v_max IS NULL OR v > v_max THEN v_max := v; END IF;
  END LOOP;

  RETURN v_max;
END;
$function$;
