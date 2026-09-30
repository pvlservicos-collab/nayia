CREATE OR REPLACE FUNCTION public.nay_captacao_tem_contagem(p_campos jsonb, p_campo text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT nay_captacao_tem_campo(p_campos, p_campo)
     AND NOT (v ~ '^[0-9]+([.,][0-9]+)?$' AND v !~ '[1-9]')
    FROM (SELECT btrim(coalesce(p_campos ->> p_campo, ''))) AS s(v);
$function$;
