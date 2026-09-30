CREATE OR REPLACE FUNCTION public.crm_painel_nay()
 RETURNS TABLE(respostas_hoje integer, respostas_ontem integer, respostas_1h integer, ultima_resposta timestamp with time zone, corretores_hoje integer, corretores_ontem integer, imoveis_hoje integer, imoveis_ontem integer, visitas_hoje integer, visitas_abertas integer, visitas_confirmadas integer, turnos_hoje integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET jit TO 'off'
AS $function$
  WITH t AS (
    SELECT (date_trunc('day', now() AT TIME ZONE 'America/Manaus') AT TIME ZONE 'America/Manaus') AS hoje
  ), resp AS (
    SELECT s.enviado_em, s.tipo, s.texto
      FROM nai_saida s, t
     WHERE s.estado = 'enviado'
       AND s.papel_destino IN ('turno', 'corretor', 'entrega', 'seguimento')
       AND s.enviado_em >= t.hoje - interval '1 day'
  ), tur AS (
    SELECT tu.contato_id, tu.criado_em FROM nai_turno tu, t
     WHERE tu.criado_em >= t.hoje - interval '1 day' AND NOT coalesce(tu.teste, false)
  )
  SELECT
    (SELECT count(*) FROM resp, t WHERE resp.enviado_em >= t.hoje)::int,
    (SELECT count(*) FROM resp, t WHERE resp.enviado_em < now() - interval '1 day')::int,
    (SELECT count(*) FROM resp WHERE resp.enviado_em >= now() - interval '1 hour')::int,
    (SELECT max(s.enviado_em) FROM nai_saida s WHERE s.estado = 'enviado' AND s.papel_destino IN ('turno', 'corretor', 'entrega', 'seguimento')
                                                AND s.enviado_em >= now() - interval '2 days'),
    (SELECT count(DISTINCT tur.contato_id) FROM tur, t WHERE tur.criado_em >= t.hoje)::int,
    (SELECT count(DISTINCT tur.contato_id) FROM tur WHERE tur.criado_em < now() - interval '1 day')::int,
    (SELECT count(*) FROM resp, t WHERE resp.enviado_em >= t.hoje AND resp.tipo = 'texto' AND resp.texto ~ 'C[óo]digo:\s*#?\d{2,5}')::int,
    (SELECT count(*) FROM resp WHERE resp.enviado_em < now() - interval '1 day' AND resp.tipo = 'texto' AND resp.texto ~ 'C[óo]digo:\s*#?\d{2,5}')::int,
    (SELECT count(*) FROM nai_visita v, t WHERE v.excluida_em IS NULL AND v.quando >= t.hoje AND v.quando < t.hoje + interval '1 day'
                                            AND v.estado NOT IN ('cancelada', 'expirada', 'coletando'))::int,
    (SELECT count(*) FROM nai_visita v WHERE v.excluida_em IS NULL
                                        AND v.estado NOT IN ('realizada', 'encerrada', 'cancelada', 'expirada', 'coletando'))::int,
    (SELECT count(*) FROM nai_visita v WHERE v.excluida_em IS NULL AND v.estado = 'confirmada')::int,
    (SELECT count(*) FROM tur, t WHERE tur.criado_em >= t.hoje)::int
  FROM t
$function$;
