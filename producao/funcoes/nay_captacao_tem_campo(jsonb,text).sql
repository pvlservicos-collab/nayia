CREATE OR REPLACE FUNCTION public.nay_captacao_tem_campo(p_campos jsonb, p_campo text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  -- 'null' como TEXTO acontece de verdade quando a tela serializa um campo
  -- vazio de JavaScript, e é o disfarce mais fácil de deixar passar.
  SELECT coalesce(lower(btrim(p_campos ->> p_campo)), '') NOT IN ('', 'null', '-');
$function$;
