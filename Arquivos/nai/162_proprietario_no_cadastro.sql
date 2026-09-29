-- =====================================================================
-- 162 — O PROPRIETÁRIO NO CADASTRO DO SITE NOVO (28/09/2026)
--
-- Pedro: "preciso de um conjunto de campos para pôr os dados do proprietário
-- do imóvel, e esse cadastro é a última etapa da captação pela OLX, já que a
-- OLX não dá esses dados; quando clica em salvar o imóvel ele notifica para
-- pôr os dados do proprietário".
--
-- O dono mora na tabela de sempre, `proprietarios` (a do admin antigo), e o
-- imóvel aponta para ele em DOIS lugares: `imoveis.proprietario_id` (5.647
-- imóveis, é o que a lista e o site leem) e `imovel_privado.proprietario_id`
-- -- é por este que a Nay acha o dono para pedir a visita
-- (nai_proprietario_do_imovel -> nai_pedir_ao_proprietario).
--
-- Os ids de `proprietarios` vêm do admin antigo (até 5.661, sem sequência).
-- Quem é cadastrado pelo site novo ganha id da faixa 900001+, que nunca bate
-- com um id do admin antigo (a view vw_proprietarios_site casa por id).
-- =====================================================================
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE SEQUENCE IF NOT EXISTS proprietarios_site_id_seq START WITH 900001 MINVALUE 900001 NO CYCLE;
COMMENT ON SEQUENCE proprietarios_site_id_seq IS 'Id do proprietário cadastrado pelo site novo (162); o admin antigo usa ids baixos.';
GRANT USAGE ON SEQUENCE proprietarios_site_id_seq TO nay_site_escrita;

GRANT INSERT (id, nome, telefone, email, tratamento, documento) ON proprietarios TO nay_site_escrita;
GRANT UPDATE (nome, telefone, email, tratamento, documento)     ON proprietarios TO nay_site_escrita;

GRANT INSERT (proprietario_id), UPDATE (proprietario_id) ON imoveis TO nay_site_escrita;
GRANT SELECT (proprietario_id), INSERT (proprietario_id), UPDATE (proprietario_id) ON imovel_privado TO nay_site_escrita;

COMMIT;
