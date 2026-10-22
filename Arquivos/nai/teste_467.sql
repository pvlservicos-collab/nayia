-- teste da 467: o Tel pede de novo o 5721 para a Ana Claudia (já foi hoje às 10:18) e o radar automático pede o mesmo
\echo '--- feito a mao? (painel do Tel: sim; radar automatico: nao)'
SELECT nai_turno_feito_a_mao(17621) AS painel_do_tel,
       nai_turno_feito_a_mao((SELECT id FROM nai_turno WHERE papel = 'tel' AND texto ~* 'autom[aá]tico' ORDER BY id DESC LIMIT 1)) AS radar;
\echo '--- o pedido do Tel pelo painel'
SELECT nai_disparo_enfileirar('5592981126167', ARRAY[5721], 'ensaio 467') AS resposta;
\echo '--- o que entrou na caixa (deve ter card e fotos pendentes, nenhum bloqueado)'
SELECT s.tipo, s.estado, count(*), max(s.bloqueio) AS bloqueio FROM nai_saida s
 WHERE s.turno_id = (SELECT max(id) FROM nai_turno WHERE texto LIKE 'disparo pelo painel (ensaio 467)%') GROUP BY 1, 2;
