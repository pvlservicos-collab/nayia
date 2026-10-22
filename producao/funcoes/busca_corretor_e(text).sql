CREATE OR REPLACE FUNCTION public.busca_corretor_e(p_telefone text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH t AS (SELECT right(regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g'), 8) AS t8)
  SELECT length(t.t8) = 8
     AND (EXISTS (SELECT 1 FROM privado.busca_contato c WHERE c.telefone8 = t.t8)
          OR EXISTS (SELECT 1 FROM privado.busca_grupo_membro g WHERE g.telefone8 = t.t8)
          OR EXISTS (SELECT 1 FROM privado.busca_corretor b WHERE b.telefone8 = t.t8))
     AND NOT EXISTS (SELECT 1 FROM privado.olx_lead_whatsapp o WHERE right(o.telefone, 8) = t.t8)
     AND NOT EXISTS (SELECT 1 FROM captacao_leads l WHERE right(regexp_replace(coalesce(l.telefone, ''), '\D', '', 'g'), 8) = t.t8)
    FROM t;
$function$;
