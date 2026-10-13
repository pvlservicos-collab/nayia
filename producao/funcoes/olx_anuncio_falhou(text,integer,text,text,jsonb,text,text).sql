CREATE OR REPLACE FUNCTION public.olx_anuncio_falhou(p_ad_id text, p_codigo integer, p_negocio text, p_conta text, p_conteudo jsonb, p_hash text, p_mensagem text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  INSERT INTO privado.olx_anuncio AS a (codigo, negocio, conta, ad_id, estado, conteudo, conteudo_hash, enviado_em, tentativas, mensagem)
  VALUES (p_codigo, p_negocio, p_conta, p_ad_id, 'erro', p_conteudo, p_hash, now(), 1, left(p_mensagem, 500))
  ON CONFLICT (codigo, negocio) DO UPDATE
     SET estado = CASE WHEN a.estado IN ('publicado', 'removendo') THEN a.estado ELSE 'erro' END,   -- o que já está no ar continua no ar
         -- 365: a edição que falhou não volta sozinha (só quando o cadastro mudar de novo)
         conteudo_hash = CASE WHEN a.estado IN ('publicado', 'removendo') THEN excluded.conteudo_hash ELSE a.conteudo_hash END,
         mensagem = left(p_mensagem, 500), enviado_em = now(), tentativas = a.tentativas + 1, atualizado_em = now();
  PERFORM olx_anuncio_registrar(p_ad_id, 'falhou', jsonb_build_object('mensagem', p_mensagem));
END $function$;
