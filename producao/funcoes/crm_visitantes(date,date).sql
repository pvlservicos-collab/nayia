CREATE OR REPLACE FUNCTION public.crm_visitantes(p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
 SET jit TO 'off'
AS $function$
  WITH corr AS MATERIALIZED (SELECT nai_chave(cr.telefone) AS chave, cr.nome, cr.telefone FROM corretores cr),
  v AS (
    SELECT 'parceria'::text AS origem, v.id, v.quando, v.codigo, nai_ref_imovel(v.codigo) AS imovel, v.estado, v.resultado,
           coalesce(nullif(btrim(c.nome_completo), ''), nullif(btrim(co.nome), ''), nullif(btrim(c.nome_whatsapp), ''), c.telefone) AS corretor,
           coalesce(nullif(regexp_replace(coalesce(co.telefone, c.telefone, ''), '\D', '', 'g'), ''), c.telefone) AS corretor_telefone,
           nullif(btrim(v.visitante_nome), '') AS cliente, NULL::text AS cliente_telefone
      FROM nai_visita v
      LEFT JOIN nai_contato c ON c.id = v.corretor_id
      LEFT JOIN LATERAL (SELECT cr.nome, cr.telefone FROM corr cr WHERE cr.chave = c.chave LIMIT 1) co ON true
     WHERE v.estado IN ('encerrada', 'realizada') AND v.excluida_em IS NULL AND v.quando IS NOT NULL
    UNION ALL
    SELECT 'olx', o.id, o.quando, o.codigo, nai_ref_imovel(o.codigo), o.estado, NULL,
           nullif(btrim(o.corretor_nome), ''), nullif(regexp_replace(coalesce(o.corretor_telefone, ''), '\D', '', 'g'), ''),
           coalesce(nullif(btrim(l.nome), ''), l.telefone), l.telefone
      FROM privado.olx_visita o JOIN privado.olx_lead_whatsapp l ON l.id = o.lead
     WHERE o.quando < now() AND o.estado = 'confirmada'
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'origem', v.origem, 'id', v.id, 'quando', v.quando, 'codigo', v.codigo, 'imovel', v.imovel, 'estado', v.estado,
           'resultado', v.resultado, 'corretor', v.corretor, 'corretor_telefone', v.corretor_telefone,
           'cliente', v.cliente, 'cliente_telefone', v.cliente_telefone) ORDER BY v.quando DESC), '[]'::jsonb)
    FROM v
   WHERE (p_de IS NULL OR v.quando >= (p_de::timestamp AT TIME ZONE 'America/Manaus'))
     AND (p_ate IS NULL OR v.quando < ((p_ate + 1)::timestamp AT TIME ZONE 'America/Manaus'))
$function$;
