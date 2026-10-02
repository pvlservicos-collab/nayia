-- 276 (02/10/2026): "TÁ ABERTO PARA VISITA?" É PERGUNTA DE DISPONIBILIDADE.
--
-- Lógica de atendimento do Tel (02/10), "palavras variadas para perguntar se está disponível":
--   - ainda está disponível?   - tá aberto para visita?   - tem como visitar?   - ainda tá valendo?
--
-- A porta (269/270) deixa com a Nay velha toda mensagem que fala de visita, porque a visita ainda
-- mora no sistema velho. Com isso "tá aberto para visita?" e "tem como visitar?" nem chegavam ao
-- núcleo novo, que é quem responde o corretor desde 02/10.
--
-- Agora: a pergunta de disponibilidade dita com a palavra visita, SEM dia, hora ou pedido de
-- agendar, vai para o núcleo novo (que responde "Sim, está disponível" e oferece o card e as fotos).
-- Pedido de visita de verdade ("posso visitar amanhã às 10h?", "quero agendar") continua no velho.
-- Quem já tem visita em andamento também continua no velho (a condição seguinte da porta).
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION public.nai_pergunta_se_da_para_visitar(p_texto text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT t ~ '(abert[oa] (para|pra|a) visita|tem como visitar|da (para|pra) visitar|liberad[oa] (para|pra|a) visita)'
     AND t !~ '(\mhoje\M|\mamanha\M|segunda|terca|quarta|quinta|sexta|sabado|domingo|\d\s*h\M|\d:\d\d|\mas \d|agendar|agenda\M|marcar|horario|que horas|\mdia \d)'
    FROM (SELECT public.nay_sem_acento(lower(coalesce(p_texto, ''))) AS t) x;
$function$;

COMMENT ON FUNCTION public.nai_pergunta_se_da_para_visitar(text) IS
  '276: "tá aberto para visita?", "tem como visitar?" sem dia nem hora é pergunta de disponibilidade, não pedido de visita.';

-- a porta: patch na função VIVA (o banco está à frente dos .sql)
DO $patch$
DECLARE
  v_def  text := pg_get_functiondef('public.nai_core_atende(bigint,text)'::regprocedure);
  v_novo text;
BEGIN
  v_novo := replace(v_def,
    'desmarcar)\M'' THEN false',
    'desmarcar)\M'' AND NOT public.nai_pergunta_se_da_para_visitar(p_texto) THEN false');
  IF v_novo = v_def THEN
    RAISE EXCEPTION '276: não achei a linha das palavras de visita em nai_core_atende';
  END IF;
  EXECUTE v_novo;
END
$patch$;

COMMIT;
