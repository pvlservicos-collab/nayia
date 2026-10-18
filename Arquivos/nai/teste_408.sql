-- testes da 408 (dentro do ensaio, antes do ROLLBACK)
\echo '--- listas existentes ganham pasta vazia e tipo lista'
SELECT id, nome, pasta, tipo, bloqueados FROM scrap_lista ORDER BY id LIMIT 6;

SET ROLE nay_site_escrita;
\echo '--- blacklist de 60 dias (lista nova na pasta Blacklist)'
SELECT site_scrap_lista_salvar('{"nome":"TESTE 408 falamos 60 dias","pasta":"Blacklist","tipo":"blacklist"}'::jsonb, 'teste') AS bl \gset
SELECT (:'bl'::jsonb->>'id')::bigint AS blid \gset
SELECT scrap_blacklist_60d(:blid) AS encheu;
SELECT count(*) na_blacklist, count(*) FILTER (WHERE nome IS NOT NULL) com_nome, count(*) FILTER (WHERE length(telefone) = 11) celulares
  FROM jsonb_to_recordset(site_scrap_contatos(:blid, NULL, NULL, NULL, NULL, 'anuncios', 100000, 0)->'contatos') AS x(telefone text, nome text);
SELECT c->>'nome' nome, c->>'telefone_fmt' tel, left(c->>'observacao', 60) obs FROM jsonb_array_elements(site_scrap_contatos(:blid, NULL, NULL, NULL, NULL, 'recentes', 3, 0)->'contatos') c;

\echo '--- as listas da OLX perderam quem está na blacklist (bloqueados > 0) e "Todas" não mistura a blacklist'
SELECT l->>'nome' nome, l->>'pasta' pasta, l->>'tipo' tipo, l->>'contatos' contatos, l->>'bloqueados' bloqueados
  FROM jsonb_array_elements(site_scrap_listas()->'listas') l ORDER BY l->>'pasta', (l->>'id')::int;
SELECT site_scrap_listas()->>'na_blacklist' na_blacklist, site_scrap_listas()->>'telefones_distintos' distintos_nas_normais, site_scrap_contatos(NULL)->>'total' todas;
RESET ROLE;
SELECT count(*) AS vazamentos FROM scrap_contato c JOIN scrap_lista l ON l.id = c.lista_id WHERE l.tipo = 'lista' AND c.origem = 'olx' AND scrap_bloqueado(c.telefone);
SET ROLE nay_site_escrita;

\echo '--- importar CSV numa lista normal pula a blacklist; numa blacklist entra; p_ignorar_blacklist entra'
SELECT site_scrap_lista_salvar('{"nome":"TESTE 408 normal","pasta":"OLX"}'::jsonb, 'teste') AS ln \gset
SELECT (:'ln'::jsonb->>'id')::bigint AS lnid \gset
SELECT c->>'telefone' AS telbl FROM jsonb_array_elements(site_scrap_contatos(:blid, '(92) 9', NULL, NULL, NULL, 'anuncios', 1, 0)->'contatos') c \gset
\echo 'telefone da blacklist usado no teste:' :telbl
SELECT site_scrap_importar_contatos(:lnid, jsonb_build_array(jsonb_build_object('nome', 'Bloqueado', 'telefone', :'telbl'), jsonb_build_object('nome', 'Livre', 'telefone', '92 98123-4567')), 'teste') AS csv_normal;
SELECT site_scrap_importar_contatos(:lnid, jsonb_build_array(jsonb_build_object('nome', 'Bloqueado forçado', 'telefone', :'telbl')), 'teste', true) AS csv_forcado;
SELECT site_scrap_contato_salvar(jsonb_build_object('lista_id', :lnid, 'nome', 'À mão', 'telefone', '92 98123-4567'), 'teste') AS mao_repetido;
SELECT (site_scrap_contato_salvar(jsonb_build_object('lista_id', :lnid, 'nome', 'À mão bloqueado', 'telefone', '92 98123-9999'), 'teste'))->>'ok' AS mao_ok;

\echo '--- rebuild de uma lista olx respeita a blacklist (reimporta a lista 1 e confere bloqueados)'
SELECT (site_scrap_importar(jsonb_build_object('lista', jsonb_build_object('id', 1, 'pasta', 'OLX'), 'anuncios', '[]'::jsonb), 'teste')) AS reimport_lista1;
RESET ROLE;
SELECT count(*) AS vazamentos_depois FROM scrap_contato c JOIN scrap_lista l ON l.id = c.lista_id WHERE l.tipo = 'lista' AND c.origem = 'olx' AND scrap_bloqueado(c.telefone);
SET ROLE nay_site_escrita;

SELECT site_scrap_lista_apagar(:lnid) AS apagou_normal, site_scrap_lista_apagar(:blid) AS apagou_bl;
RESET ROLE;
