SELECT c, olx_anuncio_montar(c, 'venda')->>'ok' AS ok, olx_anuncio_montar(c, 'venda')->'falta' AS falta
  FROM unnest('{5758,5754,5750,5748,5742,5741,5740,5735,4020}'::int[]) c;
SELECT right(olx_corpo_do_anuncio(5758, 'venda'), 60) AS fim_do_texto;
