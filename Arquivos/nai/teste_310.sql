-- dentro do ensaio (ROLLBACK no fim). Nada disto sai nem fica.
SET LOCAL statement_timeout = '110s';
CREATE TEMP TABLE _t (n serial, caso text, esperado text, veio text) ON COMMIT DROP;

-- um apartamento nosso no mercado, com condomínio de nome próprio e com rua que dê para comparar
CREATE TEMP TABLE _r ON COMMIT DROP AS
SELECT i.codigo, i.tipo, i.bairro, i.condominio_nome, i.quartos, i.logradouro,
       coalesce(nullif(i.area_util, 0), nullif(i.area_total, 0)) AS area,
       CASE WHEN coalesce(i.valor_aluguel, 0) > 0 THEN 'aluguel' ELSE 'venda' END AS fin,
       CASE WHEN coalesce(i.valor_aluguel, 0) > 0 THEN i.valor_aluguel ELSE i.valor_venda END AS preco
  FROM imoveis i
 WHERE nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
   AND crm_anuncio_familia(i.tipo) = 'apartamento' AND coalesce(i.quartos, 0) > 0
   AND coalesce(nullif(i.area_util, 0), nullif(i.area_total, 0)) > 20
   AND coalesce(nullif(i.valor_aluguel, 0), nullif(i.valor_venda, 0)) > 0
   AND length(nay_sem_acento(lower(nai_condominio_nucleo(coalesce(i.condominio_nome, ''))))) >= 6
   AND nay_sem_acento(lower(nai_condominio_nucleo(i.condominio_nome))) NOT IN ('nao identificado', 'apartamento', 'predio')
   AND coalesce(i.bairro, '') <> ''
   AND length(btrim(regexp_replace(regexp_replace(nay_sem_acento(lower(coalesce(i.logradouro, ''))),
         '^\s*(rua|r\.?|avenida|av\.?|travessa|tv\.?|estrada|rodovia|alameda|al\.?)\s+', ''), '[,0-9-].*$', ''))) >= 8
 ORDER BY i.codigo DESC LIMIT 1;

-- 1. mesma rua, mesma área, mesmo preço, mesmos quartos, mas o anúncio é de OUTRO condomínio: aborda
INSERT INTO _t (caso, esperado, veio)
SELECT 'outro condomínio na mesma rua, planta e preço iguais', 'abordar/nao_temos', (r ->> 'acao') || '/' || (r ->> 'motivo')
  FROM _r n, crm_anuncio_decidir(jsonb_build_object(
         'link', 'https://am.olx.com.br/regiao-de-manaus/imoveis/teste-310-outro-condominio-9000000101', 'titulo', 'Apartamento',
         'tipo', n.tipo, 'finalidade', n.fin, 'preco', n.preco, 'bairro', n.bairro, 'endereco', n.logradouro,
         'condominio_nome', 'Condomínio Zzzoutro Residence', 'area_m2', n.area, 'quartos', n.quartos, 'anunciante_nome', 'Zzzfulano Teste')) r;

-- 2. o mesmo anúncio SEM dizer o condomínio: rua + preço + área fecham
INSERT INTO _t (caso, esperado, veio)
SELECT 'mesma rua, planta e preço, sem o nome do condomínio', 'fechar/ja_temos', (r ->> 'acao') || '/' || (r ->> 'motivo')
  FROM _r n, crm_anuncio_decidir(jsonb_build_object(
         'link', 'https://am.olx.com.br/regiao-de-manaus/imoveis/teste-310-sem-condominio-9000000102', 'titulo', 'Apartamento',
         'tipo', n.tipo, 'finalidade', n.fin, 'preco', n.preco, 'bairro', n.bairro, 'endereco', n.logradouro,
         'area_m2', n.area, 'quartos', n.quartos, 'anunciante_nome', 'Zzzfulano Teste')) r;

-- 3. e dizendo o condomínio certo: fecha
INSERT INTO _t (caso, esperado, veio)
SELECT 'o condomínio certo', 'fechar/ja_temos', (r ->> 'acao') || '/' || (r ->> 'motivo')
  FROM _r n, crm_anuncio_decidir(jsonb_build_object(
         'link', 'https://am.olx.com.br/regiao-de-manaus/imoveis/teste-310-condominio-certo-9000000103', 'titulo', 'Apartamento',
         'tipo', n.tipo, 'finalidade', n.fin, 'preco', n.preco, 'bairro', n.bairro,
         'condominio_nome', n.condominio_nome, 'area_m2', n.area, 'quartos', n.quartos, 'anunciante_nome', 'Zzzfulano Teste')) r;

-- 4. as consultas de verdade que já estão gravadas não mudam de resposta
INSERT INTO _t (caso, esperado, veio)
SELECT 'consultas gravadas que mudariam de resposta', '0',
       count(*) FILTER (WHERE (c.motivo = 'ja_temos') IS DISTINCT FROM (crm_anuncio_mesma_unidade(c.dados, crm_imovel_candidatos(c.dados)) IS NOT NULL)
                          AND c.motivo IN ('ja_temos', 'nao_temos'))::text
  FROM privado.anuncio_consulta c;

\echo == os casos
SELECT n, caso, esperado, veio, CASE WHEN esperado = veio THEN 'ok' ELSE '<<< FALHOU' END AS r FROM _t ORDER BY n;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM _t WHERE esperado IS DISTINCT FROM veio) THEN
    RAISE EXCEPTION 'teste_310: % caso(s) falharam', (SELECT count(*) FROM _t WHERE esperado IS DISTINCT FROM veio);
  END IF;
END $$;
