-- Testes da 356 (dentro do ensaio, antes do ROLLBACK)
CREATE TEMP TABLE _t (caso text, esperado text, veio text);
INSERT INTO _t SELECT 'ninguém em conversa ou na fila fica com "no Casa" / "no Prédio"', '0',
  (SELECT count(*)::text FROM captacao_leads WHERE status IN ('novo','enviado','respondendo','erro')
      AND imovel_desc ~* '^no (casa|pr[eé]dio|apartamento em via p[uú]blica|terreno|lote|sala)$');
INSERT INTO _t SELECT 'o Sr. Júlio (3166) passa a "no bairro ..."', 'sim',
  (SELECT CASE WHEN imovel_desc LIKE 'no bairro %' THEN 'sim' ELSE imovel_desc END FROM captacao_leads WHERE codigo = '3166' AND quem_importou LIKE 'Pedro (lista 6%');
INSERT INTO _t SELECT 'condomínio de verdade não muda (Forest Hill, Mundi Resort)', '0',
  (SELECT count(*)::text FROM captacao_leads WHERE condominio IN ('Forest Hill', 'Mundi Resort', 'Quinta das Marinas') AND imovel_desc LIKE 'no bairro %');
INSERT INTO _t SELECT 'quem já concluiu não muda', (SELECT count(*)::text FROM captacao_leads WHERE status IN ('concluido','sem_whatsapp') AND imovel_desc LIKE 'no bairro %'),
  (SELECT count(*)::text FROM captacao_leads WHERE status IN ('concluido','sem_whatsapp') AND imovel_desc LIKE 'no bairro %');
SELECT CASE WHEN esperado = veio THEN 'ok' ELSE 'FALHOU' END AS r, caso,
       CASE WHEN esperado = veio THEN '' ELSE 'esperado ' || esperado || ', veio ' || coalesce(veio, '(nulo)') END AS detalhe FROM _t;
SELECT condominio, imovel_desc, status, count(*) FROM captacao_leads
 WHERE atualizado_em > now() - interval '1 minute' AND imovel_desc LIKE 'no bairro %' GROUP BY 1,2,3 ORDER BY 1,2;
