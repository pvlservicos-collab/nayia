CREATE OR REPLACE FUNCTION public.captacao_data_do_contrato(p_texto text, p_dito_em date)
 RETURNS date
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  t       text := lower(unaccent(coalesce(p_texto, '')));
  meses   text[] := ARRAY['janeiro','fevereiro','marco','abril','maio','junho','julho','agosto','setembro','outubro','novembro','dezembro'];
  re_mes  text := '\m(janeiro|fevereiro|marco|abril|maio|junho|julho|agosto|setembro|outubro|novembro|dezembro)\M';
  m       text[];
  n_meses int;
  v_mes   int;
  v_ano   int;
  v_hoje  int := extract(year FROM p_dito_em)::int;
BEGIN
  IF btrim(t) = '' OR p_dito_em IS NULL THEN RETURN NULL; END IF;
  SELECT count(*) INTO n_meses FROM regexp_matches(t, re_mes, 'g');
  IF n_meses = 0 THEN
    m := regexp_match(t, '\m(final|fim)\s+de\s+(20\d\d)\M');
    IF m IS NOT NULL AND m[2]::int BETWEEN v_hoje AND v_hoje + 6 THEN RETURN make_date(m[2]::int, 12, 31); END IF;
    RETURN NULL;
  END IF;
  IF n_meses <> 1 THEN RETURN NULL; END IF;                    -- "de maio a março do ano que vem"
  IF t ~ '\d{2,4}\s+e\s+\d{2,4}' THEN RETURN NULL; END IF;      -- "dezembro de 27 e 28"
  v_mes := array_position(meses, (regexp_match(t, re_mes))[1]);
  m := regexp_match(t, re_mes || '\s*(?:de|/|-)?\s*(20\d\d|\d\d)\M');
  IF m IS NOT NULL THEN
    v_ano := m[2]::int;
    IF v_ano < 100 THEN v_ano := 2000 + v_ano; END IF;
  ELSIF t ~ '(ano que vem|proximo ano|daqui a (1|um) ano)' THEN
    v_ano := v_hoje + 1;
  ELSIF t ~ '\d' OR t ~ '\mano' THEN
    RETURN NULL;                                                -- "setembro de 3 anos": conta para gente fazer
  ELSE
    v_ano := v_hoje;                                            -- só o mês: o próximo que vier
    IF v_mes < extract(month FROM p_dito_em)::int THEN v_ano := v_ano + 1; END IF;
  END IF;
  IF v_ano NOT BETWEEN v_hoje AND v_hoje + 6 THEN RETURN NULL; END IF;
  RETURN (make_date(v_ano, v_mes, 1) + interval '1 month' - interval '1 day')::date;
END
$function$;
