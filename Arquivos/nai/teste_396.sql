-- 396: o rascunho do popup, um pedido com o texto editado, o envio pela captação
SELECT (r->'venda'->>'ok') AS venda_ok, (r->'locacao'->>'ok') AS locacao_ok, r->'venda'->>'titulo' AS titulo,
       jsonb_array_length(r->'na_olx') AS na_olx, jsonb_array_length(r->'pedidos') AS pedidos
  FROM (SELECT site_olx_anuncio_rascunho(5640) r) x;
SELECT site_olx_anuncio_pedir(5640, 'venda', '{"subject": "Casa no La Villette, 3 quartos", "price": "R$ 890.000",
        "images": ["https://imobeasy.com/system/pictures/images/000/116/490/huge/6c5e4f68-0d78-4ac2-9074-5ad3eb3e0b18.jpg?1753126264"]}'::jsonb,
        'ensaio') AS pedido;
SELECT codigo, negocio, conta, estado, ad_id, anuncio->>'subject' AS titulo, anuncio->>'price' AS preco,
       jsonb_array_length(anuncio->'images') AS fotos, hash IS NOT NULL AS tem_hash
  FROM privado.olx_anuncio_pedido ORDER BY id DESC LIMIT 1;
SELECT site_olx_anuncio_pedido((SELECT max(id) FROM privado.olx_anuncio_pedido)) ->> 'estado' AS estado;
-- o segundo pedido do mesmo anúncio enquanto o primeiro sai: recusa
DO $$ BEGIN PERFORM site_olx_anuncio_pedir(5640, 'venda', '{}'::jsonb, 'ensaio'); RAISE NOTICE 'ERRADO: aceitou dois';
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'certo, recusou: %', SQLERRM; END $$;
SELECT crm_captacao_enviar_imoveis('5592991468187', ARRAY[9026, 5640, 9026], 'ensaio') AS envio;
SELECT crm_captacao_envio_estado((SELECT max(id) FROM privado.captacao_envio_pedido));
