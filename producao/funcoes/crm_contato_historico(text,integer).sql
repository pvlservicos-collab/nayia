CREATE OR REPLACE FUNCTION public.crm_contato_historico(p_telefone text, p_limite integer DEFAULT 60)
 RETURNS TABLE(quando timestamp with time zone, tipo text, codigo integer, imovel text, detalhe text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET jit TO 'off'
AS $function$
  WITH p AS MATERIALIZED (SELECT * FROM crm_pessoas(ARRAY[p_telefone])),
  irmaos AS (SELECT unnest(p.ids) AS id FROM p),
  ev AS (
    SELECT e.enviado_em AS quando, 'recebeu'::text AS tipo,
           nullif(regexp_replace(coalesce(e.codigo, ''), '\D', '', 'g'), '')::int AS codigo, NULL::text AS detalhe
      FROM envios e, p
     WHERE e.destino IS DISTINCT FROM 'grupo' AND nai_chave(e.telefone) = ANY (p.chaves)
    UNION ALL
    SELECT t.criado_em, 'pediu', t.codigo, left(regexp_replace(coalesce(t.texto, ''), '\s+', ' ', 'g'), 160)
      FROM nai_turno t
     WHERE t.contato_id IN (SELECT id FROM irmaos) AND t.codigo IS NOT NULL AND NOT coalesce(t.teste, false)
    UNION ALL
    SELECT coalesce(v.quando, v.criado_em), 'visita', v.codigo, v.estado
      FROM nai_visita v
     WHERE v.estado <> 'coletando' AND v.excluida_em IS NULL
       AND (v.corretor_id IN (SELECT id FROM irmaos) OR v.proprietario_id IN (SELECT id FROM irmaos))
  )
  SELECT ev.quando, ev.tipo, ev.codigo, CASE WHEN ev.codigo IS NOT NULL THEN nai_ref_imovel(ev.codigo) END, ev.detalhe
    FROM ev WHERE ev.quando IS NOT NULL
   ORDER BY ev.quando DESC
   LIMIT greatest(1, least(coalesce(p_limite, 60), 300))
$function$;
