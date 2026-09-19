-- Lembrete de retorno: a Nay cobra o corretor no dia e hora prometidos.
--
-- ORIGEM: a conversa do Tel com a corretora sobre as duas clientes que
-- decidiriam "até amanhã". Ele quer que a Nay pergunte QUANDO pode
-- procurar, entenda a resposta em linguagem solta, e cobre na hora certa.
-- Plano completo e os 205 jeitos de dizer "amanhã": doc 31.
--
-- AS SEIS DECISÕES DO TEL (31/08), que são a especificação:
--  1. TETO: no máximo 1 mensagem por corretor por dia que a NAY começa.
--     Três lembretes vencendo juntos viram uma mensagem só, com lista.
--     Resposta a mensagem do corretor não conta -- isso é conversa.
--  2. SEM janela de silêncio por dia da semana: domingo e sábado valem.
--     (Ele já tinha dito: "no domingo de manhã manda a partir das 08:00".)
--     Mantido só o piso/teto de 08:00 às 20:00, porque todos os horários
--     que ele descreveu vivem lá dentro -- ver NOTA no fim.
--  3. TRÊS toques: o do horário prometido, o das 19:00 do mesmo dia, e um
--     no dia seguinte. Depois disso para e avisa o Tel.
--  4. O que ela NÃO conseguiu ler (áudio, imagem) CONGELA o lembrete e vai
--     para o Tel. Nunca cobra por cima de uma resposta que existe e ela
--     não entendeu -- foi o que mais irritou corretor neste projeto.
--  5. Caso escalado entra na lista do comando PENDENCIAS, com nome e idade.
--  6. Se o Tel sumir por 24h num imóvel em negociação nossa, a Nay avisa o
--     corretor por conta, com o texto que ele ditou.
--
-- O QUE MATA O LEMBRETE, e a ordem importa:
--  * qualquer mensagem nova do corretor CONGELA na hora (não precisa
--    entender, basta existir) -- silêncio de verdade é ausência de linha
--    em `mensagens`, não ausência de match do parser;
--  * VENDEU/ALUGOU no imóvel, ou ele sair de disponível;
--  * o Tel respondendo, ou a terceira tentativa sem retorno.
--
--   docker cp lembrete.sql nay-postgres:/tmp/lb.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/lb.sql

CREATE TABLE IF NOT EXISTS lembrete (
  id              bigserial PRIMARY KEY,
  telefone        text NOT NULL,           -- já resolvido, nunca @lid
  codigo          text,                    -- imóvel; NULL impede o envio
  referencia      text,                    -- "a cliente que viu sábado"
  estado          text NOT NULL DEFAULT 'agendado',
  disparar_em     timestamptz NOT NULL,
  tentativa       smallint NOT NULL DEFAULT 0,
  expressao       text,                    -- o que ele escreveu, cru
  regra_aplicada  text,                    -- qual linha do mapa decidiu
  criado_em       timestamptz NOT NULL DEFAULT now(),
  atualizado_em   timestamptz NOT NULL DEFAULT now(),
  motivo_fim      text,
  CONSTRAINT lembrete_estado_ok CHECK (estado IN
    ('agendado','enviado','congelado','morto','escalado'))
);

-- Nunca dois lembretes vivos para o mesmo corretor e imóvel. É o que
-- impede o caso "ele pediu mais prazo" de virar duas cobranças.
CREATE UNIQUE INDEX IF NOT EXISTS lembrete_um_vivo
  ON lembrete (telefone, coalesce(codigo,''))
  WHERE estado IN ('agendado','enviado','congelado');

CREATE INDEX IF NOT EXISTS lembrete_agenda ON lembrete (disparar_em)
  WHERE estado = 'agendado';

-- Livro-caixa de toque: TODO emissor grava aqui antes de mandar mensagem
-- que a Nay começa. Sem isto os três emissores continuam sem saber um do
-- outro e o corretor leva quatro mensagens numa manhã (decisão 1).
CREATE TABLE IF NOT EXISTS contato_corretor (
  id        bigserial PRIMARY KEY,
  telefone  text NOT NULL,
  quando    timestamptz NOT NULL DEFAULT now(),
  motivo    text NOT NULL,
  ref_id    bigint
);
CREATE INDEX IF NOT EXISTS contato_por_dia
  ON contato_corretor (telefone, quando);

-- --------------------------------------------------------------------
-- O teto de 1 por dia. Conta só o que a NAY começou: resposta a mensagem
-- do corretor não passa por aqui.
CREATE OR REPLACE FUNCTION nay_pode_falar(p_telefone text)
RETURNS boolean
LANGUAGE sql STABLE AS $fn$
  SELECT NOT EXISTS (
    SELECT 1 FROM contato_corretor c
     -- 8 ÚLTIMOS, nunca igualdade crua: a Z-API entrega o mesmo número ora
     -- com o 9 na frente (13 dígitos) ora sem (12), e comparar cru faz a
     -- mesma pessoa contar como duas -- furando o teto de 1 por dia.
     WHERE right(regexp_replace(c.telefone,'[^0-9]','','g'),8)
         = right(regexp_replace(coalesce(p_telefone,''),'[^0-9]','','g'),8)
       AND c.quando >= date_trunc('day', now() AT TIME ZONE 'America/Manaus')
                        AT TIME ZONE 'America/Manaus'
  );
$fn$;

-- --------------------------------------------------------------------
-- Qualquer mensagem do corretor CONGELA os lembretes dele. Não tenta
-- entender: basta a linha existir. Chamada pelo fluxo a cada mensagem
-- recebida.
CREATE OR REPLACE FUNCTION nay_congelar_lembretes(p_telefone text)
RETURNS int
LANGUAGE plpgsql AS $fn$
DECLARE n int;
BEGIN
  UPDATE lembrete
     SET estado = 'congelado', atualizado_em = now()
   WHERE telefone = p_telefone
     AND estado IN ('agendado','enviado');
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$fn$;

-- --------------------------------------------------------------------
-- O que vence agora, já respeitando o teto e agrupado por corretor.
-- Um corretor com três lembretes devidos sai numa linha só.
CREATE OR REPLACE FUNCTION nay_lembretes_devidos()
RETURNS TABLE(telefone text, ids bigint[], mensagem text)
LANGUAGE sql STABLE AS $fn$
  WITH devidos AS (
    SELECT l.*,
           coalesce(NULLIF(i.condominio_nome,''), i.tipo, 'o imóvel') AS nome_imovel
      FROM lembrete l
      -- `imoveis.codigo` e INTEGER e `lembrete.codigo` e TEXT (a mesma
      -- inconsistencia de `pendencias`). Sem o ::text explode com
      -- 'operator does not exist: integer = text'.
      LEFT JOIN imoveis i ON i.codigo::text = l.codigo
     WHERE l.estado = 'agendado'
       AND l.disparar_em <= now()
       AND l.codigo IS NOT NULL          -- sem imóvel não cobra: a mensagem
                                          -- ficaria genérica demais
       AND coalesce(i.disponivel, true)   -- imóvel que saiu não se cobra
       AND nay_pode_falar(l.telefone)
  )
  SELECT d.telefone,
         array_agg(d.id ORDER BY d.criado_em),
         CASE WHEN count(*) = 1
              THEN 'sobre o ' || min(d.codigo) || ' (' || min(d.nome_imovel) || '), '
                   || coalesce(min(d.referencia), 'o cliente') || ' já te deu retorno?'
              ELSE 'ficaram ' || count(*) || ' coisas pendentes:' || chr(10)
                   || string_agg('• ' || d.codigo || ' (' || d.nome_imovel || ')'
                                 || coalesce(' — ' || d.referencia, ''),
                                 chr(10) ORDER BY d.criado_em)
                   || chr(10) || 'alguma delas já te deu retorno?'
         END
    FROM devidos d
   GROUP BY d.telefone;
$fn$;

-- --------------------------------------------------------------------
-- Reserva atômica antes de enviar. `postar_agora` já provou neste projeto
-- que sem isto o cron de minuto em minuto manda duas vezes.
CREATE OR REPLACE FUNCTION nay_reservar_lembretes(p_ids bigint[])
RETURNS int
LANGUAGE plpgsql AS $fn$
DECLARE n int;
BEGIN
  UPDATE lembrete
     SET estado = 'enviado',
         tentativa = tentativa + 1,
         atualizado_em = now()
   WHERE id = ANY(p_ids) AND estado = 'agendado';
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$fn$;

-- --------------------------------------------------------------------
-- Depois do envio: agenda o próximo toque ou encerra. Três toques
-- (decisão 3), e o terceiro sem resposta vira caso do Tel.
CREATE OR REPLACE FUNCTION nay_proximo_toque(p_ids bigint[])
RETURNS int
LANGUAGE plpgsql AS $fn$
DECLARE n int;
BEGIN
  INSERT INTO contato_corretor (telefone, motivo, ref_id)
  SELECT DISTINCT telefone, 'lembrete', min(id) FROM lembrete
   WHERE id = ANY(p_ids) GROUP BY telefone;

  UPDATE lembrete SET
    estado = CASE WHEN tentativa >= 3 THEN 'escalado' ELSE 'agendado' END,
    motivo_fim = CASE WHEN tentativa >= 3
                      THEN 'tres toques sem retorno' END,
    -- 2o toque: 19:00 do mesmo dia. 3o: 09:00 do dia seguinte.
    disparar_em = CASE
      WHEN tentativa = 1 THEN
        date_trunc('day', now() AT TIME ZONE 'America/Manaus')
          AT TIME ZONE 'America/Manaus' + interval '19 hours'
      ELSE
        date_trunc('day', now() AT TIME ZONE 'America/Manaus')
          AT TIME ZONE 'America/Manaus' + interval '1 day 9 hours'
      END,
    atualizado_em = now()
  WHERE id = ANY(p_ids) AND estado = 'enviado';
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$fn$;

-- NOTA sobre o piso e teto de horário. O Tel escolheu SEM janela de
-- silêncio: domingo, sábado e feriado valem. Mas todos os horários que
-- ele descreveu vivem entre 08:00 e 19:00, e nenhum caso dele manda
-- mensagem de madrugada. O agendador em Python vai empurrar para 08:00 o
-- que cair antes, e para 08:00 do dia seguinte o que cair depois das
-- 20:00 -- se ele quiser mensagem às 22h, é uma linha para mudar.
