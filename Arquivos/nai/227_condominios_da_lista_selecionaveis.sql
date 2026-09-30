-- 227 (30/09/2026): OS CONDOMÍNIOS DA LISTA DO PEDRO PASSAM A SER SELECIONÁVEIS.
-- Pedro: "nem atualizou os condomínios que eu pedi ... preciso que isso esteja
-- online no site e nos bancos de dados para selecionar direitinho".
-- A 210 gravou a ficha dos 11 condomínios (condominio_ficha), mas só 3 existiam em
-- `condominios` -- a tabela de onde o site tira a lista para escolher o condomínio
-- (/api/condominios, /api/condominios/sugerir, o cadastro do imóvel). Os outros 8
-- ficaram só na aba Condomínios, sem dar para selecionar. Nenhum deles existia com
-- outro nome (conferido por semelhança: os parecidos são outros condomínios).
BEGIN;
SET LOCAL lock_timeout = '3s';

WITH novos AS (
  SELECT f.id AS fid, f.nome, f.bairro, row_number() OVER (ORDER BY f.nome) AS n
    FROM condominio_ficha f
   WHERE f.condominio_id IS NULL
     AND NOT EXISTS (SELECT 1 FROM condominios c WHERE lower(unaccent(c.nome)) = lower(unaccent(f.nome)))
), ins AS (
  INSERT INTO condominios (id, nome, bairro)
  SELECT (SELECT max(id) FROM condominios) + n, nome, bairro FROM novos
  RETURNING id, nome
)
UPDATE condominio_ficha f SET condominio_id = ins.id, atualizado_em = now()
  FROM ins WHERE ins.nome = f.nome AND f.condominio_id IS NULL;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM condominio_ficha WHERE condominio_id IS NULL) THEN
    RAISE EXCEPTION 'ainda há ficha sem condomínio: %',
      (SELECT string_agg(nome, ', ') FROM condominio_ficha WHERE condominio_id IS NULL);
  END IF;
END $$;
COMMIT;

SELECT f.nome, f.bairro, f.condominio_id FROM condominio_ficha f ORDER BY f.nome;
