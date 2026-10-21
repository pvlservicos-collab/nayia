-- teste da 460: o lead de teste com fichas de tipos diferentes; mostra a próxima pergunta de cada uma
CREATE TEMP TABLE _casos (n int, campos jsonb) ON COMMIT DROP;
INSERT INTO _casos VALUES
 (1, '{"detalhes": "tenho um imóvel no Alvorada"}'),
 (2, '{"tipo": "prédio com salas comerciais", "bairro": "Alvorada", "negocio": "os dois", "area": "8 por 22", "valor": "5 mil"}'),
 (3, '{"tipo": "sala comercial", "condominio": "Empresarial Rio Negro", "bairro": "Centro", "negocio": "locação", "area": "40", "valor": "2 mil"}'),
 (4, '{"tipo": "apartamento", "condominio": "Weck", "bairro": "Parque 10", "negocio": "locação", "quartos": "2", "banheiros": "2", "vagas": "1", "area": "60", "valor": "2500"}'),
 (5, '{"tipo": "galpão", "bairro": "Distrito", "negocio": "locação", "area": "500", "valor": "8 mil"}');
\echo '--- a próxima pergunta de cada caso (1 tipo desconhecido, 2 prédio, 3 sala em condomínio, 4 apartamento, 5 galpão)'
DO $$
DECLARE r record; v text; tel text := (SELECT valor FROM captacao_config WHERE chave = 'telefone_teste');
BEGIN
  FOR r IN SELECT * FROM _casos ORDER BY n LOOP
    DELETE FROM captacao_cadastro WHERE lead_id = (SELECT id FROM captacao_leads WHERE telefone_chave = nay_fone_chave(tel));
    v := captacao_ficha(tel, 'outro', r.campos, false);
    RAISE NOTICE 'caso %: %', r.n, substring(v FROM '\): "([^"]*)"');
  END LOOP;
END $$;
