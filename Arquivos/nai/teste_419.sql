-- testes da 419 (dentro do ensaio): ./scripts/nay ensaio Arquivos/nai/419_aprovar_imoveis.sql Arquivos/nai/teste_419.sql
\pset pager off
SET ROLE nay_site_escrita;
WITH l AS (SELECT x FROM jsonb_array_elements(site_aprovar_imoveis()->'itens') x)
SELECT x->>'fonte' fonte, x->>'origem' origem, x->>'status' status, count(*) FROM l GROUP BY 1,2,3 ORDER BY 1,2,3;
WITH l AS (SELECT x FROM jsonb_array_elements(site_aprovar_imoveis()->'itens') x)
SELECT x->>'chave' chave, left(x->>'origem_detalhe', 70) detalhe, left(x->>'motivo', 70) motivo, x->'campos'->>'tipo' tipo,
       x->'campos'->>'bairro' bairro, x->'campos'->>'valor_aluguel' aluguel, x->'campos'->>'valor_venda' venda, x->>'fotos' fotos
  FROM l LIMIT 12;
-- tirar e voltar
SELECT site_aprovar_tirar((SELECT x->>'chave' FROM jsonb_array_elements(site_aprovar_imoveis()->'itens') x LIMIT 1), true, 'teste', 'ensaio');
SELECT (site_aprovar_imoveis()->>'fora')::int AS fora_depois_de_tirar;
RESET ROLE;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(site_aprovar_imoveis()->'itens') x
              JOIN imoveis i ON i.codigo = (x->>'codigo')::int WHERE i.e_parceiro OR i.status IN ('Disponível', 'Excluído')) THEN
    RAISE EXCEPTION 'parceiro, Disponível ou Excluído entrou na lista';
  END IF;
  RAISE NOTICE 'teste 419: ok';
END $$;
