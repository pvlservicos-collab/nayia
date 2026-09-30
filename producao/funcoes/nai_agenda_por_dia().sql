CREATE OR REPLACE FUNCTION public.nai_agenda_por_dia()
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_hoje date := (now() AT TIME ZONE 'America/Manaus')::date;
  v_txt  text;
BEGIN
  SELECT string_agg(bloco, E'\n\n' ORDER BY dia) INTO v_txt FROM (
    SELECT d.dia,
           '*' || nai_dia_por_extenso(d.dia, v_hoje) || '*' || E'\n' ||
           string_agg(d.linha, E'\n' ORDER BY d.quando, d.id) AS bloco
      FROM (
        SELECT x.id,
               x.quando,
               ((x.quando AT TIME ZONE 'America/Manaus')::date) AS dia,
               to_char(x.quando AT TIME ZONE 'America/Manaus', 'HH24:MI') || ' - ' ||
               nai_ref_imovel(x.codigo) ||
               -- o nome do corretor como o resto do sistema o enxerga: o que ele
               -- mesmo passou, e so entao o do WhatsApp (que pode ser empresa).
               coalesce(' - ' || nullif(btrim(coalesce(k.nome_completo,
                        nay_nome_de_pessoa(k.nome_whatsapp))), ''), '') ||
               ' - ' || nai_estado_por_extenso(x.estado, x.aguardando) AS linha
          FROM nai_visita x
          LEFT JOIN nai_contato k ON k.id = x.corretor_id
         WHERE nai_visita_aberta(x.estado)
           AND x.quando IS NOT NULL
           AND (x.quando AT TIME ZONE 'America/Manaus')::date >= v_hoje
      ) d
     GROUP BY d.dia
  ) z;

  IF v_txt IS NULL THEN
    RETURN 'Agenda de visitas' || E'\n\n' || 'Nenhuma visita marcada de hoje em diante.';
  END IF;
  RETURN 'Agenda de visitas' || E'\n\n' || v_txt;
END;
$function$;
