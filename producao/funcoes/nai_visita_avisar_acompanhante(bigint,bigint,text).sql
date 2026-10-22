CREATE OR REPLACE FUNCTION public.nai_visita_avisar_acompanhante(p_visita bigint, p_turno bigint, p_por text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  v    nai_visita;
  moto record;
BEGIN
  SELECT * INTO v FROM nai_visita WHERE id = p_visita FOR UPDATE;
  IF v.id IS NULL OR coalesce(nai_cfg('visita_avisar_motoboy', 'sim'), 'sim') <> 'sim' THEN RETURN NULL; END IF;
  IF EXISTS (SELECT 1 FROM nai_visita_evento e WHERE e.visita_id = v.id AND e.tipo = 'motoboy_avisado') THEN
    RETURN 'o acompanhante já tinha sido avisado';
  END IF;
  SELECT * INTO moto FROM nai_motoboy();
  IF moto.contato_id IS NULL OR moto.contato_id = v.corretor_id THEN RETURN 'sem acompanhante ativo na equipe'; END IF;
  UPDATE nai_visita SET motoboy_id = moto.contato_id, ult_msg_moto_em = now() WHERE id = v.id;
  PERFORM nai_enfileirar_texto(p_turno, v.id, moto.contato_id, 'motoboy',
    nai_texto_visita_completa(v.id, 'Oi, ' || coalesce(nullif(split_part(btrim(coalesce(moto.nome, '')), ' ', 1), ''), 'tudo bem')
      || '! Aqui é a Nay, da Imob Easy. Visita confirmada pelo proprietário')
      || E'\n\nVocê consegue acompanhar? Me responde SIM ou NÃO, por favor.',
    'visita_motoboy', 520);
  PERFORM nai_evento(v.id, 'motoboy_avisado', left(coalesce(moto.nome, '') || ' (' || coalesce(p_por, '?') || ')', 200));
  RETURN 'avisei o ' || coalesce(nullif(split_part(btrim(coalesce(moto.nome, '')), ' ', 1), ''), 'acompanhante');
END $function$;
