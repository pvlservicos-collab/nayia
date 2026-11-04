-- 591: os 34 ganham o condomínio da tabela, e a cópia de antes ficou
SELECT 'com condo_id' caso, count(*) FILTER (WHERE condo_id IS NOT NULL) AS n, count(*) AS de
  FROM imoveis WHERE codigo IN (2741, 2845, 3382, 3700, 3721, 3727, 3785, 3931, 9056, 9065, 9069, 9074, 9075, 9076, 9083, 9084, 9090, 9094, 9098, 9099, 9103, 9105, 9106, 9111, 9113, 9114, 9115, 9119, 9121, 9127, 9128, 9129, 9130, 9131);
SELECT 'copia de antes' caso, count(*) FROM privado.imovel_condominio_antes_591;
SELECT codigo, condo_id, condominio_nome FROM imoveis WHERE codigo IN (9127, 9105, 9090, 3700, 9056) ORDER BY codigo;
