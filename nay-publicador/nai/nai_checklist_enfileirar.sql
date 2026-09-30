CREATE OR REPLACE FUNCTION public.nai_checklist_enfileirar(p_telefone text, p_tipo text, p_quem text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_tel   bigint := nai_contato_do_cadastro(nai_cfg('tel_telefone'), 'Tel');
  v_turno bigint;
  v_msg   text;
BEGIN
  INSERT INTO nai_turno (contato_id, papel, texto)
  VALUES (v_tel, 'tel', left('checklist pelo CRM (' || coalesce(nullif(btrim(p_quem), ''), '?') || '): '
                            || coalesce(p_tipo, '?') || ' para ' || coalesce(p_telefone, ''), 500))
  RETURNING id INTO v_turno;
  v_msg := nai_enviar_checklist_para(v_turno, p_tipo, p_telefone);
  UPDATE nai_saida SET enviar_apos = now() + interval '2 seconds' WHERE turno_id = v_turno AND estado = 'pendente';
  UPDATE nai_turno SET fechado_em = now() WHERE id = v_turno;
  RETURN v_msg;
END;
$function$
;
