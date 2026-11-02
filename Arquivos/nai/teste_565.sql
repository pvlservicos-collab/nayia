-- 565: o 9115 ganhou a Luci como proprietária nos dois lugares; um parceiro novo da busca ganha sozinho; a Luci não vira dona
DO $$
DECLARE v_p int; v_pp int; v_nome text; v_tel text; v_novo int;
BEGIN
  SELECT i.proprietario_id, ip.proprietario_id, p.nome, p.telefone INTO v_p, v_pp, v_nome, v_tel
    FROM imoveis i JOIN imovel_privado ip ON ip.codigo = i.codigo JOIN proprietarios p ON p.id = i.proprietario_id WHERE i.codigo = 9115;
  IF v_p IS NULL OR v_p <> v_pp THEN RAISE EXCEPTION '9115 sem proprietário (% / %)', v_p, v_pp; END IF;
  RAISE NOTICE '9115: % %', v_nome, v_tel;

  INSERT INTO imoveis (codigo, origem, status, disponivel, publicado_no_site, e_parceiro, tipo, extras)
  VALUES (nextval('imoveis_crm_codigo_seq'), 'busca', 'Rascunho', false, false, true, 'Apartamento',
          '{"corretor_parceiro": "Luci Ferreira | Corretora de Imóveis", "corretor_telefone": "559284162127"}')
  RETURNING codigo INTO v_novo;
  IF (SELECT proprietario_id FROM imoveis WHERE codigo = v_novo) IS DISTINCT FROM v_p THEN
    RAISE EXCEPTION 'o novo não ligou à mesma Luci';
  END IF;
  IF nai_e_proprietario_contato((SELECT id FROM nai_contato WHERE chave = nai_chave('559284162127') LIMIT 1)) THEN
    RAISE EXCEPTION 'a Luci virou proprietária para a Nay';
  END IF;
  RAISE NOTICE 'sem proprietário ainda (busca): %',
    (SELECT string_agg(codigo::text, ', ') FROM imoveis WHERE origem = 'busca' AND proprietario_id IS NULL AND status <> 'Excluído');
END $$;
