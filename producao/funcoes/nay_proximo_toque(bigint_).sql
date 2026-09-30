CREATE OR REPLACE FUNCTION public.nay_proximo_toque(p_ids bigint[])
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE n int;
BEGIN
  INSERT INTO contato_corretor (telefone, motivo, ref_id)
  SELECT DISTINCT telefone, 'lembrete', min(id) FROM lembrete
   WHERE id = ANY(p_ids) GROUP BY telefone;

  UPDATE lembrete SET
    estado = CASE WHEN tentativa >= 3 THEN 'escalado' ELSE 'agendado' END,
    motivo_fim = CASE WHEN tentativa >= 3
                      THEN 'tres toques sem retorno' END,
    -- 2o toque: 19:00 do mesmo dia. 3o: 09:00 do dia seguinte.
    disparar_em = CASE
      WHEN tentativa = 1 THEN
        date_trunc('day', now() AT TIME ZONE 'America/Manaus')
          AT TIME ZONE 'America/Manaus' + interval '19 hours'
      ELSE
        date_trunc('day', now() AT TIME ZONE 'America/Manaus')
          AT TIME ZONE 'America/Manaus' + interval '1 day 9 hours'
      END,
    atualizado_em = now()
  WHERE id = ANY(p_ids) AND estado = 'enviado';
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$function$;
