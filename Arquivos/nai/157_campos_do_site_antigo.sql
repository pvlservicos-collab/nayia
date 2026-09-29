-- =====================================================================
-- 157 — OS CAMPOS DO SITE ANTIGO NO CADASTRO NOVO (28/09/2026)
--
-- Pedro: "ponha todos os campos do site antigo mas sem ser obrigatório, põe
-- só as informações que tivermos". E antes: o Tel "relatou que não tava
-- conseguindo cadastrar no novo, e tem campos que não tem no novo, tipo
-- número de apartamento".
--
-- ONDE CADA CAMPO MORA (e por quê):
--
--   * Características e negócio do site antigo (salas, área construída,
--     terreno, lances de escada, incluso no aluguel, garantia, aceita
--     financiamento, permuta, indicado/inspecionado por...): em
--     `imoveis.extras`, com o MESMO nome de chave da raspagem do site antigo.
--     A Nay já lê "incluso no aluguel" e "aceita financiamento" de lá
--     (nai_card_do_imovel, nai_resposta_da_base, nay_custo_cheio,
--     vw_imoveis_todos); uma coluna nova dividiria a verdade em dois lugares.
--     Não precisa de DDL em `imoveis` -- só o direito de gravar `extras`.
--
--   * A UNIDADE (torre, apartamento, bloco, casa, lote): em `imovel_privado`.
--     Torre e unidade já moravam lá e a Nay monta o endereço interno com elas
--     (nai_endereco_interno, o que vai para o motoboy); bloco, casa e lote
--     eram do site antigo e não tinham lugar.
--
--   * A LOCAÇÃO ATUAL (nome e contato do locatário, observação do aluguel) e
--     as OBSERVAÇÕES internas: dado de pessoa. Schema próprio, fora do
--     `public` -- o /api/tabelas lê o public inteiro sem senha, e a role de
--     leitura ganha SELECT automático em toda tabela nova de lá (ver a
--     memória "API do site não tem senha"; mesmo molde do schema `vagas`).
--
--   * O VENCIMENTO do contrato continua em `contratos_locacao` (é de lá que sai
--     a lista de proprietários por vencimento; os 625 que existem nos dois
--     lugares batem).
--
--   * `captado_por` / `captado_em` já eram colunas (iguais ao extras).
--
-- Sem chave estrangeira na tabela nova: FK para `imoveis` trava a tabela que
-- a Nay lê o tempo todo (ver "Estado da conversa não cala", 28/09).
-- =====================================================================
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL lock_timeout = '3s';

-- 1) a unidade
ALTER TABLE imovel_privado
  ADD COLUMN IF NOT EXISTS bloco text,
  ADD COLUMN IF NOT EXISTS casa  text,
  ADD COLUMN IF NOT EXISTS lote  text;

-- 2) a locação atual e as observações, fora do public
CREATE SCHEMA IF NOT EXISTS privado AUTHORIZATION nay;
REVOKE ALL ON SCHEMA privado FROM PUBLIC;

CREATE TABLE IF NOT EXISTS privado.imovel_ficha (
  codigo             integer PRIMARY KEY,
  locatario_nome     text,
  locatario_contato  text,
  observacao_aluguel text,
  observacoes        text,
  atualizado_em      timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE privado.imovel_ficha IS
  'Dado interno do imóvel que o site antigo tinha: locatário atual e observações. Fora do public de propósito (157).';

REVOKE ALL ON privado.imovel_ficha FROM PUBLIC;
GRANT USAGE ON SCHEMA privado TO nay_site_escrita;
GRANT SELECT, INSERT, UPDATE ON privado.imovel_ficha TO nay_site_escrita;

-- 3) o que o cadastro passa a gravar
GRANT UPDATE (extras, captado_por, captado_em) ON imoveis TO nay_site_escrita;
GRANT INSERT (status, extras, captado_por, captado_em) ON imoveis TO nay_site_escrita;

GRANT SELECT (codigo, torre, unidade, bloco, casa, lote) ON imovel_privado TO nay_site_escrita;
GRANT INSERT (codigo, torre, unidade, bloco, casa, lote) ON imovel_privado TO nay_site_escrita;
GRANT UPDATE (torre, unidade, bloco, casa, lote)         ON imovel_privado TO nay_site_escrita;

GRANT SELECT (codigo, vencimento) ON contratos_locacao TO nay_site_escrita;
GRANT INSERT (codigo, vencimento) ON contratos_locacao TO nay_site_escrita;
GRANT UPDATE (vencimento)         ON contratos_locacao TO nay_site_escrita;
GRANT USAGE ON SEQUENCE contratos_locacao_id_seq TO nay_site_escrita;

COMMIT;
