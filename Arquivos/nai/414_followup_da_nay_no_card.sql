-- 414: o FOLLOW-UP DA NAY aparece no card do contato da Parceria (19/10/2026)
--
-- Pedro: "quero que se a Nay já tiver agendado um follow-up para aquele lead, apareça ali como criado pela Nay também".
--
-- A Nay não guarda o follow-up com antecedência: nai_followup_rodar (dentro do nai_agenda_tick) decide na hora, de
-- segunda a sábado entre followup_inicio e followup_fim (09:00-18:00), para quem RECEBEU imóvel no dia anterior
-- (imovel_enviado_no_dia), e grava em nai_followup o que mandou ou por que pulou. Esta função devolve, para um
-- telefone (com as duas linhas da pessoa, crm_pessoas):
--   'previsto' -- recebeu imóvel hoje (sai amanhã às 09:00, se amanhã não é domingo) ou ontem e a rodada de hoje
--                 ainda não passou por ele. É previsão: na hora ela pula se ele já conversou no dia, recusou, tem
--                 visita aberta, o Tel está com a conversa ou o Tel disse que não é corretor.
--   'enviado' / 'pulado' -- os últimos 5 de nai_followup, com o motivo do pulo.
-- Só leitura; o CRM chama pelo papel nay_disparo.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION public.crm_parceria_followup_nay(p_telefone text)
RETURNS TABLE(estado text, quando timestamptz, mensagem text, motivo text, codigos integer[])
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $function$
  WITH p AS (
    SELECT pe.contato_id, pe.chaves FROM crm_pessoas(ARRAY[p_telefone]) pe LIMIT 1
  ), cfg AS (
    SELECT (now() AT TIME ZONE 'America/Manaus')::date AS hoje,
           (now() AT TIME ZONE 'America/Manaus')::time AS hora,
           nai_cfg('followup_inicio', '09:00')::time AS ini,
           nai_cfg('followup_fim', '18:00')::time AS fim,
           nai_cfg('followup_ligado', 'nao') = 'sim' AND nai_cfg('pausada', 'sim') = 'nao'
             AND nai_cfg('modo', 'desligado') = 'todos' AS ligado
  ), nome AS (
    SELECT nai_vocativo(coalesce(k.nome_completo, k.nome_whatsapp)) AS v
      FROM p JOIN nai_contato k ON k.id = p.contato_id
  ), texto AS (
    SELECT 'Oi' || coalesce(' ' || (SELECT v FROM nome), '') || ', seu cliente tem interesse?' || E'\n'
           || coalesce((SELECT v FROM nome) || ', q', 'Q')
           || 'ualquer coisa temos muitas opções de imóveis para locação e venda, o que está procurando para seus clientes?'
           AS t
  ), recebeu AS (     -- o dia em que recebeu imóvel (hoje ou ontem), em Manaus
    SELECT (e.primeiro_em AT TIME ZONE 'America/Manaus')::date AS dia, array_agg(DISTINCT e.codigo ORDER BY e.codigo) AS codigos
      FROM imovel_enviado_no_dia e, p, cfg
     WHERE e.chave = ANY (p.chaves)
       AND (e.primeiro_em AT TIME ZONE 'America/Manaus')::date IN (cfg.hoje, cfg.hoje - 1)
     GROUP BY 1
  ), previsto AS (
    SELECT 'previsto'::text AS estado,
           CASE WHEN r.dia = cfg.hoje THEN ((cfg.hoje + 1) + cfg.ini) AT TIME ZONE 'America/Manaus'
                ELSE greatest(now(), (cfg.hoje + cfg.ini) AT TIME ZONE 'America/Manaus') END AS quando,
           (SELECT t FROM texto) AS mensagem,
           'a Nay confere na hora: pula se ele já conversou no dia, recusou, tem visita aberta ou está com o Tel'::text AS motivo,
           r.codigos
      FROM recebeu r, cfg, p
     WHERE cfg.ligado
       AND NOT EXISTS (SELECT 1 FROM nai_followup f WHERE f.chave = ANY (p.chaves) AND f.dia_recebeu = r.dia)
       AND (   (r.dia = cfg.hoje AND extract(isodow FROM cfg.hoje + 1) <> 7)
            OR (r.dia = cfg.hoje - 1 AND extract(isodow FROM cfg.hoje) <> 7 AND cfg.hora <= cfg.fim))
  ), feitos AS (
    SELECT f.estado, f.criado_em AS quando,
           CASE WHEN f.estado = 'enviado' THEN (SELECT t FROM texto) END AS mensagem,
           f.motivo, f.codigos
      FROM nai_followup f, p
     WHERE f.chave = ANY (p.chaves)
     ORDER BY f.criado_em DESC
     LIMIT 5
  )
  SELECT * FROM previsto
  UNION ALL
  SELECT * FROM feitos
$function$;
COMMENT ON FUNCTION public.crm_parceria_followup_nay(text) IS
  '414: o follow-up da Nay para o card da Parceria: previsto (pela regra do nai_followup_rodar) e os últimos feitos.';
REVOKE ALL ON FUNCTION public.crm_parceria_followup_nay(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.crm_parceria_followup_nay(text) TO nay_disparo;

COMMIT;
