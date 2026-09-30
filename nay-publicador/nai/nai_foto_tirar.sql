CREATE OR REPLACE FUNCTION public.nai_foto_tirar(p_rotulo text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE v_id bigint; v_n int; v_rot text;
BEGIN
  v_rot := coalesce(nullif(btrim(coalesce(p_rotulo, '')), ''),
                    'foto de ' || to_char(now() AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI'));
  -- A sequência do cabeçalho dá o número: sem `max(id)+1`, sem corrida.
  INSERT INTO nai_foto (rotulo) VALUES (v_rot) RETURNING id INTO v_id;
  INSERT INTO nai_funcao_foto (foto_id, funcao, args, setor, familia, tamanho, hash)
  SELECT v_id, v.funcao, v.args, v.setor, v.familia, v.tamanho, v.hash
    FROM vw_nai_funcao_viva v;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN jsonb_build_object('foto', v_id, 'rotulo', v_rot, 'funcoes', v_n);
END;
$function$
;
