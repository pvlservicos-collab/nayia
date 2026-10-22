-- teste da 470
\echo '--- o modelo do nó (escolhido e o padrão de quem não tem escolha)'
SELECT ia_modelo_do_no('captacao.atender', 'x') AS captacao, ia_modelo_do_no('core.classificador', 'gpt-6-luna') AS core;
\echo '--- registrar uma chamada da captação: 6.000 de entrada (2.000 em cache), 300 de saída'
SELECT ia_uso_registrar('captacao.atender', 'gpt-6-luna', 6000, 2000, 300);
SELECT no, modelo, custo_usd FROM privado.ia_uso ORDER BY id DESC LIMIT 1;
\echo '--- a página: tempo e um pedaço'
\timing on
SELECT jsonb_pretty(jsonb_build_object('totais', r->'totais', 'nos_core', (SELECT jsonb_object_agg(k, v) FROM jsonb_each(r->'nos') AS e(k, v) WHERE k LIKE 'core.%' OR k LIKE 'captacao%'),
                                       'n8n', r#>'{nos,n8n.corretor}', 'escolhidos', r->'escolhidos'))
  FROM (SELECT site_ia_modelos() AS r) x;
\timing off
\echo '--- trocar: um nó trocável, um que não é, um nome inválido'
SELECT site_ia_modelo_trocar('olx.whatsapp', 'gpt-6-sol', 'ensaio');
SELECT site_ia_modelo_trocar('core.classificador', 'gpt-6-sol', 'ensaio');
SELECT site_ia_modelo_trocar('olx.whatsapp', 'drop table; --', 'ensaio');
