-- 232 (30/09/2026): CONJUNTO E AVENIDA DA LISTA VALEM PELO NOME SOZINHO.
-- Pedro: "preciso de tudo aquilo na memória da Nay para ela responder" e "relacione
-- com os bairros as avenidas também". Conferido item a item: 30/38 conjuntos e 24/43
-- avenidas já viravam bairro; o resto só com "conjunto"/"av" na frente. Agora o nome
-- basta -- menos onde confunde: "31 de março" e "sete de maio" (datas), "tancredo
-- neves" (é bairro), "pedro teixeira" (nome de gente), "perimetral/preciosa/margarita"
-- (palavras comuns): esses continuam pedindo "av/na/conjunto/no" na frente.
BEGIN;
SET LOCAL lock_timeout = '3s';
UPDATE nai_lugar_conjunto SET expressao = CASE nome
  WHEN 'Conjunto Tiradentes'      THEN '\m((conjunto|conj|cjto|cj|residencial|loteamento|condominio) )?tiradentes\M'
  WHEN 'Residencial Viver Melhor' THEN '\m((conjunto|conj|cjto|cj|residencial|condominio|no|do) )?viver melhor\M'
  WHEN 'Conjunto Canaranas'       THEN '\m((conjunto|conj|cjto|cj|no|do|nas|das) )?canaranas?\M'
  WHEN 'Conjunto Galileia'        THEN '\m((conjunto|conj|cjto|cj|no|do|na|da) )?galil(e|é)ia\M'
  WHEN 'Conjunto Águas Claras'    THEN '\m((conjunto|conj|cjto|cj|residencial|no|do|nas|das) )?aguas claras\M'
  WHEN 'Conjunto Japiim I e II'   THEN '\m((conjunto|conj|cjto|cj) )?japiim( (i|ii|1|2)( e (ii|2))?)?\M'
  WHEN 'Conjunto 31 de Março'     THEN '\m(conjunto|conj|cjto|cj|no|do) 31 de marco\M'
  ELSE expressao END
 WHERE nome IN ('Conjunto Tiradentes','Residencial Viver Melhor','Conjunto Canaranas','Conjunto Galileia',
                'Conjunto Águas Claras','Conjunto Japiim I e II','Conjunto 31 de Março');

-- P = prefixo opcional; nomes que confundem mantêm o prefixo obrigatório
UPDATE nai_lugar_avenida SET expressao = CASE nome
  WHEN 'Av. André Araújo'               THEN '\m((av|avenida|na|pela|perto da|proximo da|proximo a) )?andre araujo\M'
  WHEN 'Av. Cosme Ferreira'             THEN '\m((av|avenida|na|pela|perto da|proximo da|proximo a) )?cosme ferreira\M'
  WHEN 'Av. Rodrigo Otávio'             THEN '\m((av|avenida|na|pela|perto da|proximo da|proximo a) )?(general )?rodrigo otavio( jordao)?\M'
  WHEN 'Av. João Valério'               THEN '\m((av|avenida|na|pela|perto da|proximo da|proximo a) )?joao valerio\M'
  WHEN 'Av. Álvaro Maia'                THEN '\m((av|avenida|na|pela|perto da|proximo da|proximo a) )?alvaro maia\M'
  WHEN 'Av. Desembargador João Machado' THEN '\m((av|avenida|na|pela|perto da|proximo da|proximo a) )?((desembargador|des) )?joao machado\M'
  WHEN 'Av. Nathan Xavier'              THEN '\m((av|avenida|na|pela|perto da|proximo da|proximo a) )?nath?an xavier\M'
  WHEN 'Av. Itaúba'                     THEN '\m((av|avenida|na|pela|perto da|proximo da|proximo a) )?itauba\M'
  WHEN 'Av. Mulateiro'                  THEN '\m((av|avenida|na|pela|perto da|proximo da|proximo a) )?mulateiro\M'
  WHEN 'Av. Camapuã'                    THEN '\m((av|avenida|na|pela|perto da|proximo da|proximo a) )?camapua\M'
  WHEN 'Av. Guaranás'                   THEN '\m((av|avenida|na|pela|perto da|proximo da|proximo a) )?guaranas\M'
  WHEN 'Av. Timbiras'                   THEN '\m((av|avenida|na|pela|perto da|proximo da|proximo a) )?timbiras\M'
  WHEN 'Av. Curaçao'                    THEN '\m((av|avenida|na|pela|perto da|proximo da|proximo a) )?curacao\M'
  WHEN 'Av. Tancredo Neves'             THEN '\m(av|avenida|na|pela|perto da|proximo da|proximo a) tancredo neves\M'
  WHEN 'Av. Pedro Teixeira'             THEN '\m(av|avenida|na|pela|perto da|proximo da|proximo a) pedro teixeira\M'
  WHEN 'Av. Perimetral'                 THEN '\m(av|avenida|na|pela|perto da|proximo da|proximo a) perimetral\M'
  WHEN 'Av. Preciosa'                   THEN '\m(av|avenida|na|pela|perto da|proximo da|proximo a) preciosa\M'
  WHEN 'Av. Margarita'                  THEN '\m(av|avenida|na|pela|perto da|proximo da|proximo a) margarita\M'
  WHEN 'Av. Sete de Maio'               THEN '\m(av|avenida|na|pela|perto da|proximo da|proximo a) (sete|7) de maio\M'
  ELSE expressao END
 WHERE nome IN ('Av. André Araújo','Av. Cosme Ferreira','Av. Rodrigo Otávio','Av. João Valério','Av. Álvaro Maia',
                'Av. Desembargador João Machado','Av. Nathan Xavier','Av. Itaúba','Av. Mulateiro','Av. Camapuã',
                'Av. Guaranás','Av. Timbiras','Av. Curaçao','Av. Tancredo Neves','Av. Pedro Teixeira','Av. Perimetral',
                'Av. Preciosa','Av. Margarita','Av. Sete de Maio');

INSERT INTO nai_caso (quem, frase, pergunta, esperado, regra) VALUES
  ('Pedro 30/09', 'tem casa no tiradentes?', 'lugar', '{Aleixo}', 'conjunto pelo nome sozinho'),
  ('Pedro 30/09', 'viver melhor', 'lugar', '{"Lago Azul"}', 'conjunto pelo nome sozinho'),
  ('Pedro 30/09', 'algo nas canaranas', 'lugar', '{"Cidade Nova"}', 'conjunto pelo nome sozinho'),
  ('Pedro 30/09', 'galileia', 'lugar', '{"Nova Cidade"}', 'conjunto pelo nome sozinho'),
  ('Pedro 30/09', 'aguas claras', 'lugar', '{"Novo Aleixo"}', 'conjunto pelo nome sozinho'),
  ('Pedro 30/09', 'japiim 2', 'lugar', '{Japiim}', 'conjunto pelo nome sozinho'),
  ('Pedro 30/09', 'no 31 de março', 'lugar', '{Japiim}', 'conjunto com "no" na frente'),
  ('Pedro 30/09', 'perto da cosme ferreira', 'lugar', '{Aleixo,"São José Operário"}', 'avenida pelo nome sozinho'),
  ('Pedro 30/09', 'algo na rodrigo otávio jordão', 'lugar', '{Aleixo,Japiim}', 'avenida pelo nome sozinho'),
  ('Pedro 30/09', 'cliente pedro teixeira quer 2 quartos', 'lugar', '-', 'nome de gente não é avenida'),
  ('Pedro 30/09', 'visita dia sete de maio', 'lugar', '-', 'data não é avenida'),
  ('Pedro 30/09', 'na av tancredo neves', 'lugar', '{"Parque 10 de Novembro"}', 'avenida com av na frente');
COMMIT;
