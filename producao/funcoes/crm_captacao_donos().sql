CREATE OR REPLACE FUNCTION public.crm_captacao_donos()
 RETURNS TABLE(telefone text, chat_lid text, nome text, condominio text, codigo text, bairro text, tipo text, captacao_id bigint, imoveis integer, abas text[])
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET jit TO 'off'
AS $function$
  SELECT DISTINCT ON (nai_fone_br(l.telefone))
         nai_fone_br(l.telefone),
         nullif(regexp_replace(coalesce(l.chat_lid, ''), '\D', '', 'g'), ''),
         nullif(btrim(l.nome), ''),
         nullif(btrim(coalesce(nullif(btrim(l.condominio), ''), i.condominio_nome)), ''),
         nullif(btrim(l.codigo), ''),
         nullif(btrim(l.bairro), ''),
         nullif(btrim(l.tipo_imovel), ''),
         l.id,
         greatest(1, coalesce(jsonb_array_length(CASE WHEN jsonb_typeof(l.imoveis_prop) = 'array' THEN l.imoveis_prop END), 1)),
         -- 236: as abas do CRM
         array_remove(ARRAY[
           CASE WHEN l.humano_assumiu_em IS NOT NULL THEN 'com_o_tel' END,
           CASE WHEN l.situacao = 'disponivel' THEN 'disponiveis' END,
           CASE WHEN l.situacao = 'alugado' THEN 'alugados' END,
           CASE WHEN l.situacao = 'vendido' THEN 'ja_vendeu' END,
           CASE WHEN l.quer_vender THEN 'quer_vender' END,
           CASE WHEN l.tem_outro_imovel THEN 'tem_outro_imovel' END,
           CASE WHEN l.respondeu_em IS NOT NULL AND coalesce(l.etapa, '') <> 'concluido' AND l.fechado_em IS NULL THEN 'em_andamento' END,
           CASE WHEN l.ultimo_envio_em IS NOT NULL AND l.respondeu_em IS NULL THEN 'sem_resposta' END
         ], NULL)
    FROM captacao_leads l
    LEFT JOIN imoveis i ON i.codigo::text = btrim(l.codigo)
   WHERE coalesce(l.telefone, '') <> ''
     AND nai_fone_br(l.telefone) IS NOT NULL
   ORDER BY nai_fone_br(l.telefone), l.ultimo_envio_em DESC NULLS LAST, l.id DESC
$function$;
