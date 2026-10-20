-- 425: a Meta terminou a revisão dos cadastro_imobeasy_01-30 (lido em 20/10). Troca a etiqueta "em revisão · enviado 19/10"
-- pela categoria final no painel (aba WhatsApp › Mensagens, whats_modelo_nota). Utilidade: 02 06 08 10 17 18 20-24 26 28 29.
BEGIN;
UPDATE whats_modelo_nota n
   SET etiquetas = (SELECT coalesce(array_agg(DISTINCT e ORDER BY e), '{}')
                      FROM unnest(array_remove(n.etiquetas, 'em revisão · enviado 19/10')
                                  || CASE WHEN n.nome IN ('cadastro_imobeasy_02','cadastro_imobeasy_06','cadastro_imobeasy_08','cadastro_imobeasy_10',
                                       'cadastro_imobeasy_17','cadastro_imobeasy_18','cadastro_imobeasy_20','cadastro_imobeasy_21','cadastro_imobeasy_22',
                                       'cadastro_imobeasy_23','cadastro_imobeasy_24','cadastro_imobeasy_26','cadastro_imobeasy_28','cadastro_imobeasy_29')
                                     THEN ARRAY['aprovado · utilidade'] ELSE ARRAY['aprovado · marketing'] END) e),
       atualizado_por = 'Claude (425, 20/10)', atualizado_em = now()
 WHERE n.nome ~ '^cadastro_imobeasy_(0[1-9]|[12][0-9]|30)$' AND n.idioma = 'pt_BR';
SELECT e, count(*) FROM whats_modelo_nota, unnest(etiquetas) e WHERE nome LIKE 'cadastro_imobeasy_%' GROUP BY e ORDER BY e;
COMMIT;
