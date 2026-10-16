-- 377 -- O SITE ANTIGO MANDA: status, valor, financia e condomínio de 116 imóveis como estão no antigo
--
-- Pedro, 16/10/2026: "o Tel fez mudanças nos status dos imóveis do site antigo, preciso que você atualize as do novo
-- baseado nessas mudanças" -- com a comparação dos dois sites (117 diferenças: "valor no antigo -> no novo"). Perguntado,
-- respondeu "faz todas essas no site novo" e "tudo aí muda no site novo": vale também para as 55 que estavam travadas
-- no novo (30 mudadas à mão no admin, 25 ditas pelo dono na captação) e para valor, financia e condomínio.
--
-- O status entra como o admin grava (PUT /admin/api/imoveis/<cod>): disponível e no site só quando é Disponível (nunca
-- para imóvel de parceiro) e a trava com o motivo, para a varredura diária não desfazer.
-- O VALOR DE RESERVA: a lista do admin (vw_imoveis_todos) completa valor, financia e condomínio vazios com
-- imoveis_admin_detalhe, a cópia do admin antigo de setembro. Quando o antigo está VAZIO hoje, a reserva também é
-- limpa; sem isso a lista mostraria de novo o valor velho (era de onde vinham os R$ 7.500 do 2202).
-- Cópia de antes: privado.imoveis_antes_377 e privado.imoveis_admin_detalhe_antes_377.
-- Fora: 5745 (Smart Vista do Sol 1) existe só no antigo, e lá está Removido.

BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS privado.imoveis_antes_377 AS SELECT now() AS copiado_em, i.* FROM imoveis i WHERE false;
INSERT INTO privado.imoveis_antes_377 SELECT now(), i.* FROM imoveis i WHERE i.codigo IN (193, 216, 293, 331, 462, 505, 964, 1179, 1281, 1441, 1487, 1500, 1569, 1622, 1651, 1696, 1699, 1827, 1840, 1850, 1875, 1877, 1885, 1902, 2052, 2095, 2127, 2133, 2146, 2193, 2202, 2215, 2228, 2266, 2298, 2304, 2342, 2411, 2420, 2465, 2503, 2626, 2876, 3050, 3132, 3134, 3147, 3205, 3266, 3347, 3437, 3456, 3463, 3564, 3566, 3568, 3581, 3592, 3605, 3612, 3613, 3641, 3647, 3740, 3755, 3760, 3765, 3827, 3839, 3879, 3883, 3892, 3972, 3990, 4086, 4161, 4170, 4252, 4255, 4322, 4336, 4437, 4458, 4517, 4525, 4578, 4802, 4807, 4812, 4870, 4879, 4899, 4946, 4980, 4982, 5046, 5076, 5278, 5326, 5374, 5447, 5473, 5485, 5606, 5609, 5614, 5644, 5664, 5666, 5699, 5711, 5713, 5723, 5738, 5744, 5753);
CREATE TABLE IF NOT EXISTS privado.imoveis_admin_detalhe_antes_377 AS SELECT now() AS copiado_em, d.* FROM imoveis_admin_detalhe d WHERE false;
INSERT INTO privado.imoveis_admin_detalhe_antes_377 SELECT now(), d.* FROM imoveis_admin_detalhe d
 WHERE d.codigo IN ('193', '216', '293', '331', '462', '505', '964', '1179', '1281', '1441', '1487', '1500', '1569', '1622', '1651', '1696', '1699', '1827', '1840', '1850', '1875', '1877', '1885', '1902', '2052', '2095', '2127', '2133', '2146', '2193', '2202', '2215', '2228', '2266', '2298', '2304', '2342', '2411', '2420', '2465', '2503', '2626', '2876', '3050', '3132', '3134', '3147', '3205', '3266', '3347', '3437', '3456', '3463', '3564', '3566', '3568', '3581', '3592', '3605', '3612', '3613', '3641', '3647', '3740', '3755', '3760', '3765', '3827', '3839', '3879', '3883', '3892', '3972', '3990', '4086', '4161', '4170', '4252', '4255', '4322', '4336', '4437', '4458', '4517', '4525', '4578', '4802', '4807', '4812', '4870', '4879', '4899', '4946', '4980', '4982', '5046', '5076', '5278', '5326', '5374', '5447', '5473', '5485', '5606', '5609', '5614', '5644', '5664', '5666', '5699', '5711', '5713', '5723', '5738', '5744', '5753');

-- 1. o status
UPDATE imoveis i SET status = v.st,
       disponivel = (v.st = 'Disponível'),
       publicado_no_site = (v.st = 'Disponível' AND NOT coalesce(i.e_parceiro, false)),
       travado = true, travado_motivo = 'site antigo: o Tel atualizou lá (Pedro, 16/10)', travado_em = now()
  FROM (VALUES (193, 'Alugado'), (1179, 'Alugado'), (1281, 'Alugado'), (1487, 'Alugado'), (1651, 'Alugado'), (1696, 'Alugado'), (1827, 'Alugado'), (1902, 'Alugado'), (2052, 'Alugado'), (2095, 'Alugado'), (2127, 'Alugado'), (2146, 'Alugado'), (2503, 'Alugado'), (2626, 'Alugado'), (3147, 'Alugado'), (3566, 'Alugado'), (3581, 'Alugado'), (3740, 'Alugado'), (3839, 'Alugado'), (3892, 'Alugado'), (4086, 'Alugado'), (4252, 'Alugado'), (964, 'Alugado'), (1500, 'Alugado'), (1569, 'Alugado'), (1875, 'Alugado'), (3050, 'Alugado'), (3641, 'Alugado'), (4255, 'Alugado'), (4517, 'Alugado'), (4802, 'Alugado'), (216, 'Alugado'), (3755, 'Alugado'), (4812, 'Alugado'), (1877, 'Alugado'), (2133, 'Alugado'), (1850, 'Disponível'), (2193, 'Disponível'), (3605, 'Disponível'), (5374, 'Disponível'), (5713, 'Disponível'), (293, 'Disponível'), (4161, 'Disponível'), (1441, 'Disponível'), (3132, 'Disponível'), (4437, 'Disponível'), (4980, 'Disponível'), (5606, 'Disponível'), (5711, 'Disponível'), (5738, 'Disponível'), (3760, 'Disponível'), (5664, 'Disponível'), (5744, 'Disponível'), (3613, 'Disponível'), (3827, 'Disponível'), (4899, 'Disponível'), (5485, 'Disponível'), (3437, 'Vendido'), (3564, 'Vendido'), (4458, 'Vendido'), (4870, 'Vendido'), (4982, 'Vendido'), (5278, 'Vendido'), (5473, 'Vendido'), (5753, 'Vendido'), (1885, 'Vendido'), (3456, 'Vendido'), (505, 'Arquivado'), (2215, 'Arquivado'), (2266, 'Arquivado'), (3765, 'Arquivado'), (3972, 'Arquivado'), (4336, 'Arquivado'), (4578, 'Arquivado'), (5046, 'Arquivado'), (5614, 'Arquivado'), (5326, 'Arquivado'), (3205, 'Removido'), (3463, 'Removido'), (3612, 'Removido'), (4322, 'Removido'), (2304, 'Removido'), (2420, 'Removido'), (1699, 'Removido'), (2342, 'Rascunho'), (4946, 'Rascunho'), (3568, 'Revisão'), (3990, 'Revisão')) v(codigo, st)
 WHERE i.codigo = v.codigo;

-- 2. os valores
UPDATE imoveis i SET valor_venda = v.valor FROM (VALUES (216, 860000::numeric), (4812, 850000::numeric), (1441, 550000::numeric), (2298, 750000::numeric), (2465, 2500000::numeric), (3347, 1500000::numeric), (5666, 1800000::numeric), (5723, 596000::numeric), (3266, NULL::numeric), (3647, NULL::numeric), (5644, NULL::numeric)) v(codigo, valor) WHERE i.codigo = v.codigo;
UPDATE imoveis i SET valor_aluguel = v.valor FROM (VALUES (3755, 1200::numeric), (293, NULL::numeric), (4161, NULL::numeric), (2342, 1500::numeric), (5447, 2500::numeric), (2202, NULL::numeric), (2228, NULL::numeric), (2411, NULL::numeric), (3134, NULL::numeric), (4807, NULL::numeric), (5609, NULL::numeric)) v(codigo, valor) WHERE i.codigo = v.codigo;
UPDATE imoveis_admin_detalhe d SET valor_venda = NULL WHERE d.codigo IN ('3266', '3647', '5644');
UPDATE imoveis_admin_detalhe d SET valor_aluguel = NULL WHERE d.codigo IN ('293', '4161', '2202', '2228', '2411', '3134', '4807', '5609');

-- 3. aceita financiamento
UPDATE imoveis i SET extras = coalesce(i.extras, '{}'::jsonb) || jsonb_build_object('aceita financiamento', v.f)
  FROM (VALUES (4161, 'Sim'), (2411, 'Sim'), (3134, 'Sim'), (4807, 'Sim'), (5609, 'Sim'), (331, 'Não'), (3883, 'Não'), (4879, 'Não'), (462, 'Sim'), (5699, 'Sim')) v(codigo, f) WHERE i.codigo = v.codigo;

-- 4. o condomínio (vazio no antigo = vazio aqui, inclusive na reserva)
UPDATE imoveis i SET condominio_nome = v.nome FROM (VALUES (2876, 'Residencial Villaretto'::text), (3879, 'Residencial Villaretto'::text), (4170, NULL::text), (5076, NULL::text), (1622, 'Conquista Tarumã'::text), (1840, 'Conquista Tarumã'::text), (3592, 'Conquista Tarumã'::text), (4525, 'Conquista Tarumã'::text), (5326, 'Conquista Tarumã'::text)) v(codigo, nome) WHERE i.codigo = v.codigo;
UPDATE imoveis_admin_detalhe d SET condominio = NULL WHERE d.codigo IN ('4170', '5076');

COMMIT;
