-- 367: a lista do que a taxa inclui grava, substitui, e chave ausente não mexe
DO $$
DECLARE r jsonb; v text[];
BEGIN
  r := site_condominio_salvar(100, '{"taxa_inclui": ["Água", "Gás", "Energia", " ", "água"]}'::jsonb);
  IF NOT (r->>'ok')::boolean OR NOT (r->'mudou' ? 'taxa_inclui') THEN RAISE EXCEPTION 'não gravou: %', r; END IF;
  SELECT taxa_inclui INTO v FROM condominio_ficha WHERE condominio_id = 100;
  IF v <> ARRAY['Água', 'Gás', 'Energia'] THEN RAISE EXCEPTION 'lista errada: %', v; END IF;

  r := site_condominio_salvar(100, '{"observacao": "teste 367"}'::jsonb);
  SELECT taxa_inclui INTO v FROM condominio_ficha WHERE condominio_id = 100;
  IF v <> ARRAY['Água', 'Gás', 'Energia'] THEN RAISE EXCEPTION 'chave ausente mexeu: %', v; END IF;

  r := site_condominio_salvar(100, '{"taxa_inclui": []}'::jsonb);
  SELECT taxa_inclui INTO v FROM condominio_ficha WHERE condominio_id = 100;
  IF v <> '{}' THEN RAISE EXCEPTION 'lista vazia não apagou: %', v; END IF;
  RAISE NOTICE 'teste 367 ok';
END $$;

SELECT c.nome, f.taxa_inclui FROM condominio_ficha f JOIN condominios c ON c.id = f.condominio_id
 WHERE f.taxa_inclui <> '{}' ORDER BY cardinality(f.taxa_inclui) DESC, c.nome LIMIT 15;
