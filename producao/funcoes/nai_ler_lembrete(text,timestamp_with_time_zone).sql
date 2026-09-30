CREATE OR REPLACE FUNCTION public.nai_ler_lembrete(p text, p_agora timestamp with time zone DEFAULT now())
 RETURNS TABLE(quando timestamp with time zone, oque text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  s      text := lower(unaccent(coalesce(p, '')));
  agora  timestamp := p_agora AT TIME ZONE 'America/Manaus';
  m      text[];
  v_dia  date;
  v_h    int;
  v_min  int := 0;
  v_n    int;
  v_q    timestamp;
  v_txt  text := coalesce(p, '');
  v_dow  int;
  v_alvo int;
BEGIN
  -- relativo: "daqui 30 minutos", "em 2 horas", "daqui a uma hora", "daqui meia hora"
  m := regexp_match(s, '\m(daqui|em|dentro\s+de)\s+(a\s+)?(\d{1,3}|uma|um|meia)\s*(min\w*|h\M|hs\M|hora\w*)');
  IF m IS NOT NULL THEN
    v_n := CASE WHEN m[3] IN ('uma', 'um') THEN 1 WHEN m[3] = 'meia' THEN 0 ELSE m[3]::int END;
    IF m[4] ~ '^min' THEN
      v_q := agora + make_interval(mins => v_n);
    ELSIF m[3] = 'meia' THEN
      v_q := agora + interval '30 minutes';
    ELSE
      v_q := agora + make_interval(hours => v_n);
    END IF;
  ELSE
    -- o dia
    IF s ~ '\mdepois\s+de\s+amanha\M' THEN
      v_dia := agora::date + 2;
    ELSIF s ~ '\mamanha\M' THEN
      v_dia := agora::date + 1;
    ELSIF s ~ '\mhoje\M' THEN
      v_dia := agora::date;
    ELSE
      m := regexp_match(s, '\mdia\s+(\d{1,2})(\s*/\s*(\d{1,2}))?');
      IF m IS NOT NULL THEN
        BEGIN
          v_dia := make_date(extract(year FROM agora)::int,
                             coalesce(m[3]::int, extract(month FROM agora)::int), m[1]::int);
          IF v_dia < agora::date THEN
            v_dia := CASE WHEN m[3] IS NULL THEN (v_dia + interval '1 month')::date ELSE (v_dia + interval '1 year')::date END;
          END IF;
        EXCEPTION WHEN OTHERS THEN v_dia := NULL;
        END;
      ELSE
        m := regexp_match(s, '\m(segunda|terca|quarta|quinta|sexta|sabado|domingo)\M');
        IF m IS NOT NULL THEN
          v_alvo := array_position(ARRAY['segunda', 'terca', 'quarta', 'quinta', 'sexta', 'sabado', 'domingo'], m[1]);
          v_dow := extract(isodow FROM agora)::int;
          v_dia := agora::date + ((v_alvo - v_dow + 7) % 7);
        END IF;
      END IF;
    END IF;

    -- a hora
    IF s ~ '\mmeio[\s-]dia\M' THEN
      v_h := 12; v_min := 0;
    ELSE
      m := regexp_match(s, '\m(\d{1,2})\s*(h|:|hs|horas?)\s*(\d{2})?(\s*(da|de)\s+(manha|tarde|noite))?');
      IF m IS NULL THEN
        m := regexp_match(s, '\m(as|a)\s+(\d{1,2})(\s*(da|de)\s+(manha|tarde|noite))?\M');
        IF m IS NOT NULL THEN
          m := ARRAY[m[2], 'h', NULL, m[3], m[4], m[5]];
        END IF;
      END IF;
      IF m IS NOT NULL THEN
        v_h := m[1]::int;
        v_min := coalesce(m[3]::int, 0);
        IF m[6] IN ('tarde', 'noite') AND v_h < 12 THEN v_h := v_h + 12; END IF;
      END IF;
    END IF;

    IF v_h IS NULL AND v_dia IS NULL THEN
      RETURN;   -- nao deu para saber quando
    END IF;
    IF v_h IS NULL OR v_h > 23 OR v_min > 59 THEN
      IF v_h IS NOT NULL THEN RETURN; END IF;
      v_h := 9; v_min := 0;   -- dia sem hora: 09h00
    END IF;
    v_q := coalesce(v_dia, agora::date) + make_time(v_h, v_min, 0);
    IF v_dia IS NULL AND v_q <= agora THEN
      v_q := v_q + interval '1 day';
    ELSIF v_dia IS NOT NULL AND v_dia = agora::date AND v_q <= agora AND s ~ '\m(segunda|terca|quarta|quinta|sexta|sabado|domingo)\M' THEN
      v_q := v_q + interval '7 days';
    END IF;
  END IF;

  -- o que lembrar: o pedido sem o comando, sem o quando e sem os conectivos
  v_txt := regexp_replace(v_txt, '^\s*@?nay[\s,:;.!-]*', '', 'i');
  v_txt := regexp_replace(v_txt, '^\s*((me|nos)\s+(lembr\w*|avis\w*)|lembr\w*-me|(agenda\s+(um\s+)?|cria\s+(um\s+)?)?lembrete)[\s,:;.!-]*', '', 'i');
  v_txt := regexp_replace(v_txt, '\m(daqui|em|dentro\s+de)\s+(a\s+)?(\d{1,3}|uma|um|meia)\s*(min\w*|h\M|hs\M|hora\w*)', ' ', 'gi');
  v_txt := regexp_replace(v_txt, '\m(depois\s+de\s+amanh[ãa]|amanh[ãa]|hoje)\M', ' ', 'gi');
  v_txt := regexp_replace(v_txt, '\m((na|no|nesta|neste|pr[óo]xim[ao])\s+)?(segunda|ter[çc]a|quarta|quinta|sexta|s[áa]bado|domingo)(-feira)?\M', ' ', 'gi');
  v_txt := regexp_replace(v_txt, '\mdia\s+\d{1,2}(\s*/\s*\d{1,2})?', ' ', 'gi');
  v_txt := regexp_replace(v_txt, '\m(à|a|às|as)?\s*\d{1,2}\s*(h|:|hs|horas?)\s*(\d{2})?(\s*(da|de)\s+(manh[ãa]|tarde|noite))?', ' ', 'gi');
  v_txt := regexp_replace(v_txt, '\m(à|a|às|as)\s+\d{1,2}(\s*(da|de)\s+(manh[ãa]|tarde|noite))?\M', ' ', 'gi');
  v_txt := regexp_replace(v_txt, '\m(ao\s+|a\s+|à\s+)?meio[\s-]dia\M', ' ', 'gi');
  v_txt := regexp_replace(v_txt, '\s{2,}', ' ', 'g');
  v_txt := btrim(v_txt, E' \t\n,:;.-');
  v_txt := regexp_replace(v_txt, '^(de|que|para|pra|pro|sobre|do|da)\s+', '', 'i');
  v_txt := btrim(v_txt, E' \t\n,:;.-');

  quando := v_q AT TIME ZONE 'America/Manaus';
  oque := nullif(v_txt, '');
  RETURN NEXT;
END;
$function$;
