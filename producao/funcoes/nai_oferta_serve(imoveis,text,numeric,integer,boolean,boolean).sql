CREATE OR REPLACE FUNCTION public.nai_oferta_serve(i imoveis, p_telefone text, p_teto numeric, p_quartos integer, p_sem boolean, p_com boolean)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT nai_oferta_serve(i, p_telefone, p_teto, p_quartos, p_sem, p_com, NULL::text, NULL::text);
$function$;
