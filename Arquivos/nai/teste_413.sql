-- 413: parceiros antigos marcados e fora dos dois portões da Nay de captação; os novos do Tel continuam saindo
SELECT count(*) AS antigos_marcados, min(criado_em)::date AS de, max(criado_em)::date AS ate
  FROM imoveis WHERE coalesce(extras->>'parceiro_antigo', '') = 'sim';
SELECT codigo, status, origem, criado_em::date AS criado, extras->>'parceiro_manual' AS manual
  FROM imoveis WHERE e_parceiro AND coalesce(extras->>'parceiro_antigo', '') <> 'sim' ORDER BY codigo;
-- o código citado: antigo não vai; novo do Tel vai (cliente final com telefone)
SELECT codigo, status, imovel_parceiro_antigo(codigo) AS antigo, olx_imovel_vai_ao_cliente(codigo, '92991234567') AS vai_ao_cliente
  FROM imoveis WHERE codigo IN (3595, 2688, 9050, 9051) ORDER BY codigo;
-- a busca por perfil: venda em Flores até 870 mil com aceita_parceiro traz os novos (9050/9051), nenhum antigo
SELECT b.codigo, b.condominio, b.preco, imovel_parceiro_antigo(b.codigo) AS antigo
  FROM olx_cliente_buscar('{"finalidade":"venda","aceita_parceiro":"true","teto":"870000","bairros":["Flores"]}'::jsonb, '{}', 10) b;
SELECT count(*) AS antigos_na_busca_de_locacao
  FROM olx_cliente_buscar('{"finalidade":"locacao","aceita_parceiro":"true","qualquer_bairro":"true"}'::jsonb, '{}', 10) b
  JOIN imoveis i ON i.codigo = b.codigo WHERE coalesce(i.extras->>'parceiro_antigo', '') = 'sim';
-- a API do site (papel de leitura) consegue perguntar
SET ROLE nay_site_leitura;
SELECT imovel_parceiro_antigo(3595) AS leitura_antigo_3595, imovel_parceiro_antigo(9050) AS leitura_antigo_9050;
RESET ROLE;
