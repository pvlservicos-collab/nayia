CREATE OR REPLACE FUNCTION public.crm_me_envia_por_telefone(p_telefones text[], p_desde timestamp with time zone)
 RETURNS TABLE(telefone text, pedidos bigint, imoveis_enviados bigint, imoveis_distintos bigint, ultimo timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  SELECT t.tel, count(m.id), coalesce(sum(m.enviados), 0)::bigint,
         (SELECT count(DISTINCT c) FROM privado.me_envia m2, unnest(m2.codigos) c
           WHERE m2.chave = nai_chave(t.tel) AND m2.enviados > 0 AND m2.criado_em >= p_desde),
         max(m.criado_em)
    FROM unnest(p_telefones) AS t(tel)
    LEFT JOIN privado.me_envia m ON m.chave = nai_chave(t.tel) AND m.criado_em >= p_desde
   GROUP BY t.tel
$function$;
