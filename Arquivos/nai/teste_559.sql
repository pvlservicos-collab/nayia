-- teste da 559 (dentro do ensaio)
DO $t$
DECLARE r jsonb;
BEGIN
  ASSERT (SELECT count(*) FROM privado.link_organico) >= 11, 'os links de partida';
  -- a mensagem pronta liga o telefone ao link; a marca mais comprida vence (stories, não instagram)
  INSERT INTO captacao_mensagens (telefone, direcao, origem, texto, status)
  VALUES ('5592900000559', 'recebida', 'texto', 'Olá! Vim dos stories da Imob Easy e quero saber mais sobre imóveis.', 'Recebido');
  ASSERT (SELECT codigo FROM privado.link_organico_lead WHERE telefone8 = '00000559') = 'stories',
         (SELECT string_agg(codigo, ',') FROM privado.link_organico_lead WHERE telefone8 = '00000559');
  INSERT INTO captacao_mensagens (telefone, direcao, origem, texto, status)
  VALUES ('5592900000558', 'recebida', 'texto', 'ola vim do blog da imob easy e quero saber mais sobre imoveis', 'Recebido');
  ASSERT (SELECT codigo FROM privado.link_organico_lead WHERE telefone8 = '00000558') = 'blog', 'sem acento e sem pontuação';
  -- mensagem comum não liga a nada; mensagem nossa também não
  INSERT INTO captacao_mensagens (telefone, direcao, origem, texto, status)
  VALUES ('5592900000557', 'recebida', 'texto', 'Boa tarde, vim de outro lugar', 'Recebido'),
         ('5592900000556', 'enviada', 'resposta', 'Olá! Vim do site da Imob Easy', 'Enviado');
  ASSERT NOT EXISTS (SELECT 1 FROM privado.link_organico_lead WHERE telefone8 IN ('00000557', '00000556')), 'não liga';
  -- o clique
  r := site_link_organico_clique('Blog', '{"utm_source":"blog"}', 'https://blog.imobeasy.online/x', '1.2.3.4');
  ASSERT r->>'mensagem' LIKE 'Olá! Vim do blog%', 'clique';
  ASSERT site_link_organico_clique('nao-existe', '{}', NULL, NULL) IS NULL, 'link que não existe';
  -- salvar: marca fora da mensagem e marca repetida são recusadas; sem marca, sai da primeira frase
  ASSERT NOT (site_link_organico_salvar('{"codigo":"x1","canal":"X","nome":"X","mensagem":"Olá! Vim do X.","marca":"Vim do Y"}', 't')->>'ok')::boolean, 'marca fora';
  ASSERT NOT (site_link_organico_salvar('{"codigo":"x2","canal":"X","nome":"X","mensagem":"Olá! Vim do blog da Imob Easy e pronto.","marca":"Vim do blog da Imob Easy"}', 't')->>'ok')::boolean, 'marca repetida';
  ASSERT (site_link_organico_salvar('{"codigo":"whatsapp-status","canal":"WhatsApp","nome":"Status do WhatsApp","mensagem":"Olá! Vim do status do WhatsApp da Imob Easy. Quero saber de imóveis."}', 't')->>'ok')::boolean, 'novo';
  ASSERT (SELECT marca FROM privado.link_organico WHERE codigo = 'whatsapp-status') = 'Vim do status do WhatsApp da Imob Easy', 'marca da primeira frase';
  r := site_links_organicos();
  ASSERT (SELECT (x->>'leads')::int FROM jsonb_array_elements(r) x WHERE x->>'codigo' = 'stories') = 1, 'a página conta o lead';
  ASSERT (SELECT (x->>'cliques')::int FROM jsonb_array_elements(r) x WHERE x->>'codigo' = 'blog') = 1, 'a página conta o clique';
  RAISE NOTICE 'teste_559: ok';
END
$t$;
