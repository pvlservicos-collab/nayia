-- =====================================================================
-- NAI -- 18: o CPF passa a ser aceito pela CONTAGEM dos digitos
--            (Tel, 15/09/2026)
--
-- Ele: "sinto que ta com problema la no cpf eu ja mandei e ela não reconhece
-- o cpf, isso não pode parar assim, ela tem que aceitar o cpf mesmo errado
-- só conferir os digitos mesmo".
--
-- O QUE ACONTECIA. `nai_cpf_valido` conferia os dois digitos verificadores
-- (o calculo oficial da Receita). O numero que o Tel mandou no teste --
-- 970.651.102-34 -- nao fecha essa conta, entao a funcao devolvia NULL, a
-- visita ficava com `visitante_cpf` vazio e ela pedia o CPF de novo, e de
-- novo: o loop que ele viu.
--
-- O QUE PASSA A VALER. Onze digitos = aceito, e o atendimento segue. A
-- funcao continua limpando ponto, traco e espaco, e continua devolvendo so
-- os numeros -- o resto do fluxo nao muda em nada.
--
-- O QUE ISSO CUSTA, dito na cara: 11111111111 e qualquer numero digitado
-- errado tambem passam. Era o preco de nao travar o atendimento, e foi a
-- escolha do Tel. Quem confere o documento de verdade e a portaria, na hora
-- da visita.
-- =====================================================================

CREATE OR REPLACE FUNCTION nai_cpf_valido(p text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  -- Tira tudo que nao e numero e devolve os 11 digitos. Qualquer outra
  -- quantidade devolve NULL, e ai ela pede de novo -- que e o caso do
  -- corretor que mandou o CPF pela metade.
  SELECT nullif(regexp_replace(coalesce(p, ''), '\D', '', 'g'), '')
   WHERE regexp_replace(coalesce(p, ''), '\D', '', 'g') ~ '^[0-9]{11}$';
$$;

COMMENT ON FUNCTION nai_cpf_valido(text) IS
  'Aceita CPF pela contagem de digitos (11), sem conferir digito verificador. Ordem do Tel, 15/09.';
