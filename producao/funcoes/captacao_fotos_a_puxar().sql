CREATE OR REPLACE FUNCTION public.captacao_fotos_a_puxar()
 RETURNS TABLE(codigo integer, foto_id text, url text, ordem integer)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT i.codigo,
         'capt' || c.id || '_' || regexp_replace(regexp_replace(f.url, '^.*/', ''), '\.[A-Za-z0-9]+$', '') AS foto_id,
         f.url, f.ord::int
    FROM captacao_leads l
    JOIN imoveis i ON i.codigo::text = l.codigo
    JOIN captacao_cadastro c ON c.lead_id = l.id AND c.tipo = 'atualizar' AND (c.codigo IS NULL OR c.codigo = i.codigo)
   CROSS JOIN LATERAL jsonb_array_elements_text(CASE WHEN jsonb_typeof(c.fotos) = 'array' THEN c.fotos ELSE '[]'::jsonb END)
         WITH ORDINALITY f(url, ord)
   WHERE l.situacao = 'disponivel'
     AND NOT coalesce(i.e_parceiro, false) AND i.status IS DISTINCT FROM 'Excluído'
     AND f.url ~ '^https://imobeasy\.online/fotos-captacao/whatsapp/[0-9]+/[A-Za-z0-9_-]+\.(jpe?g|png|webp)$'
     -- o imóvel não tem foto própria (as que vieram por aqui não contam)
     AND NOT EXISTS (SELECT 1 FROM imovel_fotos x WHERE x.codigo = i.codigo
                        AND x.url NOT LIKE '%/crm/' || i.codigo || '/capt%')
     -- e esta ainda não foi trazida
     AND NOT EXISTS (SELECT 1 FROM imovel_fotos x WHERE x.codigo = i.codigo
                        AND x.url LIKE '%/crm/' || i.codigo || '/capt' || c.id || '\_'
                                       || regexp_replace(regexp_replace(f.url, '^.*/', ''), '\.[A-Za-z0-9]+$', '') || '.%')
   ORDER BY i.codigo, c.id, f.ord;
$function$;
