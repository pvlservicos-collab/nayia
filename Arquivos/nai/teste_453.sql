-- teste da 453: dentro da transação do ensaio
\echo '--- o acompanhante ativo (esperado: só o Diego, final 2845)'
SELECT nome, papel, ativo, right(telefone, 4) AS fim FROM equipe WHERE papel = 'acompanhante' ORDER BY ativo DESC, nome;
\echo '--- quem a Nay avisa como motoboy e o nome que ela cita'
SELECT nome, right(telefone, 4) AS fim FROM nai_motoboy();
SELECT nai_acompanhante() AS nome_citado, nai_e_motoboy(nai_chave('5592982092845')) AS diego_e_motoboy;
\echo '--- a visita de locação da OLX continua chamando o Diego'
SELECT valor FROM privado.olx_config WHERE chave = 'visita_locacao';
