-- dentro do ensaio (ROLLBACK no fim): um corretor de verdade que o núcleo atendeu nos últimos dias, sem marca nenhuma.
-- Nada disto sai nem fica: turno, mensagem, marca e instrução são desfeitos junto com a transação.
CREATE TEMP TABLE _t303 ON COMMIT DROP AS
SELECT k.id AS contato, k.chave, k.telefone, coalesce(nai_contato_irmaos(k.id), ARRAY[k.id]) AS ids,
       (SELECT i.codigo FROM imoveis i
         WHERE i.disponivel AND NOT i.e_parceiro AND i.codigo BETWEEN 1000 AND 99999 ORDER BY i.codigo DESC LIMIT 1) AS codigo
  FROM nai_contato k
 WHERE k.chave ~ '^55' AND k.humano_assumiu_em IS NULL
   AND k.id IN (SELECT t.contato_id FROM nai_core_turno c JOIN nai_turno t ON t.id = c.turno_id
                 WHERE c.criado_em > now() - interval '4 days')
   AND NOT nai_tel_com_a_conversa(k.id) AND nai_com_a_rayssa(k.id, 'corretor') IS NULL
   AND nai_core_atende(k.id, 'tem apartamento no parque 10?')
 ORDER BY k.id DESC LIMIT 1;

SELECT right(chave, 4) AS corretor_fim, cardinality(ids) AS linhas, codigo AS imovel FROM _t303;

-- A. INSTRUÇÃO: sem ela o núcleo atende; com ela valendo, fica com a velha; vencida, volta
SELECT nai_core_atende(contato, 'tem apartamento no parque 10?') AS a1_sem_instrucao_nucleo_atende_esperado_t FROM _t303;
INSERT INTO nai_instrucao (contato_id, texto, criado_por) SELECT contato, 'teste 303: cliente quer casa no Tarumã', 'teste' FROM _t303;
SELECT nai_core_atende(contato, 'tem apartamento no parque 10?') AS a2_com_instrucao_nucleo_atende_esperado_f,
       left(nai_instrucao_texto(contato), 40) AS a2_a_velha_le
  FROM _t303;
-- a porta inteira: com a instrução valendo o turno NÃO vai para o núcleo e o cabeçalho leva a instrução
CREATE TEMP TABLE _r303i ON COMMIT DROP AS
SELECT nai_abrir_turno(telefone, NULL, 'tem apartamento no parque 10?', NULL, '{}'::bigint[]) AS r FROM _t303;
SELECT r ->> 'ok' AS a2_ok, coalesce(r ->> 'motivo', '-') AS a2_motivo_nao_e_core_atende,
       (r ->> 'contexto') LIKE 'INSTRUÇÃO DA EQUIPE%' AS a2_cabecalho_leva_a_instrucao
  FROM _r303i;
UPDATE nai_instrucao SET valido_ate = now() - interval '1 minute' WHERE criado_por = 'teste' AND texto LIKE 'teste 303%';
SELECT nai_core_atende(contato, 'tem apartamento no parque 10?') AS a3_instrucao_vencida_nucleo_atende_esperado_t FROM _t303;

-- B. A PAUSA: a Nay nova escalou a dúvida (marca nas linhas da pessoa) e GENTE respondeu há 2 minutos
UPDATE nai_contato SET humano_assumiu_em = now() - interval '5 minutes',
                       humano_motivo = 'duvida fora da base (nay-core): teste 303'
 WHERE id = ANY ((SELECT ids FROM _t303)::bigint[]);
INSERT INTO mensagens (telefone, direcao, origem, texto, status, message_id, criada_em, fluxo)
SELECT telefone, 'enviada', 'texto', 'já te respondo', 'Enviado', 'TESTE303GENTE', now() - interval '2 minutes', 'nai' FROM _t303;
SELECT nai_gente_escreveu_ha_pouco(ids) AS b1_gente_ha_pouco_esperado_t FROM _t303;

-- o corretor cita OUTRO imóvel: antes a 240 soltava; agora a porta segura ("Com o Tel")
CREATE TEMP TABLE _r303a ON COMMIT DROP AS
SELECT nai_abrir_turno(telefone, NULL, 'me fala do ' || codigo, NULL, '{}'::bigint[]) AS r FROM _t303;
SELECT r ->> 'ok' AS b2_ok, r ->> 'motivo' AS b2_motivo_esperado_tel_assumiu FROM _r303a;
SELECT count(*) FILTER (WHERE k.humano_assumiu_em IS NOT NULL) AS b2_linhas_ainda_marcadas, count(*) AS de
  FROM nai_contato k WHERE k.id = ANY ((SELECT ids FROM _t303)::bigint[]);

-- a mesma mensagem com a de gente há 40 minutos: a 240 solta como sempre soltou
UPDATE mensagens SET criada_em = now() - interval '40 minutes' WHERE message_id = 'TESTE303GENTE';
SELECT nai_gente_escreveu_ha_pouco(ids) AS b3_gente_ha_pouco_esperado_f FROM _t303;
CREATE TEMP TABLE _r303b ON COMMIT DROP AS
SELECT nai_abrir_turno(telefone, NULL, 'me fala do ' || codigo, NULL, '{}'::bigint[]) AS r FROM _t303;
SELECT r ->> 'ok' AS b3_ok, r ->> 'motivo' AS b3_motivo_esperado_core_atende FROM _r303b;
SELECT count(*) FILTER (WHERE k.humano_assumiu_em IS NOT NULL) AS b3_linhas_ainda_marcadas_esperado_0, count(*) AS de
  FROM nai_contato k WHERE k.id = ANY ((SELECT ids FROM _t303)::bigint[]);

-- eco de robô não é gente: uma mensagem que a caixa do núcleo mandou, trazida para 1 minuto atrás, não segura a 240
CREATE TEMP TABLE _eco ON COMMIT DROP AS
SELECT m.id AS msg, k.id AS contato
  FROM core_saida s
  JOIN mensagens m ON m.message_id = s.message_id AND m.direcao = 'enviada'
  JOIN nai_contato k ON k.chave = nai_chave(m.telefone)
 WHERE s.estado = 'enviado' AND s.message_id IS NOT NULL
 ORDER BY s.id DESC LIMIT 1;
UPDATE mensagens SET criada_em = now() - interval '1 minute' WHERE id = (SELECT msg FROM _eco);
SELECT nai_gente_escreveu_ha_pouco(ARRAY[contato]) AS b4_eco_do_nucleo_e_gente_esperado_f FROM _eco;
