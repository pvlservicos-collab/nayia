CREATE OR REPLACE FUNCTION public.nay_quando_cobrar(p_frase text)
 RETURNS TABLE(quando timestamp with time zone, regra text)
 LANGUAGE plpgsql
 STABLE
AS $function$
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
$function$;
