-- 546: a busca da Nay Leads com o "ao redor" pela distância do imóvel (os casos da revisão de 30/10)
SELECT 'Planalto 2q até 2.500' AS caso, r.codigo, r.bairro, r.preco, r.perto, p.km
  FROM olx_cliente_buscar('{"finalidade":"locacao","bairros":["Planalto"],"quartos":"2"}', '{}', 10) r
  LEFT JOIN nay_imoveis_perto(ARRAY['Planalto']) p USING (codigo);
SELECT 'Ponta Negra 3q até 6.000' AS caso, r.codigo, r.bairro, r.preco, r.perto, p.km
  FROM olx_cliente_buscar('{"finalidade":"locacao","bairros":["Ponta Negra"],"quartos":"3"}', '{}', 10) r
  LEFT JOIN nay_imoveis_perto(ARRAY['Ponta Negra']) p USING (codigo);
SELECT 'Cidade Nova 2q até 2.000' AS caso, r.codigo, r.bairro, r.preco, r.perto, p.km
  FROM olx_cliente_buscar('{"finalidade":"locacao","bairros":["Cidade Nova"],"quartos":"2"}', '{}', 10) r
  LEFT JOIN nay_imoveis_perto(ARRAY['Cidade Nova']) p USING (codigo);
SELECT 'Glória/Santo Antônio 2q até 2.500' AS caso, r.codigo, r.bairro, r.preco, r.perto, p.km
  FROM olx_cliente_buscar('{"finalidade":"locacao","bairros":["Glória","Santo Antônio"],"quartos":"2"}', '{}', 10) r
  LEFT JOIN nay_imoveis_perto(ARRAY['Glória','Santo Antônio']) p USING (codigo);
-- o nome já normalizado (o que a busca passa) dá o mesmo que o nome do cadastro
SELECT 'normalizado = cadastro' AS caso,
       (SELECT count(*) FROM nay_imoveis_perto(ARRAY[nay_normalizar_lugar('Ponta Negra', true)])) AS normalizado,
       (SELECT count(*) FROM nay_imoveis_perto(ARRAY['Ponta Negra'])) AS cadastro;
