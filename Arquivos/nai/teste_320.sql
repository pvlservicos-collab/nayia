-- Testes da 320 (rodam dentro do ensaio, antes do ROLLBACK). Usam o lead de TESTE (835) e nada fica gravado.
CREATE TEMP TABLE _t (caso text, esperado text, veio text);
SELECT telefone AS tel FROM captacao_leads WHERE id = 835 \gset

UPDATE captacao_leads SET tratamento = 'Sr.', nome = 'PEDRO Silva', quer_vender = false WHERE id = 835;
INSERT INTO _t SELECT 'Sr., imóvel de locação',
  'Sr. Pedro, estamos com uma demanda alta de clientes querendo imóveis para locação nesse final de ano, o Sr. teria alguém para indicar que queira alugar ou vender?',
  captacao_indicacao_frase(:'tel');

UPDATE captacao_leads SET tratamento = 'Sra.', nome = 'maria das graças' WHERE id = 835;
INSERT INTO _t SELECT 'Sra., nome em minúscula',
  'Sra. Maria, estamos com uma demanda alta de clientes querendo imóveis para locação nesse final de ano, a Sra. teria alguém para indicar que queira alugar ou vender?',
  captacao_indicacao_frase(:'tel');

UPDATE captacao_leads SET tratamento = NULL, nome = 'Sra Ana Paula' WHERE id = 835;
INSERT INTO _t SELECT 'sem tratamento (o do nome não conta)',
  'Ana, estamos com uma demanda alta de clientes querendo imóveis para locação nesse final de ano, você teria alguém para indicar que queira alugar ou vender?',
  captacao_indicacao_frase(:'tel');

UPDATE captacao_leads SET tratamento = 'Sr.', nome = 'Pedro', quer_vender = true WHERE id = 835;
INSERT INTO _t SELECT 'quem quer vender ouve "comprar" e "vender ou alugar"',
  'Sr. Pedro, estamos com uma demanda alta de clientes querendo comprar imóveis nesse final de ano, o Sr. teria alguém para indicar que queira vender ou alugar?',
  captacao_indicacao_frase(:'tel');

-- imóvel que no cadastro só tem valor de venda: também é "de venda"
UPDATE captacao_leads SET quer_vender = false,
       codigo = (SELECT i.codigo::text FROM imoveis i WHERE coalesce(i.valor_venda, 0) > 0 AND coalesce(i.valor_aluguel, 0) = 0 ORDER BY i.codigo LIMIT 1)
 WHERE id = 835;
INSERT INTO _t SELECT 'imóvel só com valor de venda no cadastro', 'sim',
  CASE WHEN captacao_indicacao_frase(:'tel') LIKE '%querendo comprar imóveis%vender ou alugar?' THEN 'sim' ELSE captacao_indicacao_frase(:'tel') END;

INSERT INTO _t SELECT 'telefone que não é lead: a frase sem nome', 'sim',
  CASE WHEN captacao_indicacao_frase('5500000000000') LIKE 'Estamos com uma demanda alta%você teria alguém%' THEN 'sim' ELSE 'não' END;

-- a parede: enquanto a pergunta não saiu devolve a frase; depois que saiu, nada
UPDATE captacao_leads SET codigo = '99001' WHERE id = 835;
INSERT INTO captacao_mensagens (lead_id, telefone, direcao, origem, texto, status, message_id)
VALUES (835, :'tel', 'enviada', 'disparo', 'Olá, Sr. Pedro! (modelo de teste da 320)', 'Enviado', 'teste320-a');
INSERT INTO _t SELECT 'pendente: devolve a frase nova', captacao_indicacao_frase(:'tel'), captacao_indicacao_pendente(:'tel');
INSERT INTO captacao_mensagens (lead_id, telefone, direcao, origem, texto, status, message_id)
SELECT 835, :'tel', 'enviada', 'resposta', captacao_indicacao_frase(:'tel'), 'Enviado', 'teste320-b';
INSERT INTO _t SELECT 'depois que a frase saiu, não pede de novo', '(nada)', coalesce(captacao_indicacao_pendente(:'tel'), '(nada)');

SELECT caso, CASE WHEN esperado = veio THEN 'ok' ELSE 'FALHOU: ' || coalesce(veio, '(nulo)') END AS r FROM _t;

DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM _t WHERE esperado IS DISTINCT FROM veio;
  IF n > 0 THEN RAISE EXCEPTION '320: % teste(s) falharam', n; END IF;
END $$;
