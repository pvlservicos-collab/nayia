CREATE OR REPLACE FUNCTION public.nai_bloco_colher(p_bloco bigint, p_turno bigint)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
  UPDATE nai_treino_bloco b SET
    turno_novo  = p_turno,
    ela_agora   = (SELECT string_agg(s.texto, E'\n---\n' ORDER BY s.ordem, s.id)
                     FROM nai_saida s WHERE s.turno_id = p_turno AND s.tipo='texto'),
    fotos_agora = (SELECT count(*) FROM nai_saida s WHERE s.turno_id = p_turno AND s.tipo='imagem'),
    ferramentas = coalesce((SELECT t.ferramentas FROM nai_turno t WHERE t.id = p_turno), '{}'),
    atendente   = (SELECT t.atendente FROM nai_turno t WHERE t.id = p_turno),
    intencao    = (SELECT d.intencao FROM nai_turno_decisao d WHERE d.turno_id = p_turno),
    confianca   = (SELECT d.confianca FROM nai_turno_decisao d WHERE d.turno_id = p_turno),
    cortes      = (SELECT string_agg(c.etapa || ': ' || left(c.detalhe,70), ' | ')
                     FROM nai_conferencia c
                    WHERE c.turno_id = p_turno AND c.resultado IN ('cortou','parou')),
    estado      = 'rodado',
    erro        = NULL,
    rodado_em   = now()
  WHERE b.id = p_bloco;
END;
$function$
;
