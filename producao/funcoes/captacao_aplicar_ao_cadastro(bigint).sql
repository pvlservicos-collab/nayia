CREATE OR REPLACE FUNCTION public.captacao_aplicar_ao_cadastro(p_lead bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
 SET lock_timeout TO '3s'
AS $function$
DECLARE
  l        captacao_leads;
  i        imoveis;
  v_cod    int;
  v_dito   timestamptz;
  v_dia    text;
  v_para   text;
  v_trava  text;
  v_fotos  int;
  v_valor  numeric;
  v_vv     numeric;
  v_hon    text;
  v_data   date;
  v_venc   date;
  v_linhas int;
  v_a_mao  boolean := false;
  v_mudou  jsonb := '{}'::jsonb;
  v_antes  jsonb := '{}'::jsonb;
  v_conf   text[] := '{}';
  v_apl    bigint;
BEGIN
  SELECT * INTO l FROM captacao_leads WHERE id = p_lead;
  IF l.id IS NULL OR l.situacao IS NULL THEN RETURN NULL; END IF;
  IF coalesce(l.codigo, '') ~ '^\d{1,9}$' THEN
    v_cod := l.codigo::int;
    SELECT * INTO i FROM imoveis WHERE codigo = v_cod FOR UPDATE;
  END IF;

  IF i.codigo IS NULL THEN
    v_conf := array_append(v_conf, 'o imóvel do lead não está no cadastro: nada para atualizar');
  ELSIF coalesce(i.e_parceiro, false) THEN
    v_conf := array_append(v_conf, 'imóvel de parceiro: não mexi');
  ELSE
    SELECT coalesce(max(m.criada_em), l.atualizado_em) INTO v_dito
      FROM captacao_mensagens m WHERE m.lead_id = l.id AND m.direcao = 'recebida';
    v_dia   := to_char(v_dito AT TIME ZONE 'America/Manaus', 'DD/MM');
    v_para  := CASE l.situacao WHEN 'vendido' THEN 'Vendido' WHEN 'alugado' THEN 'Alugado' WHEN 'disponivel' THEN 'Disponível' END;
    v_trava := 'captação: o dono disse ' || lower(v_para) || ' em ' || v_dia;
    SELECT count(*) INTO v_fotos FROM imovel_fotos WHERE codigo = v_cod;
    SELECT max(c.vencimento), count(*) INTO v_venc, v_linhas FROM contratos_locacao c WHERE c.codigo = l.codigo;
    -- alguém mudou o cadastro à mão DEPOIS do que o dono disse: a mão vale mais
    v_a_mao := i.travado AND i.travado_em > v_dito AND coalesce(i.travado_motivo, '') NOT LIKE 'captação%';
    -- 361: o retrato de antes, para o voltar atrás
    v_antes := jsonb_build_object('status', i.status, 'disponivel', i.disponivel, 'publicado_no_site', i.publicado_no_site,
                                  'travado', i.travado, 'travado_motivo', i.travado_motivo, 'travado_em', i.travado_em,
                                  'valor_aluguel', i.valor_aluguel, 'valor_venda', i.valor_venda, 'vencimento', v_venc);

    -- 1. A SITUAÇÃO
    IF i.status IS DISTINCT FROM v_para THEN
      IF i.status IN ('Rascunho', 'Em revisão', 'Revisão', 'Excluído') THEN
        v_conf := array_append(v_conf, format('o dono disse %s, mas o cadastro está como %s: não mexi', l.situacao, i.status));
      ELSIF v_a_mao THEN
        v_conf := array_append(v_conf, format('o dono disse %s em %s, mas a situação (%s) foi mudada à mão depois, em %s: não mexi',
                                   l.situacao, v_dia, coalesce(i.status, 'sem situação'),
                                   to_char(i.travado_em AT TIME ZONE 'America/Manaus', 'DD/MM')));
      ELSIF l.situacao = 'disponivel' AND coalesce(i.bloqueado, false) THEN
        v_conf := array_append(v_conf, format('o dono disse disponível, mas o imóvel está bloqueado (%s): não mexi',
                                   coalesce(i.motivo_bloqueio, 'sem motivo anotado')));
      ELSIF l.situacao = 'disponivel' THEN
        UPDATE imoveis SET status = 'Disponível', disponivel = true, publicado_no_site = (v_fotos > 0),
               travado = true, travado_motivo = v_trava, travado_em = now()
         WHERE codigo = v_cod;
        v_mudou := v_mudou || jsonb_build_object('status', jsonb_build_object('de', i.status, 'para', 'Disponível'));
        IF v_fotos = 0 THEN
          v_conf := array_append(v_conf, 'ficou Disponível mas FORA do site: o imóvel não tem foto (entra no site quando a foto chegar)');
        END IF;
      ELSE
        UPDATE imoveis SET status = v_para, travado = true, travado_motivo = v_trava, travado_em = now()
         WHERE codigo = v_cod;
        v_mudou := v_mudou || jsonb_build_object('status', jsonb_build_object('de', i.status, 'para', v_para));
        -- 361: antes isto ficava parado esperando gente; agora entra e a tela tem o voltar atrás
        IF l.situacao = 'alugado' AND i.status = 'Disponível' AND coalesce(i.valor_venda, 0) > 0 THEN
          v_conf := array_append(v_conf, format('estava anunciado para VENDA por R$ %s: se a venda continua, volte atrás',
                                     replace(to_char(i.valor_venda, 'FM999,999,999'), ',', '.')));
        END IF;
      END IF;
    END IF;

    -- 2. O VALOR DO ALUGUEL (só de quem disse disponível, e só quando ele deu UM número)
    IF l.situacao = 'disponivel' AND nullif(btrim(l.valor_locacao_pedido), '') IS NOT NULL
       AND (SELECT status FROM imoveis WHERE codigo = v_cod) = 'Disponível' THEN
      IF (SELECT count(*) FROM regexp_matches(l.valor_locacao_pedido, '\d[\d.,]*', 'g')) = 1 THEN
        v_valor := captacao_numero(l.valor_locacao_pedido);
        IF v_valor BETWEEN 300 AND 200000 AND v_valor IS DISTINCT FROM i.valor_aluguel THEN
          UPDATE imoveis SET valor_aluguel = v_valor WHERE codigo = v_cod;
          v_mudou := v_mudou || jsonb_build_object('valor_aluguel', jsonb_build_object('de', i.valor_aluguel, 'para', v_valor));
        END IF;
      ELSE
        v_conf := array_append(v_conf, format('valor dito com mais de um número: "%s"', left(l.valor_locacao_pedido, 120)));
      END IF;
    END IF;

    -- 3. O FIM DO CONTRATO (de quem disse alugado)
    IF l.situacao = 'alugado' AND nullif(btrim(l.contrato_ate), '') IS NOT NULL THEN
      v_data := captacao_data_do_contrato(l.contrato_ate, (v_dito AT TIME ZONE 'America/Manaus')::date);
      IF v_data IS NULL THEN
        v_conf := array_append(v_conf, format('fim do contrato dito de um jeito que não vira data: "%s"', left(l.contrato_ate, 120)));
      ELSE
        IF v_linhas = 0 THEN
          INSERT INTO contratos_locacao (codigo, vencimento) VALUES (l.codigo, v_data);
          v_mudou := v_mudou || jsonb_build_object('vencimento', jsonb_build_object('de', NULL, 'para', v_data));
        ELSIF v_venc IS NULL OR to_char(v_venc, 'YYYY-MM') <> to_char(v_data, 'YYYY-MM') THEN
          -- o mesmo mês e ano já está lá com o dia certo: o que o site sabe é mais preciso, fica
          UPDATE contratos_locacao SET vencimento = v_data WHERE codigo = l.codigo;
          v_mudou := v_mudou || jsonb_build_object('vencimento', jsonb_build_object('de', v_venc, 'para', v_data));
        END IF;
      END IF;
    END IF;

    -- 4. O VALOR DE VENDA (361). Entra sozinho quando ele respondeu a pergunta dos 6%: incluso = o número dele;
    --    líquido = o número dele + 6% (é como o cadastro guarda: 270 mil -> 286.200).
    IF nullif(btrim(l.valor_venda_pedido), '') IS NOT NULL AND l.situacao <> 'vendido'
       AND coalesce(i.status, '') NOT IN ('Rascunho', 'Em revisão', 'Revisão', 'Excluído', 'Vendido') THEN
      v_vv  := captacao_valor_venda_num(l.valor_venda_pedido);
      v_hon := captacao_honorarios_tipo(l.id);
      IF v_vv IS NULL OR v_vv < 10000 THEN
        v_conf := array_append(v_conf, format('valor de venda dito de um jeito que não vira número: "%s" (no cadastro: %s)',
                                   left(l.valor_venda_pedido, 80), coalesce(i.valor_venda::text, 'sem valor')));
      ELSIF coalesce(i.valor_venda, 0) > 0 AND v_vv NOT BETWEEN i.valor_venda * 0.5 AND i.valor_venda * 2 THEN
        v_conf := array_append(v_conf, format('valor de venda dito ("%s") muito longe do cadastro (%s): não mexi',
                                   left(l.valor_venda_pedido, 80), i.valor_venda::text));
      ELSIF v_a_mao THEN
        IF v_vv IS DISTINCT FROM i.valor_venda THEN
          v_conf := array_append(v_conf, format('o dono disse venda por "%s", mas o cadastro foi mudado à mão depois (venda em %s): não mexi',
                                     left(l.valor_venda_pedido, 80), coalesce(i.valor_venda::text, 'sem valor')));
        END IF;
      ELSIF v_hon IS NULL THEN
        IF v_vv IS DISTINCT FROM i.valor_venda THEN
          v_conf := array_append(v_conf, format('o dono disse venda por "%s" (no cadastro: %s), mas não disse se os 6%% já estão no valor: não mexi',
                                     left(l.valor_venda_pedido, 80), coalesce(i.valor_venda::text, 'sem valor')));
        END IF;
      ELSE
        IF v_hon = 'liquido' THEN v_vv := round(v_vv * 1.06); END IF;
        IF v_vv IS DISTINCT FROM i.valor_venda THEN
          UPDATE imoveis SET valor_venda = v_vv, travado = true, travado_em = now(),
                 travado_motivo = CASE WHEN travado AND travado_motivo LIKE 'captação%' AND travado_em > v_dito THEN travado_motivo
                                       ELSE 'captação: o dono disse o valor de venda em ' || v_dia END
           WHERE codigo = v_cod;
          v_mudou := v_mudou || jsonb_build_object('valor_venda', jsonb_build_object('de', i.valor_venda, 'para', v_vv));
          IF v_hon = 'liquido' THEN
            v_conf := array_append(v_conf, format('ele quer "%s" líquido: somei os 6%% de honorários', left(l.valor_venda_pedido, 80)));
          END IF;
        END IF;
      END IF;
    END IF;
  END IF;

  INSERT INTO captacao_aplicado (lead_id, codigo, situacao, valor_dito, contrato_dito, mudou, conferir)
  VALUES (l.id, v_cod, l.situacao, l.valor_locacao_pedido, l.contrato_ate, v_mudou, v_conf)
  RETURNING id INTO v_apl;
  -- 361: o histórico do imóvel (a tela Mudanças recentes e o "Última atualização" do editar leem daqui)
  IF i.codigo IS NOT NULL AND NOT coalesce(i.e_parceiro, false) THEN
    PERFORM imovel_mudanca_registrar(v_cod, l.id, v_apl, v_dito, v_mudou, v_antes, v_conf);
  END IF;
  RETURN jsonb_build_object('lead', l.id, 'codigo', v_cod, 'mudou', v_mudou, 'conferir', to_jsonb(v_conf));
END
$function$;
