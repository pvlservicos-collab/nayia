-- 249 (01/10/2026): A FOTO IMPORTADA PODE MORAR NA PASTA DA CAPTAÇÃO.
-- A `nai_foto_trocar_url` (248) só aceitava a URL nova em
-- `imobeasy.online/fotos/<codigo>/`, mas a API do site só tem a pasta
-- `fotos-captacao` montada no container -- escrever em `/fotos/` pediria mexer
-- no docker-compose e reiniciar a API. Então a foto baixada de fora vai para
-- `fotos-captacao/importado/<codigo>/`, que é o mesmo caminho que a conferência
-- do envio no n8n passou a aceitar hoje (`fotos-captacao/<de onde veio>/<codigo>/`).
--
-- E a trava fica melhor do que era: agora confere o CÓDIGO no caminho, não só o
-- domínio -- a foto do imóvel 5747 tem que estar numa pasta 5747.
BEGIN;
SET LOCAL lock_timeout = '3s';

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
COMMENT ON FUNCTION nai_foto_trocar_url(integer, text, text) IS '249: troca a URL de uma foto para a nossa cópia, conferindo o código no caminho';
REVOKE ALL ON FUNCTION nai_foto_trocar_url(integer, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION nai_foto_trocar_url(integer, text, text) TO nay_site_escrita;
COMMIT;
