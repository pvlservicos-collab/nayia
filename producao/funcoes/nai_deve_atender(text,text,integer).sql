CREATE OR REPLACE FUNCTION public.nai_deve_atender(p_telefone text, p_texto text, p_codigo_citado integer DEFAULT NULL::integer)
 RETURNS TABLE(atende boolean, motivo text)
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_chave  text := nai_chave(p_telefone);
  v_desde  timestamptz;
  v_antigo boolean;
  v_lib    timestamptz;
  v_humano timestamptz;
  v_id     bigint;
  v_cod    boolean;
BEGIN
  IF lower(coalesce(nai_cfg('regra_publico', 'nao'), 'nao')) <> 'sim' THEN
    RETURN QUERY SELECT true, 'regra desligada'::text; RETURN;
  END IF;
  v_desde := nullif(btrim(nai_cfg('regra_publico_desde', '')), '')::timestamptz;
  IF v_desde IS NULL THEN
    RETURN QUERY SELECT true, 'sem carimbo: regra nao vale'::text; RETURN;
  END IF;

  SELECT c.id, c.liberado_em, c.humano_assumiu_em INTO v_id, v_lib, v_humano
    FROM nai_contato c WHERE c.chave = v_chave;

  -- MENSAGEM POR HUMANO PAUSA (Tel, 15/09), AGORA POR MEIA HORA (Tel, 16/09).
  -- Vale antes de tudo. Passado o gap, a conversa nao volta para ela de
  -- presente: volta a ser julgada pelas regras abaixo, como qualquer outra.
  -- Conversa antiga continua sendo do Tel, a nao ser que a pessoa peca fotos
  -- de um imovel ou peca imoveis -- que e o desenho dele desde 15/09.
  IF nai_tel_com_a_conversa(v_id) THEN
    RETURN QUERY SELECT false,
      CASE WHEN (SELECT c2.humano_motivo FROM nai_contato c2 WHERE c2.id = v_id)
                = 'o Tel escreveu pelo celular'
           THEN 'o Tel escreveu ha menos de ' || greatest(nai_cfg_int('gap_tel_min', 30), 0) || ' min'
           ELSE 'o Tel assumiu essa conversa' END;
    RETURN;
  END IF;

  -- A LISTA CURTA E QUEM ELA ATENDE -- E ATENDE SEMPRE (27/09/2026, 135).
  -- "responder as minhas mensagens e do tel" (25/09) e, no dia 27, "precisa
  -- enviar os imoveis que ele, eu ou a rayssa pedem". Ate aqui a lista so
  -- ABRIA a primeira parede: quem estava nela seguia sendo julgado como
  -- corretor la embaixo, e a Rayssa caia em "contato novo, assunto que nao e
  -- de corretor". E a lista olhava so a linha que chegou: o Pedro pelo @lid
  -- dava "fora da lista curta de teste". Agora olha as duas linhas da pessoa,
  -- e quem esta nela passa direto.
  IF nai_na_lista_curta(v_id, v_chave) THEN
    RETURN QUERY SELECT true, 'da lista curta: sempre atendida'::text; RETURN;
  END IF;
  -- A EQUIPE E SEMPRE ATENDIDA, COM OU SEM LISTA CURTA (137, 28/09/2026). O
  -- ensaio da religacao das 7h mostrou: sem a lista, Tel, Pedro @lid e Rayssa
  -- caiam em "conversa que ja existia: quem responde e o Tel" -- o porteiro
  -- julgava a equipe como corretor com conversa antiga. Equipe = o Tel e a
  -- tabela `equipe` (a mesma definicao da 130), pelas duas linhas da pessoa.
  IF v_id IS NOT NULL AND nai_e_da_equipe_contato(v_id) THEN
    RETURN QUERY SELECT true, 'da equipe: sempre atendida'::text; RETURN;
  END IF;

  -- A LISTA CURTA (Tel, 25/09/2026): "responder as minhas mensagens e do
  -- tel somente por enquanto". Vazia, a parede nem existe. Preenchida, ela
  -- vem antes da lista de corretor porque e mais restritiva -- e o Tel
  -- passa sempre, senao ele perderia o proprio comando de religar.
  IF btrim(nai_cfg('so_estes_numeros', '')) <> ''
     AND v_chave <> nai_chave(nai_cfg('tel_telefone'))
     AND NOT (v_chave = ANY (nai_chaves_de('so_estes_numeros')))
     -- O ESPELHO DO TREINO PASSA (26/09/2026). A lista curta existe para a
     -- Nay nao falar com ninguem no WhatsApp fora do Tel. O espelho do
     -- treino nao esta no WhatsApp -- ele roda aqui dentro, com
     -- envio_simulado=sim -- e a lista o derrubava junto, o que travou a
     -- rodada 12 inteira em "nao estabilizou". Quem esta em `numeros_teste`
     -- e lista nossa, escrita a mao: nao e publico.
     AND NOT (v_chave = ANY (nai_chaves_teste())) THEN
    RETURN QUERY SELECT false, 'fora da lista curta de teste'::text; RETURN;
  END IF;

  -- SO CORRETOR DOS GRUPOS (Tel, 18/09/2026): "voce so vai responder essas
  -- pessoas". Vem logo DEPOIS da pausa do Tel -- a pausa dele continua valendo
  -- antes de tudo -- e ANTES de "conversa ja liberada": a lista decide QUEM
  -- ela pode atender, as regras de baixo decidem QUANDO. So vale para quem
  -- seria corretor: `nai_lista_governa` isenta Tel, equipe, motoboy e dono de
  -- imovel com visita. Desligada enquanto `so_corretor_da_lista` <> 'sim'.
  IF lower(coalesce(nai_cfg('so_corretor_da_lista', 'nao'), 'nao')) = 'sim'
     AND nai_lista_governa(v_chave, v_id)
     AND NOT nai_pode_falar(v_chave, p_telefone) THEN
    IF EXISTS (SELECT 1 FROM nai_corretor_pergunta q
                WHERE q.chave = v_chave AND q.decisao = 'nao') THEN
      RETURN QUERY SELECT false, 'o Tel disse que nao e corretor'::text; RETURN;
    END IF;
    IF nai_pergunta_de_imovel(p_texto, p_telefone, p_codigo_citado) THEN
      -- A pergunta ao Tel sai do gatilho `nai_turno_pergunta_corretor`, que le
      -- ESTE texto no turno. Mudou a frase aqui, muda la tambem.
      IF EXISTS (SELECT 1 FROM nai_corretor_pergunta q WHERE q.chave = v_chave) THEN
        RETURN QUERY SELECT false, 'fora da lista: esperando o Tel dizer se e corretor'::text; RETURN;
      END IF;
      RETURN QUERY SELECT false, 'fora da lista: perguntou de imovel, perguntar ao Tel'::text; RETURN;
    END IF;
    RETURN QUERY SELECT false, 'fora da lista de corretores'::text; RETURN;
  END IF;

  IF v_lib IS NOT NULL THEN
    RETURN QUERY SELECT true, 'conversa ja liberada'::text; RETURN;
  END IF;

  -- CONVERSA QUE ELA JA ATENDEU e dela ate o Tel digitar. Sem isto a porta
  -- julgava cada mensagem sozinha, e "pode mandar" -- resposta de quem esta
  -- negociando -- virava "assunto que nao e de corretor".
  IF v_id IS NOT NULL AND EXISTS (
       SELECT 1 FROM nai_saida s
        WHERE s.contato_id = v_id
          AND s.papel_destino IN ('turno', 'corretor', 'seguimento')
          AND s.estado IN ('enviado', 'enviando', 'simulado')
          AND s.criado_em > v_desde) THEN
    RETURN QUERY SELECT true, 'conversa que ela ja estava atendendo'::text; RETURN;
  END IF;

  -- 305: A CONVERSA QUE A NAY NOVA (nay-core) JA ESTA ATENDENDO tambem e dela. A regra de cima so
  -- olha a caixa da velha; quem responde o corretor desde 02/10 e o nucleo, em core_saida. Em 07/10
  -- o "Isso, por favor" de quem tinha acabado de ouvir "Quer que eu te mande as fotos?" caiu em
  -- "assunto que nao e de corretor" (24 turnos de 16 corretores em 5 dias).
  IF v_id IS NOT NULL AND EXISTS (
       SELECT 1 FROM core_saida s
        WHERE s.chave_destino IN (SELECT k.chave FROM nai_contato k
                                   WHERE k.id = ANY (coalesce(nai_contato_irmaos(v_id), ARRAY[v_id])))
          AND s.papel_destino = 'turno'
          AND s.estado IN ('enviado', 'enviando', 'pendente')
          AND s.criado_em > v_desde) THEN
    RETURN QUERY SELECT true, 'conversa que ela ja estava atendendo'::text; RETURN;
  END IF;

  -- MARCOU UMA MENSAGEM (o card do grupo, o imovel que ela mandou): e imovel,
  -- seja o que for que ele tenha escrito junto. E o filtro que o Tel deu.
  IF p_codigo_citado IS NOT NULL THEN
    RETURN QUERY SELECT true, 'marcou uma mensagem de imovel'::text; RETURN;
  END IF;

  SELECT EXISTS (SELECT 1 FROM mensagens m
                  WHERE nai_chave(m.telefone) = v_chave AND m.criada_em < v_desde)
      OR EXISTS (SELECT 1 FROM nai_turno t JOIN nai_contato c ON c.id = t.contato_id
                  WHERE c.chave = v_chave AND t.criado_em < v_desde)
    INTO v_antigo;

  IF NOT v_antigo THEN
    IF nai_assunto_de_corretor(p_texto)
       OR (nai_pedido_de_perfil(p_texto)->>'e_pedido')::boolean
       -- 16/09: colar a ficha de um imovel nosso, mesmo sem a linha "Codigo:",
       -- e falar de imovel.
       OR coalesce(array_length(nai_imovel_pelo_condominio(p_texto, p_telefone), 1), 0) > 0 THEN
      RETURN QUERY SELECT true, 'contato novo falando de imovel'::text; RETURN;
    END IF;
    RETURN QUERY SELECT false, 'contato novo, assunto que nao e de corretor'::text; RETURN;
  END IF;

  v_cod := EXISTS (SELECT 1 FROM unnest(coalesce(nay_codigos_citados(coalesce(p_texto, '')), '{}'::text[])) x
                    WHERE x ~ '^[0-9]{3,5}$');

  -- MANDOU O IMOVEL PELO LINK DO CATALOGO (111, Tel 23/09). O link nao diz
  -- qual imovel e, mas diz que o assunto E imovel -- e e por isso que a porta
  -- abre. Quem descobre qual e o Tel, logo adiante.
  IF nai_e_link_de_produto(p_texto) THEN
    UPDATE nai_contato SET liberado_em = now(),
                           liberado_motivo = left('mandou link de catalogo: ' || coalesce(p_texto, ''), 200)
     WHERE chave = v_chave;
    RETURN QUERY SELECT true, 'mandou o imovel pelo link do catalogo'::text; RETURN;
  END IF;

  -- COLOU O CARD, OU ESCREVEU O CODIGO (101, Tel 23/09). E o caso mais
  -- claro de "falar de imovel nosso" que existe -- e era o unico que a porta
  -- recusava, porque a regra do nome logo abaixo comeca com `NOT v_cod`.
  -- O codigo tem que ser de imovel que existe: numero solto nao abre porta.
  IF v_cod AND EXISTS (
       SELECT 1 FROM imoveis i
        WHERE i.codigo::text = ANY (coalesce(nay_codigos_citados(coalesce(p_texto, '')), '{}'::text[]))) THEN
    UPDATE nai_contato SET liberado_em = now(),
                           liberado_motivo = left('colou o card / citou o codigo: ' || coalesce(p_texto, ''), 200)
     WHERE chave = v_chave;
    RETURN QUERY SELECT true, 'colou o card de um imovel nosso'::text; RETURN;
  END IF;

  -- CITOU UM IMOVEL NOSSO PELO NOME (Tel, 16/09). Vale o mesmo que pedir foto
  -- de um imovel: a pessoa disse de qual imovel fala, entao a conversa abre.
  IF NOT v_cod
     AND coalesce(array_length(nai_imovel_pelo_condominio(p_texto, p_telefone), 1), 0) > 0 THEN
    UPDATE nai_contato SET liberado_em = now(),
                           liberado_motivo = left('citou o imovel pelo nome: ' || coalesce(p_texto, ''), 200)
     WHERE chave = v_chave;
    RETURN QUERY SELECT true, 'citou um imovel nosso pelo nome'::text; RETURN;
  END IF;

  IF nai_pede_foto(p_texto) AND v_cod THEN
    UPDATE nai_contato SET liberado_em = now(),
                           liberado_motivo = left('pediu foto: ' || coalesce(p_texto, ''), 200)
     WHERE chave = v_chave;
    RETURN QUERY SELECT true, 'pediu foto de um imovel'::text; RETURN;
  END IF;

  IF (nai_pedido_de_perfil(p_texto)->>'e_pedido')::boolean THEN
    UPDATE nai_contato SET liberado_em = now(),
                           liberado_motivo = left('pediu imoveis: ' || coalesce(p_texto, ''), 200)
     WHERE chave = v_chave;
    RETURN QUERY SELECT true, 'pediu imoveis'::text; RETURN;
  END IF;

  IF nai_pede_foto(p_texto) THEN
    RETURN QUERY SELECT false, 'pediu foto mas nao da para saber o imovel'::text; RETURN;
  END IF;
  RETURN QUERY SELECT false, 'conversa que ja existia: quem responde e o Tel'::text;
END;
$function$;
