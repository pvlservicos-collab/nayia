CREATE OR REPLACE FUNCTION public.nay_reservar_disparo_de_lista(p_categoria text, p_negocio text, p_destino text, p_forcar boolean DEFAULT false)
 RETURNS TABLE(id integer, ja_foi_em timestamp with time zone)
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_min    int;
  v_ultimo timestamptz;
  v_id     int;
BEGIN
  PERFORM pg_advisory_xact_lock(
    hashtext('lista_disparada:' || coalesce(p_categoria,'') || ':' ||
             coalesce(p_negocio,'') || ':' || coalesce(p_destino,'')));

  SELECT nullif(c.valor,'')::int INTO v_min
    FROM config c WHERE c.chave = 'lista_repete_minutos';
  v_min := coalesce(v_min, 30);

  IF NOT coalesce(p_forcar, false) THEN
    SELECT max(d.enviado_em) INTO v_ultimo
      FROM lista_disparada d
     WHERE d.categoria = p_categoria
       AND d.negocio   = p_negocio
       AND d.destino   = p_destino
       AND d.enviado_em > now() - make_interval(mins => v_min);
    IF v_ultimo IS NOT NULL THEN
      RETURN QUERY SELECT NULL::int, v_ultimo;
      RETURN;
    END IF;
  END IF;

  INSERT INTO lista_disparada (categoria, negocio, destino)
       VALUES (p_categoria, p_negocio, p_destino)
    RETURNING lista_disparada.id INTO v_id;

  RETURN QUERY SELECT v_id, NULL::timestamptz;
END;
$function$;
