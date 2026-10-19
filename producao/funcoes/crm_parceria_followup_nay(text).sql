CREATE OR REPLACE FUNCTION public.crm_parceria_followup_nay(p_telefone text)
 RETURNS TABLE(estado text, quando timestamp with time zone, mensagem text, motivo text, codigos integer[])
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  ), recebeu AS (     -- o dia em que recebeu imóvel (de anteontem a hoje), em Manaus
    SELECT (e.primeiro_em AT TIME ZONE 'America/Manaus')::date AS dia, array_agg(DISTINCT e.codigo ORDER BY e.codigo) AS codigos
      FROM imovel_enviado_no_dia e, p, cfg
     WHERE e.chave = ANY (p.chaves)
       AND (e.primeiro_em AT TIME ZONE 'America/Manaus')::date BETWEEN cfg.hoje - 2 AND cfg.hoje
     GROUP BY 1
  ), rodada AS (     -- 415: a rodada que pega cada dia: o dia seguinte; o sábado vai para a segunda (domingo não roda)
    SELECT r.*, CASE WHEN extract(isodow FROM r.dia + 1) = 7 THEN r.dia + 2 ELSE r.dia + 1 END AS dia_da_rodada
      FROM recebeu r
  ), previsto AS (
    SELECT 'previsto'::text AS estado,
           greatest(now(), (r.dia_da_rodada + cfg.ini) AT TIME ZONE 'America/Manaus') AS quando,
           (SELECT t FROM texto) AS mensagem,
           'a Nay confere na hora: pula se ele já conversou no dia, recusou, tem visita aberta ou está com o Tel'::text AS motivo,
           r.codigos
      FROM rodada r, cfg, p
     WHERE cfg.ligado
       AND NOT EXISTS (SELECT 1 FROM nai_followup f WHERE f.chave = ANY (p.chaves) AND f.dia_recebeu >= r.dia)
       AND (r.dia_da_rodada > cfg.hoje OR (r.dia_da_rodada = cfg.hoje AND cfg.hora <= cfg.fim))
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
