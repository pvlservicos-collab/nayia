-- 245 (30/09/2026): a pontuação do cadastro (244) lida pelo site.
-- `nai_imovel_pontos` fazia `SELECT * FROM imoveis`, e o papel de leitura do site
-- (nay_site_leitura) tem permissão POR COLUNA em `imoveis` -- então a lista de imóveis
-- do admin quebrou com "permission denied for table imoveis". A função passa a ser
-- SECURITY DEFINER com search_path fixo: ela só lê e devolve o resumo (pontos, pct e os
-- nomes dos campos que faltam), sem dado pessoal nenhum.
BEGIN;
SET LOCAL lock_timeout = '3s';
ALTER FUNCTION public.nai_imovel_pontos(integer) SECURITY DEFINER;
ALTER FUNCTION public.nai_imovel_pontos(integer) SET search_path TO 'public';
REVOKE ALL ON FUNCTION public.nai_imovel_pontos(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.nai_imovel_pontos(integer) TO nay_site_leitura, nay_site_conteudo, nay_disparo;
COMMIT;
