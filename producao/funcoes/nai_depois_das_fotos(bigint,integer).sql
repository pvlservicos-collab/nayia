CREATE OR REPLACE FUNCTION public.nai_depois_das_fotos(p_turno bigint, p_ordem integer)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE t nai_turno;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno',
    'Aqui as fotos, quer fazer uma visita? Só me informar um horário', 'depois_das_fotos', p_ordem + 1);
  PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno',
    'Ou se tiver alguma dúvida ou quiser mais imóveis me fala o que está procurando, que já vejo aqui para você, ok?', 'depois_das_fotos', p_ordem + 2);
  UPDATE nai_contato SET visita_sugerida_em = now() WHERE id = t.contato_id;
END;
$function$;
