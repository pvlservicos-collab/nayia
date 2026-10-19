SET ROLE nay_site_escrita;
SELECT site_blog_salvar('{"titulo":"TESTE 412 agendado","categoria":"clientes","corpo":"x","agendado_para":"2099-01-01T12:00:00-04:00"}'::jsonb, 'teste') AS agendou \gset
SELECT (:'agendou'::jsonb->>'id')::bigint AS aid \gset
SELECT a->>'publicado' pub, a->>'agendado_para' ag FROM jsonb_array_elements(site_blog_admin_lista()) a WHERE (a->>'id')::bigint = :aid;
SELECT site_blog_salvar(('{"id":' || :aid || ',"titulo":"TESTE 412 agendado","categoria":"clientes","corpo":"x","agendado_para":"2000-01-01T12:00:00-04:00"}')::jsonb, 'teste') AS agendado_no_passado_publica;
SELECT site_blog_salvar('{"titulo":"TESTE 412 futuro","categoria":"clientes","corpo":"x","agendado_para":"2099-01-01T12:00:00-04:00"}'::jsonb, 'teste') AS outro \gset
RESET ROLE;
UPDATE blog_artigo SET agendado_para = now() - interval '1 minute' WHERE id = (:'outro'::jsonb->>'id')::bigint;
SELECT blog_publicar_agendados() AS publicados_pelo_cron, (SELECT publicado FROM blog_artigo WHERE id = (:'outro'::jsonb->>'id')::bigint) AS ficou_publicado;
SELECT count(*) AS publicos_de_teste_visiveis FROM jsonb_array_elements(site_blog_lista(NULL,NULL,50,0)->'artigos') x WHERE x->>'titulo' LIKE 'TESTE 412%';
DELETE FROM blog_artigo WHERE titulo LIKE 'TESTE 412%';
