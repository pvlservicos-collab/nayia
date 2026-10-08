-- Testes da 321 (rodam dentro do ensaio, antes do ROLLBACK). A segunda metade aplica TUDO de verdade dentro da
-- transação desfeita: é a prévia do que a produção vai mudar.
CREATE TEMP TABLE _t (caso text, esperado text, veio text);

-- 1. a data do contrato, do jeito que os donos escreveram
INSERT INTO _t
SELECT 'data: ' || texto || ' (dito em ' || dito || ')', esperado, coalesce(captacao_data_do_contrato(texto, dito::date)::text, '(nada)')
  FROM (VALUES
    ('final de 2027', '2026-09-29', '2027-12-31'),
    ('Até dezembro agora', '2026-09-30', '2026-12-31'),
    ('junho do ano que vem', '2026-09-11', '2027-06-30'),
    ('julho de 27', '2026-09-12', '2027-07-31'),
    ('abril de 2028', '2026-09-12', '2028-04-30'),
    ('Até outubro de 2027', '2026-10-01', '2027-10-31'),
    ('Junho 2028', '2026-09-14', '2028-06-30'),
    ('final de dezembro de 2027', '2026-09-14', '2027-12-31'),
    ('Ate fevereiro de 2027', '2026-09-15', '2027-02-28'),
    ('por volta de dezembro/2026 (ela: contrato de 6 meses, 3 ja corridos em 15/09)', '2026-09-15', '2026-12-31'),
    ('2 anos, Outubro/28', '2026-10-06', '2028-10-31'),
    ('Setembro 28', '2026-10-07', '2028-09-30'),
    ('setembro, daqui a 1 ano', '2026-10-07', '2027-09-30'),
    ('mês de agosto', '2026-10-05', '2027-08-31'),
    ('maio', '2026-10-08', '2027-05-31'),
    ('até dezembro', '2026-10-08', '2026-12-31'),
    ('dezembro/2027', '2026-09-15', '2027-12-31'),
    -- o que NÃO vira data sozinho
    ('setembro de 3 anos', '2026-09-10', '(nada)'),
    ('renova anualmente', '2026-09-10', '(nada)'),
    ('ano que vem', '2026-09-14', '(nada)'),
    ('Até 2028', '2026-09-14', '(nada)'),
    ('2027', '2026-10-06', '(nada)'),
    ('dezembro de 27 e 28', '2026-10-04', '(nada)'),
    ('de maio a março do ano que vem', '2026-10-07', '(nada)'),
    ('renovado em 15/09/2026, prazo nao informado', '2026-09-15', '(nada)'),
    ('Só Deus sabe', '2026-10-04', '(nada)'),
    ('não tem mês marcado', '2026-10-06', '(nada)'),
    ('no outro mês o contrato encerra', '2026-10-08', '(nada)'),
    ('dezembro de 2019', '2026-10-08', '(nada)')
  ) v(texto, dito, esperado);

-- 2. a foto de antes de aplicar, para comparar
CREATE TEMP TABLE _antes AS
SELECT i.codigo, i.status, i.valor_aluguel, i.publicado_no_site, i.disponivel, i.travado_motivo,
       (SELECT max(c.vencimento) FROM contratos_locacao c WHERE c.codigo = i.codigo::text) AS vencimento
  FROM imoveis i WHERE i.codigo::text IN (SELECT codigo FROM captacao_leads WHERE situacao IS NOT NULL);
SELECT count(*) AS avisos_antes FROM aviso_de_saida WHERE avisado_em IS NULL \gset
SELECT count(*) AS fotos_a_puxar FROM captacao_fotos_a_puxar() \gset

-- 3. APLICA TUDO (sem esperar o silêncio)
CREATE TEMP TABLE _r1 AS SELECT * FROM captacao_aplicar_pendentes('0 seconds', 1000);
CREATE TEMP TABLE _r2 AS SELECT * FROM captacao_aplicar_pendentes('0 seconds', 1000);

INSERT INTO _t SELECT 'a segunda rodada não acha mais nada para fazer', '0', (SELECT count(*)::text FROM _r2);
INSERT INTO _t SELECT 'nenhuma rodada deu erro', '0', (SELECT count(*)::text FROM _r1 WHERE EXISTS (SELECT 1 FROM unnest(conferir) c WHERE c LIKE 'erro%'));
INSERT INTO _t SELECT 'o lead de teste ficou de fora', '0', (SELECT count(*)::text FROM _r1 WHERE lead_id = 835);
INSERT INTO _t SELECT 'nenhum aviso de saída novo para os grupos', :'avisos_antes', (SELECT count(*)::text FROM aviso_de_saida WHERE avisado_em IS NULL);
INSERT INTO _t SELECT 'o 293 (anunciado para venda, dono disse alugado) não mudou', 'Disponível', (SELECT status FROM imoveis WHERE codigo = 293);
INSERT INTO _t SELECT 'o 3347 (venda e locação, dono disse alugado) não mudou', 'Disponível', (SELECT status FROM imoveis WHERE codigo = 3347);
INSERT INTO _t SELECT 'e os dois ficaram anotados para conferir', '2',
  (SELECT count(*)::text FROM _r1 WHERE codigo IN (293, 3347) AND EXISTS (SELECT 1 FROM unnest(conferir) c WHERE c LIKE '%anunciado para VENDA%'));
INSERT INTO _t SELECT 'vendido que estava Alugado virou Vendido (1651)', 'Vendido', (SELECT status FROM imoveis WHERE codigo = 1651);
INSERT INTO _t SELECT 'alugado que estava Arquivado virou Alugado (3765)', 'Alugado', (SELECT status FROM imoveis WHERE codigo = 3765);
INSERT INTO _t SELECT 'disponível sem foto: Disponível, fora do site, travado (1875)', 'Disponível/false/captação',
  (SELECT status || '/' || publicado_no_site || '/' || left(travado_motivo, 8) FROM imoveis WHERE codigo = 1875);
INSERT INTO _t SELECT 'o valor que o dono deu entrou (3755: 1200 -> 1700)', '1700', (SELECT valor_aluguel::int::text FROM imoveis WHERE codigo = 3755);
INSERT INTO _t SELECT 'valor com vários números não entrou (1544 continua 3500)', '3500', (SELECT valor_aluguel::int::text FROM imoveis WHERE codigo = 1544);
INSERT INTO _t SELECT 'o fim do contrato entrou (2012: final de 2027)', '2027-12-31', (SELECT max(vencimento)::text FROM contratos_locacao WHERE codigo = '2012');
INSERT INTO _t SELECT 'o que não vira data não mexeu no vencimento (2101: renova anualmente)', '2023-06-10', (SELECT max(vencimento)::text FROM contratos_locacao WHERE codigo = '2101');
INSERT INTO _t SELECT 'quem já batia não foi tocado', '0',
  (SELECT count(*)::text FROM _antes a JOIN imoveis i USING (codigo)
    WHERE i.status = a.status AND i.travado_motivo IS DISTINCT FROM a.travado_motivo);
INSERT INTO _t SELECT 'nenhum imóvel entrou no site sem foto', '0',
  (SELECT count(*)::text FROM _antes a JOIN imoveis i USING (codigo)
    WHERE i.publicado_no_site AND NOT a.publicado_no_site AND NOT EXISTS (SELECT 1 FROM imovel_fotos f WHERE f.codigo = i.codigo));

-- 4. a foto chegou: o 3755 (10 fotos na conversa) entra no site na rodada seguinte
INSERT INTO _t SELECT 'as fotos da conversa do 3755 estão na lista de puxar', 'sim',
  CASE WHEN (SELECT count(*) FROM captacao_fotos_a_puxar() WHERE codigo = 3755) = 10 THEN 'sim' ELSE (SELECT count(*)::text FROM captacao_fotos_a_puxar() WHERE codigo = 3755) END;
INSERT INTO imovel_fotos (codigo, ordem, url, e_capa)
SELECT codigo, ordem, 'https://imobeasy.online/fotos-captacao/crm/' || codigo || '/' || foto_id || '.jpg', ordem = 1 FROM captacao_fotos_a_puxar() WHERE codigo = 3755;
INSERT INTO _t SELECT 'depois de trazidas, não pede as mesmas de novo', '0', (SELECT count(*)::text FROM captacao_fotos_a_puxar() WHERE codigo = 3755);
CREATE TEMP TABLE _r3 AS SELECT * FROM captacao_aplicar_pendentes('0 seconds', 1000);
INSERT INTO _t SELECT 'com foto, o 3755 entrou no site', 'true', (SELECT publicado_no_site::text FROM imoveis WHERE codigo = 3755);
INSERT INTO _t SELECT 'e o 1875 (sem foto nenhuma) continua fora', 'false', (SELECT publicado_no_site::text FROM imoveis WHERE codigo = 1875);

SELECT CASE WHEN esperado = veio THEN 'ok' ELSE 'FALHOU' END AS r, caso, CASE WHEN esperado = veio THEN '' ELSE 'esperado ' || esperado || ', veio ' || coalesce(veio, '(nulo)') END AS detalhe FROM _t;

\echo '== PRÉVIA: o que muda no cadastro'
SELECT r.lead_id AS lead, r.codigo, r.mudou FROM _r1 r WHERE r.mudou <> '{}'::jsonb ORDER BY r.mudou::text ~ 'status' DESC, r.codigo;
\echo '== PRÉVIA: o que fica para gente conferir'
SELECT r.lead_id AS lead, r.codigo, c AS conferir FROM _r1 r, unnest(r.conferir) c ORDER BY c, r.codigo;
\echo '== PRÉVIA: resumo'
SELECT count(*) AS leads_olhados, count(*) FILTER (WHERE mudou ? 'status') AS situacao_mudou, count(*) FILTER (WHERE mudou ? 'valor_aluguel') AS valor_mudou,
       count(*) FILTER (WHERE mudou ? 'vencimento') AS vencimento_mudou, count(*) FILTER (WHERE conferir <> '{}') AS com_algo_para_conferir,
       :fotos_a_puxar AS fotos_a_puxar FROM _r1;

DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM _t WHERE esperado IS DISTINCT FROM veio;
  IF n > 0 THEN RAISE EXCEPTION '321: % teste(s) falharam', n; END IF;
END $$;
