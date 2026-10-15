CREATE OR REPLACE FUNCTION public.captacao_olx_da_parceria(p_tel text, p_contato bigint DEFAULT NULL::bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE
AS $function$
  -- o lead da Nay proprietários da OLX que conversa pela Parceria com este número (ou com um irmão dele: @lid)
  SELECT l.id FROM captacao_leads l JOIN captacao_olx o ON o.lead_id = l.id
   WHERE l.canal = 'parceria' AND NOT coalesce(l.opt_out, false)
     AND o.atualizado_em > now() - interval '30 days'
     AND (nay_fone_chave(l.telefone) = nay_fone_chave(p_tel)
          OR nay_fone_chave(l.telefone) IN (SELECT nay_fone_chave(c.telefone) FROM nai_contato c
                                             WHERE c.id = ANY (coalesce(nai_contato_irmaos(p_contato), ARRAY[p_contato]))))
   ORDER BY l.id LIMIT 1
$function$;
