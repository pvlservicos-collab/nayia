\pset pager off
-- o pedido do Júlio (1977) e o da Cristina (1962, casa mobiliada) nos filtros do nay-core
SELECT id, privado.grupo_pedido_filtros_para_nay(id) FROM privado.grupo_pedido WHERE id IN (1977, 1962, 1963);
-- a pergunta: nada sai de verdade (o ensaio desfaz), mas a caixa e o contexto nascem
SELECT site_captacao_grupos_perguntar(1921, 9003,
  'Oi! Vi seu pedido lá no grupo. Tenho um apartamento... Serve para o seu cliente?', 'ensaio') AS r;
SELECT final8, codigo, left(pergunta, 40) p, filtros FROM nay_contexto_do_grupo ORDER BY id DESC LIMIT 2;
SET ROLE nay_core;
SELECT count(*) AS o_nay_core_le FROM nay_contexto_do_grupo;
RESET ROLE;
