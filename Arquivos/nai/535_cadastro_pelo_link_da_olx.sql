-- 535 (Pedro, 30/10/2026): "um botão lá em cima do contato, Cadastrar imóvel; se eu pegar o link da OLX da pessoa e
-- colar lá, o nosso sistema já puxa todos os dados do imóvel, dá a pontuação ... e já vai baixar as fotos no automático".
-- A API do site (nay_site_escrita, a conexão que grava o pré-cadastro) passa a LER a base raspada da OLX, de onde vêm
-- os dados e as fotos do anúncio, e a pontuação do cadastro, que a barra mostra. Só leitura; nada mais muda.
BEGIN;
GRANT SELECT ON public.scrap_anuncio TO nay_site_escrita;
GRANT SELECT ON public.vw_imovel_pontuacao TO nay_site_escrita;
COMMIT;
