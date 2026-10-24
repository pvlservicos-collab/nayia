-- 483 -- A lista "Modelos sábado" na página WhatsApp › Mensagens (Pedro, 24/10/2026): "põe os modelos aprovados lá na aba
-- modelos do site para eu ver, chama a lista de Modelos sábado". São os 8 outro_imovel_sair_* (o texto do outro_imovel_04
-- com o botão "Excluir meu contato"), todos APPROVED na Meta em 24/10 (01, 02, 04 e 06 como Marketing; 03, 05, 07 e 08 como
-- Utilidade). Só acrescenta a etiqueta (★ = categoria com botão na página); rodar de novo não duplica.
BEGIN;
INSERT INTO whats_modelo_nota (nome, idioma, etiquetas, atualizado_por)
SELECT 'outro_imovel_sair_' || lpad(n::text, 2, '0'), 'pt_BR', ARRAY['★ Modelos sábado']::text[], 'Claude (483, 24/10)'
  FROM generate_series(1, 8) n
ON CONFLICT (nome, idioma) DO UPDATE SET
  etiquetas = (SELECT coalesce(array_agg(DISTINCT e ORDER BY e), '{}') FROM unnest(whats_modelo_nota.etiquetas || EXCLUDED.etiquetas) e),
  atualizado_por = EXCLUDED.atualizado_por, atualizado_em = now();
SELECT nome, etiquetas FROM whats_modelo_nota WHERE '★ Modelos sábado' = ANY (etiquetas) ORDER BY nome;
COMMIT;
