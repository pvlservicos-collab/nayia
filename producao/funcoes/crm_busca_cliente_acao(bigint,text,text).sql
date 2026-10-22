CREATE OR REPLACE FUNCTION public.crm_busca_cliente_acao(p_id bigint, p_acao text, p_quem text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_estado text;
BEGIN
  SELECT estado INTO v_estado FROM privado.busca_cliente WHERE id = p_id FOR UPDATE;
  IF v_estado IS NULL THEN RETURN jsonb_build_object('ok', false, 'erro', 'busca não existe'); END IF;
  IF p_acao = 'ativar' THEN
    UPDATE privado.busca_cliente SET estado = 'buscando', ativada_em = coalesce(ativada_em, now()), motivo = 'ativada pela tela',
           atualizado_em = now() WHERE id = p_id;
  ELSIF p_acao = 'pausar' THEN
    UPDATE privado.busca_cliente SET estado = 'pausada', motivo = 'pausada pela tela', atualizado_em = now() WHERE id = p_id;
  ELSIF p_acao = 'encerrar' THEN
    UPDATE privado.busca_cliente SET estado = 'encerrada', motivo = 'encerrada pela tela', atualizado_em = now() WHERE id = p_id;
  ELSE
    RETURN jsonb_build_object('ok', false, 'erro', 'ação desconhecida');
  END IF;
  INSERT INTO privado.busca_cliente_passo (busca, lugar, texto) VALUES
    (p_id, 'equipe', CASE p_acao WHEN 'ativar' THEN 'Busca ativada' WHEN 'pausar' THEN 'Busca pausada' ELSE 'Busca encerrada' END
                     || coalesce(' por ' || nullif(btrim(p_quem), ''), '') || ' (tela do CRM)');
  RETURN jsonb_build_object('ok', true);
END $function$;
