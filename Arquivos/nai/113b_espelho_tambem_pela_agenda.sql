-- =====================================================================
-- NAI -- 113b: o espelho nao sai NEM pela agenda (23/09/2026)
--
-- ACHADO testando a 113. As duas mensagens que ficaram esperando as fotos
-- sairam pela AGENDA (o tique de cada minuto) e sairam como "enviado", nao
-- como "simulado" -- para o numero do espelho de treino.
--
-- POR QUE: a trava da 92 e calculada UMA VEZ, no comeco da funcao, a partir do
-- turno que veio por parametro. A agenda chama sem turno (`p_turno IS NULL`),
-- entao a subconsulta nao acha ninguem, a trava da falso e o espelho deixa de
-- ser espelho.
--
-- Nao fez estrago -- o espelho e um numero que nao existe --, mas a trava tem
-- que valer SEMPRE, e agora que mais mensagens passam pela agenda (as que
-- esperam as fotos) ela passaria a valer cada vez menos.
--
-- AGORA E POR LINHA: cada mensagem pergunta pelo SEU proprio destino.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

DO $mig$
DECLARE v_def text; v_alvo text;
BEGIN
  v_def := pg_get_functiondef('nai_liberar_saida'::regproc);
  IF position('v_simulado_linha' IN v_def) > 0 THEN
    RAISE NOTICE 'a trava do espelho ja e por linha'; RETURN;
  END IF;

  -- 1. a variavel por linha, ao lado das outras
  v_alvo := '  v_cmd      boolean;   -- e a resposta a um comando de quem pode comandar?';
  IF position(v_alvo IN v_def) = 0 THEN RAISE EXCEPTION 'nao achei o v_cmd'; END IF;
  v_def := replace(v_def, v_alvo, v_alvo || E'\n'
    || '  v_simulado_linha boolean;   -- a trava do espelho, calculada por MENSAGEM (113b)');

  -- 2. calculada logo depois de saber o destino da linha
  v_alvo := '    v_cmd := r.motivo = ''comando_tel'' AND r.papel_destino = ''turno''';
  IF position(v_alvo IN v_def) = 0 THEN RAISE EXCEPTION 'nao achei o calculo do v_cmd'; END IF;
  v_def := replace(v_def, v_alvo,
       '    -- O ESPELHO NUNCA SAI (92), agora conferido NESTA mensagem: pela' || E'\n'
    || '    -- agenda nao existe turno, e a trava calculada no topo dava falso.' || E'\n'
    || '    v_simulado_linha := v_simulado' || E'\n'
    || '      OR nai_chave(v_tel) = nai_chave(nai_cfg(''treino_espelho'', ''''))' || E'\n'
    || '      OR nai_chave(v_chave_c) = nai_chave(nai_cfg(''treino_espelho'', ''''));' || E'\n' || E'\n'
    || v_alvo);

  -- 3. quem manda na hora de soltar e a trava da linha
  v_alvo := '    IF v_simulado THEN';
  IF position(v_alvo IN v_def) = 0 THEN RAISE EXCEPTION 'nao achei o uso da trava'; END IF;
  v_def := replace(v_def, v_alvo, '    IF v_simulado_linha THEN');

  EXECUTE v_def;
  RAISE NOTICE 'trava do espelho agora e por mensagem';
END $mig$;

COMMIT;
