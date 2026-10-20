\pset pager off
-- um corretor dos grupos (o Júlio, 5516) e um número qualquer
SELECT crm_olx_busca_parceiro_abrir('{"telefone":"92999095516","finalidade":"locacao","teto":3000,"qualquer_bairro":true}') AS corretor;
SELECT olx_pode_receber_parceiro('92999095516') AS julio_pode;
