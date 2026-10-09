CREATE OR REPLACE FUNCTION public.nay_saidas_perguntar()
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  v_tel   bigint;
  v_hora  int;
  v_val   interval := make_interval(hours => greatest(nai_cfg_int('aviso_saida_validade_h', 24), 1));
  v_ids   bigint[];
  v_itens text[];
  v_texto text;
  v_saida bigint;
BEGIN
  IF lower(coalesce(nai_cfg('aviso_saida_pergunta', 'sim'), 'sim')) <> 'sim' THEN RETURN 0; END IF;

  -- o que não vale mais sai de aberto: prazo vencido, imóvel que voltou, saída que já é outra
  UPDATE aviso_de_saida_pergunta q
     SET resposta = 'vencida', respondido_em = now()
   WHERE q.resposta IS NULL
     AND (q.perguntado_em < now() - v_val
          OR NOT EXISTS (SELECT 1 FROM aviso_de_saida a JOIN imoveis i ON i.codigo::text = a.codigo
                          WHERE a.codigo = q.codigo AND a.marcado_em = q.marcado_em
                            AND a.avisado_em IS NULL AND NOT coalesce(i.disponivel, true)));

  -- parada, ou de noite: a pergunta espera (a saída continua na fila)
  IF nai_cfg('pausada', 'sim') <> 'nao' THEN RETURN 0; END IF;
  v_hora := extract(hour FROM now() AT TIME ZONE 'America/Manaus')::int;
  IF v_hora < nai_cfg_int('aviso_saida_hora_ini', 7) OR v_hora >= nai_cfg_int('aviso_saida_hora_fim', 22) THEN
    RETURN 0;
  END IF;
  v_tel := nai_contato_do_cadastro(nai_cfg('tel_telefone'), 'Tel');
  IF v_tel IS NULL THEN RETURN 0; END IF;

  WITH novas AS (
    INSERT INTO aviso_de_saida_pergunta (codigo, motivo, marcado_em, contato_id)
    SELECT a.codigo, a.motivo, a.marcado_em, v_tel
      FROM aviso_de_saida a
      JOIN imoveis i ON i.codigo::text = a.codigo
     WHERE a.avisado_em IS NULL
       AND a.marcado_em > now() - v_val
       AND NOT coalesce(i.disponivel, true)
     ORDER BY a.marcado_em
    ON CONFLICT (codigo, marcado_em) DO NOTHING
    RETURNING id, codigo, motivo)
  SELECT array_agg(n.id ORDER BY n.id), array_agg(nay_saida_rotulo(n.codigo, n.motivo) ORDER BY n.id)
    INTO v_ids, v_itens
    FROM novas n;
  IF v_ids IS NULL THEN RETURN 0; END IF;

  IF cardinality(v_ids) = 1 THEN
    v_texto := 'Tel, saiu do ar: ' || v_itens[1] || '.' || E'\n'
            || 'Aviso no grupo Easy? Responda SIM ou NÃO.';
  ELSE
    v_texto := 'Tel, saíram do ar:' || E'\n• ' || array_to_string(v_itens, E'\n• ') || E'\n'
            || 'Aviso no grupo Easy? SIM avisa todos, NÃO nenhum. Para escolher: SIM e os códigos.';
  END IF;
  v_saida := nai_avisar_tel(NULL, NULL, v_texto, 'aviso_saida_pergunta');
  UPDATE aviso_de_saida_pergunta SET saida_id = v_saida WHERE id = ANY (v_ids);
  RETURN cardinality(v_ids);
EXCEPTION WHEN others THEN
  RAISE WARNING 'nay_saidas_perguntar: %', SQLERRM;
  RETURN 0;
END
$function$;
