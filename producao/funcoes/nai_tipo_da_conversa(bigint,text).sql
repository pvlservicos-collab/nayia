CREATE OR REPLACE FUNCTION public.nai_tipo_da_conversa(p_contato bigint, p_texto text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  -- 224: o tipo é o do pedido de AGORA (3 dias, não 60).
  -- 241: e para na fronteira do PEDIDO: com um perfil de cliente aberto (223), só
  -- valem as falas desde que ele começou. Sem isso, "e para alugar, 2 quartos no
  -- Adrianópolis" herdava o "casa" do pedido anterior, de venda e de outro cliente.
  SELECT nai_tipo_das_falas(array[coalesce(p_texto, '')] || coalesce((
    SELECT array_agg(x.texto ORDER BY x.id DESC) FROM (
      SELECT t.id, t.texto FROM nai_turno t
       WHERE t.contato_id = ANY (nai_contato_irmaos(p_contato))
         AND t.criado_em > greatest(
               now() - interval '3 days',
               coalesce((SELECT k.zerado_em FROM nai_contato k WHERE k.id = p_contato), '-infinity'),
               coalesce((SELECT p.criado_em FROM nai_perfil_ativo(p_contato) p), '-infinity'))
       ORDER BY t.id DESC LIMIT 40) x), '{}'::text[]));
$function$;
