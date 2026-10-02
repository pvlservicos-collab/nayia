-- Pega o que esta pronto para sair. lote = turno (resposta, sai na hora);
-- NULL = o que a NAI inicia (respeita a janela de horario). Aqui ficam as
-- paredes: pausa, modo teste (redireciona e nunca sai para fora da lista),
-- repeticao e foto que nao confere.
SELECT * FROM nai_liberar_saida($1::bigint);
