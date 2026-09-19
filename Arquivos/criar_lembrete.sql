-- A ferramenta que CRIA o lembrete, e o mapa de horários em SQL.
--
-- Sem isto a tabela `lembrete` fica vazia e o cron não tem o que mandar.
-- Quando o corretor diz que o cliente responde "amanhã de manhã", a Nay
-- chama `guardar_retorno` e esta função decide o dia e a hora.
--
-- POR QUE O MAPA EM SQL E NÃO NO PROMPT: interpretar "final da manhã" como
-- 11:00 é regra de negócio, e regra que o modelo pondera é regra que
-- falha. Aqui ele passa a FRASE CRUA e o banco decide -- mesmo padrão do
-- `texto_pronto`. Também deixa registrado qual linha do mapa foi aplicada,
-- então dá para auditar por que a cobrança saiu naquela hora.
--
-- AS VARIAÇÕES: 205 formas levantadas (doc 31). Aqui entram as que um
-- corretor de Manaus escreve de verdade, com e sem acento, abreviadas.
-- Regra permanente do Tel: nunca só a forma canônica.
--
-- DOIS PIVÔS QUE VALEM MAIS QUE A TABELA:
--  * mensagem escrita entre 00:00 e 05:00 -> "amanhã" é HOJE no calendário;
--  * "logo" sem "cedo" é hoje (+3h); "logo cedo" é manhã de D+1. Um dia
--    inteiro de diferença numa palavra.
--
--   docker cp criar_lembrete.sql nay-postgres:/tmp/cl.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/cl.sql

CREATE OR REPLACE FUNCTION nay_quando_cobrar(p_frase text)
RETURNS TABLE(quando timestamptz, regra text)
LANGUAGE plpgsql STABLE AS $fn$
DECLARE
  t     text := lower(unaccent(btrim(coalesce(p_frase,''))));
  agora timestamptz := now();
  hoje  date := (now() AT TIME ZONE 'America/Manaus')::date;
  hora  int  := extract(hour FROM now() AT TIME ZONE 'America/Manaus')::int;
  base  date;
  h     time;
  r     text;
BEGIN
  IF t = '' THEN
    RETURN QUERY SELECT NULL::timestamptz, 'sem frase'::text;
    RETURN;
  END IF;

  -- Prazo que nao e prazo. Agendar em cima disso e chutar, e o Tel pediu
  -- que ela peca algo concreto uma vez em vez de supor (decisao 7 do doc 31).
  IF t ~ '\m(nao sei|nao faco ideia|qualquer hora|qquer hora|sei la|nao tenho ideia|depende|talvez)\M' THEN
    RETURN QUERY SELECT NULL::timestamptz, 'prazo vago demais'::text;
    RETURN;
  END IF;

  -- O DIA. "amanha" escrito de madrugada quer dizer HOJE: quem escreve
  -- 01:40 ainda esta no "dia de ontem" na cabeca dele.
  base := hoje;
  IF t ~ '\m(depois de amanha|dps de amanha)\M' THEN
    base := hoje + 2; r := 'depois de amanha';
  ELSIF t ~ '\m(amanha|amanha|amn|amanha)\M' THEN
    base := CASE WHEN hora < 5 THEN hoje ELSE hoje + 1 END;
    r := CASE WHEN hora < 5 THEN 'amanha dito de madrugada = hoje' ELSE 'amanha' END;
  ELSIF t ~ '\m(semana que vem|proxima semana|semana q vem)\M' THEN
    base := hoje + (8 - extract(isodow FROM hoje)::int);  -- proxima segunda
    r := 'semana que vem';
  ELSIF t ~ '\m(segunda|segunda-feira)\M' THEN
    base := hoje + ((8 - extract(isodow FROM hoje)::int) % 7); r := 'segunda';
  ELSIF t ~ '\m(terca|terca-feira)\M' THEN
    base := hoje + ((9 - extract(isodow FROM hoje)::int) % 7); r := 'terca';
  ELSIF t ~ '\m(quarta|quarta-feira)\M' THEN
    base := hoje + ((10 - extract(isodow FROM hoje)::int) % 7); r := 'quarta';
  ELSIF t ~ '\m(quinta|quinta-feira)\M' THEN
    base := hoje + ((11 - extract(isodow FROM hoje)::int) % 7); r := 'quinta';
  ELSIF t ~ '\m(sexta|sexta-feira)\M' THEN
    base := hoje + ((12 - extract(isodow FROM hoje)::int) % 7); r := 'sexta';
  ELSIF t ~ '\m(sabado|sab)\M' THEN
    base := hoje + ((13 - extract(isodow FROM hoje)::int) % 7); r := 'sabado';
  ELSIF t ~ '\m(domingo|dom)\M' THEN
    base := hoje + ((14 - extract(isodow FROM hoje)::int) % 7); r := 'domingo';
  END IF;
  -- Dia da semana que caiu em HOJE quer dizer o da semana que vem: quem
  -- diz "na segunda" numa segunda nao esta falando de daqui a uma hora.
  IF base = hoje AND r IN ('segunda','terca','quarta','quinta','sexta','sabado','domingo') THEN
    base := hoje + 7; r := r || ' que vem';
  END IF;
  IF base = hoje AND coalesce(r,'') = '' THEN r := 'hoje'; END IF;

  -- A HORA. Do mais especifico para o mais geral: "final da manha" tem de
  -- ser testado antes de "manha", senao "manha" ganha e vira 09:00.
  IF t ~ '\m(final da manha|fim da manha|perto do almoco|antes do almoco|antes do meio-dia|antes do meio dia)\M' THEN
    h := '11:00'; r := coalesce(r,'') || ' + final da manha';
  ELSIF t ~ '\m(depois do almoco|dps do almoco|apos o almoco|apos almocar|depois que almocar)\M' THEN
    h := '12:40'; r := coalesce(r,'') || ' + depois do almoco';
  ELSIF t ~ '\m(comeco da tarde|inicio da tarde|primeira hora da tarde)\M' THEN
    h := '13:30'; r := coalesce(r,'') || ' + inicio da tarde';
  ELSIF t ~ '\m(final da tarde|fim da tarde|fim do expediente|antes de fechar|fim do dia util)\M' THEN
    h := '17:30'; r := coalesce(r,'') || ' + final da tarde';
  ELSIF t ~ '\m(final do dia|fim do dia|ate o fim do dia|hoje ainda)\M' THEN
    h := '17:45'; r := coalesce(r,'') || ' + final do dia';
  ELSIF t ~ '\m(inicio da noite|comeco da noite|de noite|a noite|de tardezinha|depois do jantar|quando chegar em casa)\M' THEN
    h := '19:00'; r := coalesce(r,'') || ' + noite';
  ELSIF t ~ '\m(meio da tarde|meio da tarde)\M' THEN
    h := '15:30'; r := coalesce(r,'') || ' + meio da tarde';
  ELSIF t ~ '\m(a tarde|de tarde|pela tarde|no periodo da tarde|na parte da tarde)\M' THEN
    h := '14:30'; r := coalesce(r,'') || ' + tarde';
  ELSIF t ~ '\m(cedo|cedinho|bem cedo|logo cedo|cedo cedo|cedao|primeira hora|de manhazinha|assim que amanhecer)\M' THEN
    h := '08:00'; r := coalesce(r,'') || ' + cedo';
    IF base = hoje THEN base := hoje + 1; r := r || ' (cedo = amanha)'; END IF;
  ELSIF t ~ '\m(de manha|pela manha|na parte da manha|no turno da manha|manha)\M' THEN
    h := '09:00'; r := coalesce(r,'') || ' + manha';
  ELSIF t ~ '\m(mais tarde|daqui a pouco|ja ja|logo|agorinha|em breve)\M' THEN
    -- "logo" sem "cedo" e hoje. Se estourar o dia, cai para amanha cedo.
    IF hora + 3 >= 20 THEN
      base := hoje + 1; h := '08:00'; r := coalesce(r,'') || ' + logo (virou amanha)';
    ELSE
      h := ((hora + 3) || ':00')::time; r := coalesce(r,'') || ' + logo (+3h)';
    END IF;
  ELSE
    -- Sem hora dita: 08:00 do dia escolhido, como o Tel definiu.
    h := '08:00'; r := coalesce(r,'') || ' + sem hora (08:00)';
  END IF;

  -- Piso e teto do dia. Sem janela por dia da semana: domingo vale.
  IF h < '08:00'::time THEN h := '08:00'; END IF;
  IF h >= '20:00'::time THEN base := base + 1; h := '08:00';
     r := r || ' (passou das 20h, foi pro dia seguinte)'; END IF;

  quando := (base + h) AT TIME ZONE 'America/Manaus';

  -- Nunca agenda no passado: se a conta deu para tras, joga para daqui a
  -- uma hora ou para amanha cedo.
  IF quando <= agora THEN
    IF hora + 1 < 20 THEN
      quando := date_trunc('hour', agora) + interval '1 hour';
      r := r || ' (era passado, +1h)';
    ELSE
      quando := ((hoje + 1) + '08:00'::time) AT TIME ZONE 'America/Manaus';
      r := r || ' (era passado, amanha 08:00)';
    END IF;
  END IF;

  regra := btrim(coalesce(r,'?'));
  RETURN NEXT;
END;
$fn$;

-- --------------------------------------------------------------------
-- A ferramenta da Nay. Recebe a frase crua do corretor e o telefone vindo
-- do FLUXO (não do modelo), como todas as escritas deste projeto.
CREATE OR REPLACE FUNCTION nay_guardar_retorno(
  p_telefone   text,
  p_codigo     text,
  p_frase      text,
  p_referencia text
) RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
LANGUAGE plpgsql AS $fn$
DECLARE
  v_tel  text := regexp_replace(coalesce(p_telefone,''),'[^0-9]','','g');
  v_cod  text := NULLIF(regexp_replace(coalesce(p_codigo,''),'[^0-9]','','g'),'');
  v_ref  text := NULLIF(btrim(coalesce(p_referencia,'')),'');
  m      record;
BEGIN
  IF v_cod IS NULL THEN
    RETURN QUERY SELECT
      'de qual imóvel é esse cliente?'::text,
      ('sem o codigo do imovel o lembrete nao pode existir: a cobranca sairia '
       || 'generica demais. Pergunte de qual imovel antes de chamar de novo.')::text;
    RETURN;
  END IF;

  SELECT * INTO m FROM nay_quando_cobrar(p_frase);
  IF m.quando IS NULL THEN
    RETURN QUERY SELECT
      'quando ele te dá esse retorno?'::text,
      'nao deu para entender o prazo. peca algo concreto, como hoje a tarde ou amanha de manha.'::text;
    RETURN;
  END IF;

  -- Um lembrete vivo por corretor e imóvel: prazo novo SUBSTITUI o antigo,
  -- nunca soma (decisão 6 do Tel).
  UPDATE lembrete SET estado = 'morto', motivo_fim = 'substituido por prazo novo',
         atualizado_em = now()
   WHERE telefone = v_tel AND coalesce(codigo,'') = coalesce(v_cod,'')
     AND estado IN ('agendado','enviado','congelado');

  INSERT INTO lembrete (telefone, codigo, referencia, disparar_em,
                        expressao, regra_aplicada)
  VALUES (v_tel, v_cod, v_ref, m.quando, btrim(coalesce(p_frase,'')), m.regra);

  RETURN QUERY SELECT
    ''::text,
    ('anotado: vou cobrar esse retorno em '
     || to_char(m.quando AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI')
     || '. NAO diga a hora exata ao corretor nem que criou lembrete -- so '
     || 'confirme que ficou combinado, no seu tom.')::text;
END;
$fn$;
