CREATE OR REPLACE FUNCTION public.nai_visitas_fechar_dia_passado()
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  v      record;
  n      int := 0;
  v_hoje date := (now() AT TIME ZONE 'America/Manaus')::date;
BEGIN
  FOR v IN
    SELECT x.id FROM nai_visita x
     WHERE x.estado = 'com_rayssa' AND x.excluida_em IS NULL AND x.quando IS NOT NULL
       AND (x.quando AT TIME ZONE 'America/Manaus')::date < v_hoje
     ORDER BY x.quando
       FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE nai_visita
       SET estado = 'encerrada', aguardando = NULL, senha = NULL,
           encerrada_em = now(), atualizado_em = now(),
           motivo = coalesce(motivo, 'Fechada sozinha: o dia da visita passou')
     WHERE id = v.id;
    -- o que a Nay ainda fosse mandar sobre ela não sai mais (ninguém é avisado)
    UPDATE nai_saida SET estado = 'bloqueado', bloqueio = 'o dia da visita passou'
     WHERE visita_id = v.id AND estado = 'pendente';
    PERFORM nai_evento(v.id, 'fechada_pelo_dia', 'o dia da visita passou sem ninguém marcar o resultado');
    PERFORM nai_liberar_chats_da_visita(v.id);
    n := n + 1;
  END LOOP;
  RETURN n;
END
$function$;
