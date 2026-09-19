-- =====================================================================
-- NAI -- 51: "esse ta no grupo?" e a midia sem vacuo (Tel, 16/09/2026)
--
-- Ele: "revisa as leituras, reorganiza e decide tudo ai baseado no que eu ja
-- pedi, implementa tudo". Sao as duas decisoes que estavam comigo.
--
-- 1. "ESSE TA NO GRUPO DA EASY?"
--    Foi o que travou o corretor Leonan as 04:21: ele encaminhou o card do
--    Acquarelle no privado, perguntou isso, e ela escalou ao Tel -- a conversa
--    parou ali. Mas a resposta sempre esteve em `envios`, que guarda tudo o
--    que foi disparado nos grupos, com a hora. Agora ela responde: "Mandei
--    sim, no grupo hoje as 04:00" ou "Esse eu ainda nao mandei no grupo".
--
-- 2. MIDIA QUE ELA NAO CONSEGUIU LER
--    O escalar normal cala, e esta certo: ali ela nao sabe a resposta e nao
--    promete nada. Para midia eu decidi diferente, pelo que ele ja pediu:
--    "teve um que mandou boa noite e ela n respondeu" (15/09) e "cordialidade,
--    educacao e delicadeza" (16/09). O corretor que mandou treze fotos fica
--    olhando para a tela.
--
--    Ela manda UMA linha -- "Recebi, Sr. Ribamar! Ja te respondo por aqui." --
--    e o Tel assume. A frase nao diz que viu, nao diz que nao le, nao promete
--    prazo. E o aviso ao Tel passa a dizer o que ela falou, para ele nao
--    repetir nem contradizer.
--
-- Gerado por `scratchpad/patch51.py` a partir do que estava NO BANCO.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.nai_resposta_da_base(p_codigo integer, p_pergunta text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  i      imoveis;
  q      text := lower(unaccent(coalesce(p_pergunta, '')));
  car    text;
  des    text;
  dorig  text;
  r      text[] := '{}';   -- a resposta: o primeiro e a afirmacao, o resto vira lista
  linhas text[] := '{}';
  v_fr   text;
  v_inc  text;
  v_out  text;
  f_q    text;             -- a ficha, que sai listada depois da afirmacao
  f_b    text;
  f_v    text;
  f_a    text;
  f_an   text;
  busca  text[] := ARRAY['piscina', 'academia', 'elevador', 'portaria', 'churrasqueira', 'salao de festa', 'playground',
                         'varanda', 'sacada', 'gourmet', 'ar-condicionado', 'ar condicionado', 'area de lazer', 'quadra',
                         'sauna', 'quintal', 'jardim', 'interfone', 'cerca eletrica', 'seguranca 24'];
  exibe  text[] := ARRAY['piscina', 'academia', 'elevador', 'portaria', 'churrasqueira', 'salão de festas', 'playground',
                         'varanda', 'sacada', 'espaço gourmet', 'ar-condicionado', 'ar-condicionado', 'área de lazer', 'quadra',
                         'sauna', 'quintal', 'jardim', 'interfone', 'cerca elétrica', 'segurança 24h'];
  n      int;
BEGIN
  IF p_codigo IS NULL OR btrim(q) = '' THEN RETURN NULL; END IF;
  SELECT * INTO i FROM imoveis WHERE codigo = p_codigo;
  IF i.codigo IS NULL OR coalesce(i.e_parceiro, false) THEN RETURN NULL; END IF;
  car   := lower(unaccent(coalesce(array_to_string(i.caracteristicas, ', '), '') || ', ' || coalesce(i.extras->>'caracteristicas', '')));
  dorig := coalesce(nay_descricao_segura(i.descricao), '');
  des   := lower(unaccent(dorig));
  v_inc := lower(unaccent(coalesce(i.extras->>'incluso no aluguel', '')));

  -- A ficha basica, escrita uma vez: serve de resposta quando ele pergunta
  -- isso, e de lista depois da afirmacao quando ele pergunta outra coisa.
  f_q := CASE WHEN coalesce(i.quartos, 0) > 0 THEN
           'tem ' || i.quartos || CASE WHEN i.quartos = 1 THEN ' quarto' ELSE ' quartos' END ||
           CASE WHEN coalesce(i.suites, 0) > 0 THEN ', sendo ' || i.suites || CASE WHEN i.suites = 1 THEN ' suíte' ELSE ' suítes' END ELSE '' END END;
  f_b := CASE WHEN coalesce(i.banheiros, 0) > 0 THEN
           'tem ' || i.banheiros || CASE WHEN i.banheiros = 1 THEN ' banheiro' ELSE ' banheiros' END END;
  -- VAGAS: NULL em vagas_cobertas e "nao sei", nao "nenhuma" -- mesma regra do card.
  f_v := CASE
           WHEN coalesce(i.vagas, 0) = 0 AND coalesce(i.vagas_cobertas, 0) > 0
             THEN 'tem ' || i.vagas_cobertas || CASE WHEN i.vagas_cobertas = 1 THEN ' vaga coberta' ELSE ' vagas cobertas' END
           WHEN coalesce(i.vagas, 0) = 0 THEN NULL
           WHEN i.vagas_cobertas IS NULL THEN 'tem ' || i.vagas || CASE WHEN i.vagas = 1 THEN ' vaga de garagem' ELSE ' vagas de garagem' END
           WHEN i.vagas_cobertas = 0 THEN 'tem ' || i.vagas || CASE WHEN i.vagas = 1 THEN ' vaga descoberta' ELSE ' vagas descobertas' END
           WHEN i.vagas_cobertas >= i.vagas THEN 'tem ' || i.vagas || CASE WHEN i.vagas = 1 THEN ' vaga coberta' ELSE ' vagas cobertas' END
           ELSE 'tem ' || i.vagas || ' vagas, sendo ' || i.vagas_cobertas || CASE WHEN i.vagas_cobertas = 1 THEN ' coberta' ELSE ' cobertas' END END;
  f_a := CASE WHEN coalesce(i.area_util, 0) > 0 THEN 'tem ' || trim(to_char(i.area_util, 'FM999990')) || ' m²' END;
  f_an := CASE WHEN coalesce(i.andar, '') <> '' THEN
            CASE WHEN i.andar ~ '^\d+$' THEN 'fica no ' || i.andar || 'º andar' ELSE 'fica no andar ' || i.andar END END;

  -- FOI PARA O GRUPO? (Tel, 16/09). O corretor Leonan encaminhou o card do
  -- Acquarelle no privado e perguntou "Nay, esse ta no grupo da EASY?". Ela
  -- escalou ao Tel e a conversa parou -- mas a resposta esta em `envios`: e
  -- dali que sai tudo o que foi disparado nos grupos, com a hora.
  DECLARE v_grp timestamptz;
  BEGIN
    IF q ~ '\mgrupo|grupos\M' THEN
      SELECT max(e.enviado_em) INTO v_grp FROM envios e
       WHERE e.destino = 'grupo' AND e.codigo = p_codigo::text;
      IF v_grp IS NULL THEN
        RETURN 'Esse eu ainda não mandei no grupo.';
      END IF;
      RETURN 'Mandei sim, no grupo '
             || CASE
                  WHEN (v_grp AT TIME ZONE 'America/Manaus')::date
                       = (now() AT TIME ZONE 'America/Manaus')::date
                    THEN 'hoje às ' || to_char(v_grp AT TIME ZONE 'America/Manaus', 'HH24:MI')
                  WHEN (v_grp AT TIME ZONE 'America/Manaus')::date
                       = (now() AT TIME ZONE 'America/Manaus')::date - 1
                    THEN 'ontem às ' || to_char(v_grp AT TIME ZONE 'America/Manaus', 'HH24:MI')
                  ELSE 'dia ' || to_char(v_grp AT TIME ZONE 'America/Manaus', 'DD/MM')
                END
             || '.';
    END IF;
  END;

  -- MOBILIA ("e mobiliado?", "vem com moveis?", "tem armario planejado?", "e vazio?").
  -- Duas partes: a afirmacao e o detalhe, que vira a primeira linha da lista.
  IF q ~ '(mobil|\mmovel|moveis|semi.?mob|\mvazio|equipad|planejad|armario|guarda.?roupa|geladeira|fogao|\mcama\M)' THEN
    IF lower(coalesce(i.mobilia, '')) ~ '^semi' THEN
      r := r || 'é semi-mobiliado'::text || 'tem móveis planejados e ar-condicionado'::text;
    ELSIF lower(coalesce(i.mobilia, '')) ~ '^mobiliad' THEN
      r := r || 'é mobiliado'::text || 'tem móveis, cama e tudo'::text;
    ELSIF lower(coalesce(i.mobilia, '')) ~ 'ar.condicionado' THEN
      r := r || 'não é mobiliado'::text || 'tem só o ar-condicionado'::text;
    ELSIF car ~ 'semi.?mobiliad' THEN
      r := r || 'é semi-mobiliado'::text;
    ELSIF car ~ '(sem mobilia|nao mobiliad)' THEN
      r := r || 'não é mobiliado'::text;
    ELSIF car ~ 'mobiliad' THEN
      r := r || 'é mobiliado'::text;
    END IF;
  END IF;

  IF q ~ '(quarto|dormitorio|suite)' AND f_q IS NOT NULL THEN r := r || f_q; END IF;
  IF q ~ '(banheiro|\mwc\M|lavabo|sanitario)' AND f_b IS NOT NULL THEN r := r || f_b; END IF;
  IF q ~ '(\mvaga|garagem|estacionamento|\mcarro)' AND f_v IS NOT NULL THEN r := r || f_v; END IF;
  IF q ~ '(\marea\M|metragem|tamanho|\mm2\M|\mmetros|metro quadrado)' AND f_a IS NOT NULL THEN r := r || f_a; END IF;
  IF q ~ '(\mandar|pavimento)' AND f_an IS NOT NULL THEN r := r || f_an; END IF;

  -- SOL
  IF q ~ '(\msol\M|nascente|poente|posicao do sol|lado do sol)' AND coalesce(i.sol, '') <> '' THEN
    r := r || ('é ' || lower(i.sol));
  END IF;

  -- NOME DO CONDOMINIO
  IF q ~ '(qual|nome).{0,15}(condominio|predio|residencial|edificio)' AND q !~ '(taxa|valor|\mquanto\M|preco|custa)'
     AND coalesce(nai_condominio_ok(i.condominio_nome), '') <> '' THEN
    r := r || ('fica no ' || nai_condominio_ok(i.condominio_nome));
  -- TAXA DE CONDOMINIO
  ELSIF q ~ '(taxa|condominio)' AND q ~ '(taxa|valor|\mquanto\M|preco|custa|inclus|\mpaga)' THEN
    IF v_inc ~ 'condom' THEN
      r := r || 'a taxa de condomínio já está inclusa no aluguel'::text;
    ELSIF coalesce(i.taxa_condominio, 0) > 0 THEN
      r := r || ('a taxa de condomínio é R$ ' || replace(to_char(i.taxa_condominio, 'FM999,999,990'), ',', '.'));
    END IF;
  END IF;

  -- IPTU
  IF q ~ 'iptu' THEN
    IF v_inc ~ 'iptu' THEN
      r := r || 'o IPTU já está incluso no aluguel'::text;
    ELSIF coalesce(i.iptu, 0) > 0 THEN
      r := r || ('o IPTU é R$ ' || replace(to_char(i.iptu, 'FM999,999,990'), ',', '.'));
    END IF;
  END IF;

  -- VALOR (aluguel / venda)
  IF q ~ '(valor|preco|\mquanto\M|aluguel|custa|mensal)' AND q !~ '(condominio|iptu|taxa)' THEN
    IF q ~ '(venda|vender|compra)' AND coalesce(i.valor_venda, 0) > 0 THEN
      r := r || ('o valor de venda é R$ ' || replace(to_char(i.valor_venda, 'FM999,999,990'), ',', '.'));
    ELSIF coalesce(i.valor_aluguel, 0) > 0 THEN
      r := r || ('o aluguel é R$ ' || replace(to_char(i.valor_aluguel, 'FM999,999,990'), ',', '.') ||
                 CASE WHEN v_inc ~ 'condom' THEN ', já com a taxa de condomínio inclusa' ELSE '' END);
    END IF;
  END IF;

  -- DISPONIBILIDADE
  IF q ~ '(disponivel|disponibilidade|ainda (tem|esta|ta)|\mlivre|alugado|\mvago\M|ja alugou)' THEN
    r := r || CASE WHEN nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
                   THEN 'está disponível' ELSE 'não está mais disponível' END;
  END IF;

  -- ONDE FICA (nunca o numero do predio, da casa ou do apartamento)
  IF q ~ '(bairro|onde fica|localiza|endereco|\mrua\M|regiao|\mzona\M)' THEN
    v_fr := concat_ws(', ',
      CASE WHEN coalesce(nai_condominio_ok(i.condominio_nome), '') <> '' THEN 'no ' || nai_condominio_ok(i.condominio_nome) END,
      CASE WHEN coalesce(nay_endereco_sem_numero(i.logradouro), '') <> '' THEN 'na ' || nay_endereco_sem_numero(i.logradouro) END,
      CASE WHEN coalesce(i.bairro, '') <> '' THEN 'bairro ' || i.bairro END);
    IF coalesce(v_fr, '') <> '' THEN r := r || ('fica ' || v_fr); END IF;
  END IF;

  -- FINANCIAMENTO (venda)
  IF q ~ 'financ' AND coalesce(i.valor_venda, 0) > 0 THEN
    IF coalesce(i.extras->>'aceita financiamento', '') ~* '^s' THEN r := r || 'aceita financiamento'::text;
    ELSIF coalesce(i.extras->>'aceita financiamento', '') ~* '^n' THEN r := r || 'não aceita financiamento'::text; END IF;
  END IF;

  -- PET: so quando o anuncio fala (a frase dele, sem numero de unidade)
  IF q ~ '(\mpet|animal|animais|cachorro|\mgato|bicho|\mcao\M)' THEN
    v_fr := (regexp_match(dorig, '[^.!?\n]*(?:\mpet|animal|animais|cachorro|gato)[^.!?\n]*', 'i'))[1];
    IF coalesce(btrim(v_fr), '') <> '' THEN r := r || ('sobre pet, o anúncio diz: "' || btrim(v_fr) || '"'); END IF;
  END IF;

  -- LAZER / CARACTERISTICAS: so afirma o que o cadastro ou o anuncio dizem
  FOR n IN 1 .. array_length(busca, 1) LOOP
    IF position(busca[n] IN q) > 0 AND (position(busca[n] IN car) > 0 OR position(busca[n] IN des) > 0)
       AND NOT (('tem ' || exibe[n]) = ANY (r)) THEN
      r := r || ('tem ' || exibe[n]);
    END IF;
  END LOOP;

  IF coalesce(array_length(r, 1), 0) = 0 THEN RETURN NULL; END IF;

  -- A AFIRMACAO (Tel, 13/09): "Sim!" so quando a pergunta e de sim ou nao --
  -- "quantos quartos?" nao se responde com "Sim!". Resposta negativa fica sem
  -- o "Sim", ela mesma ja nega.
  v_out := nai_frase_maiuscula(r[1]);
  -- "Sim!" so quando a resposta e um sim inteiro. Em "e mobiliado?" com imovel
  -- SEMI-mobiliado, "Sim! E semi-mobiliado" engana o corretor: fica so a frase.
  IF q !~ '(qual|quais|quanto|quantos|quantas|onde|como)'
     AND r[1] !~ '^n[ãa]o' AND r[1] !~ '^é semi' THEN
    v_out := 'Sim! ' || v_out;
  END IF;

  -- A LISTA: o resto do que ele perguntou, e depois a ficha do imovel.
  FOR n IN 2 .. coalesce(array_length(r, 1), 1) LOOP
    linhas := linhas || nai_frase_maiuscula(r[n]);
  END LOOP;
  FOREACH v_fr IN ARRAY ARRAY[f_q, f_b, f_v, f_a, f_an] LOOP
    IF v_fr IS NOT NULL AND NOT (v_fr = ANY (r)) THEN linhas := linhas || nai_frase_maiuscula(v_fr); END IF;
  END LOOP;

  IF coalesce(array_length(linhas, 1), 0) = 0 THEN RETURN v_out; END IF;
  RETURN v_out || E'\n\n' || array_to_string(linhas, E'\n');
END;
$function$;

CREATE OR REPLACE FUNCTION public.nai_escalar(p_turno bigint, p_codigo text, p_assunto text, p_disse text)
 RETURNS TABLE(texto_pronto text)
 LANGUAGE plpgsql
AS $function$
DECLARE t nai_turno; k nai_contato; e record; v_nome text; v_cod text; v_base text;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;
  -- ANTES DE ESCALAR, A BASE (Tel, 13/09): "olá o imovel é mobiliado?" subiu ao
  -- Tel com a resposta na ficha. O codigo precisa ser dele (escrito, card que
  -- mandamos, ou o card que ele MARCOU neste turno) -- nunca da cabeca do modelo.
  v_cod := NULLIF(regexp_replace(coalesce(p_codigo, ''), '\D', '', 'g'), '');
  IF length(v_cod) BETWEEN 3 AND 5
     AND (coalesce(nay_codigo_confirmado(k.telefone, v_cod, 72), 'nao') <> 'nao'
          OR EXISTS (SELECT 1 FROM mensagens m WHERE m.id = ANY (coalesce(t.msg_ids, '{}'))
                      AND nay_imovel_da_citacao(m.citado_id) = v_cod)) THEN
    v_base := coalesce(nai_resposta_da_base(v_cod::int, p_disse), nai_resposta_da_base(v_cod::int, p_assunto));
    IF v_base IS NOT NULL THEN
      RETURN QUERY SELECT v_base;
      RETURN;
    END IF;
  END IF;
  -- PAREDE: BUSCA NAO SOBE AO TEL (Tel, 15/09). Instrucao no cabecalho o
  -- modelo pode ignorar -- e ignorou, no teste de 15/09, escalando "voce tem
  -- apartamento de 2 quartos?" em vez de procurar. Aqui a busca volta como a
  -- pergunta certa da sequencia, e o Tel nao recebe nada.
  DECLARE v_ped jsonb; r_perfil record;
  BEGIN
    v_ped := nai_pedido_de_perfil(coalesce(nullif(p_disse, ''), t.texto));
    IF (v_ped->>'e_pedido')::boolean THEN
      SELECT * INTO r_perfil FROM nai_buscar_por_perfil(
        p_turno, v_ped->>'bairro', v_ped->>'teto', v_ped->>'quartos', NULL);
      IF r_perfil.texto_pronto IS NOT NULL THEN
        RETURN QUERY SELECT r_perfil.texto_pronto;
        RETURN;
      END IF;
    END IF;
  END;

  PERFORM nai_usou_ferramenta(p_turno, 'escalar');
  v_nome := coalesce(k.nome_completo, k.nome_whatsapp, k.telefone);

  -- MIDIA VAI PARA O TEL (Tel, 16/09): "ela NUNCA deve falar que nao le
  -- imagem; se nao conseguir, manda a imagem ao Tel". O aviso padrao diria que
  -- ele "perguntou sobre o imovel: ''" -- com aspas vazias, porque nao veio
  -- texto nenhum. Quando o turno traz midia, o Tel recebe o recado certo: ele
  -- ve as fotos no proprio WhatsApp, na conversa daquela pessoa.
  DECLARE v_mid text;
  BEGIN
    v_mid := nai_midia_do_turno(p_turno);
    IF v_mid IS NOT NULL THEN
      PERFORM nai_avisar_tel(p_turno, NULL,
        'Tel, ' || v_nome || ' (' || nai_fone_fmt(k.telefone) || ') me mandou ' || v_mid ||
        CASE WHEN btrim(coalesce(nullif(p_disse, ''), t.texto, '')) <> ''
             THEN ' e escreveu: "' || left(coalesce(nullif(p_disse, ''), t.texto), 300) || '"'
             ELSE ', sem escrever nada junto' END ||
        '. Não abro imagem nem áudio: dá uma olhada aí na conversa dele?' ||
        E'\nFalei só que recebi e que já respondo. Parei de responder esse chat: quem segue é você. Para eu voltar: DEVOLVER '
        || nai_fone_fmt(k.telefone) || '.',
        'midia_para_o_tel');
      PERFORM nai_parar_chat(k.id, 'midia: ' || v_mid);
      -- UMA LINHA, E O TEL ASSUME (Tel, 16/09). O escalar normal cala, e esta
      -- certo: ali ela nao sabe a resposta e nao promete nada. Aqui e outra
      -- coisa -- o corretor acabou de mandar treze fotos e fica olhando para a
      -- tela. Calar depois disso e o mesmo "teve um que mandou boa noite e ela
      -- n respondeu" de que ele reclamou em 15/09.
      --
      -- A frase nao diz que viu, nao diz que nao consegue abrir, e nao promete
      -- prazo: diz que chegou e que a resposta vem. Quem responde e o Tel, que
      -- ja recebeu o aviso acima.
      RETURN QUERY SELECT ('Recebi'
        || coalesce(', ' || nai_vocativo(coalesce(k.nome_completo, k.nome_whatsapp)), '')
        || '! Já te respondo por aqui.')::text;
      RETURN;
    END IF;
  END;
  SELECT * INTO e FROM nay_escalar(k.telefone, v_nome, p_codigo, p_assunto, p_disse);
  IF e.acao IN ('escalar', 'esperar') THEN
    v_cod := NULLIF(regexp_replace(coalesce(p_codigo, ''), '\D', '', 'g'), '');
    PERFORM nai_avisar_tel(p_turno, NULL,
      'Tel, o corretor ' || v_nome || ' (' || nai_fone_fmt(k.telefone) || ') perguntou sobre o ' ||
      coalesce(CASE WHEN length(v_cod) BETWEEN 3 AND 5 THEN nai_ref_imovel(v_cod::int) END, 'imóvel') || ': "' ||
      left(coalesce(nullif(p_disse, ''), p_assunto, ''), 300) || '". Não achei na base, você sabe?' ||
      E'\nNão falei nada com ele e parei de responder esse chat: quem responde é você. Para eu voltar: DEVOLVER ' || nai_fone_fmt(k.telefone) || '.',
      'duvida_fora_da_base');
    PERFORM nai_parar_chat(k.id, 'duvida fora da base: ' || coalesce(p_assunto, ''));
    RETURN QUERY SELECT 'SILENCIO'::text;
    RETURN;
  END IF;
  RETURN QUERY SELECT e.texto_pronto;
END;
$function$;
