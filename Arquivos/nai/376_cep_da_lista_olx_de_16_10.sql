-- 376 -- O CEP de quatro condomínios da lista da OLX de 15/10 (à noite)
--
-- Pedro, 16/10/2026, com a lista que o Tel mandou ("terminei de colocar os códigos para gente anunciar no olx"). Desses,
-- seis não subiam por falta de CEP (a OLX exige). Os CEPs vieram do ViaCEP (Correios) pelo endereço da ficha do
-- condomínio; vão na ficha, como no 366 e no 368, e valem para todo imóvel de lá:
--   9026 Turim Residencial       Rua Francisco Loureiro 185, Ponta Negra        69037-043   ficha 17
--   9023 Boa Vista Residencial   Rua Raimundo Nonato de Castro 748, Ponta Negra  69037-042   ficha 28 (e no imóvel)
--   9042 Atlantis                Rua Lindon Johnson 668, Parque 10              69054-712   ficha 699
--   1595 Barra do Rio Negro      Av. Coronel Teixeira, Ponta Negra (sem número)  69037-000   ficha 410
-- O Boa Vista tinha "690370000" (9 dígitos) na ficha e no imóvel: não é CEP, e por isso o anúncio dizia "sem CEP".
-- De fora, para o Tel: 2659 Village Park ("Rua José Romão, Aleixo"; nos Correios essa rua é do Novo Aleixo, 69099-762)
-- e 9044 Le Boulevard (Av. Coronel Teixeira 5049, "São Jorge"; a avenida tem CEP por trecho e São Jorge não aparece).
BEGIN;
SET LOCAL lock_timeout = '3s';
UPDATE condominio_ficha f SET cep = v.cep, atualizado_em = now()
  FROM (VALUES (17, '69037-043'), (28, '69037-042'), (699, '69054-712'), (410, '69037-000')) v(id, cep)
 WHERE f.id = v.id AND coalesce(regexp_replace(f.cep, '\D', '', 'g'), '') !~ '^[0-9]{8}$';
UPDATE imoveis SET cep = '69037-042' WHERE codigo = 9023 AND coalesce(regexp_replace(cep, '\D', '', 'g'), '') !~ '^[0-9]{8}$';
COMMIT;
