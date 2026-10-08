CREATE OR REPLACE FUNCTION public.crm_anuncio_decidir(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET jit TO 'off'
AS $function$
DECLARE
  JANELA   CONSTANT interval := interval '10 minutes';
  FECHE    CONSTANT text := ' Feche o anúncio, não mande mensagem.';
  v_link   text := btrim(coalesce(p ->> 'link', ''));
  v_normal text := crm_anuncio_link_normal(p ->> 'link');
  v_portal text := left(lower(coalesce(nullif(btrim(p ->> 'portal'), ''), 'olx')), 30);
  v_id_an  text;
  v_teste  boolean := coalesce(p -> 'teste' = 'true'::jsonb OR lower(btrim(coalesce(p ->> 'teste', ''))) IN ('true', 'sim'), false);
  v_prof   boolean := coalesce(p -> 'profissional' = 'true'::jsonb OR lower(btrim(coalesce(p ->> 'profissional', ''))) IN ('true', 'sim'), false);
  v_fone   text := nai_chave(p ->> 'telefone');
  v_nome   text := nay_sem_acento(lower(coalesce(p ->> 'anunciante_nome', '')));
  v_texto  text := nay_sem_acento(lower(concat_ws(E'\n', p ->> 'titulo', p ->> 'descricao')));
  v_falta  text[] := '{}';
  v_dados  jsonb;
  v_ja     privado.anuncio_consulta;
  v_cand   jsonb;
  v_un     jsonb;
  v_acao   text := 'fechar';
  v_motivo text;
  v_expl   text;
  v_cod    integer;
  v_msg    text;
  v_linha  bigint;
  v_r      jsonb;
BEGIN
  IF p IS NULL OR jsonb_typeof(p) <> 'object' THEN
    RETURN jsonb_build_object('consulta_ok', false, 'ok', false, 'codigo_erro', 'formato',
                              'erro', 'Mande um objeto JSON com os campos do anúncio.');
  END IF;
  IF v_normal IS NULL OR v_normal !~ '^[a-z0-9.-]+\.[a-z]{2,}/' THEN
    RETURN jsonb_build_object('consulta_ok', false, 'ok', false, 'codigo_erro', 'faltam_campos', 'faltam', jsonb_build_array('link'),
                              'erro', 'Faltou o "link" do anúncio.');
  END IF;
  v_dados := p - 'hora' - 'cifrado' - 'assinatura' - 'teste';
  IF length(v_dados::text) > 60000 THEN
    RETURN jsonb_build_object('consulta_ok', false, 'ok', false, 'codigo_erro', 'grande_demais',
                              'erro', 'Os dados passaram de 60 mil caracteres: encurte a descrição.');
  END IF;
  v_id_an := coalesce(nullif(regexp_replace(coalesce(p ->> 'id_anuncio', ''), '\D', '', 'g'), ''), crm_anuncio_id_do_link(v_link));

  -- duas perguntas do mesmo anúncio ao mesmo tempo: uma espera a outra
  PERFORM pg_advisory_xact_lock(hashtext('anuncio_consulta:' || v_normal));
  SELECT * INTO v_ja FROM privado.anuncio_consulta c
   WHERE c.link_normal = v_normal OR (v_id_an IS NOT NULL AND c.portal = v_portal AND c.id_anuncio = v_id_an)
   ORDER BY (c.link_normal = v_normal) DESC, c.id LIMIT 1;

  -- A PAREDE: a mensagem deste anúncio já foi entregue
  IF v_ja.id IS NOT NULL AND v_ja.acao = 'abordar' THEN
    IF NOT v_teste THEN
      UPDATE privado.anuncio_consulta SET pedidos = pedidos + 1, atualizado_em = now() WHERE id = v_ja.id;
    END IF;
    IF v_ja.entregue_em > now() - JANELA THEN
      v_r := jsonb_build_object('consulta_ok', true, 'acao', 'abordar', 'temos', false, 'motivo', 'nao_temos',
        'repetido', true, 'id_consulta', v_ja.id::text, 'mensagem', v_ja.mensagem,
        'explicacao', 'É a mesma mensagem que entreguei há pouco para este anúncio. Mande UMA vez só, sem mudar o texto.');
    ELSE
      v_r := jsonb_build_object('consulta_ok', true, 'acao', 'fechar', 'temos', false, 'motivo', 'ja_abordado',
        'id_consulta', v_ja.id::text,
        'explicacao', 'A mensagem deste anúncio já foi entregue em '
                      || to_char(v_ja.entregue_em AT TIME ZONE 'America/Manaus', 'DD/MM "às" HH24:MI')
                      || '. Feche o anúncio, não mande de novo.');
    END IF;
    RETURN CASE WHEN v_teste THEN crm_anuncio_resposta_de_teste(v_r) ELSE v_r END;
  END IF;

  v_cand := crm_imovel_candidatos(p);
  IF coalesce((v_cand ->> 'consulta_ok')::boolean, false) IS NOT TRUE THEN
    RETURN jsonb_build_object('consulta_ok', false, 'ok', false, 'codigo_erro', 'falha',
                              'erro', coalesce(v_cand ->> 'erro', 'a busca no catálogo não respondeu'));
  END IF;
  v_un := crm_anuncio_mesma_unidade(p, v_cand);

  IF v_un IS NOT NULL THEN
    v_cod := (v_un ->> 'codigo')::int;
    v_motivo := 'ja_temos';
    v_expl := 'Já temos este imóvel no cadastro (código ' || v_cod || ').' || FECHE;
  ELSIF coalesce((v_cand -> 'entendido' ->> 'telefone_conhecido')::boolean, false) THEN
    v_motivo := 'proprietario_ja_e_nosso';
    v_expl := 'O telefone do anúncio já é de um proprietário do nosso cadastro.' || FECHE;
  ELSIF v_prof
     OR (v_fone IS NOT NULL AND EXISTS (SELECT 1 FROM corretores k WHERE nai_chave(k.telefone) = v_fone))
     OR v_texto ~ '\mcreci\M' OR v_nome ~ '\mcreci\M'
     OR v_nome ~ '(imob|imovel|imoveis|corretor|broker|realty|administradora|negocios imobiliarios)'
     OR nai_dono_e_parceiro(p ->> 'anunciante_nome') THEN
    v_motivo := 'corretor';
    v_expl := 'O anunciante é corretor ou imobiliária.' || FECHE;
  ELSIF v_texto ~ '(dispens[oa](mos)?|nao (aceito|aceitamos|atendo|atendemos|quero|queremos|trabalho com|trabalhamos com)|favor nao)[^.!?\n]{0,30}(corretor|imobiliaria|intermediari)'
     OR v_texto ~ '\msem (corretor|corretores|imobiliaria|imobiliarias|intermediario|intermediarios|intermediacao)\M' THEN
    v_motivo := 'dispensa_imobiliaria';
    v_expl := 'O anúncio diz que não quer corretor nem imobiliária.' || FECHE;
  ELSE
    -- NÃO TEMOS. Só aborda quem deu para comparar de verdade.
    IF crm_anuncio_numero(p -> 'preco') IS NULL THEN v_falta := array_append(v_falta, 'preco'); END IF;
    IF coalesce(crm_anuncio_familia(p ->> 'tipo'), crm_anuncio_familia(p ->> 'titulo')) IS NULL THEN
      v_falta := array_append(v_falta, 'tipo (ou titulo)');
    END IF;
    IF coalesce(btrim(p ->> 'bairro'), '') = '' AND coalesce(btrim(p ->> 'condominio_nome'), '') = '' THEN
      v_falta := array_append(v_falta, 'bairro (ou condominio_nome)');
    END IF;
    IF array_length(v_falta, 1) > 0 THEN
      RETURN jsonb_build_object('consulta_ok', false, 'ok', false, 'codigo_erro', 'faltam_campos', 'faltam', to_jsonb(v_falta),
        'erro', 'Não decidi: falta ' || array_to_string(v_falta, ', ') || '. Leia no anúncio e consulte de novo. Não mande mensagem sem a resposta.');
    END IF;
    v_msg := crm_anuncio_mensagem(p, v_cand -> 'entendido' ->> 'finalidade');
    IF v_msg IS NULL THEN
      RETURN jsonb_build_object('consulta_ok', false, 'ok', false, 'codigo_erro', 'texto',
        'erro', 'O texto da mensagem está com problema do nosso lado. Não mande nada e avise o Pedro no chat.');
    END IF;
    v_acao := 'abordar';
    v_motivo := 'nao_temos';
    v_expl := 'Não temos este imóvel. Mande ao anunciante exatamente o texto de "mensagem", sem mudar nada, uma vez só.';
  END IF;

  IF NOT v_teste THEN
    IF v_ja.id IS NOT NULL THEN
      UPDATE privado.anuncio_consulta c
         SET link = left(v_link, 600), id_anuncio = coalesce(v_id_an, c.id_anuncio),
             anunciante_nome = coalesce(left(nullif(btrim(p ->> 'anunciante_nome'), ''), 120), c.anunciante_nome),
             anunciante_perfil = coalesce(left(nullif(btrim(p ->> 'anunciante_perfil'), ''), 600), c.anunciante_perfil),
             telefone = coalesce(left(nullif(btrim(p ->> 'telefone'), ''), 40), c.telefone),
             dados = v_dados, acao = v_acao, motivo = v_motivo, codigo = v_cod,
             parecido = coalesce(v_un, (v_cand -> 'candidatos' -> 0) - 'dados' - 'campos_divergentes'),
             mensagem = v_msg, entregue_em = CASE WHEN v_acao = 'abordar' THEN now() END,
             pedidos = c.pedidos + 1, atualizado_em = now()
       WHERE c.id = v_ja.id
      RETURNING c.id INTO v_linha;
    ELSE
      INSERT INTO privado.anuncio_consulta (link, link_normal, portal, id_anuncio, anunciante_nome, anunciante_perfil, telefone,
                                            dados, acao, motivo, codigo, parecido, mensagem, entregue_em)
      VALUES (left(v_link, 600), v_normal, v_portal, v_id_an,
              left(nullif(btrim(p ->> 'anunciante_nome'), ''), 120), left(nullif(btrim(p ->> 'anunciante_perfil'), ''), 600),
              left(nullif(btrim(p ->> 'telefone'), ''), 40),
              v_dados, v_acao, v_motivo, v_cod,
              coalesce(v_un, (v_cand -> 'candidatos' -> 0) - 'dados' - 'campos_divergentes'),
              v_msg, CASE WHEN v_acao = 'abordar' THEN now() END)
      RETURNING id INTO v_linha;
    END IF;
  END IF;

  v_r := jsonb_strip_nulls(jsonb_build_object(
    'consulta_ok', true, 'acao', v_acao, 'temos', v_motivo = 'ja_temos', 'motivo', v_motivo, 'explicacao', v_expl,
    'id_imovel', v_cod::text, 'mensagem', v_msg, 'id_consulta', v_linha::text));
  RETURN CASE WHEN v_teste THEN crm_anuncio_resposta_de_teste(v_r) ELSE v_r END;
EXCEPTION WHEN others THEN
  -- nunca resposta vazia nem "abordar" por engano: falha é falha
  RETURN jsonb_build_object('consulta_ok', false, 'ok', false, 'codigo_erro', 'falha', 'erro', 'falha na consulta: ' || SQLERRM);
END
$function$;
