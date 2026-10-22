CREATE OR REPLACE FUNCTION public.site_ia_cotacao_salvar(p_brl numeric, p_fonte text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF p_brl IS NULL OR p_brl < 1 OR p_brl > 20 THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'cotação fora do razoável');
  END IF;
  INSERT INTO privado.ia_cotacao (moeda, brl, fonte, atualizado_em) VALUES ('USD', p_brl, left(p_fonte, 120), now())
  ON CONFLICT (moeda) DO UPDATE SET brl = EXCLUDED.brl, fonte = EXCLUDED.fonte, atualizado_em = now();
  RETURN jsonb_build_object('ok', true, 'brl', p_brl);
END $function$;
