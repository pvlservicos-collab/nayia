-- dentro do ensaio (ROLLBACK no fim). Nada disto sai nem fica.
\echo == com o papel do CRM: lê pela função
SET LOCAL ROLE nay_disparo;
SELECT count(*) AS linhas, count(*) FILTER (WHERE acao = 'abordar') AS abordar, count(*) FILTER (WHERE acao = 'fechar') AS fechar,
       count(*) FILTER (WHERE acao = 'abordar' AND mensagem IS NOT NULL AND entregue_em IS NOT NULL) AS abordar_com_mensagem,
       count(*) FILTER (WHERE titulo IS NOT NULL) AS com_titulo, count(*) FILTER (WHERE preco IS NOT NULL) AS com_preco
  FROM crm_olx_abordagens(500);
RESET ROLE;
\echo == e não entra no schema da tabela (perguntar pela tabela com esse papel dá "permission denied for schema privado")
SELECT has_schema_privilege('nay_disparo', 'privado', 'USAGE') AS entra_no_schema_esperado_f;
DO $$
BEGIN
  IF (SELECT count(*) FROM crm_olx_abordagens(500)) <> (SELECT count(*) FROM privado.anuncio_consulta)
     OR (SELECT count(*) FROM crm_olx_abordagens(1)) <> least(1, (SELECT count(*) FROM privado.anuncio_consulta))
     OR has_schema_privilege('nay_disparo', 'privado', 'USAGE') THEN
    RAISE EXCEPTION 'teste_313: a função não devolve o que está na tabela, ou o papel do CRM entra no schema privado';
  END IF;
END $$;
