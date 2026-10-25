SELECT jsonb_array_length(site_inteligencias()) AS regras;
SELECT site_inteligencia_salvar('{"regra": "Pet: perguntar o porte antes de falar com o proprietário.", "vale_para": ["parceria", "leads", "xx"]}', 'teste') AS nova;
SELECT regra, origem, vale_para, aplicada_em FROM nay_inteligencia_geral WHERE criada_por = 'teste';
SELECT max(id) AS ultimo FROM nay_inteligencia_geral \gset
SET ROLE nay_site_escrita;
SELECT jsonb_array_length(site_inteligencias()) AS como_o_site;
SELECT site_inteligencia_salvar(jsonb_build_object('id', :ultimo, 'regra', 'mudou', 'aplicada_em', '["leads"]'::jsonb), 'teste') AS mudou;
RESET ROLE;
SELECT regra, aplicada_em FROM nay_inteligencia_geral ORDER BY id DESC LIMIT 1;
