CREATE OR REPLACE FUNCTION public.nai_tipo_da_conversa(p_contato bigint, p_texto text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  -- 224: O TIPO E O DO PEDIDO DE AGORA. A fala dele e os turnos dos ultimos 3
  -- dias (a mesma janela do negocio, 190), dele e dos irmaos, depois do
  -- "zerar". Antes eram 30 dias de turnos e 60 de mensagens: um "casa" antigo
  -- do Marcio fez a Nay responder "Casa nesse perfil eu nao tenho" a quem pedia
  -- apartamento no Smart Tower Itapuranga, e barrar os apartamentos certos.
  -- Sem tipo nos 3 dias, a busca pergunta "casa ou apartamento?" (152).
  SELECT nai_tipo_das_falas(array[coalesce(p_texto, '')] || coalesce((
    SELECT array_agg(x.texto ORDER BY x.id DESC) FROM (
      SELECT t.id, t.texto FROM nai_turno t
       WHERE t.contato_id = ANY (nai_contato_irmaos(p_contato))
         AND t.criado_em > greatest(now() - interval '3 days',
                                    coalesce((SELECT k.zerado_em FROM nai_contato k WHERE k.id = p_contato), '-infinity'))
       ORDER BY t.id DESC LIMIT 40) x), '{}'::text[]));
$function$;
