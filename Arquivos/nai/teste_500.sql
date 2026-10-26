UPDATE imovel_fotos SET categoria = 'sala', etiqueta = 'Sala / cozinha americana', categoria_em = now()
 WHERE id = (SELECT id FROM imovel_fotos WHERE codigo = 5739 ORDER BY ordem LIMIT 1);
SELECT codigo, categoria, etiqueta FROM imovel_fotos WHERE codigo = 5739 AND categoria IS NOT NULL;
-- categoria inválida tem que recusar
DO $$ BEGIN
  UPDATE imovel_fotos SET categoria = 'garagem' WHERE id = (SELECT id FROM imovel_fotos WHERE codigo = 5739 LIMIT 1);
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'recusou categoria inválida, como esperado';
END $$;
