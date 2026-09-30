CREATE OR REPLACE FUNCTION public.nai_zerar_conversa(p_telefone text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE v_id bigint; v_chave text := nai_chave(p_telefone); n int; v_ts text;
BEGIN
  SELECT id INTO v_id FROM nai_contato WHERE chave = v_chave;
  IF v_id IS NULL THEN RETURN 'não achei esse número em nai_contato.'; END IF;
  v_ts := to_char(now(), 'YYYYMMDD-HH24MISS');

  UPDATE nai_contato
     SET zerado_em = now(),
         humano_assumiu_em = NULL, humano_motivo = NULL,
         visita_sugerida_em = NULL,
         liberado_em = NULL, liberado_motivo = NULL
   WHERE id = v_id;

  -- a memória do modelo é ARQUIVADA, nunca apagada
  UPDATE nai_memoria
     SET session_id = 'arquivo-' || v_ts || ':' || session_id
   WHERE session_id LIKE 'nai:%:' || v_id
      OR session_id LIKE 'nai:%:' || v_id || ':%';
  GET DIAGNOSTICS n = ROW_COUNT;

  RETURN 'conversa zerada: o contexto começa agora, ' || n || ' mensagens de memória arquivadas.';
END;
$function$;
