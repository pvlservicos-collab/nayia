-- 569 (Pedro, 03/11/2026: "diminui os disparos, retira os que estão a muito tempo com pouca pedida, e coloca Anunciar a lista
-- Top 5 mais pedidos lá nos grupos ... cuidado que cada grupo pelo nome dá pra saber a diferença, tem grupo que é de imóvel de
-- alto padrão"). Plano conferido com ele antes (pode aplicar tudo; Top 5 FIXA, ele atualiza na agenda do admin; 3x por semana).
-- Backup das vagas que saem: /root/backups-funcoes/vagas-2026-11-03.csv
--
-- SAEM da grade:
--   fora do ar: 5717 (Alugado), 5664 (Vendido), 5735 (Vendido)
--   muito tempo e pouca procura (60 dias): 5750, 5052, 3848, 5748, 5035 (alto padrão, todo dia desde setembro, 0 visita),
--   887 (Castelli, 128 posts, 0 visita), 5729 (Ariranhas, 135 posts, 0 visita)
--   os 2 cards do Comercial (5763, 5752): entram na Top 5 comercial
-- O 5725 (Cerejeiras) passa de todo dia para seg/qua/sex.
-- ENTRAM 4 listas Top 5 (texto fixo; o publicador tira sozinho a linha do imóvel que sair do ar), cada uma SÓ nos grupos
-- marcados (vagas.grupos_ids; o publicador passou a respeitar isso na lista) e com a regra de cada grupo:
--   locação  seg/qua/sex 10h  14 grupos gerais + 🟢 Locação
--   venda    ter/qui     10h  14 grupos gerais + SÓ TERCEIROS COMPRA, VEN
--   alto padrão (locação, todos ≥ R$ 6.500 e de condomínio)  todo dia 7h  os 2 grupos de Alto Padrão
--   comercial (locação)  seg/qua/sex 7h  🟢 Comercial
-- dias_semana: 0 = domingo ... 6 = sábado (agendador.py).
BEGIN;
SET LOCAL lock_timeout = '3s';

DELETE FROM vagas WHERE id IN (6, 7, 496, 547, 548, 549, 550, 551, 8, 492, 511, 544)
   AND codigos <@ ARRAY['5717', '5664', '5735', '5750', '5748', '5035', '3848', '5052', '887', '5729', '5763', '5752'];
UPDATE vagas SET tipo_recorrencia = 'semanal', dias_semana = '{1,3,5}' WHERE id = 493 AND codigos = '{5725}';

CREATE TEMP TABLE gerais ON COMMIT DROP AS
  SELECT array_agg(id_grupo ORDER BY nome) ids FROM grupos
   WHERE ativo AND aceita_venda AND aceita_locacao AND NOT todas_fotos AND NOT so_comercial AND NOT so_condominio
     AND aluguel_minimo IS NULL AND venda_minima IS NULL;

INSERT INTO vagas (horario, tipo_recorrencia, dias_semana, codigos, categoria, negocio, destino, texto_fixo, grupos_ids)
SELECT '10:00', 'semanal', '{1,3,5}', '{}', 'apartamento', 'locacao', 'parceiros',
       E'🔥 TOP 5 MAIS PEDIDOS: LOCAÇÃO 🔥\n\n'
       || E'✅Maison Rochelle cod 2944 / 3 quartos sendo 1 suíte / mobiliado / 3.8k (incluso a tx)\n'
       || E'✅Morada dos Pássaros cod 3210 / 3 suítes / com modulados e ar / 9k (incluso a tx)\n'
       || E'✅Condomínio Acquarelle cod 1125 / 3 quartos sendo 1 suíte / mobiliado / 5.5k (incluso a tx)\n'
       || E'✅Jardim das Cerejeiras cod 5725 / 3 quartos sendo 1 suíte / com modulados e ar / 3.6k (incluso a tx)\n'
       || E'✅Conquista rio negro cod 5733 / 2 quartos / com modulados e ar / 1.9k (incluso a tx)\n\n'
       || 'Os mais procurados da semana. Tem cliente para algum? Me chama no privado!',
       g.ids || (SELECT array_agg(id_grupo) FROM grupos WHERE ativo AND NOT aceita_venda AND aceita_locacao)
  FROM gerais g;

INSERT INTO vagas (horario, tipo_recorrencia, dias_semana, codigos, categoria, negocio, destino, texto_fixo, grupos_ids)
SELECT '10:00', 'semanal', '{2,4}', '{}', 'apartamento', 'venda', 'parceiros',
       E'🔥 TOP 5 MAIS PEDIDOS: VENDA 🔥\n\n'
       || E'✅Maison Rochelle cod 2944 / 3 quartos sendo 1 suíte / mobiliado / 470k\n'
       || E'✅Morada dos Pássaros cod 3210 / 3 suítes / com modulados e ar / 900k\n'
       || E'✅Condomínio Acquarelle cod 1125 / 3 quartos sendo 1 suíte / mobiliado / 750k\n'
       || E'✅Plaza Del Rey cod 2228 / 2 quartos / mobiliado / 300k\n'
       || E'✅Reserva das Flores cod 9024 / 3 quartos / com modulados e ar / 1.2M\n\n'
       || 'Os mais procurados da semana. Tem cliente para algum? Me chama no privado!',
       g.ids || (SELECT array_agg(id_grupo) FROM grupos WHERE ativo AND aceita_venda AND NOT aceita_locacao)
  FROM gerais g;

INSERT INTO vagas (horario, tipo_recorrencia, dias_semana, codigos, categoria, negocio, destino, texto_fixo, grupos_ids)
SELECT '07:00', 'diaria', NULL, '{}', 'casa_condominio', 'locacao', 'parceiros',
       E'🔥 TOP 5 MAIS PEDIDOS: ALTO PADRÃO 🔥\n\n'
       || E'✅Morada dos Pássaros cod 3210 / 3 suítes / com modulados e ar / 9k (incluso a tx)\n'
       || E'✅Reserva das Flores cod 9024 / 3 quartos / com modulados e ar / 7.6k\n'
       || E'✅Residencial Tapajós cod 2462 / 4 quartos sendo 3 suítes / com modulados e ar / 7k (incluso a tx)\n'
       || E'✅Solar da Praia cod 3647 / 3 quartos sendo 1 suíte / mobiliado / 8k (incluso a tx)\n'
       || E'✅Residencial Efhraim cod 4207 / 3 quartos sendo 1 suíte / mobiliado / 7.5k / + tx de 1.000,00\n\n'
       || 'Os mais procurados da semana. Tem cliente para algum? Me chama no privado!',
       (SELECT array_agg(id_grupo) FROM grupos WHERE ativo AND apelido IN ('alto_padrao', 'alto_padrao_easy'));

INSERT INTO vagas (horario, tipo_recorrencia, dias_semana, codigos, categoria, negocio, destino, texto_fixo, grupos_ids)
SELECT '07:00', 'semanal', '{1,3,5}', '{}', 'sala', 'locacao', 'comercial',
       E'🔥 TOP 5 MAIS PEDIDOS: COMERCIAL 🔥\n\n'
       || E'✅Galpão/Depósito Centro cod 5752 / 4k\n'
       || E'✅Loja Adrianópolis cod 5763 / 10k\n'
       || E'✅Conecct Tower cod 9036 / 100m2 / 23k (incluso a tx)\n'
       || E'✅Loja/Ponto Centro cod 3656 / 5k\n'
       || E'✅Sala/Andar Parque 10 de Novembro cod 1544 / 3.5k\n\n'
       || 'Os mais procurados da semana. Tem cliente para algum? Me chama no privado!',
       (SELECT array_agg(id_grupo) FROM grupos WHERE ativo AND apelido = 'comercial');

SELECT v.id, to_char(v.horario, 'HH24:MI') h, v.tipo_recorrencia, v.dias_semana, v.codigos, v.categoria, v.negocio,
       left(split_part(v.texto_fixo, E'\n', 1), 40) titulo,
       (SELECT string_agg(left(g.nome, 18), ', ' ORDER BY g.nome) FROM grupos g WHERE g.id_grupo = ANY (v.grupos_ids)) grupos
  FROM vagas v ORDER BY v.horario, v.id;
COMMIT;
