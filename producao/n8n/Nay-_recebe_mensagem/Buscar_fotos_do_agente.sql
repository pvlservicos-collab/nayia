-- Fotos de TODOS os imoveis que ela mandou, cada uma sabendo de qual e.
-- `imovel_fotos.codigo` e INTEGER e `string_to_array` devolve texto: sem o
-- ::text a comparacao explode com 'operator does not exist: integer = text'
-- -- foi o que derrubou o no em producao em 30/08. Comparar como texto (em
-- vez de converter o array para int) tambem evita erro se vier um codigo
-- nao numerico.
SELECT f.codigo, f.url FROM imovel_fotos f
 WHERE f.codigo::text = ANY(string_to_array($1, ','))
   AND nay_deve_mandar_fotos($2, $3)
 ORDER BY array_position(string_to_array($1, ','), f.codigo::text), f.ordem;
