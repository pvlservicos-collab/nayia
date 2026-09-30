CREATE OR REPLACE FUNCTION public.nai_pode_enviar_codigo_v2(p_turno bigint, p_codigo integer)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE v_contato bigint; v_ferr text[]; v_rej int[];
BEGIN
  SELECT contato_id INTO v_contato FROM nai_turno WHERE id = p_turno;
  IF v_contato IS NULL OR p_codigo IS NULL THEN RETURN false; END IF;

  SELECT ferramentas INTO v_ferr FROM nai_turno_decisao WHERE turno_id = p_turno;
  SELECT codigos_rejeitados INTO v_rej FROM nai_estado_conversa WHERE contato_id = v_contato;

  IF p_codigo = ANY (coalesce(v_rej, '{}')) THEN RETURN false; END IF;

  -- so sai se alguma ferramenta de imovel foi chamada de verdade
  RETURN EXISTS (
    SELECT 1 FROM unnest(coalesce(v_ferr, '{}')) f
     WHERE f IN ('imovel_por_codigo','buscar_por_perfil','listar_no_condominio',
                 'disponibilidade_no_condominio','resumo_do_condominio',
                 'imovel_do_disparo','o_que_sei_do_imovel'));
END;
$function$
;
