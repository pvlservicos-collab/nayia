CREATE OR REPLACE FUNCTION public.nai_avisar_tel(p_turno bigint, p_visita bigint, p_texto text, p_motivo text)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE v_tel bigint := nai_contato_do_cadastro(nai_cfg('tel_telefone'), 'Tel');
BEGIN
  RETURN nai_enfileirar_texto(p_turno, p_visita, v_tel, 'tel', p_texto, p_motivo, 900);
END;
$function$;
