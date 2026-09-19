-- =====================================================================
-- NAI -- 56: venda tambem agenda visita (Tel, 16/09/2026)
--
-- Ele: "confirmado, e para seguir o fluxo de agendar visita quando for venda
-- tambem".
--
-- O QUE MUDA
--
-- 1. `nai_pedir_visita` para de desviar a visita de venda para o Tel. O resto
--    da funcao nunca dependeu de aluguel -- a unica mencao era essa trava -- e
--    a mensagem ao proprietario e neutra, pergunta do horario. Imovel de
--    PARCERIA continua subindo ao Tel: aquele nao e nosso.
--
-- 2. `nai_imovel_pelo_condominio` passa a usar o crivo de IDENTIFICAR, nao o
--    de OFERECER. `nai_oferta_serve`, que eu tinha posto ali hoje de manha,
--    exige aluguel e descarta o que ja foi enviado ao corretor nos ultimos 30
--    dias -- ou seja, a Nay deixaria de reconhecer justamente o imovel que
--    acabou de mandar para ele. Agora o crivo e: esta no mercado e e nosso.
--
-- 3. Nome de condominio que e igual a um TIPO fica de fora. "Apartamento" e
--    nome de condominio na base, e a palavra aparece em quase toda mensagem de
--    corretor. A comparacao com a lista de tipos tira "Apartamento", "Casa",
--    "Predio", "Flat" e "Cobertura" de uma vez.
--
-- O QUE NAO MUDA: a BUSCA continua oferecendo so locacao. Ele pediu o fluxo de
-- VISITA para venda, nao que ela passe a oferecer os 1048 imoveis de venda
-- quando alguem pede "apartamento ate 3 mil".
--
-- Gerado por `scratchpad/patch56.py` a partir do que estava NO BANCO.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.nai_imovel_pelo_condominio(p_texto text, p_telefone text)
 RETURNS integer[]
 LANGUAGE sql
 STABLE
AS $function$
  -- CARD SEM CODIGO (Tel, 16/09). O corretor manda a ficha de um imovel
  -- copiada de outro sistema -- sem a linha "Codigo:" -- e nada no sistema o
  -- reconhecia. O nome do condominio basta.
  --
  -- VENDA CONTA (Tel, 16/09): "e para seguir o fluxo de agendar visita quando
  -- for venda tambem". Por isso aqui nao entra `nai_oferta_serve`: aquele e o
  -- crivo de OFERECER numa busca, exige aluguel e ainda descarta o que ja foi
  -- mandado ao corretor nos ultimos 30 dias. Para IDENTIFICAR o imovel de que
  -- ele fala, o que importa e estar no mercado e ser nosso.
  --
  -- NOME QUE E TIPO NAO CONTA: "Apartamento", "Casa", "Predio" e "Flat" sao
  -- nomes de condominio na base e apareceriam em qualquer frase. A comparacao
  -- com a lista de tipos tira todos de uma vez, sem lista escrita a mao.
  -- Abaixo de 8 letras tambem nao vale, e nome com barra e tipo, nao nome.
  SELECT coalesce(array_agg(DISTINCT i.codigo), '{}')
    FROM imoveis i
   WHERE nai_condominio_ok(i.condominio_nome) IS NOT NULL
     AND length(nai_condominio_ok(i.condominio_nome)) >= 8
     AND nai_condominio_ok(i.condominio_nome) !~ '/'
     AND lower(unaccent(nai_condominio_ok(i.condominio_nome))) NOT IN (
           SELECT lower(unaccent(x.tipo)) FROM imoveis x WHERE x.tipo IS NOT NULL)
     AND nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
     AND NOT coalesce(i.e_parceiro, false)
     AND position(lower(unaccent(nai_condominio_ok(i.condominio_nome)))
                  IN lower(unaccent(coalesce(p_texto, '')))) > 0;
$function$;

CREATE OR REPLACE FUNCTION public.nai_pedir_visita(p_turno bigint, p_codigo text, p_quando text, p_qualificado text)
 RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
 LANGUAGE plpgsql
AS $function$
DECLARE
  t        nai_turno;
  k        nai_contato;
  i        imoveis;
  v_cod    int := NULLIF(regexp_replace(coalesce(p_codigo, ''), '\D', '', 'g'), '')::int;
  v_q      timestamptz := nai_ler_quando(p_quando);
  v_conf   text;
  v_v      nai_visita;
  v_id     bigint;
  v_dono   record;
  v_moto   record;
  v_urg    boolean;
  d        record;
  v_min_h  int := nai_cfg_int('antecedencia_minima_horas', 2);
BEGIN
  PERFORM nai_usou_ferramenta(p_turno, 'visita');
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL OR t.papel <> 'corretor' THEN
    RETURN QUERY SELECT NULL::text, 'pedir_visita e so para o corretor. nao chame de novo neste turno.'::text; RETURN;
  END IF;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;

  IF v_cod IS NULL THEN
    RETURN QUERY SELECT NULL::text, 'voce ainda nao sabe QUAL imovel. pergunte ao corretor (ou mostre a lista com imovel_do_disparo) antes de chamar pedir_visita.'::text; RETURN;
  END IF;

  -- O codigo NAO pode vir da cabeca do modelo: ele escreveu, ou foi o unico
  -- card que mandamos para ele, ou ja existe visita aberta desse imovel.
  v_conf := nay_codigo_confirmado(k.telefone, v_cod::text, 72);
  IF v_conf = 'nao' AND NOT EXISTS (SELECT 1 FROM nai_visita x WHERE x.corretor_id = k.id AND x.codigo = v_cod AND nai_visita_aberta(x.estado)) THEN
    RETURN QUERY SELECT NULL::text,
      ('o codigo ' || v_cod || ' nao foi dito por ele nesta conversa. NAO suponha: pergunte de qual imovel ele fala, confirmando o nome ou o codigo, e so depois chame pedir_visita.')::text;
    RETURN;
  END IF;

  SELECT * INTO i FROM imoveis WHERE codigo = v_cod;
  IF i.codigo IS NULL THEN
    RETURN QUERY SELECT ('Não achei nenhum imóvel com o código ' || v_cod || '. Confere pra mim?')::text, NULL::text; RETURN;
  END IF;
  IF coalesce(i.e_parceiro, false) THEN
    RETURN QUERY SELECT NULL::text, 'esse imovel e de PARCERIA, a visita nao e com a gente: chame escalar_ao_tel com o pedido de visita e diga o texto_pronto que vier.'::text; RETURN;
  END IF;
  IF NOT nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site) THEN
    RETURN QUERY SELECT ('Esse imóvel saiu do mercado' || coalesce(', ' || nai_vocativo(coalesce(k.nome_completo, k.nome_whatsapp)), '') || '. Quer que eu veja outro parecido pro seu cliente?')::text, NULL::text; RETURN;
  END IF;
  -- VENDA SEGUE O MESMO FLUXO (Tel, 16/09): "confirmado, e para seguir o fluxo
  -- de agendar visita quando for venda tambem".
  --
  -- Aqui a visita de venda era desviada para o Tel. O resto desta funcao nunca
  -- dependeu de aluguel, e a mensagem que vai ao proprietario tambem nao fala
  -- em alugar -- ela pergunta do horario. Entao a visita de venda anda pelo
  -- mesmo caminho: proprietario, acompanhante, confirmacao.
  --
  -- Medido antes de abrir: dos imoveis no mercado e nossos, 258 sao de venda e
  -- 207 deles tem telefone do dono no cadastro. E cobertura melhor do que a da
  -- locacao (14 de 39), entao o fluxo tem com quem falar.
  --
  -- O IMOVEL DE PARCERIA continua subindo ao Tel, logo acima: aquele nao e
  -- nosso, e a visita nao e com a gente.

  IF v_q IS NULL THEN
    RETURN QUERY SELECT 'Claro! Me informa o dia e o horário que fica bom pro seu cliente, ok?'::text,
      'ele nao disse dia e hora (ou nao deu para entender). quando ele disser, chame pedir_visita de novo com o horario no formato AAAA-MM-DD HH:MM.'::text;
    RETURN;
  END IF;
  -- v_regra: ja passou
  IF v_q <= now() + interval '10 minutes' THEN
    RETURN QUERY SELECT 'Esse horário já passou. Qual outro horário fica bom pro seu cliente?'::text,
      'quando ele disser outro horario, chame pedir_visita de novo.'::text;
    RETURN;
  END IF;
  IF v_q > now() + interval '45 days' THEN
    RETURN QUERY SELECT NULL::text, 'o horario ficou para daqui a mais de 45 dias: confirme a data com ele antes de chamar de novo.'::text; RETURN;
  END IF;

  -- SEM pergunta de renda (Tel, 12/09): isso vinha da regra 2 da tabela
  -- `regras` (14/08, da Nay antiga) e NAO existe em card nenhum do fluxo do
  -- site. O fluxo e a lista completa do que ela faz com o corretor. O
  -- parametro p_qualificado continua sendo aceito (para nao quebrar chamada
  -- antiga), mas nao segura mais nada.

  -- Ja existe visita aberta deste imovel com este corretor?
  SELECT * INTO v_v FROM nai_visita x WHERE x.corretor_id = k.id AND x.codigo = v_cod AND nai_visita_aberta(x.estado);
  IF v_v.id IS NOT NULL THEN
    RETURN QUERY SELECT NULL::text,
      ('ja existe visita em andamento desse imovel com ele (' || nai_status_humano(v_v) || ', ' ||
       coalesce(nai_quando_humano(v_v.quando), 'sem horario') || '). se ele quer OUTRO horario, chame mudar_horario_da_visita; se mandou nome/CPF, chame guardar_dados_da_visita; nao chame pedir_visita.')::text;
    RETURN;
  END IF;

  v_urg := v_q < now() + make_interval(hours => v_min_h);
  SELECT * INTO v_dono FROM nai_proprietario_do_imovel(v_cod);
  SELECT * INTO v_moto FROM nai_motoboy();

  INSERT INTO nai_visita (codigo, corretor_id, quando, estado, aguardando, urgente, qualificado,
                          proprietario_cadastro, proprietario_nome, motoboy_id, proximo_lembrete_dados_em)
       VALUES (v_cod, k.id, v_q, 'coletando', 'corretor', v_urg, NULL,
               v_dono.cadastro_id, v_dono.nome, v_moto.contato_id, NULL)
  RETURNING id INTO v_id;
  PERFORM nai_evento(v_id, 'pedida', 'horario ' || nai_hora_exata(v_q));

  -- VISITA URGENTE (Tel, 12/09): menos de 3 horas nao passa pela IA. Sobe
  -- para o Tel e a Nay PARA -- e desde 13/09 para o chat inteiro do corretor.
  IF v_urg THEN
    UPDATE nai_visita SET estado = 'com_tel', aguardando = 'tel', urgente = true,
                          proximo_lembrete_dados_em = NULL, atualizado_em = now()
     WHERE id = v_id;
    PERFORM nai_evento(v_id, 'urgente_com_tel', nai_hora_exata(v_q));
    PERFORM nai_avisar_tel(p_turno, v_id,
      'Tel, VISITA URGENTE (menos de ' || v_min_h || 'h): ' || nai_ref_imovel(v_cod) || ', ' || nai_hora_exata(v_q) ||
      E'.\nCorretor: ' || coalesce(k.nome_completo, k.nome_whatsapp, '') || ' ' || nai_fone_fmt(k.telefone) ||
      E'\nEu parei aqui: não falei com o proprietário nem com o ' || nai_acompanhante() || ', e parei de responder esse corretor. A visita #' || v_id || ' é sua.' ||
      E'\nSe quiser que eu siga, responda VISITA ' || v_id || ' OK.', 'urgente');
    PERFORM nai_parar_chat(k.id, 'visita #' || v_id || ': urgente (menos de ' || v_min_h || 'h)');
    RETURN QUERY SELECT NULL::text,
      'visita URGENTE: foi para o Tel e voce PAROU neste chat. responda exatamente SILENCIO.'::text;
    RETURN;
  END IF;

  -- FLUXO v17 (Tel, 13/09): o horario vai DIRETO ao proprietario. Os dados do
  -- corretor e do visitante so sao pedidos depois da "Visita confirmada", e
  -- nesta hora o corretor nao recebe nada ("Nada, fica calada").
  PERFORM nai_pedir_ao_proprietario(v_id, p_turno);
  RETURN QUERY SELECT NULL::text,
    'o pedido foi ao proprietario (ou ao Tel). o corretor NAO recebe nada agora: responda exatamente SILENCIO. NAO peca dados e NAO diga que a visita esta confirmada.'::text;
END;
$function$;
