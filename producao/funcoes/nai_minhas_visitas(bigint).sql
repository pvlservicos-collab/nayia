CREATE OR REPLACE FUNCTION public.nai_minhas_visitas(p_turno bigint)
 RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE t nai_turno; linhas text;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  SELECT string_agg('• ' || nai_ref_imovel(x.codigo) || ' — ' || coalesce(nai_quando_humano(x.quando), 'sem horário') ||
                    ' — ' || CASE x.estado
                      WHEN 'coletando' THEN 'falta me passar os dados'
                      WHEN 'aguardando_proprietario' THEN 'esperando o proprietário confirmar'
                      WHEN 'negociando' THEN CASE WHEN x.aguardando = 'corretor' THEN 'o proprietário sugeriu ' || coalesce(nai_quando_humano(x.quando_sugerido), 'outro horário') ELSE 'vendo outro horário com o proprietário' END
                      WHEN 'aguardando_acesso' THEN 'acertando a chave com o proprietário'
                      WHEN 'aguardando_motoboy' THEN 'confirmando com o ' || nai_acompanhante() || ''
                      WHEN 'confirmada' THEN 'confirmada'
                      WHEN 'com_tel' THEN 'o Tel está vendo'
                      WHEN 'realizada' THEN 'já aconteceu'
                      ELSE x.estado END, E'\n' ORDER BY x.quando)
    INTO linhas
    FROM nai_visita x WHERE x.corretor_id = t.contato_id AND nai_visita_aberta(x.estado);
  RETURN QUERY SELECT coalesce(linhas, 'Não tem nenhuma visita em andamento com você agora.'),
                      'repita a lista como veio.'::text;
END;
$function$;
