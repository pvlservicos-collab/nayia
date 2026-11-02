-- 563: MÉTRICAS POR IMÓVEL no painel do Início (aba "Imóveis")
--
-- Pedro, 02/11/2026: "metricas de imoveis que mais tiveram visitas, que mais tiveram vendas x locações, varios numeros
-- ... por la no painel inicial do site uma aba de metricas só por imovel, visitas, visitas buscadas, vezes que o card
-- foi enviado, todos os filtros disponiveis".
--
--   site_imoveis_metricas(de, ate, sem_atividade)  uma linha por imóvel com o que aconteceu com ele no período:
--     visitas pedidas (criadas), confirmadas, agendadas para o período, realizadas / fechou / desistiu / sem resultado
--     (o que a equipe marcou na aba Visitas, pelo dia da visita), cards enviados (Parceria, Leads, corretores, grupos),
--     leads da OLX e do Chaves na Mão que citaram o imóvel; mais a ficha para filtrar (tipo, bairro, condomínio, quartos,
--     valores, mobília, origem, parceiro, captador, situação).
--   As mesmas contas e as mesmas exclusões de internos do site_painel_metricas (o time e os números de teste não contam).
--   sem_atividade = true acrescenta os imóveis Disponíveis sem nenhum movimento no período (os "parados").
--   Só LEITURA: não escreve em nada.
BEGIN;

CREATE OR REPLACE FUNCTION public.site_imoveis_metricas(p_de date, p_ate date, p_sem_atividade boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH p AS (
    SELECT p_de::timestamp AT TIME ZONE 'America/Manaus' AS ini,
           (p_ate + 1)::timestamp AT TIME ZONE 'America/Manaus' AS fim,
           site_painel_internos() AS interno
  ),
  -- visitas da Parceria (nai_visita) e do WhatsApp Leads (olx_visita), uma linha por visita
  vis AS (
    SELECT 'parceria'::text AS origem, v.id, v.codigo, v.criado_em, v.quando, v.estado,
           coalesce(v.confirmada_em, v.confirmada_corretor_em, v.aprovada_em) AS confirmada
      FROM nai_visita v WHERE v.excluida_em IS NULL
    UNION ALL
    SELECT 'olx', ov.id, ov.codigo, ov.criado_em, ov.quando, ov.estado, ov.confirmada_em
      FROM privado.olx_visita ov
      JOIN privado.olx_lead_whatsapp w ON w.id = ov.lead, p
     WHERE right(regexp_replace(coalesce(w.telefone, ''), '\D', '', 'g'), 8) <> ALL (p.interno)
  ),
  v_conta AS (
    SELECT vis.codigo,
           count(*) FILTER (WHERE vis.origem = 'parceria' AND vis.criado_em >= p.ini AND vis.criado_em < p.fim) AS visitas_parceria,
           count(*) FILTER (WHERE vis.origem = 'olx' AND vis.criado_em >= p.ini AND vis.criado_em < p.fim) AS visitas_leads,
           count(*) FILTER (WHERE vis.confirmada >= p.ini AND vis.confirmada < p.fim) AS visitas_confirmadas,
           count(*) FILTER (WHERE vis.estado NOT IN ('cancelada', 'expirada') AND vis.quando >= p.ini AND vis.quando < p.fim) AS visitas_agendadas_para,
           -- o resultado que a equipe marcou, pelo dia da visita, só das que já passaram (como o painel do Início)
           count(*) FILTER (WHERE vis.quando >= p.ini AND vis.quando < least(p.fim, now()) AND r.resultado IN ('realizada', 'fechou')) AS visitas_realizadas,
           count(*) FILTER (WHERE vis.quando >= p.ini AND vis.quando < least(p.fim, now()) AND r.resultado = 'fechou') AS visitas_fechou,
           count(*) FILTER (WHERE vis.quando >= p.ini AND vis.quando < least(p.fim, now()) AND r.resultado = 'desistiu') AS visitas_desistiu,
           count(*) FILTER (WHERE vis.quando >= p.ini AND vis.quando < least(p.fim, now()) AND r.resultado IS NULL) AS visitas_sem_resultado,
           max(vis.criado_em) AS ultima_visita_em
      FROM vis
      LEFT JOIN privado.visita_resultado r ON r.origem = vis.origem AND r.visita_id = vis.id, p
     GROUP BY vis.codigo
  ),
  -- cards: "vezes que o card foi enviado" = a mesma pessoa no mesmo dia conta uma vez (as várias fotos do card são uma só vez)
  s AS (
    SELECT codigo, chave_destino, enviado_em FROM nai_saida
     WHERE estado = 'enviado' AND codigo IS NOT NULL
    UNION ALL
    SELECT codigo, chave_destino, enviado_em FROM core_saida
     WHERE estado = 'enviado' AND codigo IS NOT NULL
  ),
  c_parceria AS (
    SELECT s.codigo,
           count(DISTINCT (s.chave_destino, (s.enviado_em AT TIME ZONE 'America/Manaus')::date)) AS cards_parceria,
           count(DISTINCT s.chave_destino) AS pessoas_parceria,
           max(s.enviado_em) AS ultimo_card_em
      FROM s, p
     WHERE s.enviado_em >= p.ini AND s.enviado_em < p.fim
       AND right(regexp_replace(s.chave_destino, '\D', '', 'g'), 8) <> ALL (p.interno)
     GROUP BY s.codigo
  ),
  c_leads AS (
    SELECT e.codigo, count(*) AS cards_leads, count(DISTINCT e.lead) AS pessoas_leads, max(e.enviado_em) AS ultimo_card_leads_em
      FROM privado.olx_cliente_enviada e
      JOIN privado.olx_lead_whatsapp w ON w.id = e.lead, p
     WHERE e.tipo = 'card' AND e.codigo IS NOT NULL AND e.enviado_em >= p.ini AND e.enviado_em < p.fim
       AND right(regexp_replace(coalesce(w.telefone, ''), '\D', '', 'g'), 8) <> ALL (p.interno)
     GROUP BY e.codigo
  ),
  c_publicador AS (
    SELECT e.codigo::int AS codigo,
           count(*) FILTER (WHERE e.destino = 'grupo') AS posts_grupo,
           count(*) FILTER (WHERE e.destino = 'corretor') AS envios_corretor
      FROM envios e, p
     WHERE e.codigo ~ '^[0-9]{1,9}$' AND e.enviado_em >= p.ini AND e.enviado_em < p.fim
     GROUP BY e.codigo::int
  ),
  -- quem chegou perguntando por este imóvel: OLX (WhatsApp Leads) e Chaves na Mão
  l_olx AS (
    SELECT w.codigo, count(*) AS leads_olx
      FROM privado.olx_lead_whatsapp w, p
     WHERE w.codigo IS NOT NULL AND w.criado_em >= p.ini AND w.criado_em < p.fim
       AND right(regexp_replace(coalesce(w.telefone, ''), '\D', '', 'g'), 8) <> ALL (p.interno)
     GROUP BY w.codigo
  ),
  l_cnm AS (
    SELECT l.codigo, count(*) AS leads_cnm
      FROM privado.cnm_lead l, p
     WHERE l.codigo IS NOT NULL AND l.recebido_em >= p.ini AND l.recebido_em < p.fim
     GROUP BY l.codigo
  ),
  -- onde o imóvel está anunciado agora: no feed do Chaves na Mão (cnm_imoveis) e publicado na OLX
  portais AS (
    SELECT c.codigo, true AS no_cnm FROM cnm_imoveis() c WHERE c.ok
  ),
  no_olx AS (
    SELECT a.codigo FROM privado.olx_anuncio a WHERE a.estado = 'publicado' GROUP BY a.codigo
  ),
  base AS (
    SELECT i.codigo, i.tipo, i.status, i.bairro, i.condominio_nome AS condominio, i.quartos, i.valor_venda, i.valor_aluguel,
           i.mobilia, i.origem, i.e_parceiro, i.captado_por, i.disponivel, i.publicado_no_site, i.criado_em,
           coalesce(vc.visitas_parceria, 0) AS visitas_parceria, coalesce(vc.visitas_leads, 0) AS visitas_leads,
           coalesce(vc.visitas_confirmadas, 0) AS visitas_confirmadas, coalesce(vc.visitas_agendadas_para, 0) AS visitas_agendadas_para,
           coalesce(vc.visitas_realizadas, 0) AS visitas_realizadas, coalesce(vc.visitas_fechou, 0) AS visitas_fechou,
           coalesce(vc.visitas_desistiu, 0) AS visitas_desistiu, coalesce(vc.visitas_sem_resultado, 0) AS visitas_sem_resultado,
           coalesce(cp.cards_parceria, 0) AS cards_parceria, coalesce(cp.pessoas_parceria, 0) AS pessoas_parceria,
           coalesce(cl.cards_leads, 0) AS cards_leads, coalesce(cl.pessoas_leads, 0) AS pessoas_leads,
           coalesce(pu.posts_grupo, 0) AS posts_grupo, coalesce(pu.envios_corretor, 0) AS envios_corretor,
           coalesce(lo.leads_olx, 0) AS leads_olx, coalesce(lc.leads_cnm, 0) AS leads_cnm,
           greatest(cp.ultimo_card_em, cl.ultimo_card_leads_em) AS ultimo_card_em, vc.ultima_visita_em,
           coalesce(po.no_cnm, false) AS no_cnm, (oo.codigo IS NOT NULL) AS no_olx
      FROM imoveis i
      LEFT JOIN portais po ON po.codigo = i.codigo
      LEFT JOIN no_olx oo ON oo.codigo = i.codigo
      LEFT JOIN v_conta vc ON vc.codigo = i.codigo
      LEFT JOIN c_parceria cp ON cp.codigo = i.codigo
      LEFT JOIN c_leads cl ON cl.codigo = i.codigo
      LEFT JOIN c_publicador pu ON pu.codigo = i.codigo
      LEFT JOIN l_olx lo ON lo.codigo = i.codigo
      LEFT JOIN l_cnm lc ON lc.codigo = i.codigo
  )
  SELECT jsonb_build_object(
    'de', p_de, 'ate', p_ate, 'gerado_em', now(),
    'imoveis', coalesce(jsonb_agg(jsonb_build_object(
        'codigo', b.codigo, 'tipo', b.tipo, 'status', b.status, 'bairro', b.bairro, 'condominio', b.condominio,
        'quartos', b.quartos, 'valor_venda', b.valor_venda, 'valor_aluguel', b.valor_aluguel, 'mobilia', b.mobilia,
        'origem', b.origem, 'parceiro', b.e_parceiro, 'captado_por', b.captado_por, 'disponivel', b.disponivel,
        'no_site', b.publicado_no_site, 'cadastrado_em', b.criado_em,
        'visitas_parceria', b.visitas_parceria, 'visitas_leads', b.visitas_leads,
        'visitas_confirmadas', b.visitas_confirmadas, 'visitas_agendadas_para', b.visitas_agendadas_para,
        'visitas_realizadas', b.visitas_realizadas, 'visitas_fechou', b.visitas_fechou,
        'visitas_desistiu', b.visitas_desistiu, 'visitas_sem_resultado', b.visitas_sem_resultado,
        'cards_parceria', b.cards_parceria, 'pessoas_parceria', b.pessoas_parceria,
        'cards_leads', b.cards_leads, 'pessoas_leads', b.pessoas_leads,
        'posts_grupo', b.posts_grupo, 'envios_corretor', b.envios_corretor,
        'leads_olx', b.leads_olx, 'leads_cnm', b.leads_cnm,
        'ultimo_card_em', b.ultimo_card_em, 'ultima_visita_em', b.ultima_visita_em,
        'no_cnm', b.no_cnm, 'no_olx', b.no_olx)
      ORDER BY (b.visitas_parceria + b.visitas_leads) DESC, (b.cards_parceria + b.cards_leads) DESC, b.codigo), '[]'::jsonb))
    FROM base b
   WHERE (b.visitas_parceria + b.visitas_leads + b.visitas_confirmadas + b.visitas_agendadas_para + b.visitas_realizadas
          + b.visitas_desistiu + b.visitas_sem_resultado + b.cards_parceria + b.cards_leads + b.posts_grupo
          + b.envios_corretor + b.leads_olx + b.leads_cnm) > 0
      OR (p_sem_atividade AND b.disponivel AND b.status = 'Disponível');
$function$;

REVOKE ALL ON FUNCTION public.site_imoveis_metricas(date, date, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.site_imoveis_metricas(date, date, boolean) TO nay_site_escrita;
COMMIT;
