CREATE OR REPLACE FUNCTION public.nai_turno_dono_respondeu()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v     nai_visita;
  v_msg text;
  v_apr bigint := nai_aprovador_contato();
BEGIN
  IF coalesce(NEW.teste, false) OR NOT nai_dono_disse_sim(NEW.texto) THEN RETURN NULL; END IF;
  SELECT * INTO v FROM nai_visita x
   WHERE x.proprietario_id = NEW.contato_id AND (NEW.visita_id IS NULL OR x.id = NEW.visita_id)
     AND x.estado = 'com_rayssa' AND x.prop_ok_em IS NULL AND x.excluida_em IS NULL
     AND x.ult_msg_prop_em IS NOT NULL AND x.ult_msg_prop_em < NEW.criado_em
     AND (x.quando IS NULL OR x.quando > now())
   ORDER BY x.quando NULLS LAST LIMIT 1;
  IF v.id IS NULL THEN RETURN NULL; END IF;
  UPDATE nai_visita SET prop_ok_em = now(), atualizado_em = now() WHERE id = v.id;
  PERFORM nai_evento(v.id, 'proprietario_confirmou', left('pela resposta dele: ' || NEW.texto, 200));
  v_msg := nai_visita_avisar_acompanhante(v.id, NEW.id, 'o proprietário respondeu');
  PERFORM nai_avisar_tel(NEW.id, v.id,
    nai_texto_visita_completa(v.id, 'Tel, o proprietário confirmou a visita ("' || left(btrim(NEW.texto), 60) || '"): '
      || coalesce(v_msg, 'o acompanhante não foi avisado')), 'visita_proprietario_ok');
  IF v_apr IS NOT NULL THEN
    PERFORM nai_enfileirar_texto(NEW.id, v.id, v_apr, 'equipe',
      nai_cfg('aprovador_visita_nome', 'Rayssa') || ', o proprietário confirmou a visita #' || v.id || ' ('
        || nai_ref_imovel(v.codigo) || ', ' || nai_quando_humano(v.quando) || '): "' || left(btrim(NEW.texto), 60) || '". '
        || initcap(left(coalesce(v_msg, 'o acompanhante não foi avisado'), 1)) || substr(coalesce(v_msg, 'o acompanhante não foi avisado'), 2) || '.',
      'visita_proprietario_ok', 451);
  END IF;
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  -- a mensagem do dono nunca se perde por causa disto: a Rayssa segue como antes
  RAISE WARNING '468 nai_turno_dono_respondeu: %', SQLERRM;
  RETURN NULL;
END $function$;
