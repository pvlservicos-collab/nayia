-- teste da 455: dentro da transação do ensaio, com o lead de teste (o número do Pedro)
DELETE FROM captacao_cadastro WHERE lead_id = (SELECT id FROM captacao_leads
  WHERE telefone_chave = nay_fone_chave((SELECT valor FROM captacao_config WHERE chave = 'telefone_teste')));
\echo '--- terreno: a próxima pergunta NÃO é a dos cômodos (esperado: a área)'
SELECT captacao_ficha((SELECT valor FROM captacao_config WHERE chave = 'telefone_teste'), 'outro',
       '{"tipo": "terreno", "bairro": "Tarumã", "negocio": "venda", "detalhes": "um terreno no Tarumã"}'::jsonb, false) AS terreno;
DELETE FROM captacao_cadastro WHERE lead_id = (SELECT id FROM captacao_leads
  WHERE telefone_chave = nay_fone_chave((SELECT valor FROM captacao_config WHERE chave = 'telefone_teste')));
\echo '--- sem tipo, a descrição começa com "um lote": também pula'
SELECT captacao_ficha((SELECT valor FROM captacao_config WHERE chave = 'telefone_teste'), 'outro',
       '{"bairro": "Ponta Negra", "negocio": "venda", "detalhes": "um lote de 300 metros na Ponta Negra"}'::jsonb, false) AS lote;
DELETE FROM captacao_cadastro WHERE lead_id = (SELECT id FROM captacao_leads
  WHERE telefone_chave = nay_fone_chave((SELECT valor FROM captacao_config WHERE chave = 'telefone_teste')));
\echo '--- apartamento: continua perguntando os cômodos'
SELECT captacao_ficha((SELECT valor FROM captacao_config WHERE chave = 'telefone_teste'), 'outro',
       '{"tipo": "apartamento", "bairro": "Vieiralves", "negocio": "venda", "detalhes": "apartamento com sala ampla"}'::jsonb, false) AS apartamento;
