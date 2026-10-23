-- ensaio da 480: os 9 grupos e as chaves
SELECT nome, locacao, venda, locacao_min, venda_min, ativo FROM privado.busca_grupo ORDER BY nome;
SELECT chave, valor FROM privado.olx_config WHERE chave IN ('busca_fluxo', 'busca_grupos', 'busca_olx', 'busca_corretor') ORDER BY 1;
DO $$ BEGIN
  IF (SELECT count(*) FROM privado.busca_grupo WHERE ativo) <> 9 THEN RAISE EXCEPTION 'esperava 9 grupos ativos'; END IF;
  IF (SELECT count(*) FROM privado.olx_config WHERE chave IN ('busca_olx', 'busca_corretor') AND valor = 'sim') <> 2 THEN
    RAISE EXCEPTION 'busca_olx e busca_corretor deviam estar em sim'; END IF;
END $$;
