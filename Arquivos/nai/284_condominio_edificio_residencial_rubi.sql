-- 284 (03/10/2026): O EDIFÍCIO RESIDENCIAL RUBI ENTRA NO CADASTRO DE CONDOMÍNIOS.
--
-- Pedro, 03/10: "tem um condomínio que não está no site, precisa estar: Edifício Residencial Rubi; veja se tem
-- no antigo, ou se já está no novo e com informações só não aparecendo direito".
--
-- O QUE HAVIA: o nome "Edifício Residencial Rubi" escrito em 8 imóveis vindos da planilha do site antigo
-- (Parque 10 de Novembro, Av. Maneca Marques, 55), todos Vendido ou Removido e sem ligação (condo_id nulo). Na
-- tabela `condominios` -- de onde saem a lista, a aba Condomínios e o seletor do cadastro -- só existia o
-- "CONQUISTA RUBI" (Colônia Terra Nova), que é outro. A 238 só cadastrou condomínio de imóvel que a Nay
-- oferecia; quem só tinha unidade vendida ficou de fora. No site antigo público não sobrou nada dele (os
-- anúncios vendidos saíram do ar e não há página de condomínio): os dados daqui são os das próprias unidades.
--
-- 1. cadastra o condomínio; 2. abre a ficha dele com o endereço (as 8 unidades concordam); 3. liga as unidades.
-- Só o `condo_id` muda nos imóveis: situação, anúncio e o resto ficam como estão.
BEGIN;
SET LOCAL lock_timeout = '3s';

INSERT INTO condominios (id, nome, bairro)
SELECT (SELECT max(id) FROM condominios) + 1, 'Edifício Residencial Rubi', 'Parque 10 de Novembro'
 WHERE NOT EXISTS (SELECT 1 FROM condominios c
                    WHERE lower(unaccent(btrim(c.nome))) = lower(unaccent('Edifício Residencial Rubi')));

INSERT INTO condominio_ficha (condominio_id, nome, nomes_no_imovel, tipo, bairro, endereco, logradouro, numero, cidade, estado, fonte)
SELECT c.id, c.nome, ARRAY['Edifício Residencial Rubi'], 'apartamentos', 'Parque 10 de Novembro',
       'Av. Maneca Marques, nº 55, Bairro Parque 10 de Novembro, Manaus - AM', 'Av. Maneca Marques', '55', 'Manaus', 'AM',
       'unidades do site antigo (planilha de 26/09/2026)'
  FROM condominios c
 WHERE c.nome = 'Edifício Residencial Rubi'
   AND NOT EXISTS (SELECT 1 FROM condominio_ficha f WHERE f.condominio_id = c.id OR f.nome = c.nome);

UPDATE imoveis i
   SET condo_id = c.id
  FROM condominios c
 WHERE c.nome = 'Edifício Residencial Rubi'
   AND i.condo_id IS NULL
   AND lower(unaccent(btrim(i.condominio_nome))) = lower(unaccent(c.nome));

COMMIT;
