-- teste da 556 (roda dentro do ensaio, antes do ROLLBACK)
DO $t$
BEGIN
  ASSERT nai_dono_disse_que_saiu('Só vai estar liberado em janeiro') = 'ocupado', nai_dono_disse_que_saiu('Só vai estar liberado em janeiro');
  ASSERT nai_dono_disse_que_saiu('fica livre só dia 15/12') = 'ocupado', 'dia';
  ASSERT nai_dono_disse_que_saiu('o inquilino só desocupa mês que vem') = 'ocupado', 'mes que vem';
  -- o que já era continua
  ASSERT nai_dono_disse_que_saiu('Bom dia Loquei pra um parente por 2100') = 'alugado', 'loquei';
  ASSERT nai_dono_disse_que_saiu('ainda não aluguei') IS NULL, 'negação';
  ASSERT nai_dono_disse_que_saiu('está livre sim, pode visitar em janeiro') IS NULL, 'livre sem "só"';
  ASSERT nai_dono_disse_que_saiu('só posso receber visita amanhã') IS NULL, 'só sem liberar';
  -- o card do 9058 com o condomínio incluso
  ASSERT (SELECT texto_pronto FROM nai_card_do_banco(9058)) LIKE '%(incluso a tx)%', (SELECT texto_pronto FROM nai_card_do_banco(9058));
  ASSERT (SELECT texto_pronto FROM nai_card_do_banco(9058)) NOT LIKE '%fora taxa%', 'sem fora taxa';
  RAISE NOTICE 'teste_556: ok';
END
$t$;
