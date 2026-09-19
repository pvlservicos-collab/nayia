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
          AND s.papel_destino IN ('turno', 'corretor')
          AND s.estado IN ('enviado', 'enviando', 'simulado')
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
