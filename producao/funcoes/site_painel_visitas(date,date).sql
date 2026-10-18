CREATE OR REPLACE FUNCTION public.site_painel_visitas(p_de date, p_ate date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH v AS (
    SELECT 'parceria'::text AS origem, v.id, v.quando, v.codigo, v.estado, v.criado_em,
           CASE WHEN v.criada_no_crm_por IS NULL THEN 'Nay' ELSE 'CRM' END AS marcada_por,
           nullif(split_part(btrim(coalesce(c.nome_completo, c.nome_whatsapp, '')), ' ', 1), '') AS corretor,
           nullif(split_part(btrim(coalesce(v.visitante_nome, '')), ' ', 1), '') AS cliente,
           nullif(btrim(coalesce(v.resultado, '')), '') AS nota_do_sistema
      FROM nai_visita v LEFT JOIN nai_contato c ON c.id = v.corretor_id
     WHERE v.excluida_em IS NULL AND v.quando IS NOT NULL
       AND v.quando >= p_de::timestamp AT TIME ZONE 'America/Manaus'
       AND v.quando < (p_ate + 1)::timestamp AT TIME ZONE 'America/Manaus'
    UNION ALL
    SELECT 'olx', ov.id, ov.quando, ov.codigo, ov.estado, ov.criado_em, 'Nay do WhatsApp (OLX)',
           nullif(split_part(btrim(coalesce(ov.corretor_nome, '')), ' ', 1), ''),
           nullif(split_part(btrim(coalesce(w.nome, '')), ' ', 1), ''), NULL
      FROM privado.olx_visita ov LEFT JOIN privado.olx_lead_whatsapp w ON w.id = ov.lead
     WHERE ov.quando IS NOT NULL
       AND ov.quando >= p_de::timestamp AT TIME ZONE 'America/Manaus'
       AND ov.quando < (p_ate + 1)::timestamp AT TIME ZONE 'America/Manaus'
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'origem', v.origem, 'id', v.id, 'quando', v.quando, 'codigo', v.codigo, 'estado', v.estado,
           'marcada_por', v.marcada_por, 'corretor', v.corretor, 'cliente', v.cliente, 'nota_do_sistema', v.nota_do_sistema,
           'passou', v.quando < now(),
           'imovel', concat_ws(' · ', nullif(i.condominio_nome, ''), nullif(i.tipo, ''), nullif(i.bairro, '')),
           'resultado', r.resultado, 'marcado_por', r.marcado_por, 'marcado_em', r.marcado_em)
         ORDER BY v.quando DESC, v.id DESC), '[]'::jsonb)
    FROM v
    LEFT JOIN imoveis i ON i.codigo = v.codigo
    LEFT JOIN privado.visita_resultado r ON r.origem = v.origem AND r.visita_id = v.id;
$function$;
