CREATE OR REPLACE FUNCTION public.nay_saida_resposta_valida(p_contato bigint, p_texto text, p_citado text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
BEGIN
  RETURN EXISTS (SELECT 1 FROM nay_saida_resposta_ler(p_contato, p_texto, p_citado));
EXCEPTION WHEN others THEN
  RETURN false;
END
$function$;
