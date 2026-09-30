CREATE OR REPLACE FUNCTION public.nai_etapa_atualizar(p_contato bigint)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  r      record;
  v_ant  text;
BEGIN
  IF p_contato IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO r FROM nai_etapa_calcular(p_contato);
  SELECT etapa INTO v_ant FROM nai_etapa_contato WHERE contato_id = p_contato;
  INSERT INTO nai_etapa_contato (contato_id, etapa, motivo)
  VALUES (p_contato, r.etapa, r.motivo)
  ON CONFLICT (contato_id) DO UPDATE
     SET etapa = EXCLUDED.etapa, motivo = EXCLUDED.motivo, atualizado_em = now(),
         desde = CASE WHEN nai_etapa_contato.etapa <> EXCLUDED.etapa THEN now() ELSE nai_etapa_contato.desde END;
  IF v_ant IS DISTINCT FROM r.etapa THEN
    INSERT INTO nai_etapa_evento (contato_id, de, para, motivo) VALUES (p_contato, v_ant, r.etapa, r.motivo);
  END IF;
  RETURN r.etapa;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'nai_etapa_atualizar (%): %', p_contato, SQLERRM;
  RETURN NULL;
END;
$function$;
