SELECT chave, valor, atualizado_por FROM privado.olx_config
 WHERE chave IN ('busca_grupos', 'busca_venda_min', 'busca_aluguel_min', 'busca_lote_min') ORDER BY chave;
