-- 536 (Pedro, 30/10/2026): "os que foram cadastrados com escrita, troca para um dos tipos lá que já estão os outros
-- imóveis". A mobília tem 4 tipos (344, 11/10): sem nada, só climatizado, com modulados e ar (o antigo semi), mobiliado.
-- Fora deles havia 2, escritos à mão:
--   9037 "mobiliado (moveis + cama + tudo)" -> mobiliado
--   9094 "Semi mobiliado" (cadastro pelo link da OLX, 30/10, a caixa livre da barra) -> com modulados e ar
BEGIN;
UPDATE imoveis SET mobilia = 'mobiliado' WHERE codigo = 9037 AND mobilia = 'mobiliado (moveis + cama + tudo)';
UPDATE imoveis SET mobilia = 'com modulados e ar' WHERE codigo = 9094 AND mobilia = 'Semi mobiliado';
SELECT codigo, mobilia FROM imoveis WHERE mobilia IS NOT NULL AND btrim(mobilia) <> ''
   AND mobilia NOT IN ('sem nada', 'só climatizado', 'com modulados e ar', 'mobiliado');
COMMIT;
