CREATE OR REPLACE FUNCTION public.crm_campanha_liberar(p_lista text, p_ids bigint[] DEFAULT NULL::bigint[], p_quantos integer DEFAULT NULL::integer, p_quem text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE v_n int;
BEGIN
  IF btrim(coalesce(p_quem, '')) = '' THEN
    RAISE EXCEPTION 'diga quem liberou (p_quem)';
  END IF;
  WITH alvo AS (
    SELECT c.id FROM campanha_contato c
     WHERE c.lista = p_lista AND c.estado = 'preparada'
       AND c.dia = (SELECT max(dia) FROM campanha_contato WHERE lista = p_lista)
       AND (p_ids IS NULL OR c.id = ANY (p_ids))
     ORDER BY c.prioridade DESC, c.id
     LIMIT CASE WHEN p_quantos IS NULL OR p_ids IS NOT NULL THEN NULL ELSE greatest(p_quantos, 0) END
  ), lib AS (
    UPDATE campanha_contato c SET estado = 'liberada', liberada_em = now(), liberada_por = btrim(p_quem), atualizado_em = now()
      FROM alvo WHERE c.id = alvo.id RETURNING c.id
  ), ev AS (
    INSERT INTO campanha_evento (contato, tipo, texto) SELECT id, 'liberada', 'por ' || btrim(p_quem) FROM lib RETURNING 1
  )
  SELECT count(*) INTO v_n FROM ev;
  RETURN v_n;
END;
$function$;
