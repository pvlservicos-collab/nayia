CREATE OR REPLACE FUNCTION public.nay_normalizar_lugar(p_texto text, p_fundo boolean)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT btrim(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
    regexp_replace(regexp_replace(nay_normalizar_lugar(p_texto),
      '\m(quatorze|catorze)\M', '14', 'g'),
      '\m(sto)\M', 'santo', 'g'),
      '\m(sta)\M', 'santa', 'g'),
      '\m(cj|conj)\M', 'conjunto', 'g'),
      '\m(jd)\M', 'jardim', 'g'),
      '\s+', ' ', 'g'));
$function$;
