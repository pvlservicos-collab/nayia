-- =====================================================================
-- 159 — A CAPTAÇÃO PELA OLX NO SITE NOVO (28/09/2026)
--
-- Pedro: "cola um link da olx e ele importa as fotos e todos os dados... fique
-- pré-cadastrado automaticamente... só aparece disponível depois de um clique
-- humano".
--
-- O pré-cadastro entra em `imoveis` (origem 'olx', Rascunho) pelo que a 157 já
-- liberou. Faltava a tabela de FOTOS: a role de escrita do site não tinha
-- nenhum direito em `imovel_fotos`. Ganha só o que a rota usa: ler, gravar a
-- foto baixada e apagar (reimportar um rascunho). A rota confere que o imóvel é
-- um pré-cadastro da OLX antes de tocar em foto.
-- =====================================================================
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL lock_timeout = '3s';

GRANT SELECT (id, codigo, ordem, url, e_capa, e_fachada) ON imovel_fotos TO nay_site_escrita;
GRANT INSERT (codigo, ordem, url, e_capa) ON imovel_fotos TO nay_site_escrita;
GRANT DELETE ON imovel_fotos TO nay_site_escrita;
GRANT USAGE ON SEQUENCE imovel_fotos_id_seq TO nay_site_escrita;

COMMIT;
