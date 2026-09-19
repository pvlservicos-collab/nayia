-- Doc 28, passo 2: campos aceita_venda/aceita_locacao na tabela grupos.
-- Não rodar ainda -- revisar antes.

ALTER TABLE grupos
  ADD COLUMN aceita_venda boolean NOT NULL DEFAULT true,
  ADD COLUMN aceita_locacao boolean NOT NULL DEFAULT true;

-- "SÓ TERCEIROS COMPRA, VEN" -- único grupo que não aceita locação.
UPDATE grupos SET aceita_locacao = false WHERE id_grupo = '559291807424-1424569650';
