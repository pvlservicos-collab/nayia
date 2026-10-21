-- 454 -- A campanha de cada lead do outro_imovel_04: alugado (lista 5), vendido (lista 4) ou removido (lista 3)
--
-- Pedro, 21/10/2026, para o disparo do outro_imovel_04 nas listas 3, 4 e 5: na lista 5 (imóvel alugado) a Nay "pergunta
-- da data de expiração e se ele não tem outro imóvel"; nas listas 3 e 4 "estamos com uma demanda alta de imóveis e
-- queremos saber se você tem imóveis para vender". A Nay de captação (nay-captacao, atender._prompt) lê esta coluna para
-- escolher o roteiro. Os 163 da lista 5 (447) ficam 'alugado'. Ninguém entra na fila aqui.
BEGIN;
SET LOCAL lock_timeout = '3s';

ALTER TABLE captacao_leads ADD COLUMN IF NOT EXISTS campanha text;
COMMENT ON COLUMN captacao_leads.campanha IS
  '454: o roteiro do modelo outro_imovel_04: alugado (lista 5: o contrato e o outro imóvel), vendido (lista 4) ou removido (lista 3: imóvel para vender). NULL = não é dessa campanha.';

UPDATE captacao_leads SET campanha = 'alugado'
 WHERE modelo_abertura = 'outro_imovel_04' AND quem_importou LIKE 'Pedro (lista 5:%' AND campanha IS NULL;

COMMIT;
