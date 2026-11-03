-- 568 (Pedro, 02/11/2026: "sobe os imóveis novos cadastrados no Chaves na Mão"). O portal lê só a escolha publicada
-- (privado.cnm_envio_selecao, a URL /api/chavesnamao/envio.xml). Dos imóveis novos, o único pronto para o portal e fora da
-- escolha era o 9044; ele entra no fim da lista, sem destaque. O 9118 (sem foto) e o 9040 (sem tipo) não passam no portal.
BEGIN;
SELECT cnm_envio_publicar(s.ids || ARRAY[9044], s.destaques, 'Claude (pedido do Pedro, 02/11: imóveis novos)')
  FROM privado.cnm_envio_selecao s WHERE s.id = 1 AND NOT 9044 = ANY (s.ids);
SELECT cardinality(ids) AS publicados, cardinality(destaques) AS destaques, 9044 = ANY (ids) AS tem_9044
  FROM privado.cnm_envio_selecao WHERE id = 1;
COMMIT;
