CREATE OR REPLACE FUNCTION public.nay_imovel_marcado(p_telefone text, p_message_id text)
 RETURNS TABLE(texto_pronto text, codigo text, instrucao_para_voce text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_cod  text := nay_imovel_da_citacao(p_message_id);
  v_nome text;
BEGIN
  IF v_cod IS NOT NULL THEN
    SELECT coalesce(NULLIF(i.condominio_nome,''), i.tipo, 'o imóvel')
      INTO v_nome FROM imoveis i WHERE i.codigo::text = v_cod;

    RETURN QUERY SELECT
      ''::text, v_cod,
      ('ele marcou a mensagem do imovel ' || v_cod || ' (' || coalesce(v_nome,'?')
       || '). E DESSE que ele fala -- isto nao e palpite, e a mensagem que ele '
       || 'apontou. Siga a conversa com esse codigo, sem perguntar qual e.')::text;
    RETURN;
  END IF;

  -- Não resolveu: cai na lista da conversa. NUNCA chuta.
  RETURN QUERY
  SELECT q.texto_pronto, NULL::text,
         q.instrucao_para_voce || ' (Ele marcou uma mensagem que voce nao '
         || 'consegue identificar -- pode ser card de outro corretor, de outro '
         || 'grupo, ou anterior ao registro. Por isso pergunte.)'
    FROM nay_qual_imovel(p_telefone) q;
END;
$function$;
