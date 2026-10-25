-- teste da 499
SELECT count(*) AS camadas FROM nay_inteligencia_geral WHERE assunto = 'infraestrutura';
SELECT left(regra, 60) regra, vale_para, aplicada_em FROM nay_inteligencia_geral WHERE assunto = 'infraestrutura' ORDER BY id LIMIT 4;
