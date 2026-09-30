CREATE OR REPLACE FUNCTION public.crm_captacao_imoveis_do_dono(p_captacao bigint)
 RETURNS TABLE(codigo integer, condominio text, tipo text, bairro text, status text, disponivel boolean, e_parceiro boolean, valor_aluguel numeric, valor_venda numeric, capa text, fotos integer, da_campanha boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET jit TO 'off'
AS $function$
  WITH l AS (SELECT * FROM captacao_leads WHERE id = p_captacao),
  cods AS (
    SELECT btrim(l.codigo)::int AS codigo, true AS campanha FROM l WHERE btrim(coalesce(l.codigo, '')) ~ '^[0-9]{1,6}$'
    UNION
    SELECT btrim(x->>'codigo')::int, false FROM l, jsonb_array_elements(CASE WHEN jsonb_typeof(l.imoveis_prop) = 'array' THEN l.imoveis_prop ELSE '[]'::jsonb END) x
     WHERE btrim(coalesce(x->>'codigo', '')) ~ '^[0-9]{1,6}$'
    UNION
    SELECT i.codigo, false FROM l JOIN imoveis i ON i.proprietario_id = l.proprietario_id WHERE l.proprietario_id IS NOT NULL
    UNION
    SELECT p.codigo, false FROM l JOIN imovel_privado p ON p.proprietario_id = l.proprietario_id WHERE l.proprietario_id IS NOT NULL
  )
  SELECT i.codigo, nullif(btrim(i.condominio_nome), ''), i.tipo, i.bairro, i.status, i.disponivel,
         coalesce(i.e_parceiro, false), i.valor_aluguel, i.valor_venda,
         (SELECT f.url FROM imovel_fotos f WHERE f.codigo = i.codigo ORDER BY f.e_capa DESC NULLS LAST, f.ordem LIMIT 1),
         (SELECT count(*)::int FROM imovel_fotos f WHERE f.codigo = i.codigo),
         bool_or(c.campanha)
    FROM (SELECT codigo, bool_or(campanha) AS campanha FROM cods GROUP BY codigo) c
    JOIN imoveis i ON i.codigo = c.codigo
   GROUP BY i.codigo
   ORDER BY bool_or(c.campanha) DESC, i.codigo
   LIMIT 20
$function$;
