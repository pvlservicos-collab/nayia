-- dentro do ensaio (ROLLBACK no fim): um corretor de verdade que o núcleo atendeu nos últimos dias, sem marca nenhuma,
-- recebe uma instrução pelo caminho do CRM. Nada disto sai nem fica.
CREATE TEMP TABLE _t304 ON COMMIT DROP AS
SELECT k.id AS contato, k.chave, k.telefone
  FROM nai_contato k
 WHERE k.chave ~ '^55' AND k.humano_assumiu_em IS NULL
   AND k.id IN (SELECT t.contato_id FROM nai_core_turno c JOIN nai_turno t ON t.id = c.turno_id
                 WHERE c.criado_em > now() - interval '4 days')
   AND NOT nai_tel_com_a_conversa(k.id) AND nai_com_a_rayssa(k.id, 'corretor') IS NULL
   AND nai_core_atende(k.id, 'tem apartamento no parque 10?')
 ORDER BY k.id DESC LIMIT 1;
-- a chave do corretor do teste numa variável da transação: o papel do núcleo não lê a tabela temporária
SELECT set_config('teste304.chave', (SELECT chave FROM _t304), true) IS NOT NULL AS preparado;

INSERT INTO nai_instrucao (contato_id, texto, criado_por)
SELECT contato, 'teste 304: ele pediu o card e as fotos do 2944', 'teste' FROM _t304;

-- 1. com a instrução valendo o turno VAI para o núcleo (na 303 ficava com a velha)
SELECT right(chave, 4) AS corretor_fim,
       nai_core_atende(contato, 'tem apartamento no parque 10?') AS a1_nucleo_atende_esperado_t
  FROM _t304;
SELECT r ->> 'ok' AS a2_ok, r ->> 'motivo' AS a2_motivo_esperado_core_atende
  FROM _t304 p, LATERAL nai_abrir_turno(p.telefone, NULL, 'tem apartamento no parque 10?', NULL, '{}'::bigint[]) r;

-- 2. o núcleo enxerga a instrução pendente, com o papel dele e a consulta dele (nay-core, nay/instrucao/repo.py)
SET LOCAL ROLE nay_core;
SELECT current_user AS papel, count(*) AS b1_pendentes_para_o_nucleo_esperado_1, min(left(i.texto, 30)) AS b1_texto
  FROM nai_instrucao i
 WHERE i.valido_ate > now()
   AND i.contato_id IN (SELECT unnest(coalesce(nai_contato_irmaos(k.id), ARRAY[k.id]))
                          FROM nai_contato k WHERE k.chave = current_setting('teste304.chave'))
   AND NOT EXISTS (SELECT 1 FROM core_instrucao_feita f WHERE f.instrucao_id = i.id)
   AND NOT EXISTS (SELECT 1 FROM nai_turno t
                    WHERE t.contato_id IN (SELECT unnest(coalesce(nai_contato_irmaos(k.id), ARRAY[k.id]))
                                             FROM nai_contato k WHERE k.chave = current_setting('teste304.chave'))
                      AND t.papel = 'corretor' AND t.criado_em > i.criado_em
                      AND NOT EXISTS (SELECT 1 FROM nai_core_turno n WHERE n.turno_id = t.id)
                      AND EXISTS (SELECT 1 FROM nai_saida s
                                   WHERE s.turno_id = t.id AND s.papel_destino = 'turno'
                                     AND s.estado IN ('pendente', 'enviando', 'enviado')));
-- ...e marca que executou, como o worker faz
INSERT INTO core_instrucao_feita (instrucao_id, feito)
SELECT i.id, '{"teste": 304}'::jsonb FROM nai_instrucao i WHERE i.criado_por = 'teste' AND i.texto LIKE 'teste 304%';
RESET ROLE;

-- 3. executada pelo núcleo: não está mais pendente e a Nay velha deixa de ver no cabeçalho dela
SELECT (SELECT count(*) FROM nai_instrucao i WHERE i.criado_por = 'teste' AND i.texto LIKE 'teste 304%'
           AND NOT EXISTS (SELECT 1 FROM core_instrucao_feita f WHERE f.instrucao_id = i.id)) AS c1_pendentes_esperado_0,
       nai_instrucao_texto(contato) IS NULL AS c2_a_velha_nao_ve_mais_esperado_t
  FROM _t304;

-- 4. uma instrução que o núcleo NÃO executou continua no cabeçalho da velha (turno de visita, mídia)
INSERT INTO nai_instrucao (contato_id, texto, criado_por) SELECT contato, 'teste 304: segunda', 'teste' FROM _t304;
SELECT left(nai_instrucao_texto(contato), 60) AS d1_a_velha_ve_a_que_ninguem_executou FROM _t304;
