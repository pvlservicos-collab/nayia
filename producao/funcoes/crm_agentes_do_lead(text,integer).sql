CREATE OR REPLACE FUNCTION public.crm_agentes_do_lead(p_telefone text, p_limite integer DEFAULT 60)
 RETURNS TABLE(em timestamp with time zone, agente text, nome text, cor text, acao text, detalhe text, modo text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  SELECT t.em, t.agente, a.nome, a.cor, t.acao, t.detalhe, t.modo
    FROM privado.agente_linha_do_tempo(now() - interval '60 days',
                                       right(regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g'), 8)) t
    JOIN privado.agente a ON a.chave = t.agente
   WHERE length(right(regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g'), 8)) = 8
   ORDER BY t.em DESC
   LIMIT greatest(1, least(coalesce(p_limite, 60), 300))
$function$;
