-- dentro do ensaio (ROLLBACK). 1) o Marcos (final 1000, lista 4) diz "1.5 M morada dos pássaros": o tipo e o bairro vêm do banco
SELECT telefone FROM captacao_leads WHERE right(telefone,4) = '1000' AND quem_importou LIKE 'Pedro (lista 4%' LIMIT 1 \gset
SELECT captacao_ficha(:'telefone', 'outro', '{"negocio":"venda","detalhes":"1.5 M morada dos pássaros"}'::jsonb, false) AS marcos;
SELECT dados->>'tipo' tipo, dados->>'bairro' bairro, dados->>'condominio' condominio, dados->>'_perguntou' proxima
  FROM captacao_cadastro WHERE lead_id = (SELECT id FROM captacao_leads WHERE telefone = :'telefone') AND estado = 'coletando' ORDER BY id DESC LIMIT 1;
-- 2) outro dono, que NÃO cita condomínio nosso: continua perguntando tipo e local
SELECT telefone AS tel2 FROM captacao_leads WHERE right(telefone,4) <> '1000' AND quem_importou LIKE 'Pedro (lista 4%' AND status = 'novo' ORDER BY id LIMIT 1 \gset
SELECT captacao_ficha(:'tel2', 'outro', '{"negocio":"venda","detalhes":"uma casa perto da praça"}'::jsonb, false) AS sem_condominio;
-- 3) outro dono que cita o Vista das Mangueiras (só apartamentos): vira apartamento
SELECT telefone AS tel3 FROM captacao_leads WHERE right(telefone,4) <> '1000' AND telefone <> :'tel2' AND quem_importou LIKE 'Pedro (lista 4%' AND status = 'novo' ORDER BY id LIMIT 1 \gset
SELECT captacao_ficha(:'tel3', 'outro', '{"negocio":"venda","condominio":"Vista das Mangueiras"}'::jsonb, false) AS vista;
SELECT dados->>'tipo' tipo, dados->>'bairro' bairro, dados->>'condominio' condominio
  FROM captacao_cadastro WHERE lead_id = (SELECT id FROM captacao_leads WHERE telefone = :'tel3') AND estado = 'coletando' ORDER BY id DESC LIMIT 1;
