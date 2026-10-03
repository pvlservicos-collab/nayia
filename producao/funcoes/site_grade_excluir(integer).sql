CREATE OR REPLACE FUNCTION public.site_grade_excluir(p_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE r vagas%ROWTYPE;
BEGIN
  DELETE FROM vagas WHERE id = p_id RETURNING * INTO r;
  IF r.id IS NULL THEN RETURN jsonb_build_object('ok', false, 'erro', 'Essa mensagem não existe mais.'); END IF;
  INSERT INTO privado.grade_excluida (vaga) VALUES (to_jsonb(r));
  RETURN jsonb_build_object('ok', true);
END;
$function$;
