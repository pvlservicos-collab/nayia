CREATE OR REPLACE FUNCTION public.imovel_mudanca_trocar(p_id bigint, p_desfazer boolean, p_quem text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET lock_timeout TO '3s'
AS $function$
DECLARE
  m        privado.imovel_mudanca;
  i        imoveis;
  k        text;
  v_esp    jsonb;
  v_alvo   jsonb;
  v_st     text;
  v_disp   boolean;
  v_pub    boolean;
  v_venc   date;
  v_feito  text[] := '{}';
  v_pulado text[] := '{}';
  v_tocou  boolean := false;
  v_quem   text := left(coalesce(nullif(btrim(p_quem), ''), 'painel'), 80);
  v_dia    text := to_char(now() AT TIME ZONE 'America/Manaus', 'DD/MM');
  v_nome   text;
BEGIN
  SELECT * INTO m FROM privado.imovel_mudanca WHERE id = p_id FOR UPDATE;
  IF m.id IS NULL THEN RAISE EXCEPTION 'mudança % não existe', p_id; END IF;
  IF m.tipo <> 'mudanca' THEN RAISE EXCEPTION 'esta linha não mudou nada no cadastro: não há o que voltar'; END IF;
  IF p_desfazer AND m.desfeito_em IS NOT NULL THEN RAISE EXCEPTION 'esta mudança já foi desfeita'; END IF;
  IF NOT p_desfazer AND m.desfeito_em IS NULL THEN RAISE EXCEPTION 'esta mudança está valendo: não há o que refazer'; END IF;
  SELECT * INTO i FROM imoveis WHERE codigo = m.codigo FOR UPDATE;
  IF i.codigo IS NULL THEN RAISE EXCEPTION 'o imóvel % não está mais no cadastro', m.codigo; END IF;

  FOR k IN SELECT jsonb_object_keys(m.campos) LOOP
    IF NOT p_desfazer AND NOT (k = ANY (coalesce(m.desfeito_campos, '{}'))) THEN CONTINUE; END IF;
    v_esp  := CASE WHEN p_desfazer THEN m.campos->k->'para' ELSE m.campos->k->'de' END;
    v_alvo := CASE WHEN p_desfazer THEN m.campos->k->'de' ELSE m.campos->k->'para' END;
    v_nome := CASE k WHEN 'status' THEN 'situação' WHEN 'valor_aluguel' THEN 'valor do aluguel' WHEN 'valor_venda' THEN 'valor de venda'
                     WHEN 'vencimento' THEN 'fim do contrato' WHEN 'publicado_no_site' THEN 'no site' ELSE k END;

    IF k = 'status' THEN
      IF i.status IS DISTINCT FROM (v_esp #>> '{}') THEN
        v_pulado := array_append(v_pulado, format('%s (agora está %s)', v_nome, coalesce(i.status, 'sem situação'))); CONTINUE;
      END IF;
      v_st := v_alvo #>> '{}';
      IF v_st = 'Disponível' THEN
        v_disp := true;
        v_pub  := CASE WHEN p_desfazer AND m.antes ? 'publicado_no_site' AND m.antes->>'publicado_no_site' IS NOT NULL
                       THEN (m.antes->>'publicado_no_site')::boolean
                       ELSE EXISTS (SELECT 1 FROM imovel_fotos f WHERE f.codigo = m.codigo) END;
      ELSIF v_st IS NULL AND p_desfazer THEN
        v_disp := coalesce((m.antes->>'disponivel')::boolean, false);
        v_pub  := coalesce((m.antes->>'publicado_no_site')::boolean, false);
      ELSE
        v_disp := false; v_pub := false;
      END IF;
      UPDATE imoveis SET status = v_st, disponivel = v_disp, publicado_no_site = v_pub WHERE codigo = m.codigo;
      v_tocou := true;
    ELSIF k IN ('valor_aluguel', 'valor_venda') THEN
      IF (CASE k WHEN 'valor_aluguel' THEN i.valor_aluguel ELSE i.valor_venda END) IS DISTINCT FROM (v_esp #>> '{}')::numeric THEN
        v_pulado := array_append(v_pulado, format('%s (agora está %s)', v_nome,
                      coalesce((CASE k WHEN 'valor_aluguel' THEN i.valor_aluguel ELSE i.valor_venda END)::text, 'vazio'))); CONTINUE;
      END IF;
      EXECUTE format('UPDATE imoveis SET %I = $1 WHERE codigo = $2', k) USING (v_alvo #>> '{}')::numeric, m.codigo;
      v_tocou := true;
    ELSIF k = 'publicado_no_site' THEN
      IF i.publicado_no_site IS DISTINCT FROM (v_esp #>> '{}')::boolean THEN
        v_pulado := array_append(v_pulado, v_nome || ' (já foi mudado depois)'); CONTINUE;
      END IF;
      UPDATE imoveis SET publicado_no_site = (v_alvo #>> '{}')::boolean WHERE codigo = m.codigo;
      v_tocou := true;
    ELSIF k = 'vencimento' THEN
      SELECT max(c.vencimento) INTO v_venc FROM contratos_locacao c WHERE c.codigo = m.codigo::text;
      IF v_venc IS DISTINCT FROM (v_esp #>> '{}')::date THEN
        v_pulado := array_append(v_pulado, format('%s (agora está %s)', v_nome, coalesce(to_char(v_venc, 'DD/MM/YYYY'), 'vazio'))); CONTINUE;
      END IF;
      -- nada se apaga: o contrato que a captação criou fica, só sem a data
      UPDATE contratos_locacao SET vencimento = (v_alvo #>> '{}')::date WHERE codigo = m.codigo::text;
    ELSE
      CONTINUE;
    END IF;
    v_feito := array_append(v_feito, k);
  END LOOP;

  IF v_feito = '{}' THEN
    RETURN jsonb_build_object('ok', false, 'feito', '[]'::jsonb, 'pulado', to_jsonb(v_pulado),
                              'erro', 'nada voltou: o cadastro já foi mudado depois desta mudança');
  END IF;
  IF v_tocou THEN
    -- a trava segura a decisão: nem a raspagem do site antigo nem a mesma resposta do dono refazem por cima
    UPDATE imoveis SET travado = true, travado_em = now(),
           travado_motivo = CASE WHEN p_desfazer THEN format('voltei atrás em %s (%s) na mudança que a captação fez', v_dia, v_quem)
                                 ELSE format('captação: mudança refeita em %s (%s)', v_dia, v_quem) END
     WHERE codigo = m.codigo;
  END IF;
  UPDATE privado.imovel_mudanca
     SET desfeito_em = CASE WHEN p_desfazer THEN now() END,
         desfeito_por = CASE WHEN p_desfazer THEN v_quem END,
         desfeito_campos = CASE WHEN p_desfazer THEN v_feito END
   WHERE id = m.id;
  RETURN jsonb_build_object('ok', true, 'feito', to_jsonb(v_feito), 'pulado', to_jsonb(v_pulado));
END
$function$;
