-- Quem pediu para entrar no grupo Alto Padrão, e por onde ele anuncia.
--
-- O PEDIDO (Tel, 23/09/2026): "preciso filtrar os corretores então quero saber
-- quem são os corretores que postam no instagram que quero avaliar o instagram
-- deles". As três perguntas são dele, palavra por palavra:
--
--   "você trabalha anunciando pelo instagram anunciando alto padrão ou por
--    portais imobiliarios? se usa portais qual seriam? e o seu instagram pode
--    me enviar caso trabalhe por lá?"
--
-- POR QUE UMA TABELA NOVA e não colunas em `corretores`: a resposta é sobre a
-- CANDIDATURA a um grupo, não sobre o corretor. Ele pode já estar aprovado em
-- `corretores` há meses e nunca ter sido avaliado para o Alto Padrão -- e a
-- avaliação é do Tel, olhando o Instagram, não do cadastro.
--
-- MEDIDO em 23/09 antes de escrever: em 6.114 mensagens recebidas, NENHUM
-- corretor tinha dado o Instagram espontaneamente. O dado não existe em lugar
-- nenhum do banco; só existe se for perguntado.

CREATE TABLE IF NOT EXISTS corretor_alto_padrao (
  telefone      text PRIMARY KEY,
  nome          text,

  -- o que ELE escreveu, para o Tel ver a frase real e não a minha leitura dela
  pediu_em      timestamptz NOT NULL DEFAULT now(),
  pediu_texto   text,

  -- uma pergunta por pessoa, para sempre. Sem isto, cada "sobre o grupo" dele
  -- refaz as três perguntas e a conversa vira interrogatório.
  perguntado_em timestamptz,

  anuncia_instagram boolean,
  instagram         text,
  anuncia_portais   boolean,
  portais           text,
  respondido_em     timestamptz,

  -- o Tel olhou o Instagram e decidiu. NULL = ainda não olhou.
  aprovado    boolean,
  avaliado_em timestamptz,

  criado_em timestamptz NOT NULL DEFAULT now()
);

-- A fila do Tel: quem já respondeu e ainda não foi avaliado, mais novo primeiro.
CREATE INDEX IF NOT EXISTS corretor_alto_padrao_a_avaliar
    ON corretor_alto_padrao (respondido_em DESC)
 WHERE respondido_em IS NOT NULL AND avaliado_em IS NULL;
