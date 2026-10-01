CREATE OR REPLACE FUNCTION public.crm_captacao_donos()
 RETURNS TABLE(telefone text, chat_lid text, nome text, condominio text, codigo text, bairro text, tipo text, captacao_id bigint, imoveis integer, abas text[], etapa_manual text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET jit TO 'off'
AS $function$
  WITH base AS (
    SELECT DISTINCT ON (nai_fone_br(l.telefone))
           nai_fone_br(l.telefone) AS fone,
           nullif(regexp_replace(coalesce(l.chat_lid, ''), '\D', '', 'g'), '') AS lid,
           nullif(btrim(l.nome), '') AS nome,
           nullif(btrim(coalesce(nullif(btrim(l.condominio), ''), i.condominio_nome)), '') AS condominio,
           nullif(btrim(l.codigo), '') AS codigo,
           nullif(btrim(l.bairro), '') AS bairro,
           nullif(btrim(l.tipo_imovel), '') AS tipo,
           l.id AS captacao_id,
           greatest(1, coalesce(jsonb_array_length(CASE WHEN jsonb_typeof(l.imoveis_prop) = 'array' THEN l.imoveis_prop END), 1)) AS imoveis,
           array_remove(ARRAY[
             CASE WHEN l.humano_assumiu_em IS NOT NULL THEN 'com_o_tel' END,
             CASE WHEN l.situacao = 'disponivel' THEN 'disponiveis' END,
             CASE WHEN l.situacao = 'alugado' THEN 'alugados' END,
             CASE WHEN l.situacao = 'vendido' THEN 'ja_vendeu' END,
             CASE WHEN l.quer_vender THEN 'quer_vender' END,
             CASE WHEN l.tem_outro_imovel THEN 'tem_outro_imovel' END,
             CASE WHEN l.respondeu_em IS NOT NULL AND coalesce(l.etapa, '') <> 'concluido' AND l.fechado_em IS NULL THEN 'em_andamento' END,
             CASE WHEN l.ultimo_envio_em IS NOT NULL AND l.respondeu_em IS NULL THEN 'sem_resposta' END
           ], NULL) AS abas,
           right(regexp_replace(l.telefone, '\D', '', 'g'), 8) AS fim8
      FROM captacao_leads l
      LEFT JOIN imoveis i ON i.codigo::text = btrim(l.codigo)
     WHERE coalesce(l.telefone, '') <> '' AND nai_fone_br(l.telefone) IS NOT NULL
     ORDER BY nai_fone_br(l.telefone), l.ultimo_envio_em DESC NULLS LAST, l.id DESC
  ),
  -- 242: quem só existe na escolha à mão (contato do Tel, fora da campanha) também aparece
  so_manual AS (
    SELECT nai_fone_br(e.telefone) AS fone, NULL::text AS lid, NULL::text AS nome, NULL::text AS condominio,
           NULL::text AS codigo, NULL::text AS bairro, NULL::text AS tipo, NULL::bigint AS captacao_id,
           1 AS imoveis, '{}'::text[] AS abas, right(e.telefone, 8) AS fim8
      FROM captacao_etapa_manual e
     WHERE nai_fone_br(e.telefone) IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM base b WHERE b.fim8 = right(e.telefone, 8))
  ),
  tudo AS (SELECT * FROM base UNION ALL SELECT * FROM so_manual)
  SELECT t.fone, t.lid, t.nome, t.condominio, t.codigo, t.bairro, t.tipo, t.captacao_id, t.imoveis,
         CASE WHEN e.etapa IS NULL THEN t.abas ELSE ARRAY[e.etapa] END,
         e.etapa
    FROM tudo t
    LEFT JOIN captacao_etapa_manual e ON right(e.telefone, 8) = t.fim8
$function$;
