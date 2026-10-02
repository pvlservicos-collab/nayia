CREATE OR REPLACE FUNCTION public.site_me_envia_ranking(p_dias integer DEFAULT 30)
 RETURNS TABLE(telefone text, nome text, e_corretor boolean, pedidos bigint, imoveis_enviados bigint, imoveis_distintos bigint, primeiro timestamp with time zone, ultimo timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT max(m.telefone),
         coalesce((SELECT c.nome FROM corretores c WHERE nai_chave(c.telefone) = m.chave LIMIT 1),
                  (SELECT coalesce(k.nome_completo, k.nome_whatsapp) FROM nai_contato k WHERE k.chave = m.chave)) AS nome,
         EXISTS (SELECT 1 FROM corretores c WHERE nai_chave(c.telefone) = m.chave) AS e_corretor,
         count(*) AS pedidos, sum(m.enviados)::bigint AS imoveis_enviados,
         (SELECT count(DISTINCT c) FROM privado.me_envia m2, unnest(m2.codigos) c
           WHERE m2.chave = m.chave AND m2.enviados > 0 AND m2.criado_em > now() - make_interval(days => p_dias)) AS imoveis_distintos,
         min(m.criado_em), max(m.criado_em)
    FROM privado.me_envia m
   WHERE m.criado_em > now() - make_interval(days => p_dias)
   GROUP BY m.chave
   ORDER BY sum(m.enviados) DESC, count(*) DESC;
$function$;
