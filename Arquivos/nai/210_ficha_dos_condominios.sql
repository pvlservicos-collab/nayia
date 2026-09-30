-- 210 (Pedro, 30/09/2026): A FICHA DO CONDOMÍNIO. "Atualiza também a lista de
-- condomínios com a lista de características de condomínios, e lá em todos os
-- imóveis põe a aba Condomínios listando tudo, também com as características que
-- pegamos do site antigo."
--
-- `condominios` (id, nome, bairro) vem do site antigo e só tem isso. A ficha fica
-- numa tabela ao lado, para não mexer na tabela que os imóveis referenciam:
--   condominio_id    o condomínio do cadastro, quando existe
--   nomes_no_imovel  o nome como está escrito no imóvel, quando não há cadastro
--                    (a lista liga o imóvel pelo id OU pelo nome, como /api/condominios)
-- As características do site antigo continuam onde estão (imovel_ficha.
-- caracteristicas_condominio, lidas do anúncio); a aba junta as dos imóveis de
-- cada condomínio.
--
-- Os 11 da lista dele, com a fonte gravada. Ligados ao cadastro: Predilleto (38),
-- Up Ponta Negra (624), Villa Marieta (660). Pelo nome no imóvel: BellaVile e
-- "Vivendas Do parque (parque mosaico)" (Prime Vivendas do Parque -- a conferir).
-- Sem imóvel no catálogo: Città Oasis Azzure, UP Flores, Altos do Aleixo, Vista dos
-- Oitis, Bosque das Torres e Quintas de São José do Rio Negro (o "Parque São José
-- do Rio Negro" do catálogo é no Adrianópolis, outro lugar).
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS condominio_ficha (
  id               serial PRIMARY KEY,
  condominio_id    integer UNIQUE,
  nome             text NOT NULL UNIQUE,
  nomes_no_imovel  text[] NOT NULL DEFAULT '{}',
  tipo             text NOT NULL DEFAULT 'apartamentos' CHECK (tipo IN ('apartamentos', 'casas_lotes')),
  bairro           text,
  endereco         text,
  ano_lancamento   integer,
  construtora      text,
  revestimento     text,
  torres           text,
  andares          text,
  aptos_por_andar  text,
  elevador         text,
  unidades         text,
  lazer            text[] NOT NULL DEFAULT '{}',
  fonte            text,
  criado_em        timestamptz NOT NULL DEFAULT now(),
  atualizado_em    timestamptz NOT NULL DEFAULT now()
);

INSERT INTO condominio_ficha (nome, condominio_id, nomes_no_imovel, tipo, bairro, endereco, ano_lancamento, construtora,
                              revestimento, torres, andares, aptos_por_andar, elevador, unidades, lazer, fonte) VALUES
  ('Città Oasis Azzure', NULL, '{}', 'apartamentos', 'Flores',
   'Rua Santa Bárbara, nº 200, Bairro Flores / Parque das Laranjeiras, Manaus - AM', 2025,
   'Riva Incorporadora (Grupo Direcional)', 'Pintura texturizada padrão', '7 blocos residenciais',
   '8 andares (Térreo + 7 pavimentos)', '8 apartamentos por andar (448 unidades)', 'Sim', NULL,
   ARRAY['Academia climatizada', 'Churrasqueira', 'Pet place', 'Piscinas (adulto e infantil)', 'Playground',
         'Quadra poliesportiva', 'Salão de festas com espaço gourmet'], 'lista do Pedro, 30/09/2026'),
  ('UP Flores', NULL, '{}', 'apartamentos', 'Flores',
   'Av. Professor Nilton Lins, nº 1411, Bairro Flores, Manaus - AM', 2021,
   'Construtora Capital', 'Pintura acrílica e textura', '1 torre única', '8 andares',
   '8 apartamentos por andar (64 unidades)', 'Sim', NULL,
   ARRAY['Piscina adulto e infantil', 'Churrasqueiras', 'Salão de festas', 'Academia', 'Playground', 'Pet place',
         'Quadra esportiva'], 'lista do Pedro, 30/09/2026'),
  ('Predilleto Residencial', 38, '{}', 'apartamentos', 'Parque 10 de Novembro',
   'Travessa Carlos, nº 15, Bairro Parque 10 de Novembro, Manaus - AM', 2020,
   'RD Engenharia', 'Pintura acrílica de alta resistência', '2 torres (Torre Felicidade e Torre Sonho)',
   '8 andares (Térreo + 7 pavimentos)', '8 apartamentos por andar', 'Sim, 2 elevadores por torre', NULL,
   ARRAY['Deck Park', 'Brinquedoteca', 'Churrasqueiras', 'Espaço fitness', 'Piscina', 'Playground', 'Salão de festas',
         'Salão de jogos'], 'lista do Pedro, 30/09/2026'),
  ('Altos do Aleixo', NULL, '{}', 'apartamentos', 'Aleixo',
   'Av. Cosme Ferreira, nº 4731, Bairro Aleixo, Manaus - AM', 2019,
   'Direcional Engenharia', 'Pintura texturizada', '4 torres', '14 andares (Térreo + 13 pavimentos)',
   '8 apartamentos por andar', 'Sim', NULL,
   ARRAY['Piscinas adulto e infantil', 'Solarium', 'Quadra de esportes', 'Salão de festas',
         'Espaço gourmet com churrasqueira', 'Playground', 'Fitness ao ar livre', 'Praças'], 'lista do Pedro, 30/09/2026'),
  ('UP Ponta Negra I', 624, '{}', 'apartamentos', 'Ponta Negra',
   'Av. Thales Loureiro, s/n, Bairro Ponta Negra, Manaus - AM', 2022,
   'Construtora Capital', 'Pintura texturizada', '1 torre única', '11 andares', '8 apartamentos por andar',
   'Sim, elevador inteligente', NULL,
   ARRAY['Piscina com deck', 'Churrasqueira', 'Salão de festas gourmet', 'Playground integrado', 'Brinquedoteca',
         'Fitness equipado', 'Guarita blindada'], 'lista do Pedro, 30/09/2026'),
  ('Vista dos Oitis (MRV)', NULL, '{}', 'apartamentos', 'Planalto',
   'Av. Desembargador João Machado, s/n (Complexo Parque Mosaico), Bairro Planalto, Manaus - AM', 2023,
   'MRV Engenharia', 'Pintura texturizada padrão MRV', '5 torres', '8 andares (Térreo + 7 pavimentos)',
   '8 apartamentos por andar', 'Sim, em todas as torres', NULL,
   ARRAY['Salão de festas', 'Playground', 'Pet place', 'Salão de jogos', 'Espaço gourmet',
         'Piscinas adulto e infantil', 'Pomar', 'Bicicletário com paraciclo'], 'lista do Pedro, 30/09/2026'),
  ('Prime Vivendas do Parque', NULL, ARRAY['Vivendas Do parque (parque mosaico)'], 'apartamentos', 'Planalto',
   'Av. Desembargador João Machado, nº 140, Bairro Planalto, Manaus - AM', 2021,
   'Construtora Prime', 'Pintura acrílica e textura', '4 torres', '8 andares (Térreo + 7 pavimentos)',
   '8 apartamentos por andar', 'Sim, 2 elevadores por torre', NULL,
   ARRAY['Piscina adulto e infantil', 'Deck molhado', 'Solarium', 'Salão de festas', 'Fitness', 'Churrasqueiras',
         'Playground', 'Quadra recreativa'], 'lista do Pedro, 30/09/2026'),
  ('Bosque das Torres', NULL, '{}', 'apartamentos', 'Lago Azul',
   'Av. das Torres, s/n, Bairro Lago Azul, Manaus - AM', 2020,
   'Direcional Engenharia', 'Pintura texturizada', 'Blocos de apartamentos periféricos',
   '5 andares (Térreo + 4 pavimentos)', '8 apartamentos por andar', 'Não', NULL,
   ARRAY['Quadra poliesportiva', 'Piscinas adulto e infantil', 'Playground', 'Churrasqueiras independentes',
         'Salão de festas', 'Pista de caminhada'], 'lista do Pedro, 30/09/2026'),
  ('Residencial Villa Marieta', 660, '{}', 'casas_lotes', 'Ponta Negra',
   'Av. Coronel Teixeira, s/n, Bairro Ponta Negra, Manaus - AM', 2021,
   'Engeco Engenharia', 'Pintura acrílica texturizada', NULL, NULL, NULL, NULL, '53 casas duplex',
   ARRAY['Piscina do condomínio', 'Área gourmet com churrasqueira', 'Playground', 'Salão de festas',
         'Vigilância integrada'], 'lista do Pedro, 30/09/2026'),
  ('Quintas de São José do Rio Negro', NULL, '{}', 'casas_lotes', 'Tarumã',
   'Estrada de Acesso ao Cetur, nº 3020, Bairro Tarumã, Manaus - AM', 2022,
   'Incorporadora e Curadoria Conceito (arquiteto Benedito Abbud)',
   'Muros ecológicos (verdes) e vias internas em paver', NULL, NULL, NULL, NULL, '180 lotes (a partir de 1.500 m²)',
   ARRAY['Complexo hípico com baias', 'Heliponto homologado', 'Marina privativa', 'Espaço de golfe',
         'Quadras de tênis e beach tênis', 'Boliche profissional', 'Cinema privativo', 'Spa com concierge',
         'Academia climatizada', 'Piscinas', 'Capela ecumênica', 'Restaurante', 'Ciclovias em 300 mil m² de mata preservada'],
   'lista do Pedro, 30/09/2026'),
  ('Bellavile Residencial', NULL, ARRAY['Condomínio Residencial BellaVile'], 'casas_lotes', 'Tarumã-Açu',
   'Av. Professor Paulo Graça, s/n, Bairro Tarumã-Açu, Manaus - AM', 2023,
   'Amazonas Incorporadora', 'Pavimentação asfáltica e meio-fio', NULL, NULL, NULL, NULL, '247 lotes residenciais',
   ARRAY['Central de lazer com Wi-Fi', 'Piscina adulto e infantil com solarium', 'Salão de festas mobiliado',
         'Academia equipada', 'Quiosques com churrasqueira', 'Trilhas ecológicas', 'Espaço pet', 'Redário',
         'Playground'], 'lista do Pedro, 30/09/2026')
ON CONFLICT (nome) DO UPDATE SET condominio_id = EXCLUDED.condominio_id, nomes_no_imovel = EXCLUDED.nomes_no_imovel,
  tipo = EXCLUDED.tipo, bairro = EXCLUDED.bairro, endereco = EXCLUDED.endereco, ano_lancamento = EXCLUDED.ano_lancamento,
  construtora = EXCLUDED.construtora, revestimento = EXCLUDED.revestimento, torres = EXCLUDED.torres,
  andares = EXCLUDED.andares, aptos_por_andar = EXCLUDED.aptos_por_andar, elevador = EXCLUDED.elevador,
  unidades = EXCLUDED.unidades, lazer = EXCLUDED.lazer, fonte = EXCLUDED.fonte, atualizado_em = now();

-- a aba lê pela API do site (nay_site_leitura): a ficha inteira e, do anúncio
-- antigo, só o código e as características do condomínio
GRANT SELECT ON condominio_ficha TO nay_site_leitura, nay_leitura;
GRANT SELECT (codigo, caracteristicas_condominio) ON imovel_ficha TO nay_site_leitura;
COMMIT;
