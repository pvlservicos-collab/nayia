-- Imóvel que saiu do site não é oferecido -- nas TRÊS portas.
--
-- O CASO (Tel, 09/09): *"Brisas Lirio já tirei do site e ainda está
-- aparecendo"*. Ele tirou os sete apartamentos do Brisas do Lírio (5110 a
-- 5116) do site, a varredura viu e marcou `publicado_no_site = false`, e eles
-- continuaram saindo na lista de apartamentos para locação. Das 17 funções da
-- Nay que leem `imoveis`, **nenhuma** olhava essa coluna: 35 imóveis fora do
-- site seguiam sendo oferecidos.
--
-- As três portas por onde um imóvel é oferecido têm que fechar juntas, senão
-- fecha-se a que o Tel viu e o mesmo imóvel volta pela outra:
--   1. a lista por categoria    (`nay_lista_de_imoveis`)
--   2. a busca por perfil       (`nay_buscar_por_perfil`)
--   3. o condomínio             (`nay_disponibilidade_no_condominio`)
--
-- E o outro lado, que é o mais fácil de quebrar sem perceber: RECONHECER o
-- nome e PODER oferecer são decisões diferentes (o bug 6). Tirar do site não
-- pode fazer o condomínio virar "esse condomínio não existe".
--
--   docker cp teste_oferta_so_com_anuncio.sql nay-postgres:/tmp/t.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/t.sql

BEGIN;

CREATE TEMP TABLE resultado(caso text, deu text, esperado text);

-- A regra crua, inclusive o nulo. A coluna é NOT NULL DEFAULT true hoje, mas
-- a proteção não pode depender da sorte do cadastro -- é a mesma disciplina
-- do "todo portão falha FECHADO".
INSERT INTO resultado VALUES
 ('no mercado: disponível, não bloqueado, no site',
  nay_esta_no_mercado(true, false, true)::text, 'true'),
 ('fora do site NÃO está no mercado',
  nay_esta_no_mercado(true, false, false)::text, 'false'),
 ('bloqueado NÃO está no mercado',
  nay_esta_no_mercado(true, true, true)::text, 'false'),
 ('indisponível NÃO está no mercado',
  nay_esta_no_mercado(false, false, true)::text, 'false'),
 ('site nulo falha FECHADO',
  nay_esta_no_mercado(true, false, NULL)::text, 'false'),
 ('disponível nulo é disponível (compatível com o coalesce de sempre)',
  nay_esta_no_mercado(NULL, false, true)::text, 'true');

-- Dois imóveis iguais no mesmo condomínio inventado: um no site, outro fora.
INSERT INTO imoveis (codigo, tipo, condominio_nome, bairro, quartos,
                     valor_aluguel, disponivel, bloqueado, e_parceiro,
                     publicado_no_site)
VALUES (999001, 'Apartamento', 'Condominio De Teste Zzz',
        'Bairro De Teste Zzz', 2, 1234, true, false, false, true),
       (999002, 'Apartamento', 'Condominio De Teste Zzz',
        'Bairro De Teste Zzz', 2, 4321, true, false, false, false);

-- A lista não traz código -- ela sai como
-- "Condominio De Teste Zzz / 2 quartos / 1.23k". É pelo VALOR que se
-- distingue um do outro ali dentro.

-- 1. A LISTA POR CATEGORIA -- foi onde ele viu o Brisas do Lírio.
INSERT INTO resultado
SELECT 'lista: mostra o que está no site',
       CASE WHEN texto_pronto LIKE '%1.23k%' THEN 'mostra' ELSE 'sumiu' END,
       'mostra'
  FROM nay_lista_de_imoveis('apartamento', 'locacao');

INSERT INTO resultado
SELECT 'lista: NÃO mostra o que saiu do site',
       CASE WHEN texto_pronto LIKE '%4.32k%' THEN 'mostra' ELSE 'nao mostra' END,
       'nao mostra'
  FROM nay_lista_de_imoveis('apartamento', 'locacao');

-- 2. A BUSCA POR PERFIL.
INSERT INTO resultado
SELECT 'busca por bairro: mostra o que está no site',
       CASE WHEN texto_pronto LIKE '%999001%' THEN 'mostra' ELSE 'sumiu' END,
       'mostra'
  FROM nay_buscar_por_perfil('Bairro De Teste Zzz', 'locacao', NULL, NULL, NULL);

INSERT INTO resultado
SELECT 'busca por bairro: NÃO mostra o que saiu do site',
       CASE WHEN texto_pronto LIKE '%999002%' THEN 'mostra' ELSE 'nao mostra' END,
       'nao mostra'
  FROM nay_buscar_por_perfil('Bairro De Teste Zzz', 'locacao', NULL, NULL, NULL);

-- 3. O CONDOMÍNIO.
INSERT INTO resultado
SELECT 'condomínio: oferece o que está no site',
       CASE WHEN texto_pronto LIKE '%999001%' THEN 'oferece' ELSE 'nao oferece' END,
       'oferece'
  FROM nay_disponibilidade_no_condominio('Condominio De Teste Zzz', 'locacao');

INSERT INTO resultado
SELECT 'condomínio: NÃO oferece o que saiu do site',
       CASE WHEN texto_pronto LIKE '%999002%' THEN 'oferece' ELSE 'nao oferece' END,
       'nao oferece'
  FROM nay_disponibilidade_no_condominio('Condominio De Teste Zzz', 'locacao');

-- Agora tira o ÚNICO que estava no site: o condomínio continua sendo
-- RECONHECIDO, e a resposta é "não tenho nada disponível", nunca "não existe".
UPDATE imoveis SET publicado_no_site = false WHERE codigo = 999001;

INSERT INTO resultado
SELECT 'condomínio sem nada no site: reconhece o nome',
       CASE WHEN texto_pronto ILIKE '%Condominio De Teste Zzz%'
            THEN 'reconhece' ELSE texto_pronto END, 'reconhece'
  FROM nay_disponibilidade_no_condominio('Condominio De Teste Zzz', 'locacao');

INSERT INTO resultado
SELECT 'condomínio sem nada no site: NÃO diz que não existe',
       CASE WHEN instrucao_para_voce ILIKE '%nao existe%'
                 OR instrucao_para_voce ILIKE '%não existe%'
            THEN 'diz que nao existe' ELSE 'nao diz' END, 'nao diz'
  FROM nay_disponibilidade_no_condominio('Condominio De Teste Zzz', 'locacao');

INSERT INTO resultado
SELECT 'condomínio sem nada no site: manda NÃO escalar',
       CASE WHEN instrucao_para_voce ILIKE '%NAO escale%'
            THEN 'manda nao escalar' ELSE instrucao_para_voce END,
       'manda nao escalar'
  FROM nay_disponibilidade_no_condominio('Condominio De Teste Zzz', 'locacao');

-- E o caso real que ele reclamou, contra o catálogo de verdade.
INSERT INTO resultado
SELECT 'Brisas do Lírio não sai mais na lista de apartamentos',
       CASE WHEN texto_pronto ILIKE '%Brisas do Lírio%'
            THEN 'ainda sai' ELSE 'nao sai' END, 'nao sai'
  FROM nay_lista_de_imoveis('apartamento', 'locacao');

INSERT INTO resultado
SELECT 'nenhuma oferta com imóvel fora do site (catálogo inteiro)',
       (SELECT count(*) FROM imoveis i
         WHERE NOT coalesce(i.publicado_no_site, false)
           AND nay_esta_no_mercado(i.disponivel, i.bloqueado,
                                   i.publicado_no_site))::text, '0';

SELECT CASE WHEN deu = esperado THEN 'OK  ' ELSE 'ERRO' END AS r,
       caso, deu, esperado
  FROM resultado ORDER BY (deu = esperado), caso;

SELECT CASE WHEN falhas = 0
            THEN 'TODOS OS ' || total || ' CASOS PASSARAM'
            ELSE falhas || ' DE ' || total || ' FALHARAM' END AS resumo
  FROM (SELECT count(*) FILTER (WHERE deu <> esperado) AS falhas,
               count(*) AS total FROM resultado) s;

ROLLBACK;
