-- 446 (Pedro, 20/10/2026): "e os de disparo de apresentação para corretores? vê lá e cria outra lista lá". Medido na Meta
-- em 20/10 à noite (listar_utilidade.js): dos cadastro_imobeasy_01-40 e l1_util_*:
--   aprovados como Utilidade: cadastro_imobeasy 02 06 08 10 17 18 20 21 22 23 24 26 28 29 + l1_util_11-13 (cadastro de
--     corretor parceiro, botões Pedir imóvel por número / Grupo de corretores) + l1_util_16-19 (perfil Proprietário /
--     Corretor / Os dois: serve para quem não se sabe se é corretor);
--   aprovados como Marketing (saem, mas a Meta cobra mais): cadastro_imobeasy 01 03 04 05 07 09 11-16 19 25 27 30;
--   pendentes: cadastro_imobeasy_31-40 (33, 35 e 38 com Utilidade provisória).
-- Três categorias (★): a página WhatsApp › Mensagens mostra cada uma num botão. Só acrescenta; rodar de novo não duplica.
BEGIN;
INSERT INTO whats_modelo_nota (nome, idioma, etiquetas, atualizado_por)
SELECT v.nome, 'pt_BR', ARRAY[v.etiqueta]::text[], 'Claude (446, 20/10)'
  FROM (
    SELECT 'cadastro_imobeasy_' || lpad(n::text, 2, '0') AS nome, '★ Corretores · apresentação · Utilidade aprovada' AS etiqueta
      FROM unnest(ARRAY[2, 6, 8, 10, 17, 18, 20, 21, 22, 23, 24, 26, 28, 29]) n
    UNION ALL SELECT 'l1_util_' || n, '★ Corretores · apresentação · Utilidade aprovada' FROM unnest(ARRAY[11, 12, 13, 16, 17, 18, 19]) n
    UNION ALL
    SELECT 'cadastro_imobeasy_' || lpad(n::text, 2, '0'), '★ Corretores · apresentação · Marketing aprovada'
      FROM unnest(ARRAY[1, 3, 4, 5, 7, 9, 11, 12, 13, 14, 15, 16, 19, 25, 27, 30]) n
    UNION ALL
    SELECT 'cadastro_imobeasy_' || n, '★ Corretores · apresentação · aguardando a Meta' FROM generate_series(31, 40) n
  ) v
ON CONFLICT (nome, idioma) DO UPDATE SET
  etiquetas = (SELECT coalesce(array_agg(DISTINCT e ORDER BY e), '{}') FROM unnest(whats_modelo_nota.etiquetas || EXCLUDED.etiquetas) e),
  atualizado_por = EXCLUDED.atualizado_por, atualizado_em = now();
SELECT e AS categoria, count(*) FROM whats_modelo_nota, unnest(etiquetas) e WHERE e LIKE '★ Corretores%' GROUP BY 1 ORDER BY 1;
COMMIT;
