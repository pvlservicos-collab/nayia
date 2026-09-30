CREATE OR REPLACE FUNCTION public.nai_quem_atende(p_phone text, p_grupo boolean)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_modo  text := nai_cfg('modo', 'desligado');
  v_chave text := nai_chave(p_phone);
BEGIN
  IF coalesce(p_grupo, true) OR v_chave IS NULL THEN RETURN 'nay'; END IF;
  IF v_modo = 'todos' THEN RETURN 'nai'; END IF;
  IF v_modo = 'teste' AND v_chave = ANY (nai_chaves_teste()) THEN RETURN 'nai'; END IF;
  RETURN 'nay';
EXCEPTION WHEN others THEN
  RETURN 'nay';
END;
$function$;
