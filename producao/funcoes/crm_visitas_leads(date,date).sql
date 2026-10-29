CREATE OR REPLACE FUNCTION public.crm_visitas_leads(p_desde date DEFAULT NULL::date, p_ate date DEFAULT NULL::date)
 RETURNS TABLE(id bigint, codigo integer, imovel text, estado text, aberta boolean, quando timestamp with time zone, criado_em timestamp with time zone, cliente_confirmou_em timestamp with time zone, confirmada_em timestamp with time zone, realizada_em timestamp with time zone, realizada_por text, feedback_para text, feedback_em timestamp with time zone, atualizado_em timestamp with time zone, corretor_nome text, corretor_telefone text, proprietario_nome text, proprietario_telefone text, cliente_nome text, cliente_telefone text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  -- as abertas sempre; as fechadas na janela pedida (sem janela, todas), como a crm_visitas
  SELECT o.id, o.codigo, nai_ref_imovel(o.codigo), o.estado,
         o.estado IN ('confirmar_cliente', 'buscando_corretor', 'pedindo_proprietario', 'confirmada'),
         o.quando, o.criado_em, o.cliente_confirmou_em, o.confirmada_em, o.realizada_em, o.realizada_por,
         o.feedback_para, CASE WHEN o.feedback_para IS NOT NULL THEN o.depois_em END, o.atualizado_em,
         nullif(btrim(o.corretor_nome), ''), nullif(regexp_replace(coalesce(o.corretor_telefone, ''), '\D', '', 'g'), ''),
         nullif(btrim(o.proprietario_nome), ''), nullif(regexp_replace(coalesce(o.proprietario_telefone, ''), '\D', '', 'g'), ''),
         nullif(btrim(l.nome), ''), nullif(regexp_replace(coalesce(l.telefone, ''), '\D', '', 'g'), '')
    FROM privado.olx_visita o
    LEFT JOIN privado.olx_lead_whatsapp l ON l.id = o.lead
   WHERE o.estado IN ('confirmar_cliente', 'buscando_corretor', 'pedindo_proprietario', 'confirmada')
      OR ((p_desde IS NULL OR o.quando >= p_desde::timestamptz)
          AND (p_ate IS NULL OR o.quando < (p_ate + 1)::timestamptz))
   ORDER BY o.quando DESC
   LIMIT 300
$function$;
