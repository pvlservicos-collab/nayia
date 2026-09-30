CREATE OR REPLACE FUNCTION public.nai_comando_lembrete(p_turno bigint, p_texto text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  t      nai_turno;
  s      text := lower(unaccent(btrim(coalesce(p_texto, ''))));
  m      text[];
  r      record;
  v_id   bigint;
  v_lista text;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL OR NOT nai_e_da_equipe_contato(t.contato_id) THEN
    RETURN 'O lembrete é só da equipe.';
  END IF;

  -- cancelar
  m := regexp_match(s, 'cancel\w*\s+(o\s+)?lembrete\s*#?\s*(\d+)');
  IF m IS NOT NULL THEN
    UPDATE nai_lembrete SET estado = 'cancelado'
     WHERE id = m[2]::bigint AND estado = 'agendado' AND contato_id = ANY (nai_contato_irmaos(t.contato_id))
    RETURNING id INTO v_id;
    IF v_id IS NULL THEN RETURN 'Não achei o lembrete ' || m[2] || ' agendado para você.'; END IF;
    RETURN 'Cancelei o lembrete ' || v_id || '.';
  END IF;

  -- listar
  IF s ~ '\mmeus\s+lembretes\M' OR s ~ '^(@?nay[\s,:;.!-]*)?lembretes\s*[?.!]*$' THEN
    SELECT string_agg('#' || l.id || ' — ' || nai_quando_lembrete(l.quando) || ': ' || l.texto, E'\n' ORDER BY l.quando)
      INTO v_lista FROM nai_lembrete l
     WHERE l.estado = 'agendado' AND l.contato_id = ANY (nai_contato_irmaos(t.contato_id));
    RETURN coalesce(E'Seus lembretes:\n' || v_lista, 'Você não tem lembrete agendado.');
  END IF;

  -- gravar
  SELECT * INTO r FROM nai_ler_lembrete(p_texto);
  IF r.quando IS NULL THEN
    RETURN 'Me diz quando, assim: "me lembra às 15h de ligar pro proprietário", "amanhã 9h", ou "daqui 30 minutos".';
  END IF;
  IF r.quando <= now() + interval '30 seconds' THEN
    RETURN 'Esse horário já passou. Me diz outro, por favor.';
  END IF;
  IF r.oque IS NULL THEN
    RETURN 'Te lembro do quê? Me manda de novo com o assunto, assim: "me lembra às 15h de ligar pro proprietário".';
  END IF;
  INSERT INTO nai_lembrete (contato_id, quando, texto, turno_id, pedido)
  VALUES (t.contato_id, r.quando, r.oque, p_turno, p_texto)
  RETURNING id INTO v_id;
  RETURN 'Combinado! Te lembro ' || nai_quando_lembrete(r.quando) || ': ' || r.oque || '.'
         || E'\n(lembrete ' || v_id || ' -- para cancelar: cancela lembrete ' || v_id || ')';
END;
$function$
;
