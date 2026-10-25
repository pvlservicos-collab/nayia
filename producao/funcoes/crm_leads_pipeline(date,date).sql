CREATE OR REPLACE FUNCTION public.crm_leads_pipeline(p_de date, p_ate date)
 RETURNS TABLE(id bigint, telefone text, nome text, origem text, codigo integer, chegou_em timestamp with time zone, ultimo_em timestamp with time zone, etapa text, foi_ate text, imoveis integer, humano boolean, parada_motivo text, visita_quando timestamp with time zone, procura text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  WITH v AS (
    SELECT ov.lead,
           bool_or(r.resultado = 'fechou') AS fechou,
           bool_or(r.resultado IN ('realizada', 'fechou')) AS visitou,
           bool_or(ov.estado = 'confirmada' OR ov.confirmada_em IS NOT NULL) AS confirmada,
           max(ov.quando) AS quando
      FROM privado.olx_visita ov
      LEFT JOIN privado.visita_resultado r ON r.origem = 'olx' AND r.visita_id = ov.id
     GROUP BY ov.lead
  )
  SELECT l.id, l.telefone, l.nome, l.origem, l.codigo, l.criado_em,
         greatest(l.atualizado_em, l.etapa_em, l.criado_em), l.etapa,
         CASE
           WHEN l.etapa = 'proprietarios' THEN 'proprietario'
           WHEN v.fechou THEN 'fechou'
           WHEN v.visitou THEN 'visitou'
           WHEN v.confirmada THEN 'confirmada'
           WHEN v.lead IS NOT NULL OR l.visita IS NOT NULL OR l.etapa IN ('visita', 'fechamento') THEN 'visita'
           WHEN cardinality(l.enviados) > 0 OR l.etapa = 'imoveis_enviados' THEN 'enviados'
           WHEN l.etapa = 'feito_busca' OR l.filtros <> '{}'::jsonb THEN 'busca'
           ELSE 'chegou'
         END,
         cardinality(l.enviados), l.humano_em IS NOT NULL, l.parada_motivo,
         coalesce(v.quando, nullif(l.visita->>'quando', '')::timestamptz),
         nullif(nullif(btrim(coalesce(l.perfil->>'procura', '')), ''), 'escreveu direto no WhatsApp')
    FROM privado.olx_lead_whatsapp l
    LEFT JOIN v ON v.lead = l.id
   WHERE l.criado_em >= p_de::timestamp AT TIME ZONE 'America/Manaus'
     AND l.criado_em < (p_ate + 1)::timestamp AT TIME ZONE 'America/Manaus'
   ORDER BY l.criado_em DESC
$function$;
