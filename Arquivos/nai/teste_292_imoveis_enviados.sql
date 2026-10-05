-- Testes da 292 (crm_imoveis_enviados): dentro do ensaio, antes do ROLLBACK. Telefones só pelos 4 últimos dígitos.
SET LOCAL statement_timeout = '20s';
\echo '== 1. a corretora do caso (turno 944 do core): o 3210 aparece, em 2 dias'
SELECT e.codigo, e.imovel, to_char(e.primeiro_em, 'DD/MM HH24:MI') AS primeiro, to_char(e.ultimo_em, 'DD/MM HH24:MI') AS ultimo, e.dias
  FROM crm_imoveis_enviados((SELECT k.telefone FROM nai_contato k WHERE k.chave = (SELECT chave FROM core_turno WHERE id = 944))) e;
\echo '== 2. quem recebeu pelo publicador e pela Nay velha: as três fontes somam, sem repetir o código'
WITH quem AS (SELECT k.telefone FROM nai_contato k JOIN imovel_enviado_no_dia d ON d.chave = k.chave
               GROUP BY k.telefone ORDER BY count(DISTINCT d.codigo) DESC LIMIT 1)
SELECT count(*) AS imoveis, count(DISTINCT e.codigo) AS distintos, max(e.dias) AS mais_dias, count(*) FILTER (WHERE e.imovel IS NULL) AS sem_nome
  FROM quem, crm_imoveis_enviados(quem.telefone) e;
\echo '== 3. telefone que a Nay não conhece, vazio e nulo: nenhuma linha, sem erro'
SELECT (SELECT count(*) FROM crm_imoveis_enviados('5592000000000')) AS desconhecido,
       (SELECT count(*) FROM crm_imoveis_enviados('')) AS vazio, (SELECT count(*) FROM crm_imoveis_enviados(NULL)) AS nulo;
\echo '== 4. o papel do CRM pode chamar'
SELECT has_function_privilege('nay_disparo', 'public.crm_imoveis_enviados(text)', 'EXECUTE') AS crm_pode;
\echo '== 5. quanto custa'
EXPLAIN (ANALYZE, TIMING ON, COSTS OFF, SUMMARY ON)
SELECT * FROM crm_imoveis_enviados((SELECT k.telefone FROM nai_contato k WHERE k.chave = (SELECT chave FROM core_turno WHERE id = 944)));
