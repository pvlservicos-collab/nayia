-- 368 -- O CEP de nove imóveis da lista da OLX e o telefone do texto padronizado
--
-- Pedro, 14/10/2026, com a lista que o Tel mandou ("Dispara esses na olx ... já com aquela mensagem nova padronizada
-- que mandei"). Nove dos códigos não subiam só por falta de CEP (a OLX exige). Os CEPs vieram do ViaCEP (Correios)
-- pelo endereço que já estava no cadastro; vão na ficha do condomínio, como no 366, e valem para todo imóvel de lá:
--   5758 Kopenhagen            Av. Tancredo Neves 173, Parque 10 (até 859/860)      69054-040   ficha 418
--   5754 Smile Village C. Nova Av. Max Teixeira 1838 (lado par, até 1882)           69058-415   ficha 333
--   5750 Alphaville 2          Av. José Augusto Loureiro, Ponta Negra              69037-225   ficha 462
--   5748 Jardim Adrianópolis   Av. Via Láctea, Aleixo                              69060-085   ficha 432
--   5742 Sainte Marie          R. Salvador, Adrianópolis                           69057-040   ficha 676
--   5741 Vista das Mangueiras  R. Jequié, Planalto                                 69044-802   ficha 446
--   5740 Solarium do Aruanã    R. João Pimentel, Compensa                          69036-360   ficha 329
--   4020 Boulevard Amazonas    Av. Álvaro Maia 1421, Adrianópolis                  69057-035   ficha 444
-- e o 5735 (Residencial Tarumã) no PRÓPRIO imóvel: ele diz Av. do Cetur (69022-155) e a ficha do condomínio diz
-- Av. da Floresta; não sei qual vale para o condomínio todo.
-- Dúvida que fica: o 5754 está no cadastro como Colônia Santo Antônio, mas pelos Correios o número 1838 (par) é Flores.
--
-- O telefone: o modelo que o Tel mandou termina em "Informações e contatos: 92 98595-6408 Wpp". A chave `telefone`
-- (do 364) é a que vai no texto e no campo de telefone da OLX (oculto).
BEGIN;
SET LOCAL lock_timeout = '3s';
UPDATE condominio_ficha f SET cep = v.cep, atualizado_em = now()
  FROM (VALUES (418, '69054-040'), (333, '69058-415'), (462, '69037-225'), (432, '69060-085'), (676, '69057-040'),
               (446, '69044-802'), (329, '69036-360'), (444, '69057-035')) v(id, cep)
 WHERE f.id = v.id AND coalesce(btrim(f.cep), '') = '';
UPDATE imoveis SET cep = '69022-155' WHERE codigo = 5735 AND coalesce(btrim(cep), '') = '';
UPDATE privado.olx_config SET valor = '92985956408' WHERE chave = 'telefone';
COMMIT;
