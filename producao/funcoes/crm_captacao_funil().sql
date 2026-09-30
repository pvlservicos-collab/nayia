CREATE OR REPLACE FUNCTION public.crm_captacao_funil()
 RETURNS TABLE(telefone text, nome text, etapa text, mudou_em timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET jit TO 'off'
AS $function$
  SELECT nai_fone_br(l.telefone), nullif(btrim(l.nome), ''),
         CASE WHEN EXISTS (SELECT 1 FROM captacao_cadastro c WHERE c.lead_id = l.id AND c.estado = 'pronto') THEN 'Mandou os dados'
              WHEN l.situacao = 'vendido' THEN 'Vendido'
              WHEN l.situacao = 'alugado' THEN 'Alugado'
              WHEN l.situacao = 'disponivel' THEN 'Disponível'
              WHEN l.respondeu_em IS NOT NULL THEN 'Respondeu'
              ELSE 'Não respondeu' END,
         greatest(l.atualizado_em, l.respondeu_em, l.ultimo_envio_em)
    FROM captacao_leads l
   WHERE l.ultimo_envio_em IS NOT NULL
     AND coalesce(l.canal, '') <> 'oficial'
     AND coalesce(l.telefone, '') <> ''
$function$;
