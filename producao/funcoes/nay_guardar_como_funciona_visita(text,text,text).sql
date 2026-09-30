CREATE OR REPLACE FUNCTION public.nay_guardar_como_funciona_visita(p_codigo text, p_texto text, p_telefone text)
 RETURNS TABLE(texto_pronto text)
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_cod int := NULLIF(regexp_replace(coalesce(p_codigo,''),'[^0-9]','','g'),'')::int;
  v_tel text := regexp_replace(coalesce(p_telefone,''),'[^0-9]','','g');
  v_txt text := btrim(coalesce(p_texto,''));
  v_n   int;
BEGIN
  -- A parede: quem não é o Tel não grava, mesmo que o modelo tente.
  IF v_tel <> '[telefone …7316]' THEN
    RETURN QUERY SELECT
      'so o Tel pode registrar como funciona a visita. nao grave nada e nao diga que gravou.'::text;
    RETURN;
  END IF;

  IF v_cod IS NULL OR v_txt = '' THEN
    RETURN QUERY SELECT
      'faltou o codigo do imovel ou o texto. pergunte ao Tel de qual imovel e como funciona.'::text;
    RETURN;
  END IF;

  IF length(v_txt) > 600 THEN
    RETURN QUERY SELECT
      'esse texto ficou longo demais. peca ao Tel para resumir como funciona a visita.'::text;
    RETURN;
  END IF;

  INSERT INTO imovel_privado (codigo, como_funciona_visita, visita_atualizada_em)
       VALUES (v_cod, v_txt, now())
  ON CONFLICT (codigo) DO UPDATE
       SET como_funciona_visita = EXCLUDED.como_funciona_visita,
           visita_atualizada_em = now();
  GET DIAGNOSTICS v_n = ROW_COUNT;

  IF v_n = 0 THEN
    RETURN QUERY SELECT
      ('nao consegui guardar no imovel ' || v_cod || '. avise o Tel.')::text;
    RETURN;
  END IF;

  RETURN QUERY SELECT
    ('guardei como funciona a visita no imovel ' || v_cod ||
     '. diga ao Tel que anotou e que nao vai perguntar de novo.')::text;
END;
$function$;
