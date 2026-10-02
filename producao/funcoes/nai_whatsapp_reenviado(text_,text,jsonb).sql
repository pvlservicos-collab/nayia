CREATE OR REPLACE FUNCTION public.nai_whatsapp_reenviado(p_antigos text[], p_novo text, p_resposta jsonb DEFAULT '{}'::jsonb)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  r      record;
  v_onde text := 'fora_da_caixa';
BEGIN
  IF nullif(btrim(coalesce(p_novo, '')), '') IS NULL OR coalesce(array_length(p_antigos, 1), 0) = 0 THEN
    RETURN 'sem_id';
  END IF;

  FOR r IN
    SELECT s.id, s.message_id, s.telefone_final, s.texto, s.imagem_url
      FROM nai_saida s
     WHERE s.estado = 'enviado' AND s.criado_em > now() - interval '4 days'
       AND (s.message_id = ANY (p_antigos) OR s.resposta->>'zaapId' = ANY (p_antigos)
            OR s.resposta->>'messageId' = ANY (p_antigos))
  LOOP
    UPDATE nai_saida
       SET message_id = p_novo, enviado_em = now(),
           resposta = coalesce(resposta, '{}'::jsonb) || coalesce(p_resposta, '{}'::jsonb)
                      || jsonb_build_object('reenviado_em', now(), 'id_antigo', r.message_id)
     WHERE id = r.id;
    INSERT INTO mensagem_saida (message_id, telefone, texto)
         VALUES (p_novo, r.telefone_final, coalesce(r.texto, r.imagem_url))
    ON CONFLICT (message_id) DO NOTHING;
    UPDATE envios SET message_id = p_novo, enviado_em = now() WHERE message_id = r.message_id;
    v_onde := 'nai_saida';
  END LOOP;

  -- a caixa do núcleo novo (nay-core)
  UPDATE core_saida
     SET message_id = p_novo, enviado_em = now(),
         resposta = coalesce(resposta, '{}'::jsonb) || coalesce(p_resposta, '{}'::jsonb)
                    || jsonb_build_object('reenviado_em', now(), 'id_antigo', message_id)
   WHERE estado = 'enviado' AND criado_em > now() - interval '4 days' AND message_id = ANY (p_antigos);
  IF FOUND AND v_onde = 'fora_da_caixa' THEN v_onde := 'core_saida'; END IF;

  RETURN v_onde;
END;
$function$;
