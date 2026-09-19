-- Prova que valor não vira código e que código de card não some.
--
-- As duas metades importam e já se atropelaram: a primeira versão tirava
-- os valores certo e, no mesmo movimento, comia o "Código: 1327" do card,
-- porque o vão entre rótulo e valor pulava a quebra de linha. Passar em
-- metade da tabela é o estado do bug, não do conserto.
--
--   docker cp teste_valor_nao_e_codigo.sql nay-postgres:/tmp/t.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/t.sql

BEGIN;
CREATE TEMP TABLE casos(texto text, deveria text);
INSERT INTO casos(texto, deveria) VALUES
  -- valores que NÃO são código (todos colhidos de mensagem real ou da
  -- forma que o corretor escreve de verdade)
  ('Até 4500   Vou enviar as opções que vc passou no grupo', '{}'),
  ('A proposta é para $4000',                    '{}'),
  ('Paga até 4000',                              '{}'),
  ('cliente paga no maximo 3500 de aluguel',     '{}'),
  ('orçamento de 4500',                          '{}'),
  ('entre 3000 e 5000',                          '{}'),
  ('aluguel de 3500 no Parque 10',               '{}'),
  ('R$ 4.000 por mês',                           '{}'),
  ('valor 4000',                                 '{}'),
  ('4 mil de aluguel',                           '{}'),
  ('venda por 450000',                           '{}'),
  ('condominio 800',                             '{}'),
  ('apartamento de 109m2',                       '{}'),
  ('88 m² no Aleixo',                            '{}'),
  -- códigos que TÊM que sobreviver
  ('me manda o 2539',                            '{2539}'),
  ('o 2539 tem porcelanato?',                    '{2539}'),
  ('3495  3471',                                 '{3471,3495}'),
  ('Me fala do 1327',                            '{1327}'),
  ('posta o 3210 todo dia as 14 horas',          '{3210}'),
  ('manda o 4000 e o 4500 pra mim',              '{4000,4500}'),
  -- os dois juntos na mesma frase
  ('quero o 3500, ele paga até 4000',            '{3500}'),
  ('me manda o 3500, 3210 e 2943',               '{2943,3210,3500}'),
  ('area de 120,50 m2 no 2539',                  '{2539}'),
  -- o card colado, que é como o código chega na prática
  ('📍 Casa' || chr(10) || '• Bairro: Nova Cidade' || chr(10) || '• 109m2' ||
   chr(10) || 'Locação: R$ 2.300' || chr(10) || 'Código: 1327',  '{1327}'),
  ('📍 Condomínio Acquarelle • Bairro: Ponta Negra • 88m2' || chr(10) ||
   'Venda: R$ 690.000' || chr(10) || 'Código: 5611',             '{5611}');

SELECT CASE WHEN nay_codigos_citados(texto) = deveria::text[] THEN 'OK  ' ELSE 'ERRO' END AS r,
       left(replace(texto, chr(10), ' / '), 48) AS caso,
       nay_codigos_citados(texto)::text AS deu,
       deveria
  FROM casos
 ORDER BY (nay_codigos_citados(texto) = deveria::text[]), texto;

SELECT CASE WHEN count(*) FILTER (WHERE NOT ok) = 0
            THEN 'TODOS OS ' || count(*) || ' CASOS PASSARAM'
            ELSE count(*) FILTER (WHERE NOT ok) || ' DE ' || count(*) || ' FALHARAM'
       END AS resumo
  FROM (SELECT nay_codigos_citados(texto) = deveria::text[] AS ok FROM casos) s;
ROLLBACK;
