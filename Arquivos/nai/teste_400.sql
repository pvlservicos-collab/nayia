-- 400: imóvel de parceiro vai ao cliente final do 8595 (nunca à Parceria)
-- o card: para a Parceria igual a antes; para o cliente, completo
SELECT 'parceria' AS para, left(texto_pronto, 90) AS card, qtd_fotos FROM nai_card_do_imovel(5553)
UNION ALL SELECT 'cliente', left(texto_pronto, 90), qtd_fotos FROM nai_card_do_imovel(5553, true);
-- um nosso não muda
SELECT (SELECT texto_pronto FROM nai_card_do_imovel(5725)) = (SELECT texto_pronto FROM nai_card_do_imovel(5725, true)) AS nosso_igual;
-- quem pode receber: cliente comum sim, corretor dos grupos não
SELECT olx_pode_receber_parceiro('92991540843') AS cliente_felipe,
       olx_pode_receber_parceiro((SELECT telefone FROM corretores WHERE ativo LIMIT 1)) AS um_corretor,
       olx_imovel_vai_ao_cliente(5553, '92991540843') AS parceiro_ao_cliente,
       olx_imovel_vai_ao_cliente(5553, (SELECT telefone FROM corretores WHERE ativo LIMIT 1)) AS parceiro_ao_corretor,
       olx_imovel_vai_ao_cliente(5725, (SELECT telefone FROM corretores WHERE ativo LIMIT 1)) AS nosso_ao_corretor;
-- a busca: sem a chave igual a antes; com ela entram parceiros
SELECT count(*) AS sem_parceiro FROM olx_cliente_buscar('{"finalidade":"locacao","teto":"3000","bairros":["Ponta Negra"]}'::jsonb, '{}', 50);
SELECT count(*) AS com_parceiro, count(*) FILTER (WHERE i.e_parceiro) AS deles
  FROM olx_cliente_buscar('{"finalidade":"locacao","teto":"3000","bairros":["Ponta Negra"],"aceita_parceiro":"true"}'::jsonb, '{}', 50) b
  JOIN imoveis i ON i.codigo = b.codigo;
-- a marca à mão vence o site antigo
UPDATE imoveis SET extras = coalesce(extras, '{}') || '{"parceiro_manual":"nao"}' WHERE codigo = 5553;
SELECT codigo, e_parceiro AS depois_de_nao FROM imoveis WHERE codigo = 5553;
UPDATE imoveis SET e_parceiro = true WHERE codigo = 5553;   -- a leitura do site antigo regravando
SELECT codigo, e_parceiro AS sync_nao_desfaz FROM imoveis WHERE codigo = 5553;
UPDATE imoveis SET extras = extras || '{"parceiro_manual":"sim"}' WHERE codigo = 5725;
SELECT codigo, e_parceiro AS marcado_a_mao FROM imoveis WHERE codigo = 5725;
