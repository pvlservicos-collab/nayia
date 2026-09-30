CREATE OR REPLACE FUNCTION public.nai_gravar_fotos_do_site(p_lote jsonb)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
  e jsonb; v_cod int; v_urls text[]; n int := 0; i int;
BEGIN
  FOR e IN SELECT * FROM jsonb_array_elements(coalesce(p_lote, '[]'::jsonb)) LOOP
    v_cod := NULLIF(regexp_replace(coalesce(e->>'codigo', ''), '\D', '', 'g'), '')::int;
    -- mantem a ordem do site (a capa primeiro), sem repetir URL
    SELECT array_agg(u ORDER BY ord) INTO v_urls FROM (
      SELECT u, min(ord) AS ord FROM jsonb_array_elements_text(coalesce(e->'urls', '[]'::jsonb)) WITH ORDINALITY x(u, ord)
       WHERE u ~ '^https://imobeasy\.com/system/pictures/' GROUP BY u) y;
    IF v_cod IS NULL OR v_urls IS NULL OR NOT EXISTS (SELECT 1 FROM imoveis WHERE codigo = v_cod) THEN CONTINUE; END IF;
    IF EXISTS (SELECT 1 FROM imovel_fotos WHERE codigo = v_cod) THEN CONTINUE; END IF;
    FOR i IN 1..array_length(v_urls, 1) LOOP
      INSERT INTO imovel_fotos (codigo, ordem, url, e_capa) VALUES (v_cod, i, v_urls[i], i = 1);
      n := n + 1;
    END LOOP;
  END LOOP;
  RETURN n;
END;
$function$;
