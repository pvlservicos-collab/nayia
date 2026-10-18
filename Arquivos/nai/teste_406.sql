-- 406: o blog, pelo papel do site
SET ROLE nay_site_escrita;
SELECT site_blog_salvar('{"titulo":"Como funciona a parceria de 50% da Imob Easy","resumo":"O corretor parceiro fica com metade da comissão. Veja como entrar.","categoria":"corretores","corpo":"## Parceria\n\nTexto de teste com algumas palavras.\n\n## Como entrar\n\nMande mensagem.","faq":[{"pergunta":"Quanto o corretor recebe?","resposta":"50% da comissão."}],"publicado":true}'::jsonb, 'ensaio') AS salvo \gset
SELECT :'salvo'::jsonb ->> 'slug' AS slug \gset
SELECT site_blog_salvar(('{"titulo":"Apartamento no Life Parque Dez","categoria":"locacao","tipo":"imovel","codigo":"5739","corpo":"Post de imóvel.","publicado":true}')::jsonb, 'ensaio') AS salvo2;
SELECT site_blog_salvar('{"titulo":"Como funciona a parceria de 50% da Imob Easy","categoria":"corretores","corpo":"outro","publicado":false}'::jsonb) ->> 'slug' AS slug_repetido_vira_2;
SELECT site_blog_salvar('{"titulo":"Sem categoria","corpo":"x"}'::jsonb) AS recusa;
SELECT (site_blog_lista(NULL, NULL, 12, 0)) -> 'total' AS publicados, jsonb_array_length(site_blog_lista('locacao', NULL, 12, 0) -> 'artigos') AS de_locacao;
SELECT a->>'slug' AS slug, a->'imovel'->>'condominio' AS imovel, jsonb_array_length(a->'proximos') AS proximos, jsonb_array_length(a->'outros') AS outros, a->>'bairro' AS bairro
  FROM site_blog_artigo('apartamento-no-life-parque-dez') a;
SELECT jsonb_array_length(site_blog_artigo(:'slug') -> 'proximos') AS proximos_do_post_sem_imovel;
SELECT site_blog_visita(:'slug', 'google'), site_blog_visita(:'slug', 'google'), site_blog_visita(:'slug', 'rastreador:gptbot'), site_blog_visita('nao-existe', 'x');
SELECT a->>'titulo', a->>'visitas_7d' AS v7, a->>'rastreadores_30d' AS r30 FROM jsonb_array_elements(site_blog_admin_lista()) a;
SELECT site_blog_metricas(NULL, NULL) -> 'total' AS total, site_blog_metricas(NULL, NULL) -> 'rastreadores' AS rastr;
SELECT site_blog_newsletter_cadastrar('Pedro Teste', '(92) 99999-0001', '1234') AS cad1;
SELECT site_blog_newsletter_cadastrar('Pedro Teste', '92999990001') ->> 'novo' AS de_novo_nao_e_novo;
SELECT site_blog_newsletter_cadastrar('X', '123') AS recusa_fone;
SELECT site_blog_newsletter_sair('92 99999-0001') AS saiu;
SELECT site_blog_newsletter_lista() -> 'ativos' AS ativos, site_blog_newsletter_lista() -> 'total' AS total;
SELECT site_blog_apagar(( :'salvo'::jsonb ->> 'id')::bigint) AS apagado;
RESET ROLE;
-- as boas-vindas entraram na fila (e saem no ROLLBACK)
SELECT papel_destino, motivo, left(texto, 60) FROM nai_saida WHERE motivo = 'newsletter_boas_vindas';
-- o cron: ninguém ativo agora (o teste saiu), 0
SELECT blog_newsletter_disparar() AS enviados_pelo_cron;
