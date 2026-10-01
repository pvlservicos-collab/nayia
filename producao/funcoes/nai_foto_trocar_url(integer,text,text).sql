CREATE OR REPLACE FUNCTION public.nai_foto_trocar_url(p_codigo integer, p_de text, p_para text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET lock_timeout TO '3s'
AS $function$
DECLARE v_n int;
BEGIN
  IF p_para !~ ('^https://imobeasy\.online/fotos(-captacao/[a-z]+)?/' || p_codigo::text || '/[A-Za-z0-9._-]+$') THEN
    RAISE EXCEPTION 'a URL nova tem que ser do nosso servidor e na pasta do imóvel %: %', p_codigo, p_para;
  END IF;
  UPDATE imovel_fotos SET url = p_para WHERE codigo = p_codigo AND url = p_de;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END $function$;
