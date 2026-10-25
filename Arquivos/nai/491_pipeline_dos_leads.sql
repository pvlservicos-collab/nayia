-- 491 (Pedro, 24/10): "quero que todos os leads que cheguem na aba leads fiquem em um pipeline lá do lado de visitas
-- com a data que chegaram e até onde foram, se pararam na busca, se visitaram".
--
-- crm_leads_pipeline(de, ate): cada lead da aba Leads (privado.olx_lead_whatsapp: OLX, orgânico e o posto à mão) que
-- CHEGOU entre as datas (dia de Manaus), com o ponto mais longe a que chegou:
--   chegou        só chegou (a Nay ainda não tem o que ele procura)
--   busca         disse o que procura (filtros) ou a busca rodou, sem imóvel enviado
--   enviados      recebeu imóvel
--   visita        pediu visita (olx_visita ou a visita no lead), ainda não confirmada
--   confirmada    visita confirmada
--   visitou       a visita foi marcada como realizada no painel
--   fechou        a visita foi marcada como fechou
--   proprietario  era dono de imóvel, não cliente
-- "Até onde foi" é o mais longe, não a etapa de agora: quem visitou e depois foi finalizado continua em "visitou".
BEGIN;

CREATE OR REPLACE FUNCTION public.crm_leads_pipeline(p_de date, p_ate date)
 RETURNS TABLE(id bigint, telefone text, nome text, origem text, codigo integer, chegou_em timestamp with time zone,
               ultimo_em timestamp with time zone, etapa text, foi_ate text, imoveis integer, humano boolean,
               parada_motivo text, visita_quando timestamp with time zone, procura text)
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

REVOKE ALL ON FUNCTION public.crm_leads_pipeline(date, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.crm_leads_pipeline(date, date) TO nay_disparo;

COMMIT;
