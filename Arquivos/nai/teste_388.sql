SELECT codigo, bairro, round(preco) AS preco, perto FROM olx_cliente_buscar('{"finalidade": "locacao", "teto": 3000, "quartos": 2, "mobilia": "semi", "bairros": ["Chapada", "São Jorge", "Dom Pedro", "Planalto", "Alvorada", "Ponta Negra"]}', '{9026}', 5);
SELECT count(*) AS com_vieiralves FROM olx_cliente_buscar('{"finalidade": "locacao", "teto": 4000, "bairros": ["Vieiralves"]}');
