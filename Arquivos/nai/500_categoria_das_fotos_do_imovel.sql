-- 500 (Pedro, 26/10/2026): "preciso criar umas imagens bonitinhas tipo um post para todos os imóveis disponíveis ...
-- usar minha API do Gemini para classificar as fotos ... achar a foto principal e mais 4 cômodos legais".
--
-- imovel_fotos ganha onde o Gemini marca a foto: `categoria` (sala/quarto/area_lazer/banheiro; a capa continua usando
-- o `e_capa` que já existia) e `etiqueta` (o texto curto que aparece sobre a foto no post, ex. "Sala / cozinha
-- americana", "2 quartos", "Garden privativo", "Banheiro social" — o mesmo estilo do gerador de posts do Pedro).
BEGIN;
SET LOCAL lock_timeout = '3s';

ALTER TABLE imovel_fotos ADD COLUMN IF NOT EXISTS categoria text;
ALTER TABLE imovel_fotos ADD COLUMN IF NOT EXISTS etiqueta text;
ALTER TABLE imovel_fotos ADD COLUMN IF NOT EXISTS categoria_em timestamptz;
ALTER TABLE imovel_fotos DROP CONSTRAINT IF EXISTS imovel_fotos_categoria_check;
ALTER TABLE imovel_fotos ADD CONSTRAINT imovel_fotos_categoria_check
  CHECK (categoria IS NULL OR categoria IN ('sala', 'quarto', 'area_lazer', 'banheiro'));
CREATE INDEX IF NOT EXISTS imovel_fotos_categoria ON imovel_fotos (codigo, categoria) WHERE categoria IS NOT NULL;

COMMENT ON COLUMN imovel_fotos.categoria IS
  '500 (26/10): a Gemini escolheu esta foto para mostrar sala, quarto, área de lazer ou banheiro no post do imóvel. A capa continua em e_capa.';
COMMENT ON COLUMN imovel_fotos.etiqueta IS '500: o texto curto que o post mostra sobre a foto (gerado pela Gemini).';

COMMIT;
