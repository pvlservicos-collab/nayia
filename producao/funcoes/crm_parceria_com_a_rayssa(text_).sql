CREATE OR REPLACE FUNCTION public.crm_parceria_com_a_rayssa(p_telefones text[])
 RETURNS TABLE(telefone text, visita_rayssa boolean, visita_id bigint, fechamento_id bigint, fechamento_desde timestamp with time zone, acompanhante boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT pe.telefone, vr.id IS NOT NULL, vr.id, f.id, f.iniciado_em,
         EXISTS (SELECT 1 FROM equipe e
                  WHERE e.ativo AND e.papel = 'acompanhante' AND nai_chave(e.telefone) = ANY (pe.chaves))
    FROM crm_pessoas(p_telefones) pe
    LEFT JOIN LATERAL (SELECT v.id FROM nai_visita v
                        WHERE v.corretor_id = ANY (pe.ids) AND nai_visita_com_a_rayssa(v.estado, v.quando)
                        ORDER BY v.quando NULLS LAST LIMIT 1) vr ON true
    LEFT JOIN LATERAL (SELECT f.id, f.iniciado_em FROM nai_fechamento f
                        WHERE f.contato_id = ANY (pe.ids) AND f.concluido_em IS NULL
                        ORDER BY f.id DESC LIMIT 1) f ON true;
$function$;
