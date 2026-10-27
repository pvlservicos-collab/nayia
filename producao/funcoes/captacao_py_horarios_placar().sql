CREATE OR REPLACE FUNCTION public.captacao_py_horarios_placar()
 RETURNS TABLE(horario text, enviados bigint, responderam bigint, pct_resposta numeric, pediram_sair bigint, minutos_ate_responder_mediana numeric)
 LANGUAGE sql
 STABLE
AS $function$
  WITH d AS (
    SELECT m.lead_id, m.criada_em, (SELECT h.hora FROM captacao_py_horario(m.criada_em) h) AS hora,
           (SELECT min(r.criada_em) FROM captacao_mensagens r
             WHERE r.lead_id = m.lead_id AND r.direcao = 'recebida'
               AND r.criada_em > m.criada_em AND r.criada_em < m.criada_em + interval '24 hours') AS resposta_em
      FROM captacao_mensagens m
     WHERE m.direcao = 'enviada' AND m.origem = 'disparo' AND m.status <> 'Falhou'
       AND m.criada_em >= (captacao_cfg('python_horarios_desde', '2026-10-26 23:00')::timestamp AT TIME ZONE 'America/Manaus')
  )
  SELECT coalesce(d.hora, 'fora dos horários'), count(*), count(d.resposta_em),
         round(100.0 * count(d.resposta_em) / nullif(count(*), 0), 1),
         count(*) FILTER (WHERE l.opt_out),
         round((percentile_cont(0.5) WITHIN GROUP (ORDER BY extract(epoch FROM d.resposta_em - d.criada_em) / 60))::numeric, 0)
    FROM d LEFT JOIN captacao_leads l ON l.id = d.lead_id
   GROUP BY d.hora
   ORDER BY d.hora;
$function$;
