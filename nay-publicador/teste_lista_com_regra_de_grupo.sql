-- Prova a lista FILTRADA por grupo (Tel, 15/09) contra o catálogo real.
--
-- O grupo Alto Padrão recebe só locação de 6.500 em diante e venda de
-- 1.000.000 em diante, de condomínio. A lista dele sai de
-- `nay_lista_de_imoveis(categoria, negocio, piso, so_condominio)`.
--
-- O que se prova, e o que custa se quebrar:
--   * existe UMA versão da função. A assinatura mudou, e `CREATE OR REPLACE`
--     com assinatura diferente cria SOBRECARGA -- a velha continuaria chamável;
--   * a chamada de dois argumentos (a de todos os grupos antigos e do
--     `Nay lista de ...`) é IDÊNTICA à de quatro com a regra desligada;
--   * a contagem filtrada BATE com uma consulta direta à tabela, escrita aqui à
--     parte -- se a função e a regra divergirem, fica vermelho;
--   * nenhuma casa de rua entra quando o grupo exige condomínio.
--
--   docker cp teste_lista_com_regra_de_grupo.sql nay-postgres:/tmp/t.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/t.sql

BEGIN;

CREATE TEMP TABLE resultado(caso text, deu text, esperado text);

INSERT INTO resultado
SELECT 'uma versão só da função', count(*)::text, '1'
  FROM pg_proc WHERE proname = 'nay_lista_de_imoveis';

INSERT INTO resultado
SELECT 'dois argumentos = quatro com a regra desligada: ' || c || '/' || n,
       CASE WHEN a.texto_pronto = b.texto_pronto AND a.quantos = b.quantos
            THEN 'igual' ELSE 'diferente' END, 'igual'
  FROM (VALUES ('apartamento','locacao'), ('apartamento','venda'),
               ('casa_condominio','venda'), ('sala','locacao')) AS v(c, n),
       LATERAL nay_lista_de_imoveis(v.c, v.n) a,
       LATERAL nay_lista_de_imoveis(v.c, v.n, NULL, false) b;

-- A contagem direta, escrita À PARTE da função.
INSERT INTO resultado
SELECT 'contagem filtrada bate com a tabela: ' || v.c || '/' || v.n || ' >= ' || v.piso,
       (SELECT quantos FROM nay_lista_de_imoveis(v.c, v.n, v.piso, true))::text,
       (SELECT count(*) FROM imoveis i
         WHERE nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
           AND NOT coalesce(i.e_parceiro, false)
           AND nay_categoria_do_imovel(i.tipo, i.condominio_nome) = v.c
           AND nay_condominio_de_verdade(i.tipo, i.condominio_nome) IS NOT NULL
           AND CASE WHEN v.n = 'venda' THEN coalesce(i.valor_venda,0)
                    ELSE coalesce(i.valor_aluguel,0) END >= v.piso)::text
  FROM (VALUES ('apartamento','locacao', 6500::numeric),
               ('apartamento','venda', 1000000::numeric),
               ('casa_condominio','venda', 1000000::numeric),
               ('casa_condominio','locacao', 6500::numeric)) AS v(c, n, piso);

-- Casa de RUA acima de 1 milhão existe no catálogo e NÃO pode entrar.
INSERT INTO resultado
SELECT 'casa de rua acima de 1M não entra com so_condominio',
       (SELECT quantos FROM nay_lista_de_imoveis('casa_via_publica','venda', 1000000, true))::text,
       '0';

-- A lista filtrada nunca tem MAIS imóvel que a completa.
INSERT INTO resultado
SELECT 'filtrada <= completa: apartamento/locacao',
       CASE WHEN f.quantos <= t.quantos THEN 'sim' ELSE 'não' END, 'sim'
  FROM nay_lista_de_imoveis('apartamento','locacao', 6500, true) f,
       nay_lista_de_imoveis('apartamento','locacao') t;

-- O grupo Alto Padrão carrega a regra que o Tel pediu.
INSERT INTO resultado
SELECT 'regra do Alto Padrão no banco',
       coalesce((SELECT aluguel_minimo::int || '/' || venda_minima::int || '/' || so_condominio
                   FROM grupos WHERE id_grupo = '120363319292435731-group'), '(sem linha)'),
       '6500/1000000/true';

-- E os grupos antigos continuam SEM regra.
INSERT INTO resultado
SELECT 'grupos antigos sem piso',
       count(*) FILTER (WHERE aluguel_minimo IS NOT NULL OR venda_minima IS NOT NULL
                          OR so_condominio)::text, '1'
  FROM grupos;

SELECT CASE WHEN deu = esperado THEN 'OK  ' ELSE 'ERRO' END AS r, caso, deu, esperado
  FROM resultado ORDER BY (deu = esperado), caso;

SELECT CASE WHEN falhas = 0 THEN 'TODOS OS ' || total || ' CASOS PASSARAM'
            ELSE falhas || ' DE ' || total || ' FALHARAM' END AS resumo
  FROM (SELECT count(*) FILTER (WHERE deu <> esperado) AS falhas, count(*) AS total
          FROM resultado) s;

ROLLBACK;
