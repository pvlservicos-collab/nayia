-- O TEL ASSUMIU ESTE CHAT (pedido do Tel, 11/09): a NAI para de mandar
-- mensagem para essa pessoa. nai_tel_assumiu confere antes se nao e eco
-- do que a propria NAI mandou (mesmo ID ou mesmo texto) -- por isso a
-- espera de 15s: da tempo do 'Confirmar envio' gravar o ID. Volta com
-- o comando DEVOLVER <telefone>.
SELECT nai_tel_assumiu($1, $2, $3) AS r;
