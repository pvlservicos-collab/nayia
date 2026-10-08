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
  v_data   date;
  v_venc   date;
  v_linhas int;
  v_mudou  jsonb := '{}'::jsonb;
  v_conf   text[] := '{}';
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

    -- 1. A SITUAÇÃO
    IF i.status IS DISTINCT FROM v_para THEN
      IF i.status IN ('Rascunho', 'Em revisão', 'Revisão', 'Excluído') THEN
        v_conf := array_append(v_conf, format('o dono disse %s, mas o cadastro está como %s: não mexi', l.situacao, i.status));
      ELSIF i.travado AND i.travado_em > v_dito AND coalesce(i.travado_motivo, '') NOT LIKE 'captação%' THEN
        v_conf := array_append(v_conf, format('o dono disse %s em %s, mas a situação (%s) foi mudada à mão depois, em %s: não mexi',
                                   l.situacao, v_dia, coalesce(i.status, 'sem situação'),
                                   to_char(i.travado_em AT TIME ZONE 'America/Manaus', 'DD/MM')));
      ELSIF l.situacao = 'alugado' AND i.status = 'Disponível' AND coalesce(i.valor_venda, 0) > 0 THEN
        v_conf := array_append(v_conf, 'o dono disse alugado, mas o imóvel está anunciado para VENDA: decidir se o anúncio de venda continua');
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
        SELECT max(c.vencimento), count(*) INTO v_venc, v_linhas FROM contratos_locacao c WHERE c.codigo = l.codigo;
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

    -- 4. QUER VENDER: preço e condição são conversa de gente
    IF coalesce(l.quer_vender, false) AND captacao_numero(l.valor_venda_pedido) IS DISTINCT FROM i.valor_venda THEN
      v_conf := array_append(v_conf, format('o dono quer vender (disse "%s"; no cadastro a venda está %s): decidir com ele',
                                 left(coalesce(l.valor_venda_pedido, 'sem valor'), 80), coalesce(i.valor_venda::text, 'sem valor')));
    END IF;
  END IF;

  INSERT INTO captacao_aplicado (lead_id, codigo, situacao, valor_dito, contrato_dito, mudou, conferir)
  VALUES (l.id, v_cod, l.situacao, l.valor_locacao_pedido, l.contrato_ate, v_mudou, v_conf);
  RETURN jsonb_build_object('lead', l.id, 'codigo', v_cod, 'mudou', v_mudou, 'conferir', to_jsonb(v_conf));
END
$function$;
