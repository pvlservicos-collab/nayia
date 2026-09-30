CREATE OR REPLACE FUNCTION public.nai_sec_guardar_foto(p_turno bigint, p_url text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE t nai_turno; v_id bigint;
BEGIN
  IF btrim(coalesce(p_url, '')) !~ '^https?://' THEN RETURN 0; END IF;
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL THEN RETURN 0; END IF;
  SELECT n.id INTO v_id FROM nai_imovel_novo n
   WHERE n.contato_id = t.contato_id AND n.situacao = 'colhendo'
   ORDER BY n.id DESC LIMIT 1;
  IF v_id IS NULL THEN RETURN 0; END IF;
  INSERT INTO nai_imovel_novo_foto (novo_id, url) VALUES (v_id, btrim(p_url));
  RETURN 1;
END;
$function$;
