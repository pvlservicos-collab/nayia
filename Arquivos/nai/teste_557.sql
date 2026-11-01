-- teste da 557 (roda dentro do ensaio, antes do ROLLBACK)
DO $t$
BEGIN
  ASSERT NOT EXISTS (SELECT 1 FROM imovel_conhecimento WHERE assunto LIKE 'pergunta:%' AND codigo IN
                       ('293','331','2014','2120','2462','2659','2944','4161','4207','5001','5447','5707','5709','5721','5722','5725','5727','5752','5758','9027','9043','9051','9058','9060','9064')),
         'sobrou assunto "pergunta:" nesses imóveis';
  ASSERT (SELECT texto FROM imovel_conhecimento WHERE codigo = '5709' AND assunto = 'incluso_no_aluguel') LIKE 'O IPTU fica por conta%', 'o 5709';
  ASSERT (SELECT texto FROM imovel_conhecimento WHERE codigo = '2462' AND assunto = 'incluso_no_aluguel') LIKE '%R$ 7.000%', 'o 2462';
  ASSERT (SELECT texto FROM imovel_conhecimento WHERE codigo = '2462' AND assunto = 'terreno') NOT LIKE '%Valor de venda%', 'o terreno';
  ASSERT NOT EXISTS (SELECT 1 FROM imovel_conhecimento WHERE texto ~* '^(chegou|excelente|nao|não)\.?$'), 'lixo';
  ASSERT NOT EXISTS (SELECT 1 FROM imovel_conhecimento WHERE codigo = '9027' AND texto ILIKE '%ultimo andar%'), 'o 9027';
  ASSERT (SELECT count(*) FROM imovel_conhecimento WHERE codigo = '5758' AND assunto = 'andar' AND texto = 'Fica no 2º andar.') = 1, 'o 5758';
  RAISE NOTICE 'teste_557: ok';
END
$t$;
