-- 544 (Pedro, 31/10/2026, revisão das conversas da Parceria de 30/10): a resposta do dono do 9064 foi ao corretor com
-- "precisa vender com urgência, pois está há cinco meses sem morar no imóvel e continua pagando as parcelas" e ficou na
-- memória da Nay (imovel_conhecimento 719), de onde ela repetiria a outros corretores. A frase vai para o Uso interno
-- (privado.imovel_ficha.observacoes, SIGILO 504) e sai da memória. O resto da resposta fica.
BEGIN;
UPDATE privado.imovel_ficha
   SET observacoes = concat_ws(E'\n', nullif(observacoes, ''),
         'Dono (30/10): precisa vender com urgência; há cinco meses sem morar no imóvel e continua pagando as parcelas.')
 WHERE codigo = 9064 AND coalesce(observacoes, '') NOT ILIKE '%urgência%';
UPDATE imovel_conhecimento
   SET texto = 'Ele informou que o valor está dentro do padrão, entre R$ 640 mil e R$ 670 mil.', atualizado_em = now()
 WHERE id = 719 AND codigo = '9064' AND texto ILIKE '%urgência%';
SELECT id, texto FROM imovel_conhecimento WHERE id = 719;
SELECT observacoes FROM privado.imovel_ficha WHERE codigo = 9064;
COMMIT;
