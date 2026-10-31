-- 552: o turno de follow-up entra; caminho desconhecido continua barrado
SELECT pg_get_constraintdef(oid) AS restricao FROM pg_constraint WHERE conname = 'core_turno_caminho_check';
SAVEPOINT a;
INSERT INTO core_turno (chave, papel, texto, estado_antes, estado_depois, caminho, versao_regras, ms_total, fechado_em, modo)
VALUES ('teste552', 'followup', '[follow-up teste]', 'APRESENTADO', 'APRESENTADO', 'followup', 'teste', 0, now(), 'sombra');
SELECT 'followup entrou' AS caso;
ROLLBACK TO SAVEPOINT a;
DO $$ BEGIN
  INSERT INTO core_turno (chave, papel, texto, caminho, versao_regras, ms_total, modo)
  VALUES ('teste552', 'followup', 'x', 'inventado', 'teste', 0, 'sombra');
  RAISE EXCEPTION 'caminho inventado entrou: ERRO';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'caminho inventado barrado: ok';
END $$;
