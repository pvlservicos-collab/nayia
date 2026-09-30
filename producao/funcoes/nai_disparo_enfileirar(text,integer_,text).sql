CREATE OR REPLACE FUNCTION public.nai_disparo_enfileirar(p_telefone text, p_codigos integer[], p_quem text)
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
  IF coalesce(array_length(p_codigos, 1), 0) = 0 THEN
    RETURN 'Escolha pelo menos um imóvel.';
  END IF;
  INSERT INTO nai_turno (contato_id, papel, texto)
  VALUES (v_tel, 'tel', left('disparo pelo painel (' || coalesce(nullif(btrim(p_quem), ''), '?') || '): '
                             || array_to_string(p_codigos, ', ') || ' para ' || coalesce(p_telefone, ''), 500))
  RETURNING id INTO v_turno;

  v_msg := nai_enviar_imoveis_para(v_turno, p_codigos, p_telefone);

  -- sai no próximo ciclo (hora marcada), e não daqui a 3 minutos
  UPDATE nai_saida SET enviar_apos = now() + interval '2 seconds'
   WHERE turno_id = v_turno AND estado = 'pendente';
  UPDATE nai_turno SET fechado_em = now() WHERE id = v_turno;
  RETURN v_msg;
END;
$function$;
