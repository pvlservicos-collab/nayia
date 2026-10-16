-- teste da 385 (na ensaio: termina em ROLLBACK)
SELECT 'aluguel até 3 mil, Ponta Negra, 2 quartos' AS caso, count(*) AS achou, string_agg(codigo || ' ' || bairro || ' ' || round(preco) || (CASE WHEN perto THEN ' (perto)' ELSE '' END), '; ') AS imoveis
  FROM olx_cliente_buscar('{"finalidade": "locacao", "teto": 3000, "bairros": ["ponta negra"], "quartos": 2}')
UNION ALL
SELECT 'venda até 400 mil, pq 10, 3 quartos (serve 2), financiamento', count(*), string_agg(codigo || ' ' || bairro || ' ' || round(preco) || (CASE WHEN perto THEN ' (perto)' ELSE '' END), '; ')
  FROM olx_cliente_buscar('{"finalidade": "venda", "teto": 400000, "bairros": ["pq 10"], "quartos": 3, "aceita_menos_quartos": true, "financiamento": "quer simular"}')
UNION ALL
SELECT 'venda casa até 800 mil, qualquer bairro', count(*), string_agg(codigo || ' ' || bairro || ' ' || round(preco), '; ')
  FROM olx_cliente_buscar('{"finalidade": "venda", "tipo": "casa", "teto": 800000}', '{3883}')
UNION ALL
SELECT 'locação, Vieiralves (vira Nossa Senhora das Graças)', count(*), string_agg(codigo || ' ' || bairro || ' ' || round(preco), '; ')
  FROM olx_cliente_buscar('{"finalidade": "locacao", "teto": 4000, "bairros": ["Vieiralves"]}');
SELECT * FROM crm_olx_clientes_etapas() LIMIT 3;
SELECT chave, valor FROM privado.olx_config WHERE chave LIKE 'whatsapp%' ORDER BY 1;
