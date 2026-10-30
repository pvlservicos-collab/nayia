-- 540: nenhum parceiro antigo no site; tentar publicar um antigo não pega; os novos continuam
SELECT 'antigos no site' AS caso, count(*) AS n FROM imoveis
 WHERE e_parceiro AND extras->>'parceiro_antigo' = 'sim' AND publicado_no_site;
SELECT 'novos no site' AS caso, count(*) AS n FROM imoveis
 WHERE e_parceiro AND coalesce(extras->>'parceiro_antigo', '') <> 'sim' AND publicado_no_site;
UPDATE imoveis SET publicado_no_site = true WHERE codigo = (SELECT min(codigo) FROM imoveis WHERE e_parceiro AND extras->>'parceiro_antigo' = 'sim' AND status = 'Disponível');
SELECT 'antigo depois de tentar publicar' AS caso, count(*) AS n FROM imoveis
 WHERE e_parceiro AND extras->>'parceiro_antigo' = 'sim' AND publicado_no_site;
SELECT 'nossos no site (não muda)' AS caso, count(*) AS n FROM imoveis WHERE NOT e_parceiro AND publicado_no_site AND disponivel;
