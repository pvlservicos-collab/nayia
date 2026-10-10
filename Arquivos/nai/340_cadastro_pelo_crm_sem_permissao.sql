-- 340 -- O cadastro pelo CRM dava "InsufficientPrivilege", e gente escrevendo pelo CRM não parava a Nay de captação
--
-- Pedro, 10/10/2026: "na hora de cadastrar pelo CRM dá insufficient privilege, não é pra dar isso".
--
-- O que estava errado, lido no log do banco em 10/10:
--   1. O popup de cadastro do CRM grava pela API do site (`/api/captacao/crm/imovel`, papel `nay_site_escrita`).
--      O último comando da rota é `SELECT nai_imovel_pontos(codigo)` (a pontuação que volta para a tela), e esse
--      papel nunca teve EXECUTE na função: o comando falhava e a transação INTEIRA era desfeita. O imóvel não
--      ficava gravado (os códigos 9031 e 9032, de 10/10 06:36, foram gastos assim).
--   2. "Gente escreveu, a Nay de captação para" (CRM, 09/10: `pararNayDaCaptacao.ts`) lê `captacao_leads` com o
--      papel do CRM (`nay_disparo`), que não tinha SELECT na tabela: 46 recusas desde 09/10, e a Nay de captação
--      seguia respondendo por cima de quem escrevia pelo CRM.
--
-- O que muda: só permissão. Nenhuma função é reescrita.
--   - `nay_site_escrita` passa a executar `nai_imovel_pontos`.
--   - `nay_disparo` lê de `captacao_leads` SÓ as quatro colunas que a consulta usa (o id, se já está com gente, e
--     as duas chaves por onde `captacao_lead_por_contato` acha a pessoa). Nome, telefone e o resto seguem fechados.
BEGIN;
SET LOCAL lock_timeout = '3s';

GRANT EXECUTE ON FUNCTION public.nai_imovel_pontos(integer) TO nay_site_escrita;

GRANT SELECT (id, humano_assumiu_em, telefone_chave, chat_lid) ON public.captacao_leads TO nay_disparo;

COMMIT;
