CREATE OR REPLACE FUNCTION public.olx_anuncio_enviado(p_ad_id text, p_codigo integer, p_negocio text, p_conta text, p_operacao text, p_conteudo jsonb, p_hash text, p_token text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF p_operacao = 'delete' THEN
    UPDATE privado.olx_anuncio SET estado = 'removendo', import_token = p_token, enviado_em = now(), mensagem = NULL, atualizado_em = now()
     WHERE ad_id = p_ad_id;
  ELSE
    INSERT INTO privado.olx_anuncio AS a (codigo, negocio, conta, ad_id, estado, conteudo, conteudo_hash, import_token, enviado_em, tentativas)
    VALUES (p_codigo, p_negocio, p_conta, p_ad_id, 'enviado', p_conteudo, p_hash, p_token, now(), 1)
    ON CONFLICT (codigo, negocio) DO UPDATE
       SET conta = excluded.conta, estado = 'enviado', conteudo = excluded.conteudo, conteudo_hash = excluded.conteudo_hash,
           import_token = excluded.import_token, enviado_em = now(), mensagem = NULL, removido_em = NULL,
           removido_por_fora = false, tentativas = a.tentativas + 1, atualizado_em = now();
  END IF;
  PERFORM olx_anuncio_registrar(p_ad_id, 'enviado:' || p_operacao, jsonb_build_object('token', p_token));
END $function$;
