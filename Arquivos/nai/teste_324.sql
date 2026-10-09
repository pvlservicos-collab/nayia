-- testes da 324 (sem BEGIN/COMMIT)
-- o valor escrito de vários jeitos
CREATE TEMP TABLE t (pedido text);
INSERT INTO t VALUES ('650 mil líquido (ele disse em 11/09)'), ('R$ 350 mil'), ('570.000'), ('470.000 (ela paga 4% de comissao)'), ('2,5'), ('1.350.000,00'), ('350'), ('uns 800 mil'), ('não sei');
-- a mesma conta da função, isolada (a função lê o lead; aqui é só a regra do número)
SELECT pedido, (SELECT 'R$ ' || replace(to_char(CASE
             WHEN b IS NULL THEN NULL
             WHEN pedido ~* 'milh' THEN replace(replace(b, '.', ''), ',', '.')::numeric * 1000000
             WHEN pedido ~* '\mmil\M' THEN replace(replace(b, '.', ''), ',', '.')::numeric * 1000
             WHEN b ~ '^\d{1,2}(,\d+)?$' THEN replace(b, ',', '.')::numeric * 1000000
             WHEN b ~ '^\d{3}$' THEN b::numeric * 1000
             ELSE replace(split_part(b, ',', 1), '.', '')::numeric END, 'FM999,999,999'), ',', '.')
        FROM (SELECT (regexp_match(pedido, '(\d[\d\.]*(?:,\d+)?)'))[1] AS b) z) AS escrito
  FROM t;
-- leads reais: quantos ganham a pergunta, e três exemplos
SELECT 'com pergunta' AS o_que, count(*) FROM captacao_leads l WHERE captacao_honorarios_frase(l.telefone) IS NOT NULL;
SELECT 'sem pergunta (só locação)' AS o_que, count(*) FROM captacao_leads l WHERE captacao_honorarios_frase(l.telefone) IS NULL;
SELECT left(nome, 14) AS nome, valor_venda_pedido, captacao_honorarios_frase(telefone) AS frase FROM captacao_leads WHERE valor_venda_pedido IS NOT NULL LIMIT 3;
SELECT left(nome, 14) AS nome, captacao_honorarios_frase(telefone) AS frase FROM captacao_leads l
 WHERE valor_venda_pedido IS NULL AND captacao_honorarios_frase(telefone) IS NOT NULL LIMIT 2;
-- um lead COM a pergunta: pendente, perguntou, não pendente mais, guardar
CREATE TEMP TABLE alvo AS SELECT id, telefone FROM captacao_leads l WHERE captacao_honorarios_frase(l.telefone) IS NOT NULL ORDER BY id LIMIT 1;
SELECT 'pendente antes (tem de ser t)' AS o_que, captacao_honorarios_pendente(telefone) IS NOT NULL AS pendente FROM alvo;
INSERT INTO captacao_mensagens (lead_id, telefone, direcao, origem, texto, status)
SELECT id, telefone, 'enviada', 'resposta', captacao_honorarios_frase(telefone), 'Enviado' FROM alvo;
SELECT 'pendente depois de perguntar (tem de ser f)' AS o_que, captacao_honorarios_pendente(telefone) IS NOT NULL AS pendente FROM alvo;
SELECT captacao_honorarios_guardar(telefone, 'já está incluso') AS guardar FROM alvo;
SELECT captacao_honorarios_guardar(telefone, '') AS guardar_vazio FROM alvo;
SELECT h.lead_id = a.id AS lead_certo, h.valor, h.resposta FROM privado.captacao_honorarios h, alvo a ORDER BY h.id DESC LIMIT 1;
-- o lead de teste do Pedro (835) não tem venda: sem pergunta, e encerra sem ela
SELECT 'lead 835 sem pergunta (tem de ser t)' AS o_que, captacao_honorarios_pendente(telefone) IS NULL AS sem FROM captacao_leads WHERE id = 835;
