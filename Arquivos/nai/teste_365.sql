-- testes da 365 (dentro da transação do ensaio)
\echo '== a edição que falha não volta em laço =='
SELECT codigo, negocio, ad_id, anuncio, hash FROM olx_anuncios_plano() LIMIT 1 \gset p_
SELECT olx_anuncio_enviado(:'p_ad_id', :p_codigo, :'p_negocio', 'proprietarios', 'insert', :'p_anuncio'::jsonb, :'p_hash', 't1');
SELECT olx_anuncio_resultado(:'p_ad_id', 'publicado', '1777777777', NULL, NULL);
UPDATE imoveis SET valor_venda = valor_venda + 1000, valor_aluguel = valor_aluguel + 100 WHERE codigo = :p_codigo;
SELECT acao, ad_id, anuncio, hash FROM olx_anuncios_plano() WHERE ad_id = :'p_ad_id' \gset e_
SELECT :'e_acao' AS acao_antes_da_falha;
SELECT olx_anuncio_falhou(:'p_ad_id', :p_codigo, :'p_negocio', 'proprietarios', :'e_anuncio'::jsonb, :'e_hash', 'a OLX recusou na validação: NO_REGION');
SELECT estado, mensagem, tentativas FROM privado.olx_anuncio WHERE ad_id = :'p_ad_id';
SELECT count(*) AS volta_ao_plano_sem_o_cadastro_mudar FROM olx_anuncios_plano(500) WHERE ad_id = :'p_ad_id';
UPDATE imoveis SET valor_venda = valor_venda + 1000, valor_aluguel = valor_aluguel + 100 WHERE codigo = :p_codigo;
SELECT acao AS volta_quando_o_cadastro_muda FROM olx_anuncios_plano(500) WHERE ad_id = :'p_ad_id';

\echo '== recusado na edição, com a versão antiga no ar: sai quando o imóvel sai =='
SELECT olx_anuncio_resultado(:'p_ad_id', 'recusado', NULL, NULL, 'REFUSED_GENERIC');
SELECT estado, list_id FROM privado.olx_anuncio WHERE ad_id = :'p_ad_id';
UPDATE imoveis SET status = 'Vendido' WHERE codigo = :p_codigo;
SELECT acao, ad_id, motivo FROM olx_anuncios_plano(500) WHERE ad_id = :'p_ad_id';
