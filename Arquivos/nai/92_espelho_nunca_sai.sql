-- =====================================================================
-- NAI -- 92: o espelho do treino nunca sai no WhatsApp (22/09/2026)
--
-- Com a Nay NO AR (envio_simulado = 'nao'), testar deixou de ser possivel: o
-- executor de treino exige a trava geral, e ligar a trava calaria a Nay para
-- os corretores de verdade.
--
-- A trava passa a ter duas fontes: a geral (`envio_simulado`) e o DESTINO.
-- Mensagem para o contato-espelho do treino (`nai_cfg('treino_espelho')`,
-- 559990000001 -- numero que nao existe em lugar nenhum) fica sempre em
-- 'simulado', com a Nay ligada ou desligada. Assim da para testar no ar sem
-- risco: o pior caso do espelho e uma linha no banco.
-- =====================================================================
\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE v_def text; v_novo text;
  a text := $a$  v_simulado boolean := nai_cfg('envio_simulado', 'nao') = 'sim';$a$;
BEGIN
  SELECT pg_get_functiondef('nai_liberar_saida'::regproc) INTO v_def;
  IF position('ESPELHO DO TREINO NUNCA SAI' IN v_def) > 0 THEN RAISE NOTICE 'ja aplicado'; RETURN; END IF;
  IF position(a IN v_def) = 0 THEN RAISE EXCEPTION 'o ponto de troca mudou -- confira nai_liberar_saida'; END IF;
  v_novo := replace(v_def, a, $b$  -- ESPELHO DO TREINO NUNCA SAI (92): a trava geral OU o destino ser o
  -- espelho. Com a Nay no ar, e o que permite testar sem calar ninguem.
  v_simulado boolean := nai_cfg('envio_simulado', 'nao') = 'sim'
                        OR nai_chave((SELECT c.telefone FROM nai_turno t
                                        JOIN nai_contato c ON c.id = t.contato_id
                                       WHERE t.id = p_turno))
                           = nai_chave(nai_cfg('treino_espelho', ''));$b$);
  EXECUTE v_novo;
END $$;
COMMIT;
