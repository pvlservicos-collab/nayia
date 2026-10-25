CREATE OR REPLACE FUNCTION public.nay_leads_mandar_pela_parceria(p_tel text, p_texto text, p_nome text, p_motivo text, p_lead bigint, p_horas integer DEFAULT 24)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  v_chave text := nai_chave(p_tel);
  v_turno bigint;
  v_saida bigint;
BEGIN
  IF v_chave IS NULL OR btrim(coalesce(p_texto, '')) = ''
     OR NOT EXISTS (SELECT 1 FROM nai_contato WHERE chave = v_chave) THEN
    RETURN NULL;
  END IF;
  INSERT INTO core_turno (chave, papel, texto, estado_antes, estado_depois, modo, criado_em, fechado_em)
  VALUES (v_chave, 'agente', '[Nay Leads ao proprietário] ' || left(p_texto, 200), 'NAY_LEADS', 'NAY_LEADS',
          'nay_leads_dono', now(), now())
  RETURNING id INTO v_turno;
  INSERT INTO core_saida (turno_id, chave_destino, ordem, tipo, texto, motivo, papel_destino, estado, enviar_apos, criado_em)
  VALUES (v_turno, v_chave, 1, 'texto', p_texto, 'nay_leads_dono', 'turno', 'pendente', now(), now())
  RETURNING id INTO v_saida;
  INSERT INTO privado.nay_leads_com_dono (chave, telefone, nome, motivo, lead, desde, ate)
  VALUES (v_chave, p_tel, nullif(btrim(coalesce(p_nome, '')), ''), left(p_motivo, 200), p_lead, now(),
          now() + make_interval(hours => greatest(1, p_horas)))
  ON CONFLICT (chave) DO UPDATE SET nome = coalesce(EXCLUDED.nome, nay_leads_com_dono.nome), motivo = EXCLUDED.motivo,
                                    lead = EXCLUDED.lead, desde = now(), ate = EXCLUDED.ate;
  RETURN v_saida;
END;
$function$;
