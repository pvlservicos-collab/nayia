-- Regra de VALOR e de CONDOMÍNIO por grupo (Tel, 15/09).
--
-- O PEDIDO: o grupo "🟢 Alto Padrão - OFERTA e BUSCA 🔍" só recebe locação de
-- 6.500 em diante e venda de 1.000.000 em diante, e nos dois casos só imóvel
-- de condomínio. Até aqui `grupos` só sabia dizer SE aceita venda ou locação
-- (aceita_venda/aceita_locacao), nunca a partir de QUANTO.
--
-- NULO É "SEM PISO", e é o que todos os grupos antigos têm -- o comportamento
-- deles não muda. A regra fica em coluna, e não no nome do grupo nem em lista
-- fixa no código, para o próximo grupo de nicho ser um UPDATE.
--
-- As três decisões do Tel, perguntadas em 15/09 com a medição à frente:
--   * condomínio nos DOIS negócios (as 3 casas de rua acima de 1 milhão ficam
--     de fora);
--   * 1.000.000 EM DIANTE (>=), não só acima;
--   * nas LISTAS o grupo recebe só os imóveis que passam, com título
--     recalculado -- e nada quando nenhum passa.
--
-- O piso compara o VALOR QUE O CARD MOSTRA (aluguel ou venda), não o custo
-- cheio do título da lista: é o número que o corretor lê na linha.
--
-- Ordem de deploy: ESTE arquivo antes do código. `carregar_grupos_db` passa a
-- ler as colunas novas, e código novo com tabela velha derruba todo `posta`.
--
--   docker cp grupos_regra_de_valor.sql nay-postgres:/tmp/g.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/g.sql

BEGIN;

ALTER TABLE grupos ADD COLUMN IF NOT EXISTS aluguel_minimo numeric;
ALTER TABLE grupos ADD COLUMN IF NOT EXISTS venda_minima   numeric;
ALTER TABLE grupos ADD COLUMN IF NOT EXISTS so_condominio  boolean NOT NULL DEFAULT false;

INSERT INTO grupos (id_grupo, nome, ativo, todas_fotos, limite_dia,
                    aceita_venda, aceita_locacao,
                    aluguel_minimo, venda_minima, so_condominio)
VALUES ('120363319292435731-group', '🟢 Alto Padrão - OFERTA e BUSCA 🔍',
        true, false, 5, true, true, 6500, 1000000, true)
ON CONFLICT (id_grupo) DO UPDATE
   SET aluguel_minimo = EXCLUDED.aluguel_minimo,
       venda_minima   = EXCLUDED.venda_minima,
       so_condominio  = EXCLUDED.so_condominio;

COMMIT;
