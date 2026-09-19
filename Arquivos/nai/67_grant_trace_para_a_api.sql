-- =====================================================================
-- NAI -- 67: a API enxerga as tabelas do trace (19/09/2026)
--
-- O PASSO A PASSO NAO PREVIU ISTO. Depois do 64/65/66 a rota
-- /api/nai/trace/saude devolvia 500 com:
--     psycopg2.errors.InsufficientPrivilege: permission denied for table nai_evento
--
-- Tabela nova nasce sem permissao para as roles de leitura. A API do site
-- conecta como `nay_site_nai` (NAI_DATABASE_URL), que so enxerga o que
-- alguem liberou -- e essa e a parede que faz a role NAO ver telefone de
-- proprietario. Aqui ela ganha SELECT so no que o painel do cerebro precisa.
--
-- SO LEITURA. Nenhum INSERT/UPDATE/DELETE, em nenhuma tabela.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

-- As tabelas do trace e do inventario
GRANT SELECT ON
  nai_evento, nai_setor, nai_regra,
  nai_setor_regra, nai_setor_excecao, nai_funcao_chamador,
  nai_sobrecarga_esperada, nai_funcao_foto, nai_foto
TO nay_site_nai;

-- As views que o painel le
GRANT SELECT ON
  vw_nai_setor_mapa, vw_nai_setor_saude, vw_nai_setor_etapas,
  vw_nai_execucoes, vw_nai_acoplamento, vw_nai_sobrecarga,
  vw_nai_funcao_orfa, vw_nai_funcao_viva,
  vw_nai_regras_ignoradas, vw_nai_obediencia
TO nay_site_nai;

-- DUAS DELAS SAO FUNCAO, nao view -- descobri levando 500 na cara:
-- `nai_foto_diferenca()` e `nai_trilha()` sao chamadas com FROM no
-- trace_api.py, o que faz parecer view na leitura rapida do codigo.
GRANT EXECUTE ON FUNCTION nai_trilha(bigint) TO nay_site_nai;
GRANT EXECUTE ON FUNCTION nai_foto_diferenca(bigint) TO nay_site_nai;
-- BUG CONHECIDO no trace_api.py (linha 247): ele chama
--   SELECT * FROM nai_foto_diferenca()
-- sem argumento, e a funcao pede p_foto bigint. A rota NAO quebra -- a
-- chamada esta dentro de try/except psycopg2.Error e a secao "desvio" fica
-- vazia. Para funcionar, o .py precisa passar o id da ultima foto.

COMMIT;

-- Prova: o que a role enxerga agora.
SELECT table_name, privilege_type
  FROM information_schema.table_privileges
 WHERE grantee = 'nay_site_nai'
   AND (table_name LIKE 'nai\_%' OR table_name LIKE 'vw\_nai\_%')
 ORDER BY 1;

-- ---------------------------------------------------------------------
-- nai_turno: PERMISSAO POR COLUNA, nao a tabela inteira
--
-- A rota /saude faz duas contagens em `nai_turno` (turnos nas ultimas 24h,
-- e quantos ja tem exec_id). Nenhum texto. Dar SELECT na tabela abriria a
-- coluna `texto` -- a mensagem do corretor -- para a role do site, e a
-- parede de que "essa role nunca le mensagem de ninguem" existe de
-- proposito (esta escrita no cabecalho do app.py).
--
-- Postgres aceita GRANT por coluna, e count(*) funciona com ele.
-- ---------------------------------------------------------------------
GRANT SELECT (criado_em, exec_id) ON nai_turno TO nay_site_nai;
