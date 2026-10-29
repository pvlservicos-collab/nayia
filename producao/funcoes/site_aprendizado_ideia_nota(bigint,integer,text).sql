CREATE OR REPLACE FUNCTION public.site_aprendizado_ideia_nota(p_id bigint, p_nota integer, p_quem text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r aprendizado_ideia;
BEGIN
  IF p_nota IS NULL OR p_nota < 0 OR p_nota > 100 THEN RAISE EXCEPTION 'a nota vai de 0 a 100'; END IF;
  UPDATE aprendizado_ideia
     SET nota = p_nota, nota_revisada = true, nota_por = left(p_quem, 80), mudada_em = now()
   WHERE id = p_id
  RETURNING * INTO r;
  IF NOT FOUND THEN RAISE EXCEPTION 'não achei a ideia %', p_id; END IF;
  RETURN jsonb_build_object('id', r.id, 'nota', r.nota, 'nota_revisada', r.nota_revisada);
END;
$function$;
