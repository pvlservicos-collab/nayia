-- =====================================================================
-- NAI -- 53: encerrar a visita de teste #486 (Tel, 16/09/2026)
--
-- Ele: "revisa as leituras, reorganiza e decide tudo ai baseado no que eu ja
-- pedi". Esta estava na lista de pendencias dele desde ontem, e hoje virou
-- urgente.
--
-- O QUE IA ACONTECER HOJE: a #486 e a visita que eu criei para testar o fluxo
-- -- corretor "Pedro" (96 9171-2835, o numero de teste), visitante "Maria
-- Silva Souza", proprietario em branco. Ela ficou `confirmada` para hoje as
-- 15:00, e `nai_agenda_tick` roda a cada minuto:
--
--   14:00  lembrete de 1 hora, ao corretor
--   14:30  aviso ao acompanhante -- e `motoboy_id` aponta para o FERNANDO,
--          que saiu da funcao hoje de manha (arquivo 41)
--   16:00  "como foi a visita?", ao corretor E ao Fernando
--
-- Ou seja: uma pessoa de verdade receberia hoje duas mensagens sobre uma
-- visita que nunca existiu. Depois de um dia inteiro consertando a Nay para
-- ela nao falar errado com as pessoas, deixar isso de pe seria o contrario.
--
-- POR QUE UPDATE E NAO `nai_cancelar_visita`: a funcao de cancelar AVISA o
-- corretor e o acompanhante -- que e exatamente o que nao pode sair. Aqui o
-- estado vai direto para 'cancelada', que e o que a agenda le na linha 33
-- (`WHERE estado NOT IN ('encerrada','cancelada','expirada')`), e nenhuma
-- mensagem e enfileirada.
--
-- NADA E APAGADO: a linha da visita continua inteira, com corretor, horario e
-- historico. Muda o estado e entra um evento, que e o registro de que fui eu.
-- Para reabrir, basta voltar o estado para 'confirmada'.
-- =====================================================================

DO $$
DECLARE v record;
BEGIN
  SELECT * INTO v FROM nai_visita WHERE id = 486;
  IF v.id IS NULL THEN
    RAISE NOTICE 'visita 486 nao existe -- nada a fazer';
    RETURN;
  END IF;
  IF v.estado <> 'confirmada' THEN
    RAISE NOTICE 'visita 486 ja esta em "%": nao mexo', v.estado;
    RETURN;
  END IF;

  -- A parede: so encerro se for mesmo a de teste. Se algum dia a #486 for uma
  -- visita de gente, este bloco nao faz nada.
  IF coalesce(v.visitante_nome, '') <> 'Maria Silva Souza' THEN
    RAISE EXCEPTION 'a visita 486 nao e a de teste (visitante: %) -- nao mexo',
      coalesce(v.visitante_nome, '(sem nome)');
  END IF;

  UPDATE nai_visita
     SET estado = 'cancelada',
         motivo = 'visita de teste do dia 15/09, encerrada sem avisar ninguem',
         encerrada_em = now(),
         atualizado_em = now()
   WHERE id = 486;

  PERFORM nai_evento(486, 'cancelada', 'confirmada');
  RAISE NOTICE 'visita de teste 486 encerrada. A agenda nao a enxerga mais.';
END $$;
