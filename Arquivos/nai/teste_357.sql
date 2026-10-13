-- Testes da 357 (dentro do ensaio, antes do ROLLBACK). Usa o lead de TESTE da campanha; nada sai, nada fica.
CREATE TEMP TABLE _t (caso text, esperado text, veio text);
CREATE TEMP TABLE _lead AS
  SELECT l.id, l.telefone FROM captacao_leads l
   WHERE l.telefone_chave = nay_fone_chave((SELECT valor FROM captacao_config WHERE chave = 'telefone_teste'));
DELETE FROM captacao_cadastro WHERE lead_id = (SELECT id FROM _lead);
UPDATE captacao_leads SET tratamento = 'Sr.', situacao = 'alugado' WHERE id = (SELECT id FROM _lead);

-- a ficha de um imóvel NOVO, já com local, cômodos e área; o negócio muda de caso para caso
CREATE FUNCTION pg_temp.proxima(p_negocio text, p_condominio text DEFAULT NULL, p_valor text DEFAULT NULL) RETURNS text LANGUAGE plpgsql AS $$
DECLARE v text;
BEGIN
  DELETE FROM captacao_cadastro WHERE lead_id = (SELECT id FROM _lead);
  INSERT INTO captacao_cadastro (lead_id, tipo, estado, dados)
  VALUES ((SELECT id FROM _lead), 'novo', 'coletando',
          jsonb_strip_nulls(jsonb_build_object('tipo', 'casa', 'bairro', 'Tarumã', 'condominio', p_condominio, 'negocio', p_negocio,
                             'quartos', '4', 'banheiros', '4', 'vagas', '2', 'area', '336', 'valor', p_valor,
                             '_respondidas', jsonb_build_array('local', 'negocio', 'comodos', 'area')
                                             || CASE WHEN p_valor IS NULL THEN '[]'::jsonb ELSE '["valor"]'::jsonb END)));
  v := captacao_ficha((SELECT telefone FROM _lead), 'outro', '{}'::jsonb, true);
  RETURN v;
END $$;

INSERT INTO _t SELECT 'não decidiu: o valor não fala só de aluguel', 'true', (pg_temp.proxima(NULL) ~ 'pensa em pedir, no aluguel ou na venda\?')::text;
INSERT INTO _t SELECT 'não decidiu: nada de "quer pedir no aluguel"', 'false', (pg_temp.proxima(NULL) ~ 'quer pedir no aluguel')::text;
INSERT INTO _t SELECT '"ainda não decidimos" escrito: idem', 'true', (pg_temp.proxima('ainda não decidimos') ~ 'no aluguel ou na venda\?')::text;
INSERT INTO _t SELECT 'disse alugar: a frase de sempre', 'true', (pg_temp.proxima('alugar') ~ 'quer pedir no aluguel\?')::text;
INSERT INTO _t SELECT 'disse vender: a frase de sempre', 'true', (pg_temp.proxima('vender') ~ 'quer pedir na venda\?')::text;
INSERT INTO _t SELECT 'disse os dois: os dois valores', 'true', (pg_temp.proxima('ambos') ~ 'no aluguel e na venda\?')::text;
INSERT INTO _t SELECT 'não decidiu, taxas: sem "O aluguel já inclui"', 'false', (pg_temp.proxima(NULL, 'Alphaville 4', '18.000') ~ 'aluguel j')::text;
INSERT INTO _t SELECT 'não decidiu, taxas: pergunta condomínio e IPTU', 'true', (pg_temp.proxima(NULL, 'Alphaville 4', '18.000') ~ 'condom.nio e o IPTU')::text;
INSERT INTO _t SELECT 'disse alugar, taxas: "O aluguel já inclui" continua', 'true', (pg_temp.proxima('alugar', 'Alphaville 4', '18.000') ~ 'O aluguel j. inclui')::text;

SELECT CASE WHEN esperado = veio THEN 'ok' ELSE 'FALHOU' END AS r, caso,
       CASE WHEN esperado = veio THEN '' ELSE 'esperado ' || esperado || ', veio ' || coalesce(veio, '(nulo)') END AS detalhe FROM _t;
SELECT left(pg_temp.proxima(NULL), 260) AS sem_negocio_valor;
SELECT left(pg_temp.proxima(NULL, 'Alphaville 4', '18.000'), 260) AS sem_negocio_taxas;
