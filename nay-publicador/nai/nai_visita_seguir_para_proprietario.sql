CREATE OR REPLACE FUNCTION public.nai_visita_seguir_para_proprietario(p_visita bigint, p_turno bigint)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
BEGIN
  UPDATE nai_visita SET estado = 'coletando', aguardando = 'corretor', atualizado_em = now() WHERE id = p_visita;
  RETURN nai_pedir_ao_proprietario(p_visita, p_turno);
END;
$function$
;
