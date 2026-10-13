-- testes da 361 (rodam dentro da transação do ensaio, antes do ROLLBACK)
\echo '== datas do contrato =='
SELECT t, captacao_data_do_contrato(t, date '2026-10-13') AS vira
  FROM unnest(ARRAY['até 15/10/2027', 'renovado em 15/09/2026, prazo nao informado', '2028 agosto', '10/2027', 'novembro',
                    'vence 30/11/2026', 'dezembro de 27 e 28', 'Até 2028', 'agosto de 2028', 'setembro de 3 anos']) t;

\echo '== valor de venda =='
SELECT t, captacao_valor_venda_num(t) AS vira
  FROM unnest(ARRAY['277k', '1.400.000', '165.000,00', '1800 mil', 'R$ 350 mil', '2,5', '160 ou 170 mil', '570.000']) t;

\echo '== resposta dos 6% =='
SELECT h.lead_id, left(h.resposta, 60) AS resposta, captacao_honorarios_tipo(h.lead_id) AS tipo
  FROM privado.captacao_honorarios h WHERE h.id IN (SELECT max(id) FROM privado.captacao_honorarios GROUP BY lead_id) ORDER BY 1;

\echo '== o histórico: quantas linhas de cada tipo (antigas = desde 08/10; novas = desta passada) =='
SELECT tipo, count(*) FILTER (WHERE criado_em < now()) AS antigas, count(*) FILTER (WHERE criado_em = now()) AS novas
  FROM privado.imovel_mudanca GROUP BY 1 ORDER BY 1;

\echo '== O QUE ESTA PASSADA MUDA NO CADASTRO =='
SELECT m.codigo, m.dono, m.campos, array_to_string(m.notas, ' # ') AS notas, jsonb_array_length(m.mensagens) AS msgs
  FROM privado.imovel_mudanca m WHERE m.criado_em = now() AND m.tipo = 'mudanca' ORDER BY m.id;

\echo '== o que esta passada NAO aplica (vira card com o motivo) =='
SELECT m.codigo, m.dono, left(array_to_string(m.notas, ' # '), 170) AS notas
  FROM privado.imovel_mudanca m WHERE m.criado_em = now() AND m.tipo = 'nao_aplicado' ORDER BY m.id;

\echo '== a tela, pelo papel do site =='
SET ROLE nay_site_escrita;
SELECT site_mudancas('revisar', NULL, 300)->'contagem' AS contagem,
       jsonb_array_length(site_mudancas('revisar', NULL, 300)->'itens') AS itens;
SELECT jsonb_pretty(site_mudancas(NULL, 5006, 10)->'itens'->0) AS historico_do_5006;

\echo '== voltar atrás e refazer (5006: valor de venda), pelo papel do site =='
SELECT imovel_mudanca_trocar((SELECT (site_mudancas(NULL, 5006, 10)->'itens'->0->>'id')::bigint), true, 'teste') AS desfez;
RESET ROLE;
SELECT codigo, status, valor_venda, travado, travado_motivo FROM imoveis WHERE codigo = 5006;
SET ROLE nay_site_escrita;
SELECT imovel_mudanca_trocar((SELECT (site_mudancas(NULL, 5006, 10)->'itens'->0->>'id')::bigint), false, 'teste') AS refez;
SELECT site_mudanca_revisar(ARRAY[(SELECT (site_mudancas(NULL, 5006, 10)->'itens'->0->>'id')::bigint)], true, 'teste') AS revisou;
SELECT site_mudancas('revisadas', NULL, 300)->'contagem' AS contagem_depois;
RESET ROLE;
SELECT codigo, status, valor_venda, travado, travado_motivo FROM imoveis WHERE codigo = 5006;

\echo '== voltar atrás numa mudança de situação antiga (a mais recente Disponível->Alugado ainda valendo) =='
SELECT m.id, m.codigo, m.campos, i.status FROM privado.imovel_mudanca m JOIN imoveis i ON i.codigo = m.codigo
 WHERE m.campos->'status'->>'para' = 'Alugado' AND i.status = 'Alugado' ORDER BY m.id DESC LIMIT 1 \gset t_
SELECT imovel_mudanca_trocar(:t_id, true, 'teste') AS desfez;
SELECT codigo, status, disponivel, publicado_no_site, travado_motivo FROM imoveis WHERE codigo = :t_codigo;
SELECT c.vencimento FROM contratos_locacao c WHERE c.codigo = (:t_codigo)::text;

\echo '== a segunda passada não cria linha nova =='
SELECT count(*) AS antes FROM privado.imovel_mudanca \gset
SELECT count(*) AS passadas FROM captacao_leads l, LATERAL captacao_aplicar_ao_cadastro(l.id) x
 WHERE l.situacao IS NOT NULL AND l.codigo ~ '^\d{1,9}$' AND EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = l.codigo::int) AND l.id <> (SELECT lead_id FROM privado.imovel_mudanca WHERE id = :t_id);
SELECT :antes AS antes, count(*) AS depois FROM privado.imovel_mudanca;

\echo '== a rodada de 5 min continua rodando =='
SELECT count(*) AS linhas FROM captacao_aplicar_pendentes();
