-- 333 -- A visita cujo DIA já passou fecha sozinha e para de contar como aberta
--
-- Pedro, 09/10/2026: "as visitas dos dias que já passaram devem ser excluídas, e não contarem lá como visitas lá
-- onde tem 20 visitas".
--
-- O que acontecia: desde a 199 a visita confirmada passa para a equipe no estado `com_rayssa`, e esse é o único
-- estado que a agenda (`nai_agenda_tick`) nunca fecha -- só sai dele quando alguém clica "realizada" ou exclui.
-- Medido em 09/10: 21 visitas abertas, 12 delas de dias que já passaram (a mais antiga de 02/10). É esse número
-- que aparece na aba "Visitas agendadas" da Parceria.
--
-- A regra: visita `com_rayssa` cujo dia (em Manaus) já passou vira `encerrada`, com o motivo escrito. Ninguém é
-- avisado: nenhuma mensagem sai, e o que ainda estivesse na fila sobre ela é barrado. Ela continua no histórico
-- (na agenda, voltando aos dias passados) -- só deixa de ser "aberta". A de HOJE não é tocada: a equipe ainda pode
-- marcar "realizada" no mesmo dia.
--
-- Roda dentro do `nai_agenda_tick`, que já passa a cada poucos segundos: à meia-noite de Manaus as de ontem fecham.
BEGIN;
SET LOCAL lock_timeout = '3s';

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

-- a agenda chama a regra a cada passada (depois do portão do modo, antes de olhar as visitas abertas)
DO $mig$
DECLARE
  v_def   text := pg_get_functiondef('public.nai_agenda_tick()'::regprocedure);
  v_velho text := $v$  IF nai_cfg('modo', 'desligado') NOT IN ('teste', 'todos') THEN RETURN 0; END IF;$v$;
  v_novo  text := $n$  IF nai_cfg('modo', 'desligado') NOT IN ('teste', 'todos') THEN RETURN 0; END IF;

  -- 333: a visita com a equipe cujo DIA já passou fecha sozinha (não fica contando como aberta)
  n := n + nai_visitas_fechar_dia_passado();$n$;
BEGIN
  IF position('nai_visitas_fechar_dia_passado' IN v_def) > 0 THEN
    RAISE EXCEPTION '333: já aplicada';
  END IF;
  IF (length(v_def) - length(replace(v_def, v_velho, ''))) / length(v_velho) <> 1 THEN
    RAISE EXCEPTION '333: o trecho de nai_agenda_tick mudou no banco; leia a função viva antes';
  END IF;
  EXECUTE replace(v_def, v_velho, v_novo);
END
$mig$;

-- as que já estavam vencidas fecham agora
SELECT nai_visitas_fechar_dia_passado() AS visitas_de_dias_passados_fechadas;

COMMIT;
