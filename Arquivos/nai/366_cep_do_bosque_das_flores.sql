-- 366 -- O CEP do condomínio Bosque das Flores Residencial (ficha 690)
--
-- Pedro, 14/10/2026, com o plano da OLX comprado: "testa esse 3134". O anúncio do 3134 não saía só por falta de CEP
-- (a OLX exige), e nem o imóvel nem a ficha do condomínio tinham. Rua Dom Jackson Damasceno Rodrigues, Flores:
-- CEP 69058-833 pelo ViaCEP (Correios), "Rua Dom Jackson D. Rodrigues | Flores". Vale para os três imóveis de lá
-- (681, 3134, 5448): o anúncio usa o CEP do condomínio quando o imóvel não tem o dele.
BEGIN;
SET LOCAL lock_timeout = '3s';
UPDATE condominio_ficha SET cep = '69058-833', atualizado_em = now()
 WHERE id = 690 AND coalesce(btrim(cep), '') = '';
COMMIT;
