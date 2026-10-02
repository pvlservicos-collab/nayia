CREATE OR REPLACE FUNCTION public.nai_visitas_do_bloco_avisar()
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_agora  timestamp := now() AT TIME ZONE 'America/Manaus';   -- a hora de Manaus, sem fuso
  v_manha  time := nai_cfg('resumo_tel_manha', '08:30')::time;
  v_tarde  time := nai_cfg('resumo_tel_tarde', '12:00')::time;
  v_noite  time := nai_cfg('resumo_tel_noite', '18:00')::time;
  v_bloco  text;
  v_ini    timestamp;
  v_fim    timestamp;
  v_ligar  text := '';
  v_ok     text := '';
  v_ids    bigint[] := '{}';
  v_sit    text[] := '{}';
  v_primeiro boolean;
  r        record;
  dono     record;
  v_fone   text;
  v_linha  text;
BEGIN
  IF nai_cfg('resumo_tel_ligado', 'sim') <> 'sim' THEN RETURN 0; END IF;

  -- o bloco de AGORA. Antes do aviso da manhã não há bloco: ninguém é acordado.
  IF    v_agora::time >= v_noite THEN v_bloco := 'noite'; v_ini := v_agora::date + v_noite; v_fim := v_agora::date + interval '1 day';
  ELSIF v_agora::time >= v_tarde THEN v_bloco := 'tarde'; v_ini := v_agora::date + v_tarde; v_fim := v_agora::date + v_noite;
  ELSIF v_agora::time >= v_manha THEN v_bloco := 'manha'; v_ini := v_agora::date;           v_fim := v_agora::date + v_tarde;
  ELSE RETURN 0;
  END IF;

  -- já saiu alguma visita deste bloco hoje? (decide o título: resumo ou "entrou visita")
  v_primeiro := NOT EXISTS (SELECT 1 FROM nai_aviso_bloco a WHERE a.dia = v_agora::date AND a.bloco = v_bloco);

  FOR r IN
    SELECT v.*, (v.quando AT TIME ZONE 'America/Manaus') AS local,
           -- o dono já disse sim?
           (v.prop_ok_em IS NOT NULL OR v.estado = 'confirmada'
            OR (v.ult_resp_prop_em IS NOT NULL AND v.ult_resp_prop_em >= coalesce(v.ult_msg_prop_em, v.ult_resp_prop_em))) AS dono_ok,
           coalesce(c.nome_completo, c.nome_whatsapp, 'corretor') AS corretor
      FROM nai_visita v
      LEFT JOIN nai_contato c ON c.id = v.corretor_id
     WHERE nai_visita_aberta(v.estado)
       AND v.estado NOT IN ('coletando', 'confirmando', 'realizada')
       AND v.quando IS NOT NULL
       AND v.quando > now()
       AND (v.quando AT TIME ZONE 'America/Manaus') >= v_ini
       AND (v.quando AT TIME ZONE 'America/Manaus') <  v_fim
       -- o dono foi procurado, ou já confirmou: é o que o Tel pediu para ver
       AND (v.ult_msg_prop_em IS NOT NULL OR v.prop_ok_em IS NOT NULL OR v.estado = 'confirmada')
       AND NOT EXISTS (SELECT 1 FROM nai_aviso_bloco a
                        WHERE a.visita_id = v.id AND a.dia = v_agora::date AND a.bloco = v_bloco)
     ORDER BY v.quando
  LOOP
    SELECT * INTO dono FROM nai_proprietario_do_imovel(r.codigo);
    v_fone := coalesce(nullif(r.prop_telefone_manual, ''), dono.telefone);
    v_linha := '• ' || to_char(r.local, 'HH24"h"MI') || ' · ' || nai_ref_imovel(r.codigo) || ' (visita #' || r.id || ')' || E'\n'
            || '   Proprietário: ' || coalesce(nullif(btrim(coalesce(r.proprietario_nome, dono.nome, '')), ''), 'sem nome no cadastro')
            || CASE WHEN coalesce(v_fone, '') <> '' THEN ' ' || nai_fone_fmt(v_fone) ELSE ' (sem telefone no cadastro)' END || E'\n'
            || '   Corretor: ' || r.corretor;
    IF r.dono_ok THEN
      v_ok := v_ok || v_linha || E'\n';
    ELSE
      v_ligar := v_ligar || v_linha
              || CASE WHEN r.ult_msg_prop_em IS NOT NULL
                      THEN E'\n   Escrevi ' || nai_quando_humano(r.ult_msg_prop_em, now()) || ', e não tive resposta.' ELSE '' END
              || E'\n';
    END IF;
    v_ids := array_append(v_ids, r.id);
    v_sit := array_append(v_sit, CASE WHEN r.dono_ok THEN 'confirmada' ELSE 'dono_sem_resposta' END);
  END LOOP;

  IF array_length(v_ids, 1) IS NULL THEN RETURN 0; END IF;

  PERFORM nai_avisar_tel(NULL, NULL,
    CASE WHEN v_primeiro THEN 'Tel, as visitas ' ELSE 'Tel, entrou visita para ' END
      || CASE v_bloco WHEN 'manha' THEN CASE WHEN v_primeiro THEN 'desta manhã' ELSE 'esta manhã' END
                      WHEN 'tarde' THEN CASE WHEN v_primeiro THEN 'desta tarde' ELSE 'esta tarde' END
                      ELSE CASE WHEN v_primeiro THEN 'desta noite' ELSE 'esta noite' END END || ':'
      || CASE WHEN v_ligar <> '' THEN E'\n\n☎️ *O proprietário ainda não respondeu — vale ligar:*\n' || rtrim(v_ligar, E'\n') ELSE '' END
      || CASE WHEN v_ok    <> '' THEN E'\n\n✅ *Confirmadas com o proprietário:*\n' || rtrim(v_ok, E'\n') ELSE '' END,
    'visitas_do_bloco');

  INSERT INTO nai_aviso_bloco (visita_id, dia, bloco, situacao)
  SELECT u.id, v_agora::date, v_bloco, u.sit FROM unnest(v_ids, v_sit) AS u(id, sit)
  ON CONFLICT DO NOTHING;
  RETURN array_length(v_ids, 1);
END;
$function$;
