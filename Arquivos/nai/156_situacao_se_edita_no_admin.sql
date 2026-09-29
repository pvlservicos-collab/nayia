-- =====================================================================
-- 156 — A SITUAÇÃO DO IMÓVEL SE EDITA NO ADMIN (28/09/2026)
--
-- Pedro: "o status do imóvel nem tá dando pra editar direito, quero poder
-- editar o status lá pela lista, ele fica em uma lista suspensa, eu só clico e
-- seleciono o status novo".
--
-- A role de escrita do site (`nay_site_escrita`) lia `imoveis.status` mas não
-- podia gravar -- e a rota de edição nem aceitava o campo. Aqui ela ganha só
-- o UPDATE do status. Quem decide `disponivel` e `publicado_no_site` junto é a
-- rota (regra do Tel de 27/09): nosso e Disponível fica no site e na Nay;
-- qualquer outra situação sai dos dois.
-- =====================================================================
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL lock_timeout = '3s';

GRANT UPDATE (status) ON imoveis TO nay_site_escrita;

COMMIT;
