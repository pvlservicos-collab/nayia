-- 534: as duas do Rayssa viraram Lucas; Lucas é aceito e cala a Nay; etapa errada é recusada
SELECT 'rayssa que sobrou' AS caso, count(*) AS n FROM captacao_etapa_manual WHERE etapa = 'rayssa';
SELECT 'lucas' AS caso, count(*) AS n FROM captacao_etapa_manual WHERE etapa = 'lucas';
SELECT 'escolher lucas' AS caso, ok, mensagem FROM crm_captacao_etapa_manual('5596991712835', 'lucas', 'teste 534');
SELECT 'etapa errada' AS caso, ok, mensagem FROM crm_captacao_etapa_manual('5596991712835', 'joao', 'teste 534');
