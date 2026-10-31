-- 545: os casos da revisão de 30/10 -- quem fica "aqui perto" (até 2,5 km da borda) dos bairros pedidos, e de que bairro
SELECT 'Planalto: ofertáveis perto, por bairro' AS caso, i.bairro, count(*) AS n, min(p.km) AS km_min, max(p.km) AS km_max
  FROM nay_imoveis_perto(ARRAY['Planalto']) p JOIN imoveis i USING (codigo) JOIN core_imovel_busca b USING (codigo)
 WHERE b.ofertavel GROUP BY i.bairro ORDER BY 3 DESC;
SELECT 'Ponta Negra: ofertáveis perto' AS caso, i.bairro, count(*) AS n, min(p.km), max(p.km)
  FROM nay_imoveis_perto(ARRAY['Ponta Negra']) p JOIN imoveis i USING (codigo) JOIN core_imovel_busca b USING (codigo)
 WHERE b.ofertavel GROUP BY i.bairro ORDER BY 3 DESC;
SELECT 'Glória + Santo Antônio: ofertáveis perto' AS caso, i.bairro, count(*) AS n, min(p.km), max(p.km)
  FROM nay_imoveis_perto(ARRAY['Glória', 'Santo Antônio']) p JOIN imoveis i USING (codigo) JOIN core_imovel_busca b USING (codigo)
 WHERE b.ofertavel GROUP BY i.bairro ORDER BY 3 DESC;
SELECT 'Cidade Nova: ofertáveis perto' AS caso, i.bairro, count(*) AS n, min(p.km), max(p.km)
  FROM nay_imoveis_perto(ARRAY['Cidade Nova']) p JOIN imoveis i USING (codigo) JOIN core_imovel_busca b USING (codigo)
 WHERE b.ofertavel GROUP BY i.bairro ORDER BY 3 DESC;
SELECT 'linhas na tabela' AS caso, count(*) AS n, count(DISTINCT codigo) AS imoveis FROM geo_imovel_perto;
