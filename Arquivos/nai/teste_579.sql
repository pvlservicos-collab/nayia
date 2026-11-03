-- teste da 579: a lista, as contas por canal e tipo, e um salvar/excluir (tudo some no ROLLBACK do ensaio)
SELECT canal, tipo, count(*), min(data), max(data), count(*) FILTER (WHERE tipo = 'conteudo' AND demanda_id IS NULL) soltas
  FROM midia_item GROUP BY 1, 2 ORDER BY 1, 2;
SELECT jsonb_array_length(site_midias()->'itens') AS itens, site_midias()->>'hoje' AS hoje;
SELECT site_midia_salvar('{"canal":"insta","tipo":"conteudo","titulo":"teste","data":"2026-11-05","status":"pronto"}'::jsonb, 'teste') AS novo;
SELECT site_midia_salvar(jsonb_build_object('id', (SELECT max(id) FROM midia_item), 'canal', 'face', 'titulo', 'teste 2', 'status', 'publicado'), 'teste') AS mudou;
SELECT canal, titulo, status, data, atualizado_por FROM midia_item WHERE id = (SELECT max(id) FROM midia_item);
SELECT site_midia_excluir((SELECT max(id) FROM midia_item), 'teste') AS excluiu;
SELECT count(*) AS visiveis FROM jsonb_array_elements(site_midias()->'itens');
