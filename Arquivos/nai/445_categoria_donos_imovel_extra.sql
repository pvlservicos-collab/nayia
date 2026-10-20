-- 445 (Pedro, 20/10/2026): "eu pedi modelos novos lá, mas que perguntassem de um imóvel extra; vê se acha pra mim como
-- utilidade ou que podem se encaixar nisso". Medido na Meta em 20/10 à noite (listar_utilidade.js "" texto): 40 modelos
-- perguntam direto do imóvel extra, TODOS pendentes. outro_imovel_04 ("Cadastro de proprietário: ... possui outro imóvel
-- disponível além do que já consta conosco?") é o único com Utilidade provisória; os outros 9 outro_imovel_* e os 30
-- numero_novo_* estão com Marketing provisório (a Meta ainda pode mudar na revisão).
-- Duas categorias novas (★): a do 04, em destaque, e a dos que se encaixam. Só acrescenta; rodar de novo não duplica.
BEGIN;
INSERT INTO whats_modelo_nota (nome, idioma, etiquetas, atualizado_por)
SELECT v.nome, 'pt_BR', v.etiquetas, 'Claude (445, 20/10)'
  FROM (
    SELECT 'outro_imovel_04'::text AS nome,
           ARRAY['★ Donos · imóvel extra · Utilidade (aguardando a Meta)', '★ Donos · imóvel extra · todos os modelos novos']::text[] AS etiquetas
    UNION ALL
    SELECT 'outro_imovel_' || lpad(n::text, 2, '0'), ARRAY['★ Donos · imóvel extra · todos os modelos novos']::text[]
      FROM generate_series(1, 10) n WHERE n <> 4
    UNION ALL
    SELECT 'numero_novo_' || g || '_' || lpad(n::text, 2, '0'), ARRAY['★ Donos · imóvel extra · todos os modelos novos']::text[]
      FROM unnest(ARRAY['1a', '1b', '3', 'nay_a', 'nay_b']) g, generate_series(1, 6) n
  ) v
ON CONFLICT (nome, idioma) DO UPDATE SET
  etiquetas = (SELECT coalesce(array_agg(DISTINCT e ORDER BY e), '{}') FROM unnest(whats_modelo_nota.etiquetas || EXCLUDED.etiquetas) e),
  atualizado_por = EXCLUDED.atualizado_por, atualizado_em = now();
SELECT e AS categoria, count(*) FROM whats_modelo_nota, unnest(etiquetas) e WHERE e LIKE '★ Donos · imóvel extra%' GROUP BY 1 ORDER BY 1;
COMMIT;
