-- Testes da 353 (rodam dentro do ensaio, antes do ROLLBACK). Nada é enviado no ensaio.
CREATE TEMP TABLE _t (caso text, esperado text, veio text);
CREATE TEMP TABLE _l AS SELECT * FROM captacao_leads WHERE quem_importou LIKE 'Pedro (lista _: %12/10)';
CREATE TEMP TABLE _tela AS SELECT * FROM site_publicos_disparo();

INSERT INTO _t SELECT 'entrou gente das duas listas', 'sim',
  CASE WHEN (SELECT count(*) FROM _l WHERE quem_importou LIKE '%lista 6%') > 50
        AND (SELECT count(*) FROM _l WHERE quem_importou LIKE '%lista 8%') > 20 THEN 'sim' ELSE 'não' END;
INSERT INTO _t SELECT 'não passa do que a tela mostra "para falar"', 'ok',
  CASE WHEN (SELECT count(*) FROM _l WHERE quem_importou LIKE '%lista 6%') <= (SELECT total FROM _tela WHERE n = 6)
        AND (SELECT count(*) FROM _l WHERE quem_importou LIKE '%lista 8%') <= (SELECT total FROM _tela WHERE n = 8) THEN 'ok' ELSE 'passou' END;
INSERT INTO _t SELECT 'todos novos, sem envio, sem resposta, sem gente', (SELECT count(*)::text FROM _l),
  (SELECT count(*)::text FROM _l WHERE status = 'novo' AND etapa = 'novo' AND tentativas = 0
      AND ultimo_envio_em IS NULL AND respondeu_em IS NULL AND humano_assumiu_em IS NULL AND NOT opt_out);
INSERT INTO _t SELECT 'todos estão na fila do disparo', (SELECT count(*)::text FROM _l),
  (SELECT count(*)::text FROM captacao_py_fila_do_disparo() f(id) JOIN _l l ON l.id = f.id);
INSERT INTO _t SELECT 'ninguém falou conosco em 60 dias nem é corretor', '0',
  (SELECT count(*)::text FROM _l WHERE nay_falou_conosco(telefone_chave, 60) OR nay_e_corretor_chave(telefone_chave));
INSERT INTO _t SELECT 'nenhum já recebeu mensagem da captação', '0',
  (SELECT count(*)::text FROM _l l
    WHERE EXISTS (SELECT 1 FROM captacao_mensagens m WHERE nay_fone_chave(m.telefone) = l.telefone_chave AND m.direcao = 'enviada'));
INSERT INTO _t SELECT 'nenhum está em não disparar nem é de fora da campanha', '0',
  (SELECT count(*)::text FROM _l l
    WHERE EXISTS (SELECT 1 FROM captacao_nao_disparar n WHERE n.telefone_chave = l.telefone_chave)
       OR captacao_fora_da_campanha(l.id) IS NOT NULL);
INSERT INTO _t SELECT 'todos têm nome e telefone no formato da Meta', (SELECT count(*)::text FROM _l),
  (SELECT count(*)::text FROM _l WHERE coalesce(btrim(nome), '') <> '' AND telefone ~ '^55[0-9]{10,11}$');
INSERT INTO _t SELECT 'um lead por telefone', (SELECT count(*)::text FROM _l), (SELECT count(DISTINCT telefone_chave)::text FROM _l);
INSERT INTO _t SELECT 'lista 6: todos com imóvel disponível e os imóveis do dono congelados', (SELECT count(*)::text FROM _l WHERE quem_importou LIKE '%lista 6%'),
  (SELECT count(*)::text FROM _l l WHERE l.quem_importou LIKE '%lista 6%' AND jsonb_array_length(l.imoveis_prop) >= 1
      AND EXISTS (SELECT 1 FROM vw_imoveis_todos v WHERE v.codigo::text = l.codigo AND v.status = 'Disponível' AND v.proprietario_id = l.proprietario_id));
INSERT INTO _t SELECT 'lista 8: sem imóvel (planilha antiga)', (SELECT count(*)::text FROM _l WHERE quem_importou LIKE '%lista 8%'),
  (SELECT count(*)::text FROM _l WHERE quem_importou LIKE '%lista 8%' AND codigo IS NULL AND imoveis_prop = '[]'::jsonb);
INSERT INTO _t SELECT 'a tela agora mostra esses como "já receberam"? não: só depois do envio', 'ok',
  CASE WHEN (SELECT disparados FROM site_publicos_disparo() WHERE n = 6) = (SELECT disparados FROM _tela WHERE n = 6) THEN 'ok' ELSE 'mudou' END;

SELECT CASE WHEN esperado = veio THEN 'ok' ELSE 'FALHOU' END AS r, caso,
       CASE WHEN esperado = veio THEN '' ELSE 'esperado ' || esperado || ', veio ' || coalesce(veio, '(nulo)') END AS detalhe
  FROM _t;

SELECT quem_importou, count(*) AS leads, count(*) FILTER (WHERE tratamento IS NOT NULL) AS com_sr_sra,
       count(*) FILTER (WHERE imovel_desc IS NOT NULL) AS com_imovel_desc
  FROM _l GROUP BY 1 ORDER BY 1;

-- amostra: como cada um vai ser chamado; telefone só com os 4 finais
SELECT left(quem_importou, 15) AS lista, codigo, imovel_desc, right(telefone, 4) AS fim,
       concat_ws(' ', tratamento, split_part(btrim(nome), ' ', 1)) AS "Olá, ..."
  FROM _l ORDER BY quem_importou, proprietario_id LIMIT 12;
