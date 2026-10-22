-- 471b: o teste do Unsplash no blog (Pedro, 22/10/2026: "testa aí se já consegue puxar para o blog, tem que ser uma
-- imagem que chame atenção mas tenha relação com o tema, de preferência passando alguma emoção").
-- Artigo 9, "Documentos para alugar apartamento em Manaus" (no ar desde 22/10 08:00, sem capa): o casal comemorando com a
-- chave do apartamento novo, a recompensa de quem juntou os documentos. Foto x8l4lN6-xd0 de Vitaly Gariev, servida
-- direto do Unsplash (hotlink, 1600 px); o uso já foi registrado no download_location dela.
-- Desfazer: UPDATE blog_artigo SET capa_url = NULL, capa_alt = NULL, capa_credito = NULL WHERE id = 9;

BEGIN;
UPDATE blog_artigo
   SET capa_url = 'https://images.unsplash.com/photo-1758523671285-9ff3f4e0ff38?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&ixid=M3wxMTEwNTY5fDB8MXxhbGx8fHx8fHx8fHwxNzkyNzA0NjA0fA&ixlib=rb-4.1.0&q=80&w=1600',
       capa_alt = 'Casal sorrindo e mostrando a chave no dia da mudança para o apartamento novo',
       capa_credito = '{"id": "x8l4lN6-xd0", "autor": "Vitaly Gariev", "perfil": "https://unsplash.com/@silverkblack?utm_source=pvlwordpress&utm_medium=referral", "fonte": "Unsplash", "fonte_url": "https://unsplash.com/?utm_source=pvlwordpress&utm_medium=referral", "pagina": "https://unsplash.com/photos/couple-happily-moving-into-a-new-home-x8l4lN6-xd0?utm_source=pvlwordpress&utm_medium=referral"}'::jsonb,
       atualizado_em = now()
 WHERE id = 9 AND capa_url IS NULL;
SELECT id, slug, left(capa_url, 60) capa, capa_credito->>'autor' autor FROM blog_artigo WHERE id = 9;
COMMIT;
