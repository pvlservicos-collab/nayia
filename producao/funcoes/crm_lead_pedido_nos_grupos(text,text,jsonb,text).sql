CREATE OR REPLACE FUNCTION public.crm_lead_pedido_nos_grupos(p_telefone text, p_texto text, p_enviados jsonb, p_quem text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
-- p_enviados: [{"grupo": id, "nome": nome, "mid": id da mensagem}] dos grupos em que o envio deu certo.
-- Devolve a busca em que o pedido foi anotado (NULL: o lead não tem busca; o envio já saiu de qualquer jeito).
DECLARE
  v_busca bigint;
  v_itens jsonb;
  v_quem  text := coalesce(nullif(btrim(p_quem), ''), 'a equipe');
BEGIN
  IF jsonb_typeof(p_enviados) <> 'array' OR jsonb_array_length(p_enviados) = 0 THEN
    RETURN NULL;
  END IF;
  UPDATE privado.busca_grupo SET ultimo_envio_em = now()
   WHERE grupo_id IN (SELECT x->>'grupo' FROM jsonb_array_elements(p_enviados) x);
  SELECT c.id INTO v_busca
    FROM privado.busca_cliente c JOIN privado.olx_lead_whatsapp w ON w.id = c.lead
   WHERE right(regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g'), 8) <> ''
     AND right(regexp_replace(w.telefone, '\D', '', 'g'), 8) = right(regexp_replace(p_telefone, '\D', '', 'g'), 8)
   ORDER BY w.atualizado_em DESC LIMIT 1;
  IF v_busca IS NULL THEN
    RETURN NULL;
  END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object('grupo', x->>'grupo', 'nome', x->>'nome', 'mid', x->>'mid',
                                               'em', to_char(now() AT TIME ZONE 'America/Manaus', 'YYYY-MM-DD"T"HH24:MI') || '-04:00',
                                               'texto', left(p_texto, 2000), 'manual', true, 'quem', v_quem, 'teste', false)),
                  '[]'::jsonb)
    INTO v_itens FROM jsonb_array_elements(p_enviados) x;
  UPDATE privado.busca_cliente SET grupos = coalesce(grupos, '[]'::jsonb) || v_itens, grupos_em = now(), atualizado_em = now()
   WHERE id = v_busca;
  INSERT INTO privado.busca_cliente_passo (busca, em, lugar, texto, dados)
  VALUES (v_busca, now(), 'grupos',
          'Pedido à mão no CRM (' || v_quem || ') pelo número da Parceria em ' || jsonb_array_length(p_enviados) || ' grupo'
          || CASE WHEN jsonb_array_length(p_enviados) > 1 THEN 's' ELSE '' END || ': "' || left(btrim(p_texto), 140) || '"',
          jsonb_build_object('manual', true, 'grupos', p_enviados));
  RETURN v_busca;
END
$function$;
