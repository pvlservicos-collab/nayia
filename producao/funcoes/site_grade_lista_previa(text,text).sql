CREATE OR REPLACE FUNCTION public.site_grade_lista_previa(p_categoria text, p_negocio text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE r record;
BEGIN
  IF coalesce(p_categoria, '') NOT IN ('apartamento', 'apartamento_via_publica', 'casa_condominio', 'casa_via_publica', 'sala', 'lote')
     OR coalesce(p_negocio, '') NOT IN ('locacao', 'venda') THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'Escolha o tipo de imóvel e se é locação ou venda.');
  END IF;
  SELECT texto_pronto, quantos INTO r FROM nay_lista_de_imoveis(p_categoria, p_negocio);
  RETURN jsonb_build_object('ok', true, 'quantos', coalesce(r.quantos, 0),
                            'texto', CASE WHEN coalesce(r.quantos, 0) > 0 THEN r.texto_pronto END);
END;
$function$;
