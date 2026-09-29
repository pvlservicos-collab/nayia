-- =====================================================================
-- 155 — AS REGRAS SUGERIDAS NO SITE (28/09/2026)
--
-- Pedro: "eu tinha pedido ontem uma função de novas regras sugeridas mas não
-- achei no site, se não tem põe lá". As tabelas nasceram na 128 (27/09), com
-- 16 sugestões e 52 conversas de prova, mas a tela nunca foi feita.
--
-- A tela (Cérebro da Nay -> Regras sugeridas) lê e grava pela role de
-- CONTEÚDO do site, que já lê as duas tabelas. Aqui ela ganha só o direito de
-- DECIDIR: mudar o estado (sugerida / aceita / recusada), quem e quando, e a
-- nota. Não pode reescrever a regra nem apagar sugestão.
-- =====================================================================
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL lock_timeout = '3s';

GRANT UPDATE (estado, decidido_em, decidido_por, nota_do_tel)
   ON nai_regra_sugerida TO nay_site_conteudo;

COMMIT;
