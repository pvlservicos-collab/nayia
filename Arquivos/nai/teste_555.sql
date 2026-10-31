-- teste da 555 (roda dentro do ensaio, antes do ROLLBACK)
DO $t$
BEGIN
  -- recado não é resposta
  ASSERT pergunta_fila_e_recado('chegou'), 'chegou';
  ASSERT pergunta_fila_e_recado('Ah sim'), 'ah sim';
  ASSERT pergunta_fila_e_recado('ela passa a atender'), 'passa a atender';
  ASSERT pergunta_fila_e_recado('Excelente!'), 'excelente';
  ASSERT pergunta_fila_e_recado('kkkk'), 'kkkk';
  -- resposta de verdade continua sendo resposta
  ASSERT NOT pergunta_fila_e_recado('Fica no segundo andar'), 'andar';
  ASSERT NOT pergunta_fila_e_recado('Sim, mas já alugou'), 'alugou';
  ASSERT NOT pergunta_fila_e_recado('ela não aceita pet, mas qual é o porte ? podemos tentar'), 'pet';
  ASSERT NOT pergunta_fila_e_recado('sim'), 'sim';
  -- a ordem para a Nay vira a fala dela
  ASSERT pergunta_fila_fala_do_tel('Fala que a gente vai ver via WhatsApp, tá?') = 'a gente vai ver via WhatsApp, tá?',
         pergunta_fila_fala_do_tel('Fala que a gente vai ver via WhatsApp, tá?');
  ASSERT pergunta_fila_fala_do_tel('diz pra ele que aceita sim') = 'aceita sim', pergunta_fila_fala_do_tel('diz pra ele que aceita sim');
  ASSERT pergunta_fila_fala_do_tel('Fica no segundo andar') = 'Fica no segundo andar', 'resposta comum intacta';
  ASSERT pergunta_fila_fala_do_tel('Fala') = 'Fala', 'só a palavra fica';
  ASSERT nai_frase_maiuscula(pergunta_fila_fala_do_tel('fala que a gente vai ver')) = 'A gente vai ver.', 'maiúscula';
  RAISE NOTICE 'teste_555: ok';
END
$t$;
