CREATE OR REPLACE FUNCTION public.crm_visitas(p_desde date DEFAULT NULL::date, p_ate date DEFAULT NULL::date)
 RETURNS TABLE(id bigint, codigo integer, imovel text, estado text, aberta boolean, aguardando text, urgente boolean, acesso text, quando timestamp with time zone, quando_sugerido timestamp with time zone, criado_em timestamp with time zone, confirmada_corretor_em timestamp with time zone, aprovada_em timestamp with time zone, aprovada_por text, prop_ok_em timestamp with time zone, moto_ok_em timestamp with time zone, confirmada_em timestamp with time zone, pos_visita_em timestamp with time zone, encerrada_em timestamp with time zone, atualizado_em timestamp with time zone, resultado text, motivo text, corretor_nome text, corretor_chaves text[], proprietario_nome text, visitante_nome text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET jit TO 'off'
AS $function$
  -- `nai_chave` custa ~30 us: por visita, contra 1.538 corretores e 1.620
  -- @lid, eram 5 s (medido em 29/09). Calculadas uma vez só, aqui.
  WITH corr AS MATERIALIZED (
    SELECT nai_chave(cr.telefone) AS chave, cr.nome FROM corretores cr
  ),
  lid_map AS MATERIALIZED (
    SELECT 'lid:' || regexp_replace(i.lid, '\D', '', 'g') AS lid_chave, nai_chave(i.telefone) AS fone_chave
      FROM identidade_lid i WHERE coalesce(i.telefone, '') <> ''
  )
  SELECT v.id, v.codigo, nai_ref_imovel(v.codigo), v.estado, nai_visita_aberta(v.estado), v.aguardando,
         coalesce(v.urgente, false), v.acesso, v.quando, v.quando_sugerido,
         v.criado_em, v.confirmada_corretor_em, v.aprovada_em, v.aprovada_por,
         v.prop_ok_em, v.moto_ok_em, v.confirmada_em, v.pos_visita_em,
         v.encerrada_em, v.atualizado_em, v.resultado, v.motivo,
         coalesce(nullif(btrim(c.nome_completo), ''), nullif(btrim(co.nome), ''), nullif(btrim(c.nome_whatsapp), '')),
         ARRAY(SELECT DISTINCT x FROM (
                 SELECT c.chave
                 UNION SELECT m.fone_chave FROM lid_map m WHERE m.lid_chave = c.chave
                 UNION SELECT m.lid_chave FROM lid_map m WHERE m.fone_chave = c.chave
               ) u(x) WHERE x IS NOT NULL),
         v.proprietario_nome, v.visitante_nome
    FROM nai_visita v
    LEFT JOIN nai_contato c ON c.id = v.corretor_id
    LEFT JOIN LATERAL (SELECT cr.nome FROM corr cr WHERE cr.chave = c.chave LIMIT 1) co ON true
   WHERE v.estado <> 'coletando'
     -- 312: o pedido de visita que vem da Nay não entra mais na agenda; quem põe é a equipe, à mão
     AND (v.criada_no_crm_por IS NOT NULL
          OR v.criado_em < (SELECT nai_cfg('agenda_sem_visita_da_nay_desde', 'infinity')::timestamptz))
     AND v.excluida_em IS NULL
     AND (nai_visita_aberta(v.estado)
          OR ((p_desde IS NULL OR coalesce(v.quando, v.criado_em) >= p_desde::timestamptz)
              AND (p_ate IS NULL OR coalesce(v.quando, v.criado_em) < (p_ate + 1)::timestamptz)))
   ORDER BY nai_visita_aberta(v.estado) DESC, coalesce(v.quando, v.criado_em) DESC
   LIMIT 500
$function$;
