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
  v_fin  text;   -- 191: a ficha do anuncio
  v_per  text;
  v_gar  text;
  v_esc  text;
  v_tx   text;
BEGIN
  IF p_codigo IS NULL OR btrim(q) = '' THEN RETURN NULL; END IF;
  SELECT * INTO i FROM imoveis WHERE codigo = p_codigo;
  IF i.codigo IS NULL OR coalesce(i.e_parceiro, false) THEN RETURN NULL; END IF;
  -- 191: a FICHA DO ANUNCIO entra aqui -- caracteristicas do imovel e do
  -- condominio, descricao e observacoes (sem numero de unidade). Antes era so
  -- o banco, e 117 dos 260 imoveis no ar nao tinham descricao nenhuma.
  car   := lower(unaccent(array_to_string(nai_ficha_caracteristicas(p_codigo), ', ')));
  dorig := coalesce(nai_ficha_texto_livre(p_codigo), '');
  des   := lower(unaccent(dorig));
  v_inc := lower(unaccent(coalesce(nai_ficha_valor(p_codigo, 'incluso no aluguel'), '')));  -- 191

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
  -- 295 (Pedro, 05/10): sem elevador, o andar é dito em lances de escada ("fica 3 andar troca por são 3
  -- lances de escada"); e "0 lances" não existe ("como tem 0 lances se é 3 andar").
  v_esc := nullif(regexp_replace(coalesce(nai_ficha_valor(p_codigo, 'lances de escada'), ''), '\D', '', 'g'), '');
  IF v_esc ~ '^0+$' THEN v_esc := NULL; END IF;
  IF v_esc IS NULL AND i.andar ~ '^[1-4]$' AND nai_imovel_tem_elevador(p_codigo) IS FALSE THEN v_esc := i.andar; END IF;
  f_an := CASE WHEN v_esc IS NOT NULL AND nai_imovel_tem_elevador(p_codigo) IS NOT TRUE THEN
            CASE WHEN v_esc = '1' THEN 'é 1 lance de escada' ELSE 'são ' || v_esc || ' lances de escada' END
          WHEN coalesce(i.andar, '') <> '' THEN
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
    IF nay_mobilia_nivel(i.mobilia) = 'semi' THEN
      r := r || 'é com modulados e ar'::text || 'tem móveis planejados e ar-condicionado'::text;
    ELSIF nay_mobilia_nivel(i.mobilia) = 'mobiliado' THEN
      r := r || 'é mobiliado'::text || 'tem móveis, cama e tudo'::text;
    ELSIF nay_mobilia_nivel(i.mobilia) = 'climatizado' THEN
      r := r || 'não é mobiliado'::text || 'tem só o ar-condicionado'::text;
    ELSIF nay_mobilia_nivel(i.mobilia) = 'nada' THEN
      r := r || 'não é mobiliado'::text || nay_mobilia_detalhe('nada')::text;
    ELSIF car ~ 'semi.?mobiliad' THEN
      r := r || 'é ' || nay_mobilia_rotulo('semi')::text;
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
  -- ANDAR DA UNIDADE x ANDARES DO PREDIO x TORRES (12/10, Tel): "se alguem
  -- perguntar andar, a nay vai em condominios e vai estar la pq se tem andar
  -- e porque e condominio de apartamentos". Sao perguntas diferentes, de
  -- lugares diferentes -- e `\mandar` sem `\M` casava "andares", entao quem
  -- perguntava os andares do predio recebia o andar do apartamento.
  DECLARE v_cond text;
  BEGIN
    IF q ~ '\mandares\M' THEN
      v_cond := nai_resposta_do_condominio(p_codigo, 'andares_predio');
      IF v_cond IS NOT NULL THEN r := r || v_cond; END IF;
    -- "quantos apartamentos POR ANDAR?" tem "andar" e nao e pergunta de andar:
    -- sem este `!~`, ela respondia o andar da unidade E os aptos por andar na
    -- mesma mensagem, uma contradizendo a outra (visto no ensaio).
    ELSIF q ~ '(\mandar\M|pavimento)' AND q !~ 'por andar' THEN
      IF f_an IS NOT NULL THEN
        r := r || f_an;
      ELSE
        v_cond := nai_resposta_do_condominio(p_codigo, 'andar');
        IF v_cond IS NOT NULL THEN r := r || v_cond; END IF;
      END IF;
    END IF;
    IF q ~ '\mtorres?\M' THEN
      v_cond := nai_resposta_do_condominio(p_codigo, 'torres');
      IF v_cond IS NOT NULL THEN r := r || v_cond; END IF;
    END IF;
    IF q ~ '(por andar|apartamentos? por|aptos? por|unidades? por)' THEN
      v_cond := nai_resposta_do_condominio(p_codigo, 'aptos_por_andar');
      IF v_cond IS NOT NULL THEN r := r || v_cond; END IF;
    END IF;
  END;

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
    ELSIF nai_ficha_valor(p_codigo, 'taxa de condominio') ~ '\d' THEN  -- 191
      v_tx := regexp_replace(regexp_replace(nai_ficha_valor(p_codigo, 'taxa de condominio'), '\s+', ' ', 'g'), ',00$', '');
      r := r || ('a taxa de condomínio é ' || v_tx);
    END IF;
  END IF;

  -- IPTU
  IF q ~ 'iptu' THEN
    IF v_inc ~ 'iptu' THEN
      r := r || 'o IPTU já está incluso no aluguel'::text;
    ELSIF coalesce(i.iptu, 0) > 0 THEN
      r := r || ('o IPTU é R$ ' || replace(to_char(i.iptu, 'FM999,999,990'), ',', '.'));
    ELSIF nai_ficha_valor(p_codigo, 'iptu') ~ '\d' THEN  -- 191
      v_tx := regexp_replace(regexp_replace(nai_ficha_valor(p_codigo, 'iptu'), '\s+', ' ', 'g'), ',00$', '');
      r := r || ('o IPTU é ' || v_tx);
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

  -- FORMA DE PAGAMENTO (191, 29/09): SO A FICHA RESPONDE. A Nay disse ao Paulo
  -- que o Living Comfort (5664) era "somente a vista"; o anuncio diz "Aceita
  -- Financiamento? Sim". Aqui a pergunta de financiamento, de "e a vista?" e de
  -- forma de pagamento sai da linha do anuncio. Sem a linha, NULL: a
  -- ferramenta manda escalar ao Tel, e ninguem supoe.
  v_fin := nai_ficha_valor(p_codigo, 'aceita financiamento');
  IF q ~ '(financ|a vista|avista|forma de pagamento|\mpagamento|\mparcel)' AND coalesce(i.valor_venda, 0) > 0 THEN
    IF v_fin ~* '^s' THEN
      r := r || CASE WHEN q ~ '(a vista|avista)' THEN 'não precisa ser à vista: aceita financiamento'
                     ELSE 'aceita financiamento' END;
    ELSIF v_fin ~* '^n' THEN
      r := r || 'não aceita financiamento, é só à vista'::text;
    END IF;
  END IF;
  -- FGTS: so quando o anuncio fala (a frase dele)
  IF q ~ 'fgts' THEN
    v_fr := (regexp_match(dorig, '[^.!?\n]*fgts[^.!?\n]*', 'i'))[1];
    IF coalesce(btrim(v_fr), '') <> '' THEN r := r || ('sobre FGTS, o anúncio diz: "' || btrim(v_fr) || '"'); END IF;
  END IF;
  -- PERMUTA
  IF q ~ '(permuta|\mtroca\M)' THEN
    v_per := nai_ficha_valor(p_codigo, 'aceita permuta');
    IF v_per ~* '^s' THEN
      r := r || ('aceita permuta' || coalesce(' (' || lower(nai_ficha_valor(p_codigo, 'permuta')) || ')', ''));
    ELSIF v_per ~* '^n' THEN
      r := r || 'não aceita permuta'::text;
    END IF;
  END IF;
  -- GARANTIA DO ALUGUEL (fiador, caucao, seguro-fianca)
  IF q ~ '(fiador|caucao|garantia|seguro.?fianca|titulo de capitaliza|deposito)' AND coalesce(i.valor_aluguel, 0) > 0 THEN
    v_gar := nai_ficha_valor(p_codigo, 'garantia de aluguel');
    IF v_gar IS NOT NULL THEN r := r || ('a garantia do aluguel é ' || lower(v_gar)); END IF;
  END IF;
  -- LANCES DE ESCADA
  IF q ~ '(escada|lances)' THEN
    v_esc := nullif(regexp_replace(coalesce(nai_ficha_valor(p_codigo, 'lances de escada'), ''), '\D', '', 'g'), '');
    -- 295: nunca "tem 0 lances"; e não repete o que a frase do andar já disse
    IF v_esc ~ '^0*[1-9]' AND NOT EXISTS (SELECT 1 FROM unnest(r) x WHERE x ~ 'lances? de escada') THEN
      r := r || ('tem ' || v_esc || CASE WHEN v_esc = '1' THEN ' lance de escada' ELSE ' lances de escada' END);
    END IF;
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
  -- "com modulados e ar", "Sim! E com modulados e ar" engana o corretor: fica
  -- so a frase. (12/10: a guarda testava '^é semi', a redacao de antes dos 4
  -- niveis; desde 11/10 nao casava mais e o "Sim!" tinha voltado a sair.)
  IF q !~ '(qual|quais|quanto|quantos|quantas|onde|como)'
     AND r[1] !~ '^n[ãa]o' AND r[1] !~ '^é (semi|com modulados|s[óo] climatizado)'
     -- 12/10: as frases de tipo ("é uma casa em via publica, nao tem andar";
     -- "é um apartamento em condominio, mas nao tenho o andar dele aqui")
     -- negam no MEIO, nao no comeco. "Sim!" na frente delas engana.
     AND r[1] !~ 'n[ãa]o (tem|é|e|tenho)\M' THEN
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
