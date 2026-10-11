-- 348 -- A ficha do condomínio guarda a SUGESTÃO da IA (para conferir), separada do que vale
--
-- Pedro, 11/10/2026: "puxar dados dos condomínios do site antigo e completar com o Google ... que tu vai tirar do
-- ChatGPT". O que o modelo sabe de um condomínio de Manaus pode estar errado, e a ficha é o que a Nay responde ao
-- corretor: a sugestão fica numa coluna própria, aparece no cadastro do condomínio com o botão "Usar o que está
-- vazio", e só entra na ficha quando alguém aplica e salva. Só DDL (IF NOT EXISTS, lock curto).
BEGIN;
SET LOCAL lock_timeout = '3s';
ALTER TABLE condominio_ficha
  ADD COLUMN IF NOT EXISTS ia_sugestao jsonb,
  ADD COLUMN IF NOT EXISTS ia_em timestamptz;
COMMENT ON COLUMN condominio_ficha.ia_sugestao IS '348: o que a IA sugeriu (construtora, ano, torres, andares, lazer...), para conferir e aplicar no cadastro; não é lido pela Nay.';
GRANT SELECT ON condominio_ficha TO nay_leitura;
COMMIT;
