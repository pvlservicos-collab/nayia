-- dentro do ensaio (ROLLBACK no fim). Nada disto sai nem fica.
-- 1. depois da migração: quantos corretores/parceiros ficaram marcados e quantos continuam expostos
SELECT count(*) FILTER (WHERE humano_motivo LIKE 'fora da captação:%') AS a_marcados_agora,
       count(*) FILTER (WHERE captacao_fora_da_campanha(id) IS NOT NULL AND humano_assumiu_em IS NULL
                          AND status IN ('novo', 'erro', 'reservado', 'enviado', 'respondendo')) AS a_ainda_expostos_esperado_0,
       count(*) FILTER (WHERE status IN ('novo', 'erro') AND humano_assumiu_em IS NULL AND NOT opt_out) AS a_fila_que_sobra
  FROM captacao_leads;
SELECT humano_motivo, count(*) FROM captacao_leads WHERE humano_motivo LIKE 'fora da captação:%' GROUP BY 1;

-- 2. o telefone de teste da campanha continua conversando
SELECT l.id AS lead_de_teste, captacao_fora_da_campanha(l.id) AS b_motivo_esperado_vazio
  FROM captacao_leads l
 WHERE right(l.telefone, 8) = right(regexp_replace(coalesce((SELECT valor FROM captacao_config WHERE chave = 'telefone_teste'), ''), '\D', '', 'g'), 8);

-- 3. a RESERVA, do jeito que o nó "Pegar lead novo" faz: um corretor da fila, com a marca tirada só para o teste
UPDATE captacao_leads SET humano_assumiu_em = NULL, humano_motivo = NULL WHERE id = 737;
WITH alvo AS (SELECT l.id FROM captacao_leads l WHERE l.id = 737 FOR UPDATE SKIP LOCKED),
     reservado AS (UPDATE captacao_leads l SET status = 'reservado', atualizado_em = now() FROM alvo WHERE l.id = alvo.id
                   RETURNING l.id)
SELECT count(*) AS c_linhas_reservadas_esperado_0 FROM reservado;
SELECT status AS c_status_continua_novo, humano_assumiu_em IS NOT NULL AS c_marcado, humano_motivo
  FROM captacao_leads WHERE id = 737;

-- 4. um proprietário de verdade da fila é reservado normalmente
CREATE TEMP TABLE _dono ON COMMIT DROP AS
SELECT l.id FROM captacao_leads l
 WHERE l.status = 'novo' AND l.humano_assumiu_em IS NULL AND NOT l.opt_out AND captacao_fora_da_campanha(l.id) IS NULL
 ORDER BY l.id LIMIT 1;
WITH reservado AS (UPDATE captacao_leads l SET status = 'reservado', atualizado_em = now() FROM _dono d WHERE l.id = d.id
                   RETURNING l.id)
SELECT count(*) AS d_linhas_reservadas_esperado_1 FROM reservado;

-- 5. a IA da captação: não responde o corretor que estava conversando com ela; responde o proprietário
SELECT l.id, right(l.telefone, 4) AS fim, captacao_fora_da_campanha(l.id) IS NOT NULL AS e_corretor,
       captacao_ainda_e_da_ia(l.telefone) AS e_ia_responde
  FROM captacao_leads l
 WHERE l.id IN (725, 693) OR l.id = (SELECT x.id FROM captacao_leads x
                                      WHERE x.status = 'respondendo' AND x.humano_assumiu_em IS NULL
                                        AND captacao_fora_da_campanha(x.id) IS NULL ORDER BY x.id DESC LIMIT 1)
 ORDER BY 3 DESC, 1;
