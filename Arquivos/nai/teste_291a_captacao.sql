-- Testes da 291a: dentro do ensaio, depois de criar o gatilho, antes do ROLLBACK.
SET LOCAL statement_timeout = '20s';
\echo '== 1. quem já recebeu e nunca escreveu: tentar voltar para novo -> fica enviado'
WITH alvo AS (SELECT l.id FROM captacao_leads l WHERE l.status = 'enviado'
               AND NOT EXISTS (SELECT 1 FROM captacao_mensagens m WHERE m.lead_id = l.id AND m.direcao = 'recebida') ORDER BY l.id LIMIT 1)
UPDATE captacao_leads l SET status = 'novo' FROM alvo WHERE l.id = alvo.id RETURNING l.id, l.status AS deve_ser_enviado;
\echo '== 2. quem já concluiu: tentar voltar para novo -> continua concluido'
WITH alvo AS (SELECT l.id FROM captacao_leads l WHERE l.status = 'concluido'
               AND EXISTS (SELECT 1 FROM captacao_mensagens m WHERE m.lead_id = l.id AND m.direcao = 'recebida')
               AND EXISTS (SELECT 1 FROM captacao_mensagens m WHERE m.lead_id = l.id AND m.direcao = 'enviada') ORDER BY l.id LIMIT 1)
UPDATE captacao_leads l SET status = 'novo' FROM alvo WHERE l.id = alvo.id RETURNING l.id, l.status AS deve_ser_concluido;
\echo '== 3. quem já recebeu: envio seguinte que falha não devolve para erro (que volta à fila)'
WITH alvo AS (SELECT l.id FROM captacao_leads l WHERE l.status = 'enviado' ORDER BY l.id DESC LIMIT 1)
UPDATE captacao_leads l SET status = 'erro' FROM alvo WHERE l.id = alvo.id RETURNING l.id, l.status AS nao_pode_ser_erro;
\echo '== 3b. reservado de quem já recebeu (envio gravado, ultimo_envio_em não): o destravar não devolve para a fila'
WITH alvo AS (SELECT l.id FROM captacao_leads l WHERE l.status = 'respondendo' ORDER BY l.id LIMIT 1),
     r AS (UPDATE captacao_leads l SET status = 'reservado' FROM alvo WHERE l.id = alvo.id RETURNING l.id)
SELECT count(*) AS reservou FROM r;
UPDATE captacao_leads l SET status = 'novo' WHERE l.status = 'reservado'
   AND EXISTS (SELECT 1 FROM captacao_mensagens m WHERE m.lead_id = l.id AND m.direcao = 'enviada') RETURNING l.id, l.status AS deve_ser_respondendo;
\echo '== 4. quem nunca recebeu nada: a fila anda normalmente (novo -> reservado -> novo, e -> erro)'
CREATE TEMP TABLE t_alvo ON COMMIT DROP AS SELECT id FROM captacao_leads WHERE status = 'novo' AND NOT opt_out AND humano_assumiu_em IS NULL ORDER BY id LIMIT 1;
UPDATE captacao_leads l SET status = 'reservado' FROM t_alvo WHERE l.id = t_alvo.id RETURNING l.id, l.status AS deve_ser_reservado;
UPDATE captacao_leads l SET status = 'novo' FROM t_alvo WHERE l.id = t_alvo.id RETURNING l.id, l.status AS deve_ser_novo;
UPDATE captacao_leads l SET status = 'erro' FROM t_alvo WHERE l.id = t_alvo.id RETURNING l.id, l.status AS deve_ser_erro;
\echo '== 5. mudar outra coluna de quem está na fila não mexe no status'
UPDATE captacao_leads l SET atualizado_em = now() FROM t_alvo WHERE l.id = t_alvo.id RETURNING l.id, l.status AS continua_erro;
\echo '== 6. o gatilho existe só uma vez'
SELECT count(*) AS gatilhos FROM pg_trigger WHERE tgrelid = 'public.captacao_leads'::regclass AND NOT tgisinternal;
