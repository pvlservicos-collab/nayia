-- testes da 503 (rodam dentro do ensaio, antes do ROLLBACK)
\pset footer off
SELECT 'horario 07:45' t, * FROM captacao_py_horario('2026-10-27 07:45'::timestamp AT TIME ZONE 'America/Manaus');
SELECT 'horario 18:40' t, * FROM captacao_py_horario('2026-10-27 18:40'::timestamp AT TIME ZONE 'America/Manaus');
SELECT 'horario 10:00 (vazio)' t, count(*) FROM captacao_py_horario('2026-10-27 10:00'::timestamp AT TIME ZONE 'America/Manaus');
SELECT x.hm, captacao_py_no_horario((('2026-10-27 ' || x.hm)::timestamp) AT TIME ZONE 'America/Manaus') AS pode
  FROM (VALUES ('07:29'), ('07:30'), ('09:29'), ('09:30'), ('13:00'), ('18:29'), ('18:30'), ('20:29'), ('20:30')) x(hm);
SELECT 'domingo 01/11 07:45' t, captacao_py_no_horario('2026-11-01 07:45'::timestamp AT TIME ZONE 'America/Manaus');
SELECT 'motivo agora' t, captacao_py_disparo_motivo();
\timing on
SELECT 'crm' t, crm_captacao_disparo_oficial() ->> 'motivo' motivo,
       (crm_captacao_disparo_oficial() ->> 'volta_em')::timestamptz AT TIME ZONE 'America/Manaus' AS volta_em_manaus;
\timing off
SELECT 'metades da fila' t, count(*) FILTER (WHERE f.id % 2 = 0) AS manha_0730, count(*) FILTER (WHERE f.id % 2 = 1) AS noite_1830
  FROM captacao_py_fila_do_disparo() f(id);
-- o lote: 125 disparos de mentira às 07:30 fecham o horário da manhã, não o da noite
INSERT INTO captacao_mensagens (lead_id, telefone, direcao, origem, texto, status, criada_em)
SELECT NULL, '5592000000000', 'enviada', 'disparo', 'ensaio 503', 'enviada',
       ('2026-10-27 07:30'::timestamp AT TIME ZONE 'America/Manaus') + make_interval(secs => g * 30)
  FROM generate_series(1, 125) g;
SELECT 'lote cheio 08:45' t, captacao_py_no_horario('2026-10-27 08:45'::timestamp AT TIME ZONE 'America/Manaus') AS pode,
       'noite 18:31' t2, captacao_py_no_horario('2026-10-27 18:31'::timestamp AT TIME ZONE 'America/Manaus') AS pode2;
SELECT * FROM captacao_py_horarios_placar();
