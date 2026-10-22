-- 473 -- O andar, a torre, o bloco e a unidade do ADMIN ANTIGO nos imóveis de código antigo (só o que estava vazio)
--
-- Pedro, 22/10/2026 (Everton, 5727 "Qual o andar?"): "se for código antigo pede para ver no site antigo também se tem essa
-- informação, que 90% lá do site antigo tem informação completa". Lido de imobeasy.com/admin/imoveis/<código> (o campo
-- Andar e o título "Condomínio, Torre X, Apto Y") para os imóveis de código < 9000, Disponíveis ou Alugados, sem andar.
-- - imoveis.andar: o do admin; sem ele, o do apartamento (401 -> 4, 1001 -> 10, 8A -> 8). Só onde estava vazio.
-- - imovel_privado: torre, bloco e unidade, só onde estava vazio (a Nay não diz torre nem apartamento a ninguém; a
--   unidade serve para a ficha deduzir o andar).
BEGIN;
SET LOCAL lock_timeout = '3s';
CREATE TEMP TABLE _admin (codigo int, andar text, torre text, bloco text, unidade text) ON COMMIT DROP;
INSERT INTO _admin VALUES
  (99, '8', '01', NULL, '8A'),
  (150, '10', '01', NULL, '1001'),
  (193, '4', 'Sul', NULL, '401'),
  (245, NULL, 'Única', NULL, NULL),
  (462, '7', NULL, NULL, '71'),
  (599, NULL, 'Edifício Palmares', NULL, NULL),
  (964, '12', NULL, NULL, NULL),
  (1029, '2', 'C1', NULL, '203'),
  (1202, '11', NULL, NULL, '1102'),
  (1361, NULL, NULL, NULL, '4'),
  (1485, NULL, 'Soho', NULL, '05'),
  (1595, '2', NULL, NULL, '203'),
  (1637, NULL, NULL, NULL, 'A16'),
  (2202, '7', NULL, NULL, NULL),
  (2290, NULL, 'única', NULL, NULL),
  (2411, '3', 'B', NULL, '302B'),
  (2425, '3', NULL, NULL, '310'),
  (2502, NULL, 'única', NULL, NULL),
  (2795, '4', NULL, NULL, '404'),
  (2815, NULL, 'Edifício The Office', NULL, NULL),
  (2943, '18', 'Ciano', NULL, '1803'),
  (2961, '7', 'Buriti', NULL, '705'),
  (3050, '3', 'Thassos', NULL, '305'),
  (3069, NULL, 'Business', NULL, NULL),
  (3115, NULL, 'Unica', NULL, NULL),
  (3367, '1', NULL, NULL, '134'),
  (3498, '3', '10-B', NULL, '302'),
  (3587, '4', NULL, NULL, NULL),
  (3590, '17', NULL, NULL, '1706'),
  (3595, '10', NULL, NULL, NULL),
  (3605, NULL, 'Bloco 32A', NULL, 'A'),
  (3732, '5', NULL, NULL, NULL),
  (3841, '1', 'única', NULL, '102'),
  (3929, '6', 'Torre Elizabeth', NULL, '602'),
  (4020, '7', 'Edifício Boulevard Amazonas', NULL, '704'),
  (4082, '8', 'Spring', NULL, '801'),
  (4083, '8', 'Spring', NULL, '808'),
  (4187, NULL, 'Alvorada', NULL, NULL),
  (4255, NULL, NULL, NULL, '3'),
  (4256, NULL, NULL, NULL, '4'),
  (4402, '2', NULL, NULL, NULL),
  (4567, '1', 'Bloco 1', NULL, '106'),
  (4752, '10', NULL, NULL, NULL),
  (4828, NULL, 'Torre única', NULL, NULL),
  (4849, '10', 'Torre Sul', NULL, '1003'),
  (4983, NULL, '06', NULL, '57'),
  (4987, NULL, 'Edifício Palmares', NULL, NULL),
  (5020, '15', NULL, NULL, '1501'),
  (5021, '10', NULL, NULL, '1004'),
  (5022, '10', NULL, NULL, '1005'),
  (5047, '1', 'Bloco 7', NULL, '0102'),
  (5077, '7', 'Edifício The Office', NULL, '713'),
  (5081, '7', NULL, NULL, '702'),
  (5127, '9', NULL, NULL, '901'),
  (5239, NULL, 'Condomínio Piauí', NULL, NULL),
  (5308, NULL, 'Edifício Fellini', NULL, NULL),
  (5338, NULL, 'Edifício Geneve', NULL, NULL),
  (5357, '1', NULL, NULL, '102'),
  (5426, NULL, 'Edifício The Office', NULL, NULL),
  (5427, NULL, 'Edifício The Office', NULL, NULL),
  (5447, '3', 'Edifcio Weck', NULL, '302'),
  (5465, '2', NULL, NULL, '201'),
  (5530, NULL, 'Edifício João Paulo II', NULL, NULL),
  (5548, NULL, 'Torre medical', NULL, NULL),
  (5550, '10', 'C', NULL, '1002'),
  (5633, '7', NULL, NULL, '708'),
  (5691, '11', NULL, NULL, '1103'),
  (5692, '10', NULL, NULL, '1002'),
  (5713, '2', NULL, NULL, NULL),
  (5717, '3', NULL, NULL, NULL),
  (5718, NULL, NULL, NULL, '4'),
  (5719, '8', '8', NULL, '803'),
  (5720, '5', NULL, NULL, '507'),
  (5722, '2', '13', NULL, '304'),
  (5724, '3', NULL, NULL, NULL),
  (5726, '2', NULL, NULL, NULL),
  (5728, '6', NULL, NULL, '601'),
  (5729, '2', NULL, NULL, NULL),
  (5731, '12', 'única', NULL, '1206'),
  (5732, '1', NULL, NULL, NULL),
  (5733, '1', NULL, NULL, NULL),
  (5734, '8', NULL, NULL, NULL),
  (5739, '8', NULL, NULL, NULL),
  (5744, '5', NULL, NULL, NULL),
  (5748, '2', NULL, NULL, '201'),
  (5749, '5', NULL, NULL, '502'),
  (5754, '4', NULL, NULL, NULL),
  (5761, '11', 'Edifício Antônio Simões', NULL, NULL);
UPDATE imoveis i SET andar = a.andar
  FROM _admin a
 WHERE i.codigo = a.codigo AND a.andar IS NOT NULL AND nullif(btrim(coalesce(i.andar, '')), '') IS NULL;
INSERT INTO imovel_privado (codigo, torre, bloco, unidade)
SELECT a.codigo, a.torre, a.bloco, a.unidade FROM _admin a
 WHERE (a.torre IS NOT NULL OR a.bloco IS NOT NULL OR a.unidade IS NOT NULL)
   AND EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = a.codigo)
ON CONFLICT (codigo) DO UPDATE
   SET torre   = coalesce(nullif(btrim(imovel_privado.torre), ''), EXCLUDED.torre),
       bloco   = coalesce(nullif(btrim(imovel_privado.bloco), ''), EXCLUDED.bloco),
       unidade = coalesce(nullif(btrim(imovel_privado.unidade), ''), EXCLUDED.unidade);
COMMIT;
