-- =====================================================================
-- 135 — A EQUIPE MANDA IMÓVEL, E A LISTA CURTA É SEMPRE ATENDIDA (27/09/2026)
--
-- Revisão pedida: "revisa todo funcionamento da nay, se ela segue as regras
-- de hoje para não errar". Duas regras de hoje NÃO estavam valendo:
--
-- 1. "precisa enviar os imoveis que ele, eu ou a rayssa pedem". Só o Tel
--    tinha caminho: o pedido dele vai para o publicador. O do Pedro e o da
--    Rayssa caíam na conversa comum, como corretor perguntando -- e o
--    `nai_enviar_imovel_para` (129) gravava o card com papel 'corretor' sem
--    visita, que o gatilho da caixa de saída recusa. Nunca funcionou.
--
-- 2. A lista curta (Pedro, Tel, Rayssa) só abria a primeira parede do
--    porteiro. O Pedro pelo @lid dava "fora da lista curta de teste" (a lista
--    olhava só a linha que chegou) e a Rayssa, "contato novo, assunto que não
--    é de corretor".
--
-- O QUE MUDA:
--   * `nai_na_lista_curta`: as duas linhas da pessoa; quem está nela passa.
--   * `nai_ler_pedido_de_envio`: "92 8110-1119 envia o 3210", "envia 92 ...
--     o 3210", "manda o 3210 e o 5729 para 92 ..." -> (telefone, códigos).
--   * o pedido da equipe vira turno de comando (papel 'tel') e cai em
--     `nai_comando_tel`, que chama `nai_enviar_imoveis_para`: abertura, card e
--     fotos pela caixa de saída com papel 'entrega' -- e TODAS as paredes:
--     parceiro não sai, indisponível não sai, 24h por corretor (131/132). A
--     confirmação volta para quem pediu.
--   * o pedido do TEL não muda: segue no publicador.
-- =====================================================================
\set ON_ERROR_STOP on

BEGIN;

-- ---------------------------------------------------------------------
-- Está na lista curta? Olha as duas linhas da pessoa (telefone e @lid).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION nai_na_lista_curta(p_contato bigint, p_chave text)
RETURNS boolean
LANGUAGE sql
STABLE
AS $fn$
  SELECT btrim(nai_cfg('so_estes_numeros', '')) <> ''
     AND (p_chave = ANY (nai_chaves_de('so_estes_numeros'))
          OR (p_contato IS NOT NULL AND EXISTS (
                SELECT 1 FROM nai_contato c
                 WHERE c.id = ANY (nai_contato_irmaos(p_contato))
                   AND c.chave = ANY (nai_chaves_de('so_estes_numeros')))));
$fn$;

-- ---------------------------------------------------------------------
-- Lê "envia <telefone> o <código>" nas três formas que eles usam.
-- Não casou = nenhuma linha. Descrição sem código ("os dois conquista rio
-- negro") não é lida aqui: essa continua sendo do publicador, pelo Tel.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION nai_ler_pedido_de_envio(p text)
RETURNS TABLE (telefone text, codigos integer[])
LANGUAGE plpgsql
IMMUTABLE
AS $fn$
DECLARE
  s       text := btrim(coalesce(p, ''));
  v_fone  text := '(?:55[\s.-]*)?\(?[0-9]{2}\)?[\s.-]*[0-9]{4,5}[\s.-]*[0-9]{4}';
  v_verbo text := '(?:envi|m[a]?nd|repass|encaminh)[a-zçã]*';
  v_voc   text := '(?:@?nay[\s,;:.!?-]*)?';
  v_cods  text := '(?:(?:o|os|a|as|c[oó]d(?:igo)?s?)[\s:=.-]*)?([0-9]{3,5}(?:(?:\s*[,;]\s*|\s+e\s+|\s+)(?:(?:o|os)\s+)?[0-9]{3,5})*)';
  m       text[];
BEGIN
  -- "92 8110-1119 envia o 3210"
  m := regexp_match(s, '^' || v_voc || '(' || v_fone || ')[\s,;:.-]+' || v_voc
                       || v_verbo || '\s+' || v_cods || '\s*$', 'i');
  -- "envia 92 8110-1119 o 3210" / "envia pra 92 ... o 3210"
  IF m IS NULL THEN
    m := regexp_match(s, '^' || v_voc || v_verbo || '\s+(?:(?:para|pra|pro)\s+|p/\s*)?('
                         || v_fone || ')\s+' || v_cods || '\s*$', 'i');
  END IF;
  -- "manda o 3210 e o 5729 para 92 8110-1119"
  IF m IS NULL THEN
    m := regexp_match(s, '^' || v_voc || v_verbo || '\s+' || v_cods
                         || '\s+(?:para|pra|pro|p/)\s*(' || v_fone || ')\s*$', 'i');
    IF m IS NOT NULL THEN
      m := ARRAY[m[2], m[1]];
    END IF;
  END IF;
  IF m IS NULL THEN
    RETURN;
  END IF;
  RETURN QUERY
    SELECT m[1],
           (SELECT array_agg(z.c ORDER BY z.o)
              FROM (SELECT DISTINCT ON (x[1]) x[1]::int AS c, o
                      FROM regexp_matches(m[2], '([0-9]{3,5})', 'g') WITH ORDINALITY AS r(x, o)
                     ORDER BY x[1], o) z);
END;
$fn$;

CREATE OR REPLACE FUNCTION nai_e_comando_envio(p text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT EXISTS (SELECT 1 FROM nai_ler_pedido_de_envio(p));
$fn$;

-- ---------------------------------------------------------------------
-- Manda um ou mais imóveis para um número, pela caixa de saída.
--
-- Confere TUDO antes de abrir a boca: se nenhum imóvel pode ir, o cliente não
-- recebe um "segue o imóvel" solto. Cada recusa vira uma linha na resposta
-- para quem pediu, com o motivo.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION nai_enviar_imoveis_para(p_turno bigint, p_codigos integer[],
                                                   p_telefone text)
RETURNS text
LANGUAGE plpgsql
AS $fn$
DECLARE
  v_digitos text := regexp_replace(coalesce(p_telefone, ''), '[^0-9]', '', 'g');
  v_chave   text;
  v_destino bigint;
  v_card    text;
  v_ja      timestamptz;
  v_hora    int;
  v_ordem   int := 1;
  v_fotos   int;
  v_vao     int[] := '{}';
  v_linhas  text[] := '{}';
  v_feitos  text[] := '{}';
  c         int;
  i         record;
  f         record;
BEGIN
  IF length(v_digitos) < 10 THEN
    RETURN 'Não entendi o número "' || coalesce(p_telefone, '') || '". Manda assim: envia 92 99999-9999 o 3210';
  END IF;
  v_chave := nai_chave(v_digitos);
  IF v_chave IS NULL OR coalesce(array_length(p_codigos, 1), 0) = 0 THEN
    RETURN 'Não entendi o pedido. Manda assim: envia 92 99999-9999 o 3210';
  END IF;

  -- 1. o que pode ir
  FOREACH c IN ARRAY p_codigos LOOP
    SELECT codigo, coalesce(e_parceiro, false) AS parceiro,
           nay_esta_no_mercado(disponivel, bloqueado, publicado_no_site) AS no_mercado
      INTO i FROM imoveis WHERE codigo = c;
    IF i.codigo IS NULL OR (SELECT texto_pronto FROM nai_card_do_imovel(c)) IS NULL THEN
      v_linhas := v_linhas || (c || ': não achei esse código');
    ELSIF i.parceiro THEN
      v_linhas := v_linhas || (c || ': é imóvel de parceiro, não mandei (parceria não sai)');
    ELSIF NOT coalesce(i.no_mercado, false) THEN
      v_linhas := v_linhas || (c || ': está indisponível, não mandei');
    ELSE
      v_ja := nay_reservar_imovel_do_dia(v_chave, c, 'nai', p_turno);
      IF v_ja IS NOT NULL THEN
        v_linhas := v_linhas || (c || ': já foi para esse número ' || nay_quando_foi(v_ja)
                                 || ', não mandei de novo (libera '
                                 || nay_quando_foi(v_ja + interval '24 hours') || ')');
      ELSE
        v_vao := v_vao || c;
      END IF;
    END IF;
  END LOOP;

  IF coalesce(array_length(v_vao, 1), 0) = 0 THEN
    RETURN 'Não mandei nada para ' || nai_fone_fmt(v_digitos) || E':\n'
           || array_to_string(v_linhas, E'\n');
  END IF;

  -- 2. o contato do destino (nasce aqui se não existir)
  SELECT id INTO v_destino FROM nai_contato WHERE chave = v_chave;
  IF v_destino IS NULL THEN
    INSERT INTO nai_contato (chave, telefone, nome_whatsapp)
    VALUES (v_chave, v_digitos, NULL)
    RETURNING id INTO v_destino;
  END IF;

  -- 3. uma linha antes, dizendo o que vem (Tel, 31/08: "card e foto caindo do
  --    nada"), com a mesma frase do publicador
  v_hora := extract(hour FROM now() AT TIME ZONE 'America/Manaus');
  PERFORM nai_enfileirar_texto(p_turno, NULL, v_destino, 'entrega',
    'Oi, ' || CASE WHEN v_hora < 12 THEN 'bom dia' WHEN v_hora < 18 THEN 'boa tarde' ELSE 'boa noite' END
    || '! ' || CASE WHEN array_length(v_vao, 1) > 1
                    THEN 'Seguem os imóveis que fiquei de te enviar.'
                    ELSE 'Segue o imóvel que fiquei de te enviar.' END,
    'envia_comando', v_ordem);

  -- 4. card e fotos, um imóvel de cada vez, na ordem pedida
  FOREACH c IN ARRAY v_vao LOOP
    SELECT texto_pronto INTO v_card FROM nai_card_do_imovel(c);
    v_ordem := v_ordem + 1;
    PERFORM nai_enfileirar_texto(p_turno, NULL, v_destino, 'entrega', v_card, 'envia_comando', v_ordem);
    v_fotos := 0;
    FOR f IN SELECT * FROM nai_imagens_do_envio(c) LOOP
      -- a colagem de 4 fotos é só dos grupos (Tel, 14/09)
      CONTINUE WHEN f.e_colagem;
      v_ordem := v_ordem + 1;
      INSERT INTO nai_saida (turno_id, contato_id, papel_destino, chave_destino,
                             tipo, imagem_url, codigo, ordem, motivo)
      VALUES (p_turno, v_destino, 'entrega', v_chave, 'imagem', f.url, c, v_ordem, 'foto');
      v_fotos := v_fotos + 1;
    END LOOP;
    v_feitos := v_feitos || (c || ' (card e ' || v_fotos || ' foto' || CASE WHEN v_fotos = 1 THEN '' ELSE 's' END || ')');
  END LOOP;

  RETURN 'Mandei para ' || nai_fone_fmt(v_digitos) || ': ' || array_to_string(v_feitos, ', ')
         || CASE WHEN array_length(v_linhas, 1) > 0
                 THEN E'.\n' || array_to_string(v_linhas, E'\n') ELSE '.' END;
END;
$fn$;

-- O nome antigo (129) continua valendo, agora pelo caminho novo.
CREATE OR REPLACE FUNCTION nai_enviar_imovel_para(p_turno bigint, p_codigo integer,
                                                  p_telefone text)
RETURNS text
LANGUAGE sql
AS $fn$
  SELECT nai_enviar_imoveis_para(p_turno, ARRAY[p_codigo], p_telefone);
$fn$;

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

CREATE OR REPLACE FUNCTION public.nai_abrir_turno(p_tel text, p_nome text, p_texto text, p_citado_id text, p_ids bigint[])
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_chave   text := nai_chave(p_tel);
  v_modo    text := nai_cfg('modo', 'desligado');
  v_teste   boolean;
  v_contato bigint;
  v_papel   text := 'corretor';
  v_visita  bigint;
  v_texto   text := coalesce(p_texto, '');
  v_m       text[];
  v_cit     record;
  v_n       int;
  v_turno   bigint;
  v_aprov   boolean;
  v_prim    boolean;
  v_pausado boolean;
  v_tel_lid text;
  v_porta   record;   -- a porta: atende essa mensagem?
BEGIN
  IF v_chave IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'sem_identificador');
  END IF;
  IF v_modo NOT IN ('teste', 'todos') THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'nai_desligada');
  END IF;
  v_teste := v_chave = ANY (nai_chaves_teste());

  -- O FILTRO DE PALAVRAS (106, Tel 23/09: "se ela estiver escrita mais ou
  -- menos certo, acima de 70% da palavra certa ela conserta a palavra antes
  -- ate de enviar para a Nay"). "bom pedro" vira Dom Pedro, "aquarelli" vira
  -- Acquarelle -- e isso vale para a PORTA tambem, que assim reconhece o
  -- imovel nosso mesmo quando o nome chega torto do audio.
  -- O comando do Tel nao passa por aqui: filtro de palavras nao pode ter
  -- poder de quebrar um DEVOLVER.
  IF NOT nai_pode_comandar(v_chave) THEN
    v_texto := nai_corrigir_nomes(v_texto);
  END IF;
  -- O COMANDO DELES PASSA MESMO EM MODO TESTE (Tel, 15/09: "tel mandou agenda
  -- de visitas e ela n respondeu"). O numero do Tel nao esta em
  -- `numeros_teste` -- so o do Pedro esta --, entao o turno nem abria e o
  -- comando morria calado. A excecao e so para o COMANDO: conversa normal
  -- desses numeros continua caindo na mesma porta de antes.
  IF v_modo = 'teste' AND NOT v_teste
     AND nai_pode_comandar(v_chave)
     AND (nai_e_comando_tel(v_texto) OR nai_e_comando_extra(v_texto)) THEN
    NULL;   -- deixa passar
  ELSIF v_modo = 'teste' AND NOT v_teste THEN
    -- Defesa em profundidade: o roteador nao devia ter mandado.
    RETURN jsonb_build_object('ok', false, 'motivo', 'fora_do_teste');
  END IF;

  v_contato := nai_contato_de(p_tel, p_nome);

  -- O TEL ASSUMIU este chat: a mensagem fica gravada (status 'Com o Tel') e
  -- a NAI nao responde. No teste, "T: ..." continua sendo o Tel mandando
  -- comando (e o DEVOLVER precisa passar).
  -- 16/09: a leitura da pausa passou a ser uma so, em `nai_tel_com_a_conversa`
  -- -- que sabe do gap. Antes eram tres copias de
  -- `humano_assumiu_em IS NOT NULL`, e com a janela entrando elas iam divergir.
  IF nai_tel_com_a_conversa(v_contato)
     AND NOT (v_teste AND v_texto ~* '^\s*(t|tel)\s*[:\-–]') THEN
    UPDATE mensagens SET status = 'Com o Tel' WHERE id = ANY (coalesce(p_ids, '{}')) AND status IN ('Recebido', 'Processando');
    RETURN jsonb_build_object('ok', false, 'motivo', 'tel_assumiu', 'contato_id', v_contato);
  END IF;

  IF v_teste THEN
    -- No teste, o mesmo numero faz todos os papeis. O papel vem da MARCACAO
    -- (ele respondeu marcando a mensagem que iria para o proprietario) ou
    -- do prefixo P: / M: / T:. Sem nada disso, e corretor.
    IF nullif(p_citado_id, '') IS NOT NULL THEN
      SELECT s.papel_destino, s.visita_id INTO v_cit
        FROM nai_saida s WHERE s.message_id = p_citado_id AND s.redirecionado LIMIT 1;
      IF v_cit.papel_destino IN ('proprietario', 'motoboy', 'tel') THEN
        v_papel := v_cit.papel_destino; v_visita := v_cit.visita_id;
      END IF;
    END IF;
    v_m := regexp_match(v_texto, ('^\s*(p|prop|propriet[aá]ri[oa]|m|moto|motoboy|fernando|'
                          -- as DUAS grafias do nome: quem digita "André:" e quem digita
                          -- "Andre:" tem que cair no mesmo lugar. O texto NAO passa por
                          -- unaccent -- ele e capturado aqui e vira a mensagem.
                          || lower(nai_acompanhante()) || '|' || lower(unaccent(nai_acompanhante()))
                          || '|t|tel)\s*[:\-–]\s*(.*)$'), 'is');
    IF v_m IS NOT NULL THEN
      v_texto := v_m[2];
      IF v_papel = 'corretor' THEN
        -- O NOME DO ACOMPANHANTE tambem manda para o motoboy (Tel, 16/09).
        -- Sem esta linha, "André: pode ser" caia como TEL: a decisao testava
        -- so as iniciais m e f (motoboy e Fernando), e "andre" nao comeca com
        -- nenhuma das duas. Medido antes de aplicar.
        v_papel := CASE WHEN lower(v_m[1]) ~ '^p' THEN 'proprietario'
                        WHEN lower(v_m[1]) ~ '^(m|f)' THEN 'motoboy'
                        WHEN lower(unaccent(v_m[1])) = lower(unaccent(nai_acompanhante()))
                          THEN 'motoboy'
                        ELSE 'tel' END;
      END IF;
    END IF;
    -- O NUMERO DO TEL no teste (13/09): comando da NAI (VISITAS, VISITA N, ACESSO,
    -- ASSUMIR, DEVOLVER) sem o prefixo T: tambem e o Tel. Conversa normal dele
    -- continua sendo corretor -- e assim que ele testa.
    IF v_papel = 'corretor' AND v_chave = nai_chave(nai_cfg('tel_telefone')) AND nai_e_comando_tel(v_texto) THEN
      v_papel := 'tel';
    END IF;
    -- AGENDA DE VISITAS (Tel, 15/09): "quero que o tel e eu quando digitar no
    -- pv dela Agenda de visitas". Vale para os telefones de
    -- `comando_telefones`, e SO para esse comando -- o resto da conversa deles
    -- continua caindo onde sempre caiu.
    IF v_papel = 'corretor' AND nai_e_comando_extra(v_texto) AND nai_pode_comandar(v_chave) THEN
      v_papel := 'tel';
    END IF;
    -- ENVIA <NUMERO> O <CODIGO> DA EQUIPE (27/09/2026, 135): o pedido de envio
    -- do Pedro e da Rayssa e comando, nao conversa. O do Tel continua indo para
    -- o publicador, pelo caminho de sempre -- por isso o Tel fica de fora aqui.
    IF v_papel = 'corretor' AND v_chave <> nai_chave(nai_cfg('tel_telefone'))
       AND nai_e_comando_envio(v_texto) AND nai_e_da_equipe_contato(v_contato) THEN
      v_papel := 'tel';
    END IF;
    IF v_papel IN ('proprietario', 'motoboy') AND v_visita IS NULL THEN
      -- A unica visita esperando esse papel. Mais de uma = pergunta.
      SELECT count(*), min(x.id) INTO v_n, v_visita FROM nai_visita x
       WHERE nai_visita_aberta(x.estado) AND x.aguardando = v_papel;
      IF v_n <> 1 THEN
        SELECT count(*), min(x.id) INTO v_n, v_visita FROM nai_visita x
         WHERE nai_visita_aberta(x.estado)
           AND (v_papel = 'proprietario' AND x.proprietario_id IS NOT NULL
             OR v_papel = 'motoboy' AND x.estado IN ('aguardando_motoboy', 'confirmada'));
        IF v_n <> 1 THEN v_visita := NULL; END IF;
      END IF;
    END IF;
  ELSE
    IF v_chave = nai_chave(nai_cfg('tel_telefone'))
       OR (nai_e_comando_extra(v_texto) AND nai_pode_comandar(v_chave))
       -- o pedido de envio da equipe (135)
       OR (nai_e_comando_envio(v_texto) AND nai_e_da_equipe_contato(v_contato)) THEN
      v_papel := 'tel';
    ELSIF nai_e_motoboy(v_chave) THEN
      v_papel := 'motoboy';
    ELSIF EXISTS (SELECT 1 FROM nai_visita x WHERE x.proprietario_id = v_contato AND nai_visita_aberta(x.estado)) THEN
      v_papel := 'proprietario';
    END IF;
    IF v_papel IN ('proprietario', 'motoboy') THEN
      -- Qual visita: pela mensagem marcada; senao, a unica aberta dele.
      IF nullif(p_citado_id, '') IS NOT NULL THEN
        SELECT s.visita_id INTO v_visita FROM nai_saida s
         WHERE s.message_id = p_citado_id AND s.contato_id = v_contato AND s.visita_id IS NOT NULL LIMIT 1;
      END IF;
      IF v_visita IS NULL THEN
        SELECT count(*), min(x.id) INTO v_n, v_visita FROM nai_visita x
         WHERE nai_visita_aberta(x.estado)
           AND ((v_papel = 'proprietario' AND x.proprietario_id = v_contato)
             OR (v_papel = 'motoboy' AND x.motoboy_id = v_contato AND x.estado IN ('aguardando_motoboy', 'confirmada')));
        IF v_n <> 1 THEN v_visita := NULL; END IF;
      END IF;
    END IF;
  END IF;

  -- Corretor aprovado? Teste = sim. @lid: so pelo mapeamento ja gravado,
  -- e SO para aprovar -- a conversa continua sendo a do @lid.
  IF v_teste THEN
    v_aprov := true;
  ELSE
    IF v_chave ~ '^lid:' THEN
      SELECT telefone INTO v_tel_lid FROM identidade_lid WHERE lid = p_tel;
    END IF;
    v_aprov := EXISTS (SELECT 1 FROM corretores c
                        WHERE c.aprovado AND c.ativo
                          AND nai_chave(c.telefone) = coalesce(nai_chave(v_tel_lid), v_chave));
  END IF;
  v_prim := NOT EXISTS (SELECT 1 FROM mensagens m
                         WHERE m.telefone = p_tel AND m.direcao = 'recebida'
                           AND NOT (m.id = ANY (coalesce(p_ids, '{}'))));

  -- A PORTA (Tel, 15/09): quem ela atende quando a regra publica esta ligada.
  -- Com a regra desligada devolve atende=true e o roteador segue com o
  -- porteiro de sempre -- entao ligar este campo nao muda nada sozinho.
  -- O IMOVEL DA MENSAGEM MARCADA vai junto (Tel, 15/09): quem responde o card
  -- do grupo esta falando de imovel, escreva o que escrever -- ate "Boa
  -- noite!". `nay_imovel_da_citacao` ja resolve o card do grupo, o card que ela
  -- mandou e o envio do publicador.
  SELECT * INTO v_porta FROM nai_deve_atender(
    p_tel, v_texto,
    nullif(regexp_replace(coalesce(nay_imovel_da_citacao(p_citado_id), ''), '\D', '', 'g'), '')::int);
  -- A pausa geral da Nay (config.atendimento_pausado) vale para a NAI tambem --
  -- menos para o numero de teste, do mesmo jeito que a Nay antiga isenta o Tel.
  -- A PAUSA E SO A DELA (Tel, 15/09, na revisao depois de ativar).
  --
  -- Ate aqui a pausa da Nay ANTIGA (`config.atendimento_pausado`) tambem calava
  -- a NAI, menos para o numero de teste. Enquanto ela era so teste isso nunca
  -- aparecia -- o unico que falava com ela era o Pedro, e ele e "teste". Ao
  -- abrir para todos, as 14:12, TODO MUNDO caiu naquela pausa: 133 mensagens
  -- entraram e nenhuma foi respondida, e nao havia erro nenhum para ver.
  --
  -- A Nay antiga esta pausada desde agosto, de proposito e para sempre. Ela nao
  -- pode calar um atendimento que e outro produto, com a propria chave e o
  -- proprio botao no painel.
  v_pausado := nai_cfg('pausada', 'sim') <> 'nao';

  INSERT INTO nai_turno (contato_id, papel, visita_id, teste, texto, msg_ids, porta)
       VALUES (v_contato, v_papel, v_visita, v_teste, v_texto, p_ids, v_porta.motivo)
  RETURNING id INTO v_turno;

  -- Registra que o proprietario / Fernando respondeu (para as cobrancas).
  IF v_papel = 'proprietario' THEN
    UPDATE nai_visita SET ult_resp_prop_em = now(), atualizado_em = now()
     WHERE (id = v_visita) OR (v_visita IS NULL AND proprietario_id = v_contato AND nai_visita_aberta(estado));
  ELSIF v_papel = 'motoboy' AND v_visita IS NOT NULL THEN
    UPDATE nai_visita SET ult_resp_moto_em = now(), atualizado_em = now() WHERE id = v_visita;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'turno_id', v_turno,
    'contato_id', v_contato,
    'chave', v_chave,
    'telefone', (SELECT telefone FROM nai_contato WHERE id = v_contato),
    'papel', v_papel,
    'visita_id', v_visita,
    'teste', v_teste,
    'modo', v_modo,
    'texto', v_texto,
    'aprovado', v_aprov,
    -- ATENDE: NULL quando a regra publica esta desligada (o roteador decide
    -- como sempre decidiu); true/false quando ela manda. `porta` diz o motivo,
    -- e e ele que explica um silencio depois.
    'atende', CASE WHEN lower(coalesce(nai_cfg('regra_publico', 'nao'), 'nao')) = 'sim'
                   THEN v_porta.atende END,
    'porta', v_porta.motivo,
    -- SO CUMPRIMENTOU (Tel, 15/09): "ela tem que responder o cumprimento e
    -- aguardar nesse caso". Quem chega dizendo so "boa noite" ainda nao disse a
    -- que veio -- despejar o roteiro em cima dele e responder outra pergunta.
    'so_cumprimento', nai_so_cumprimentou(v_texto),
    'primeira_vez', v_prim,
    'pausado', v_pausado,
    -- "3500" depois de "qual a faixa de preco?" e VALOR, nao codigo (13/09).
    'esperando_valor', nai_esperando_valor(v_contato),
    'memoria', 'nai:' || v_papel || ':' || v_contato || coalesce(':v' || v_visita, ''),
    -- O PROMPT VEM DO BANCO (Tel, 15/09): editar no painel vale na mensagem
    -- seguinte, sem import nem reinicio. Vazio aqui = o fluxo usa o texto que
    -- ja esta dentro dele, entao nada quebra.
    'prompt', nai_prompt_de(CASE WHEN v_papel = 'tel' THEN 'corretor' ELSE v_papel END),
    -- COMANDO DA NAI: o roteador do fluxo lia uma COPIA da regex de
    -- `nai_e_comando_tel` dentro do JS, e as duas se afastariam na primeira
    -- mudanca. Agora quem responde e o banco, e o JS so le este campo.
    'comando_nai', (v_papel = 'tel' AND (nai_e_comando_tel(v_texto) OR nai_e_comando_extra(v_texto)
                    -- 135: o envio da equipe vai para `nai_comando_tel`; o do
                    -- Tel segue no publicador (comando_nai falso para ele)
                    OR (nai_e_comando_envio(v_texto)
                        AND v_chave <> nai_chave(nai_cfg('tel_telefone'))))),
    -- A BIBLIOTECA DE PALAVRAS (96, Tel 22/09) entra colada no contexto: so a
    -- explicacao da giria que ELE escreveu nesta mensagem, e nada quando nao
    -- ha giria nenhuma.
    'contexto', nai_contexto(v_papel, v_contato, v_visita, v_teste)
                || CASE WHEN v_papel IN ('corretor', 'tel')
                        THEN nai_giria_explica(v_texto) ELSE '' END,
    -- Como chamar a pessoa: Sr./Sra. + primeiro nome (Tel, 12/09 -- o mesmo
    -- tom da captacao). Quando o nome nao diz o genero, vem so o primeiro
    -- nome: melhor sem tratamento do que chamar uma corretora de "Sr.".
    'vocativo', CASE WHEN v_papel = 'proprietario'
                     THEN nai_vocativo((SELECT proprietario_nome FROM nai_visita WHERE id = v_visita))
                     WHEN v_papel = 'corretor'
                     THEN nai_vocativo(coalesce((SELECT nome_completo FROM nai_contato WHERE id = v_contato),
                                                nay_nome_de_pessoa((SELECT nome_whatsapp FROM nai_contato WHERE id = v_contato)))) END
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.nai_comando_tel(p_turno bigint, p_texto text)
 RETURNS TABLE(msg_tel text)
 LANGUAGE plpgsql
AS $function$
DECLARE
  t     nai_turno;
  s     text := regexp_replace(btrim(coalesce(p_texto, '')), '^\s*@?nay[\s,:;.!-]*', '', 'i');
  m     text[];
  v     nai_visita;
  q     timestamptz;
  v_ac  text;
  linhas text;
  v_msg text;
  v_lib int := 0;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL THEN
    RETURN QUERY SELECT 'comando so do Tel.'::text; RETURN;
  END IF;

  -- =====================================================================
  -- ENVIA <NUMERO> O <CODIGO>  (Tel, 27/09/2026)
  --
  -- "ele pede para ela mandar um imovel para um numero e ela n manda".
  --
  -- E verdade: ele pediu NOVE VEZES em quatro dias, sempre na mesma forma --
  -- "envia 92 9450-0381 o 3050" -- e nao existia comando nenhum que casasse.
  -- A mensagem caia como conversa e ela respondia qualquer outra coisa.
  --
  -- Vem ANTES da guarda de papel porque quem manda aqui nao e so o Tel: ele
  -- pediu que valesse tambem para ele proprio, para o Pedro e para a Rayssa
  -- ("os imoveis que ele, eu ou a rayssa pedem"). Todo o RESTO dos comandos
  -- continua sendo so do Tel -- ninguem mais para o atendimento por aqui.
  --
  -- O CODIGO E O ULTIMO GRUPO DE 3 A 5 DIGITOS. O telefone vem antes e tem 10
  -- ou 11 digitos, entao ler de tras para frente e o que faz "envia 92
  -- 99462-9241 codigo 150" funcionar sem confundir as duas coisas.
  -- =====================================================================
  -- 135: a frase e lida por `nai_ler_pedido_de_envio` -- telefone antes ou
  -- depois do verbo, um ou varios codigos -- e quem pode mandar e a equipe
  -- (a mesma definicao da 130), olhando as duas linhas da pessoa.
  IF nai_e_comando_envio(s)
     AND (t.papel = 'tel' OR nai_e_da_equipe_contato(t.contato_id))
  THEN
    v_msg := (SELECT nai_enviar_imoveis_para(p_turno, p.codigos, p.telefone)
                FROM nai_ler_pedido_de_envio(s) p);
    PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_msg, 'comando_envia', 1);
    RETURN QUERY SELECT v_msg; RETURN;
  END IF;

  IF t.papel <> 'tel' THEN
    RETURN QUERY SELECT 'comando so do Tel.'::text; RETURN;
  END IF;

  -- AGENDA DE VISITAS (Tel, 15/09): a agenda de hoje em diante, separada por
  -- dia. O comando VISITAS logo abaixo continua igual ao que sempre foi.
  -- PARAR / VOLTAR ATENDIMENTO (Tel, 15/09). A chave geral sempre existiu e so
  -- se mexia por UPDATE no banco; agora ele desliga do proprio WhatsApp.
  -- Parada, ela NAO envia nada para ninguem -- as mensagens continuam chegando
  -- e ficam gravadas, e os comandos dele continuam funcionando.
  IF nai_e_comando_parada(s) THEN
    IF nai_parada_e_para(s) THEN
      UPDATE nai_config SET valor = 'sim' WHERE chave = 'pausada';
      v_msg := 'Parei o atendimento. Não respondo mais ninguém até você mandar VOLTAR ATENDIMENTO.'
               || E'\nAs mensagens continuam chegando e ficando guardadas, e seus comandos continuam valendo.';
    ELSE
      UPDATE nai_config SET valor = 'nao' WHERE chave = 'pausada';
      v_msg := 'Voltei a atender.';
    END IF;
    PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_msg, 'comando_tel', 1);
    RETURN QUERY SELECT v_msg; RETURN;
  END IF;

  IF nai_e_comando_agenda(s) THEN
    v_msg := nai_agenda_por_dia();
    PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_msg, 'comando_tel', 1);
    RETURN QUERY SELECT v_msg; RETURN;
  END IF;

  IF s ~* '^visitas\s*$' THEN
    SELECT string_agg('#' || x.id || ' · ' || nai_ref_imovel(x.codigo) || ' · ' || nai_hora_exata(x.quando) || ' · ' || x.estado ||
                      coalesce(' (esperando ' || x.aguardando || ')', ''), E'\n' ORDER BY x.quando)
      INTO linhas FROM nai_visita x WHERE nai_visita_aberta(x.estado);
    v_msg := coalesce(E'Visitas em andamento:\n' || linhas, 'Nenhuma visita em andamento.');
    PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_msg, 'comando_tel', 1);
    RETURN QUERY SELECT v_msg; RETURN;
  END IF;

  -- CORRETOR <telefone> / NAO CORRETOR <telefone> (Tel, 18/09/2026): a
  -- resposta dele ao "e corretor?" que a NAI manda quando alguem de fora dos
  -- grupos pergunta de imovel. A logica mora em nai_decidir_corretor (36c).
  m := regexp_match(s, '^(n[aã]o\s+)?corretor\s+(.+)$', 'i');
  IF m IS NOT NULL THEN
    v_msg := nai_decidir_corretor(m[2], m[1] IS NULL);
    RETURN QUERY SELECT v_msg; RETURN;
  END IF;

  -- ASSUMIR <telefone> / DEVOLVER <telefone>: o Tel pega ou devolve a conversa.
  m := regexp_match(s, '^(assumir|devolver)\s+(.+)$', 'i');
  IF m IS NOT NULL THEN
    IF nai_chave(m[2]) IS NULL THEN
      v_msg := 'Não entendi o telefone. Use: ASSUMIR 92 99999-8888  ou  DEVOLVER 92 99999-8888';
    ELSIF lower(m[1]) = 'assumir' THEN
      PERFORM nai_contato_do_cadastro(m[2], NULL);
      UPDATE nai_contato SET humano_assumiu_em = coalesce(humano_assumiu_em, now()), humano_motivo = 'comando ASSUMIR do Tel'
       WHERE chave = nai_chave(m[2]);
      v_msg := 'Feito: a conversa com ' || nai_fone_fmt(m[2]) || ' é sua. A NAI não manda mais nada para essa pessoa até você mandar DEVOLVER ' || btrim(m[2]) || '.';
    ELSE
      -- DEVOLVER COM RESPOSTA (Tel, 16/09). Ele escreveu "Devolver (92)
      -- 98807-8540 é apartamento" logo depois de a Nay ter subido a pergunta da
      -- Martinha -- e "é apartamento" era a RESPOSTA para ela, nao um comentario
      -- para a Nay. Nas palavras dele: "quando ele fala devolver, é para a Nay
      -- mandar para a pessoa".
      --
      -- O telefone sai da frente do texto, e o que sobra e a resposta. Sem
      -- sobra nenhuma, o comando continua sendo so a devolucao da conversa, do
      -- jeito que sempre foi.
      DECLARE
        v_resp text;
        v_dest bigint;
      BEGIN
        v_resp := btrim(regexp_replace(m[2], '^[\s(]*\+?[\d()\s.-]{8,}', ''));
        UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL
         WHERE chave = nai_chave(m[2])
        RETURNING id INTO v_dest;

        IF nullif(v_resp, '') IS NOT NULL AND v_dest IS NOT NULL THEN
          PERFORM nai_enfileirar_texto(p_turno, NULL, v_dest, 'entrega',
            nai_frase_maiuscula(v_resp), 'resposta_do_tel', 2);
          v_msg := 'Entreguei para ' || nai_fone_fmt(m[2]) || ': "' || v_resp
                   || '". E a NAI volta a atender essa conversa.';
        ELSE
          v_msg := 'Feito: a NAI volta a atender ' || nai_fone_fmt(m[2]) || '.';
        END IF;
      END;
    END IF;
    PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_msg, 'comando_tel', 1);
    RETURN QUERY SELECT v_msg; RETURN;
  END IF;

  m := regexp_match(s, '^acesso\s+(\d{3,5})\s+(.+)$', 'i');
  IF m IS NOT NULL THEN
    v_ac := nai_acesso_normalizar(m[2]);
    IF v_ac IS NULL OR NOT EXISTS (SELECT 1 FROM imoveis WHERE codigo = m[1]::int) THEN
      v_msg := 'Não entendi. Use: ACESSO 5611 chave com a gente / buscar a chave na portaria / fechadura / proprietário abre';
    ELSE
      INSERT INTO nai_acesso_imovel (codigo, acesso, detalhe, fonte) VALUES (m[1]::int, v_ac, m[2], 'tel')
      ON CONFLICT (codigo) DO UPDATE SET acesso = EXCLUDED.acesso, detalhe = EXCLUDED.detalhe, fonte = 'tel', atualizado_em = now();
      v_msg := 'Guardei: no ' || nai_ref_imovel(m[1]::int) || ' o acesso é ' || v_ac || '.';
    END IF;
    PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_msg, 'comando_tel', 1);
    RETURN QUERY SELECT v_msg; RETURN;
  END IF;

  -- IMOVEL ALUGADO / VENDIDO (Tel, 22/09/2026): "o Tel vai te passar quando um
  -- imovel for alugado, tu torna ele indisponivel, prepara o sistema para
  -- receber isso, do whatsapp dele". Aceita varios codigos na mesma mensagem
  -- ("ALUGADO 5727 e 5733") e a volta atras ("DISPONIVEL 5727").
  m := regexp_match(s, '^(alugad[oa]|alugou|aluguei|vendid[oa]|vendeu|vendi|indisponivel|indispon[ií]vel|dispon[ií]vel|disponibiliza|liberar?|voltou)\s+(.*)$', 'i');
  IF m IS NOT NULL THEN
    v_msg := nai_marcar_imovel(m[1], m[2], 'Tel pelo WhatsApp');
    PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_msg, 'comando_tel', 1);
    RETURN QUERY SELECT v_msg; RETURN;
  END IF;

  m := regexp_match(s, '^visita\s+#?(\d+)\s+(.*)$', 'i');
  IF m IS NULL THEN RETURN QUERY SELECT NULL::text; RETURN; END IF;
  SELECT * INTO v FROM nai_visita WHERE id = m[1]::bigint FOR UPDATE;
  IF v.id IS NULL OR NOT nai_visita_aberta(v.estado) THEN
    v_msg := 'Não achei a visita #' || m[1] || ' em andamento. Mande VISITAS para ver a lista.';
    PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_msg, 'comando_tel', 1);
    RETURN QUERY SELECT v_msg; RETURN;
  END IF;

  IF unaccent(m[2]) ~* ('^(fernando|motoboy|' || lower(unaccent(nai_acompanhante())) || ')\s+(ok|confirm)') THEN
    UPDATE nai_visita SET moto_ok_em = now() WHERE id = v.id RETURNING * INTO v;
    IF v.prop_ok_em IS NOT NULL THEN PERFORM nai_confirmar_visita(v.id, p_turno); END IF;
    v_msg := 'Feito: ' || nai_acompanhante() || ' confirmado na visita #' || v.id || CASE WHEN v.prop_ok_em IS NOT NULL THEN '. Confirmei ao corretor.' ELSE '. Ainda falta o proprietário.' END;
  ELSIF m[2] ~* '^(ok|confirm|pode)' THEN
    UPDATE nai_visita SET prop_ok_em = now(), quando = coalesce(quando_sugerido, quando) WHERE id = v.id;
    PERFORM nai_evento(v.id, 'tel_confirmou_proprietario', NULL);
    IF (SELECT acesso FROM nai_visita WHERE id = v.id) IS NULL AND NOT EXISTS (SELECT 1 FROM nai_acesso_imovel WHERE codigo = v.codigo) THEN
      UPDATE nai_visita SET acesso_detalhe = 'combinado pelo Tel' WHERE id = v.id;
    END IF;
    -- Sem conversa com o proprietario (foi o Tel): segue direto para o Fernando.
    IF v.proprietario_id IS NULL OR v.estado = 'com_tel' THEN
      UPDATE nai_visita SET acesso = coalesce(acesso, (SELECT acesso FROM nai_acesso_imovel WHERE codigo = v.codigo)) WHERE id = v.id;
      UPDATE nai_visita SET estado = 'aguardando_acesso' WHERE id = v.id AND acesso IS NULL;
      IF (SELECT acesso FROM nai_visita WHERE id = v.id) IS NULL THEN
        v_msg := 'Anotado o OK do proprietário na visita #' || v.id || '. Como é o acesso? Responda: ACESSO ' || v.codigo || ' chave com a gente / buscar a chave / fechadura / proprietário abre — e depois VISITA ' || v.id || ' OK de novo.';
        PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_msg, 'comando_tel', 1);
        RETURN QUERY SELECT v_msg; RETURN;
      END IF;
      UPDATE nai_visita SET senha = coalesce(senha, 'com o Tel') WHERE id = v.id AND acesso = 'fechadura';
      UPDATE nai_visita SET acesso_detalhe = coalesce(acesso_detalhe, 'combinado pelo Tel') WHERE id = v.id AND acesso = 'buscar_chave';
    END IF;
    PERFORM nai_prosseguir_acesso(v.id, p_turno, false);
    v_msg := 'Feito: visita #' || v.id || ' com o OK do proprietário. Estou chamando o ' || nai_acompanhante() || '.';
  ELSIF m[2] ~* '^cancel' THEN
    UPDATE nai_visita SET estado = 'cancelada', aguardando = NULL, motivo = 'Tel: ' || m[2], senha = NULL,
                          encerrada_em = now(), atualizado_em = now() WHERE id = v.id;
    PERFORM nai_evento(v.id, 'cancelada_pelo_tel', m[2]);
    PERFORM nai_enfileirar_texto(p_turno, v.id, v.corretor_id, 'corretor',
      coalesce(nai_vocativo((SELECT coalesce(nome_completo, nome_whatsapp) FROM nai_contato WHERE id = v.corretor_id)) || ', ', '') ||
      'a visita de ' || nai_quando_humano(v.quando) || ' no ' || nai_ref_imovel(v.codigo) ||
      ' não vai dar certo. Quer que eu veja outro horário?', 'cancelada_pelo_tel', 400);
    IF v.motoboy_id IS NOT NULL AND (v.moto_ok_em IS NOT NULL OR v.ult_msg_moto_em IS NOT NULL) THEN
      PERFORM nai_enfileirar_texto(p_turno, v.id, v.motoboy_id, 'motoboy',
        '' || nai_acompanhante() || ', a visita do ' || nai_ref_imovel(v.codigo) || ' de ' || nai_hora_exata(v.quando) || ' foi cancelada.', 'cancelada', 600);
    END IF;
    v_msg := 'Feito: visita #' || v.id || ' cancelada e o corretor avisado.';
  -- VISITA <id> REMARCA <quando> (Tel, 15/09): "remarcar uma visita manualmente
  -- pelo whatsapp dele". NAO e o HORARIO logo abaixo: aquele PERGUNTA ao
  -- corretor se o horario novo serve (e a negociacao que veio do proprietario);
  -- este e decisao do Tel -- muda a hora e comunica os tres.
  ELSIF m[2] ~* '^remarc' THEN
    q := nai_ler_hora_tel(m[2], v.quando);
    IF q IS NULL OR q <= now() THEN
      v_msg := 'Não entendi o horário. Use: VISITA ' || v.id || ' REMARCA 16h  ou  VISITA ' || v.id || ' REMARCA 18/09 16h';
    ELSE
      -- Os carimbos de aviso voltam a zero: senao a agenda entenderia que ja
      -- avisou desta visita e ninguem seria lembrado no horario novo.
      UPDATE nai_visita
         SET quando = q, quando_sugerido = NULL, atualizado_em = now(),
             aviso_motoboy_em = NULL, lembrete_1h_em = NULL, lembrete_periodo_em = NULL,
             aviso_tel_em = NULL, pos_visita_em = NULL
       WHERE id = v.id;
      PERFORM nai_evento(v.id, 'tel_remarcou', nai_hora_exata(q));
      PERFORM nai_enfileirar_texto(p_turno, v.id, v.corretor_id, 'corretor',
        coalesce(nai_vocativo((SELECT coalesce(nome_completo, nome_whatsapp) FROM nai_contato WHERE id = v.corretor_id)) || ', ', '') ||
        'a visita ao ' || nai_ref_imovel(v.codigo) || ' foi remarcada para ' || nai_quando_humano(q) || '.',
        'tel_remarcou', 400);
      IF v.proprietario_id IS NOT NULL THEN
        PERFORM nai_enfileirar_texto(p_turno, v.id, v.proprietario_id, 'proprietario',
          -- `nai_ref_imovel_prop` ja devolve "no seu imovel do X": sem isto sai
          -- "A visita ao no seu imovel do X".
          'A visita ' || nai_ref_imovel_prop(v.codigo) || ' foi remarcada para ' || nai_quando_humano(q) || '.',
          'tel_remarcou', 420);
      END IF;
      IF v.motoboy_id IS NOT NULL AND (v.moto_ok_em IS NOT NULL OR v.ult_msg_moto_em IS NOT NULL) THEN
        PERFORM nai_enfileirar_texto(p_turno, v.id, v.motoboy_id, 'motoboy',
          '' || nai_acompanhante() || ', a visita do ' || nai_ref_imovel(v.codigo) || ' passou para ' || nai_hora_exata(q) || '.',
          'tel_remarcou', 440);
      END IF;
      v_msg := 'Feito: visita #' || v.id || ' remarcada para ' || nai_hora_exata(q) || '. Avisei o corretor'
               || CASE WHEN v.proprietario_id IS NOT NULL THEN ', o proprietário' ELSE '' END
               || CASE WHEN v.motoboy_id IS NOT NULL AND (v.moto_ok_em IS NOT NULL OR v.ult_msg_moto_em IS NOT NULL)
                       THEN ' e o ' || nai_acompanhante() || '' ELSE '' END || '.';
    END IF;
  ELSIF m[2] ~* '^hor' THEN
    q := nai_ler_hora_tel(m[2], v.quando);
    IF q IS NULL OR q <= now() THEN
      v_msg := 'Não entendi o horário. Use: VISITA ' || v.id || ' HORARIO 16h  ou  VISITA ' || v.id || ' HORARIO 13/09 16h';
    ELSE
      UPDATE nai_visita SET quando_sugerido = q, estado = 'negociando', aguardando = 'corretor', atualizado_em = now() WHERE id = v.id;
      PERFORM nai_evento(v.id, 'tel_sugeriu_horario', nai_hora_exata(q));
      -- Mesmo card p_repassa do caminho do proprietario: com o tratamento
      -- ("Sr. Pedro, o proprietario nao consegue..."). No teste ao vivo de 13/09
      -- saia sem tratamento e com letra minuscula quando quem mandava era o Tel.
      PERFORM nai_enfileirar_texto(p_turno, v.id, v.corretor_id, 'corretor',
        coalesce(nai_vocativo((SELECT coalesce(nome_completo, nome_whatsapp) FROM nai_contato WHERE id = v.corretor_id)) || ', ', '') ||
        'o proprietário não consegue ' || nai_quando_humano(v.quando) || ', mas sugeriu ' || nai_quando_humano(q) || '. Funciona pro seu cliente?',
        'tel_sugeriu', 400);
      v_msg := 'Feito: perguntei ao corretor se ' || nai_hora_exata(q) || ' serve.';
    END IF;
  ELSIF m[2] ~* '^avis' THEN
    q := nai_ler_hora_tel(m[2], now());
    IF q IS NULL OR q <= now() THEN
      v_msg := 'Não entendi a hora. Use: VISITA ' || v.id || ' AVISA 10h';
    ELSE
      UPDATE nai_visita SET proximo_aviso_prop_em = q WHERE id = v.id;
      -- Card "Acionar o Tel" (2h antes): a resposta dele devolve a visita ao proprietario.
      UPDATE nai_visita SET estado = 'aguardando_proprietario', aguardando = 'proprietario', atualizado_em = now()
       WHERE id = v.id AND estado = 'com_tel' AND proprietario_id IS NOT NULL AND prop_ok_em IS NULL;
      v_msg := 'Combinado: mando o próximo aviso ao proprietário ' || nai_hora_exata(q) || '. Se ele não responder em ' ||
               nai_cfg_int('reenvio_proprietario_min', 30) || ' minutos, te aviso para ligar.';
    END IF;
  ELSE
    v_msg := 'Comandos: VISITAS · AGENDA DE VISITAS · VISITA ' || v.id || ' OK · VISITA ' || v.id || ' CANCELA · VISITA ' || v.id ||
             ' REMARCA 16h · VISITA ' || v.id || ' HORARIO 16h · VISITA ' || v.id || ' AVISA 10h · VISITA ' || v.id ||
             ' ' || nai_acompanhante_maiusculo() || ' OK · ACESSO <código> <como> · ASSUMIR <telefone> · DEVOLVER <telefone> · PARAR ATENDIMENTO · VOLTAR ATENDIMENTO';
  END IF;
  -- Quando o fluxo para, a Nay para os chats (13/09); o comando do Tel sobre a
  -- visita e o "pode seguir": volta a atender quem estava parado por ELA.
  IF v_msg NOT LIKE 'Comandos:%' AND v_msg NOT LIKE 'Não entendi%' THEN
    v_lib := nai_liberar_chats_da_visita(v.id);
    IF v_lib > 0 THEN v_msg := v_msg || ' Voltei a atender quem estava parado por essa visita.'; END IF;
  END IF;
  PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_msg, 'comando_tel', 1);
  RETURN QUERY SELECT v_msg;
END;
$function$;

CREATE OR REPLACE FUNCTION public.nai_saida_validar()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_chave text;
  v record;
  t record;
  v_cod int;
  v_ja  timestamptz;
BEGIN
  SELECT chave INTO v_chave FROM nai_contato WHERE id = NEW.contato_id;
  IF v_chave IS NULL THEN
    RAISE EXCEPTION 'NAI saida: contato % nao existe', NEW.contato_id;
  END IF;
  -- O destino e SEMPRE a chave do contato. Quem enfileira nao escolhe.
  NEW.chave_destino := v_chave;

  IF NEW.visita_id IS NOT NULL THEN
    SELECT * INTO v FROM nai_visita WHERE id = NEW.visita_id;
  END IF;
  IF NEW.turno_id IS NOT NULL THEN
    SELECT * INTO t FROM nai_turno WHERE id = NEW.turno_id;
  END IF;

  IF NEW.papel_destino = 'turno' THEN
    -- Resposta: so para quem escreveu aquele turno.
    IF t.id IS NULL OR t.contato_id <> NEW.contato_id THEN
      RAISE EXCEPTION 'NAI saida: resposta do turno % para contato % que nao e o autor', NEW.turno_id, NEW.contato_id;
    END IF;
  ELSIF NEW.papel_destino = 'entrega' THEN
    -- O TEL FALANDO PELA NAY (Tel, 16/09): o `DEVOLVER <telefone> <resposta>`
    -- precisa mandar texto para quem NAO escreveu aquele turno -- quem escreveu
    -- foi o Tel. A trava do papel 'turno' barrava, e estava certa.
    --
    -- Entao este papel tem trava propria: so sai de um turno cujo papel e
    -- 'tel'. Sem essa exigencia, qualquer funcao poderia mandar mensagem para
    -- qualquer pessoa do cadastro, que e o tipo de porta que nao se abre.
    IF t.id IS NULL OR t.papel <> 'tel' THEN
      RAISE EXCEPTION 'NAI saida: entrega so sai de um comando do Tel (turno %)', NEW.turno_id;
    END IF;
  ELSIF NEW.papel_destino = 'corretor' THEN
    IF v.id IS NULL OR v.corretor_id <> NEW.contato_id THEN
      RAISE EXCEPTION 'NAI saida: contato % nao e o corretor da visita %', NEW.contato_id, NEW.visita_id;
    END IF;
  ELSIF NEW.papel_destino = 'proprietario' THEN
    IF v.id IS NULL OR v.proprietario_id IS DISTINCT FROM NEW.contato_id THEN
      RAISE EXCEPTION 'NAI saida: contato % nao e o proprietario da visita %', NEW.contato_id, NEW.visita_id;
    END IF;
  ELSIF NEW.papel_destino = 'motoboy' THEN
    IF v.id IS NULL OR v.motoboy_id IS DISTINCT FROM NEW.contato_id OR NOT nai_e_motoboy(v_chave) THEN
      RAISE EXCEPTION 'NAI saida: contato % nao e o acompanhante da visita %', NEW.contato_id, NEW.visita_id;
    END IF;
  ELSIF NEW.papel_destino = 'tel' THEN
    IF v_chave IS DISTINCT FROM nai_chave(nai_cfg('tel_telefone')) THEN
      RAISE EXCEPTION 'NAI saida: contato % nao e o Tel', NEW.contato_id;
    END IF;
  END IF;

  -- IMOVEL DE PARCERIA NAO SAI DAQUI (Tel, 16/09): "a Nay enviou um imovel de
  -- parceiro; esses imoveis de parceiros nao e pra enviar, quero eles em
  -- blacklist, so listados no site mas nunca enviados".
  --
  -- O QUE ACONTECEU: as 13:46 ela mandou 13 fotos do 3649 (Vitali Residencial,
  -- Alvorada) e ainda disse que estava disponivel. O card ja sabia da regra --
  -- `nai_card_do_imovel` devolve aviso de parceria e ZERO fotos --, mas as
  -- fotos saem por outro caminho, e ali ninguem perguntava de quem era o
  -- imovel.
  --
  -- ESTA E A ULTIMA PAREDE, no gatilho por onde toda saida passa: cobre o card,
  -- a foto, a lista e qualquer caminho que venha a existir. Sao 908 imoveis de
  -- parceria no catalogo, 566 deles no mercado -- a maior parte da base --,
  -- entao a regra precisa valer por baixo, nao so na boa vontade do modelo.
  --
  -- NAO LEVANTA EXCECAO: a saida e gravada como 'bloqueado', com o motivo. Fica
  -- o rastro no painel de envios, e o resto da resposta segue viva -- estourar
  -- aqui derrubaria a mensagem inteira, inclusive o que podia ser dito.
  --
  -- O TEL CONTINUA RECEBENDO: e por ele que a parceria anda.
  IF NEW.codigo IS NOT NULL
     AND NEW.papel_destino <> 'tel'
     AND EXISTS (SELECT 1 FROM imoveis i
                  WHERE i.codigo = NEW.codigo AND coalesce(i.e_parceiro, false)) THEN
    NEW.estado   := 'bloqueado';
    NEW.bloqueio := 'imovel de parceria: so no site, nunca enviado';
    RETURN NEW;
  END IF;

  -- UM IMOVEL POR CORRETOR POR DIA (27/09/2026): "enviar somente uma vez um
  -- imovel ao corretor por dia... isso nunca pode acontecer mais". Naquele
  -- dia o 3210 chegou TRES vezes ao 92 8110-1119 a partir de um unico pedido
  -- do Tel. Ver o cabecalho da 131.
  --
  -- Aqui pega o que sai pela NAI: a foto (que traz o codigo) e o CARD (texto
  -- com o alfinete e UM "Codigo: NNNN" -- lista com varios codigos nao e card
  -- e segue). A mesma resposta continua passando inteira: o card e as fotos
  -- sao linhas separadas do mesmo turno, e a reserva e do turno.
  --
  -- Foto repetida fica 'bloqueado', com o rastro no painel de envios. Card
  -- repetido vira a frase dizendo que ja foi e a hora -- sumir calado seria
  -- pior do que avisar.
  IF NEW.papel_destino <> 'tel' AND nai_cfg('envio_simulado', 'nao') <> 'sim' THEN
    v_cod := NEW.codigo;
    IF v_cod IS NULL AND NEW.tipo = 'texto'
       AND position('📍' IN coalesce(NEW.texto, '')) > 0
       AND (SELECT count(*) FROM regexp_matches(NEW.texto, 'C[óo]digo:\s*\d{3,5}', 'gi')) = 1 THEN
      v_cod := (regexp_match(NEW.texto, 'C[óo]digo:\s*(\d{3,5})', 'i'))[1]::int;
    END IF;
    IF v_cod IS NOT NULL THEN
      v_ja := nay_reservar_imovel_do_dia(v_chave, v_cod, 'nai', NEW.turno_id);
      IF v_ja IS NOT NULL THEN
        IF NEW.tipo = 'imagem' THEN
          NEW.estado   := 'bloqueado';
          NEW.bloqueio := 'imovel ja enviado a este corretor nas ultimas 24h ('
                          || nay_quando_foi(v_ja) || ')';
          RETURN NEW;
        END IF;
        NEW.texto := 'O ' || v_cod || ' eu já mandei ' || nay_quando_foi(v_ja)
                     || ', está aqui em cima na conversa.';
      END IF;
    END IF;
  END IF;

  IF NEW.tipo = 'imagem' THEN
    -- Foto so para corretor, e so a foto que o banco diz ser DAQUELE imovel.
    -- 'entrega' (135): o card pedido pela equipe vai com as fotos. O papel so
    -- sai de turno de comando (papel 'tel'), conferido la em cima.
    IF NEW.papel_destino NOT IN ('turno', 'corretor', 'entrega')
       OR (NEW.papel_destino = 'turno' AND t.papel NOT IN ('corretor', 'tel')) THEN
      RAISE EXCEPTION 'NAI saida: foto so vai para corretor';
    END IF;
    -- A COLAGEM conta como imagem daquele imovel (Tel, 12/09): ela e nossa,
    -- montada das 4 primeiras fotos, e mora em `imovel_colagem`, nao em
    -- `imovel_fotos`. O resto da parede continua igual: url que nao esteja
    -- num dos dois lugares nao sai.
    IF NOT EXISTS (SELECT 1 FROM imovel_fotos f WHERE f.codigo = NEW.codigo AND f.url = NEW.imagem_url)
       AND NOT EXISTS (SELECT 1 FROM imovel_colagem c WHERE c.codigo = NEW.codigo AND c.url = NEW.imagem_url) THEN
      RAISE EXCEPTION 'NAI saida: a foto % nao e do imovel %', NEW.imagem_url, NEW.codigo;
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.nai_liberar_saida(p_turno bigint)
 RETURNS TABLE(id bigint, rota text, telefone text, chave_esperada text, corpo jsonb, codigo integer, papel text, redirecionado boolean)
 LANGUAGE plpgsql
AS $function$
#variable_conflict use_column
DECLARE
  r          record;
  v_modo     text := nai_cfg('modo', 'desligado');
  v_pausada  boolean := nai_cfg('pausada', 'sim') <> 'nao';
  -- ESPELHO DO TREINO NUNCA SAI (92): a trava geral OU o destino ser o
  -- espelho. Com a Nay no ar, e o que permite testar sem calar ninguem.
  v_simulado boolean := nai_cfg('envio_simulado', 'nao') = 'sim'
                        OR nai_chave((SELECT c.telefone FROM nai_turno t
                                        JOIN nai_contato c ON c.id = t.contato_id
                                       WHERE t.id = p_turno))
                           = nai_chave(nai_cfg('treino_espelho', ''));
  v_testes   text[] := nai_chaves_teste();
  v_destino  text := nai_fone_envio(nai_cfg('telefone_teste_destino', ''));
  v_tel      text;
  v_texto    text;
  v_chave_c  text;
  v_bloq     text;
  v_redir    boolean;
  v_papel_t  text;
  v_etiqueta text;
  v_nome     text;
  -- PROPRIETARIO PELO TEL (Tel, 19/09) -- ver o bloco la embaixo.
  v_prop_tel boolean := nai_cfg('proprietario_pelo_tel', 'nao') = 'sim';
  v_fone_prop text;
  v_v        record;
  v_cmd      boolean;   -- e a resposta a um comando de quem pode comandar?
  v_simulado_linha boolean;   -- a trava do espelho, calculada por MENSAGEM (113b)
BEGIN
  FOR r IN
    SELECT s.* FROM nai_saida s
     WHERE s.estado = 'pendente'
       AND s.enviar_apos <= now()
       AND ((p_turno IS NOT NULL AND s.turno_id = p_turno)
         OR (p_turno IS NULL AND (s.turno_id IS NULL OR s.criado_em < now() - interval '3 minutes'
                                   -- com hora marcada (113): e o texto que espera as fotos
                                   OR s.enviar_apos > s.criado_em + interval '1 second')
             AND (nai_dentro_da_janela() OR s.papel_destino = 'tel')))
     ORDER BY s.id
     LIMIT 80
     FOR UPDATE SKIP LOCKED
  LOOP
    v_bloq := NULL; v_redir := false; v_texto := r.texto; v_etiqueta := NULL;
    SELECT k.chave, k.telefone, coalesce(k.nome_completo, k.nome_whatsapp)
      INTO v_chave_c, v_tel, v_nome FROM nai_contato k WHERE k.id = r.contato_id;

    -- RESPOSTA A COMANDO: volta para quem mandou, sempre. Nao e redirecionada
    -- no modo teste (senao a resposta do Tel cairia no chat do Pedro) e nao e
    -- barrada pela pausa (senao PARAR ATENDIMENTO ficaria sem confirmacao --
    -- medido em 15/09: saiu 'bloqueado' com motivo nai_pausada, e ele nao
    -- soube se tinha funcionado). Vale so para o texto que a propria funcao de
    -- comando escreveu, indo para um telefone de `comando_telefones`.
    -- O ESPELHO NUNCA SAI (92), agora conferido NESTA mensagem: pela
    -- agenda nao existe turno, e a trava calculada no topo dava falso.
    v_simulado_linha := v_simulado
      OR nai_chave(v_tel) = nai_chave(nai_cfg('treino_espelho', ''))
      OR nai_chave(v_chave_c) = nai_chave(nai_cfg('treino_espelho', ''));

    v_cmd := r.motivo = 'comando_tel' AND r.papel_destino = 'turno'
             AND nai_pode_comandar(v_chave_c);

    IF v_modo NOT IN ('teste', 'todos') THEN
      v_bloq := 'nai_desligada';
    ELSIF v_pausada AND NOT v_cmd THEN
      v_bloq := 'nai_pausada';
    ELSIF v_chave_c IS DISTINCT FROM r.chave_destino THEN
      v_bloq := 'contato_mudou';
    ELSIF r.papel_destino <> 'tel'
          -- 16/09: mesma leitura da porta e da abertura do turno.
          AND nai_tel_com_a_conversa(r.contato_id)
          -- 135: a ENTREGA pedida pela equipe tambem passa. Quem pediu para
          -- mandar o imovel ao cliente foi a propria equipe -- inclusive quando
          -- o Tel esta conversando com ele.
          AND NOT (r.papel_destino IN ('turno', 'entrega') AND (SELECT t2.papel FROM nai_turno t2 WHERE t2.id = r.turno_id) = 'tel') THEN
      -- O TEL ASSUMIU esse chat: a NAI nao manda mais nada para essa pessoa
      -- (so a resposta a um comando do proprio Tel passa).
      v_bloq := 'tel_assumiu';
    ELSIF r.tipo = 'imagem'
          AND NOT EXISTS (SELECT 1 FROM imovel_fotos f WHERE f.codigo = r.codigo AND f.url = r.imagem_url)
          -- A COLAGEM tambem e imagem legitima daquele imovel (Tel, 12/09): ela
          -- nao esta em `imovel_fotos` -- e montada por nos e mora em
          -- `imovel_colagem`. Sem esta linha, toda colagem sairia bloqueada
          -- como "foto_nao_confere", que e a trava contra mandar a foto de um
          -- imovel no card de outro.
          AND NOT EXISTS (SELECT 1 FROM imovel_colagem c WHERE c.codigo = r.codigo AND c.url = r.imagem_url) THEN
      v_bloq := 'foto_nao_confere';
    -- REPETIDA: o mesmo texto para a mesma pessoa em 10 minutos não sai de novo.
    -- EXCEÇÃO (Tel, 14/09): as frases do "depois das fotos" são passo do
    -- roteiro, não repetição do modelo. Ela mandou a sugestão de visita às
    -- 20:12 e as fotos às 20:17 -- e "Ou se tiver alguma dúvida ou quiser mais
    -- imóveis..." saiu BLOQUEADA como repetida, logo depois das fotos.
    -- ...e só conta o que saiu DEPOIS do marco de conversa zerada (14/09): o
    -- pré-voo mandou as frases da sugestão em modo simulado, a conversa foi
    -- zerada, e no teste seguinte a mesma sugestão saiu BARRADA como repetida.
    -- Conversa zerada é conversa nova, também para esta trava.
    -- ...e mensagem de VISITA só é repetida se for da MESMA visita (14/09): dois
    -- pedidos de visita seguidos ao mesmo proprietário, com o mesmo texto, são
    -- duas visitas -- o segundo saía barrado e o proprietário nunca sabia.
    -- ...e RESPOSTA A COMANDO nunca e repetida (Tel, 15/09): ele mandou
    -- "agenda de visitas" duas vezes, a agenda estava igual, e a segunda saiu
    -- BLOQUEADA como repetida -- que e exatamente o sintoma de "ela nao
    -- respondeu" que ele relatou. Comando pedido duas vezes e respondido duas
    -- vezes.
    ELSIF r.tipo = 'texto' AND NOT v_cmd AND coalesce(r.motivo, '') <> 'depois_das_fotos' AND EXISTS (
            SELECT 1 FROM nai_saida s2
             WHERE s2.contato_id = r.contato_id AND s2.estado IN ('enviado', 'simulado', 'enviando')
               AND s2.tipo = 'texto' AND s2.texto = r.texto
               AND s2.visita_id IS NOT DISTINCT FROM r.visita_id
               AND coalesce(s2.enviado_em, s2.criado_em) > greatest(now() - interval '10 minutes',
                     coalesce((SELECT k3.zerado_em FROM nai_contato k3 WHERE k3.id = r.contato_id), '-infinity'::timestamptz))) THEN
      v_bloq := 'repetida';
    -- foto que ELE pediu de novo sai de novo (Tel, 22/09)
    ELSIF r.tipo = 'imagem'
      AND NOT coalesce((SELECT nai_pede_foto(coalesce(tt.texto, '')) FROM nai_turno tt WHERE tt.id = r.turno_id), false)
      AND EXISTS (
            SELECT 1 FROM nai_saida s2
             WHERE s2.contato_id = r.contato_id AND s2.estado IN ('enviado', 'simulado', 'enviando')
               AND s2.tipo = 'imagem' AND s2.imagem_url = r.imagem_url
               AND coalesce(s2.enviado_em, s2.criado_em) > greatest(now() - interval '10 minutes',
                     coalesce((SELECT k3.zerado_em FROM nai_contato k3 WHERE k3.id = r.contato_id), '-infinity'::timestamptz))) THEN
      v_bloq := 'repetida';
    END IF;

    -- MODO TESTE: o que iria para proprietario, Fernando ou Tel vai para o
    -- numero de teste, com a etiqueta de para quem iria.
    IF v_bloq IS NULL AND v_modo = 'teste' AND NOT v_cmd THEN
      IF r.papel_destino IN ('proprietario', 'motoboy', 'tel') THEN
        v_redir := true;
        v_etiqueta := '🧪 TESTE · iria para o ' ||
          CASE r.papel_destino WHEN 'proprietario' THEN 'PROPRIETÁRIO' WHEN 'motoboy' THEN '' || nai_acompanhante_maiusculo() || ' (motoboy)' ELSE 'TEL' END ||
          coalesce(' ' || v_nome, '') ||
          coalesce(' · visita #' || r.visita_id, '') || E'\n' ||
          CASE r.papel_destino
            WHEN 'proprietario' THEN 'Para responder como proprietário: MARQUE esta mensagem, ou comece com P:'
            WHEN 'motoboy' THEN 'Para responder como ' || nai_acompanhante() || ': MARQUE esta mensagem, ou comece com M:'
            ELSE 'Para responder como Tel: comece com T:' END || E'\n\n';
        v_tel := v_destino;
      ELSIF r.papel_destino = 'turno' THEN
        SELECT t.papel INTO v_papel_t FROM nai_turno t WHERE t.id = r.turno_id;
        IF v_papel_t IN ('proprietario', 'motoboy', 'tel') THEN
          v_etiqueta := '🧪 (resposta ao ' ||
            CASE v_papel_t WHEN 'proprietario' THEN 'PROPRIETÁRIO' WHEN 'motoboy' THEN '' || nai_acompanhante_maiusculo() || '' ELSE 'TEL' END || E')\n';
        END IF;
        -- TODAS AS MENSAGENS NO CHAT DELE (Tel, 13/09: "quero que as mensagens
        -- vao todas para mim, corretores, proprietarios e tal nesse teste"). O
        -- que iria para outro numero -- um corretor simulado, por exemplo --
        -- chega no numero de teste com a etiqueta de para quem iria. Antes isso
        -- morria como 'teste_fora_da_lista' e ele nao via a mensagem.
        IF nai_chave(v_tel) IS DISTINCT FROM nai_chave(v_destino) THEN
          v_redir := true;
          v_etiqueta := coalesce(v_etiqueta, '') || '🧪 TESTE · iria para o ' ||
            CASE coalesce(v_papel_t, 'corretor')
              WHEN 'proprietario' THEN 'PROPRIETÁRIO'
              WHEN 'motoboy' THEN '' || nai_acompanhante_maiusculo() || ' (motoboy)'
              WHEN 'tel' THEN 'TEL'
              ELSE 'CORRETOR' END ||
            coalesce(' ' || v_nome, '') || ' ' || nai_fone_fmt(v_tel) || E'\n\n';
          v_tel := v_destino;
        END IF;
      END IF;
      -- PAREDE DO TESTE: nada sai para numero fora da lista de teste.
      IF NOT (nai_chave(v_tel) = ANY (v_testes)) THEN
        v_bloq := 'teste_fora_da_lista';
      END IF;
    END IF;

    -- ---------------------------------------------------------------
    -- PROPRIETARIO PELO TEL (Tel, 19/09): "so as mensagens para
    -- proprietarios estao temporariamente bloqueadas, entao elas vao para o
    -- Tel". O proprietario NAO recebe nada; o Tel recebe o nome e o numero
    -- de quem ele precisa ligar.
    --
    -- Isto NAO e o modo teste: vale em producao (`modo = todos`), e o desvio
    -- do teste continua mandando tudo para o numero de teste, como antes.
    --
    -- O aviso carrega o comando de volta (`VISITA <id> OK`). Sem ele a visita
    -- fica parada para sempre: a Nay pergunta, o Tel liga para o dono, e nao
    -- tem como dizer a ela que o dono confirmou.
    --
    -- `ult_msg_prop_em` continua sendo carimbado no `nai_confirmar_envio`,
    -- de proposito: e o relogio que espaca os lembretes. Sem o carimbo, o
    -- ciclo remarcaria o passo do proprietario na hora e encheria o Tel de
    -- mensagens iguais. E o mesmo que o modo teste ja faz ao redirecionar.
    -- ---------------------------------------------------------------
    IF v_bloq IS NULL AND v_modo = 'todos' AND v_prop_tel
       AND r.papel_destino = 'proprietario' THEN
      SELECT * INTO v_v FROM nai_visita WHERE id = r.visita_id;
      IF r.tipo <> 'texto' OR v_v.id IS NULL THEN
        -- Foto para proprietario nao existe (o gatilho barra na insercao). Se
        -- um dia existir, ela para aqui em vez de virar um desvio improvisado.
        v_bloq := 'prop_pelo_tel_sem_texto';
      ELSE
        v_fone_prop := v_tel;
        v_redir     := true;
        v_tel       := nai_fone_envio(nai_cfg('tel_telefone'));
        v_texto     := 'Visita agendada, pergunte ao proprietário '
          || coalesce(nullif(btrim(coalesce(v_nome, '')), ''),
                      nullif(btrim(coalesce(v_v.proprietario_nome, '')), ''),
                      'do imóvel ' || v_v.codigo)
          || ' de número ' || nai_fone_fmt(v_fone_prop)
          || ' se a visita ' || coalesce(nai_quando_humano(coalesce(v_v.quando, v_v.quando_sugerido)),
                                         'no horário combinado')
          || ' pode ser realizada.'
          || E'\n\nImóvel ' || v_v.codigo || ' · visita #' || v_v.id
          || E'\nMe responda: VISITA ' || v_v.id || ' OK (proprietário confirmou) · VISITA '
          || v_v.id || ' CANCELA · VISITA ' || v_v.id || ' REMARCA 16h'
          || E'\n\n— o que eu ia mandar para ele:\n' || r.texto;
      END IF;
    END IF;

    IF v_bloq IS NOT NULL THEN
      UPDATE nai_saida s SET estado = 'bloqueado', bloqueio = v_bloq, telefone_final = v_tel, enviado_em = now()
       WHERE s.id = r.id;
      CONTINUE;
    END IF;

    IF r.tipo = 'texto' AND v_etiqueta IS NOT NULL THEN
      v_texto := v_etiqueta || v_texto;
    END IF;

    IF v_simulado_linha THEN
      UPDATE nai_saida s SET estado = 'simulado', telefone_final = v_tel, redirecionado = v_redir,
                             enviado_em = now(), resposta = jsonb_build_object('texto_final', v_texto)
       WHERE s.id = r.id;
      IF r.visita_id IS NOT NULL AND r.papel_destino = 'proprietario' THEN
        UPDATE nai_visita SET ult_msg_prop_em = now() WHERE nai_visita.id = r.visita_id;
      ELSIF r.visita_id IS NOT NULL AND r.papel_destino = 'motoboy' THEN
        UPDATE nai_visita SET ult_msg_moto_em = now() WHERE nai_visita.id = r.visita_id;
      END IF;
      CONTINUE;
    END IF;

    UPDATE nai_saida s SET estado = 'enviando', telefone_final = v_tel, redirecionado = v_redir
     WHERE s.id = r.id;

    id := r.id;
    rota := CASE r.tipo WHEN 'imagem' THEN 'send-image' ELSE 'send-text' END;
    telefone := v_tel;
    chave_esperada := nai_chave(v_tel);
    corpo := CASE r.tipo
               WHEN 'imagem' THEN jsonb_build_object('phone', v_tel, 'image', r.imagem_url)
               ELSE jsonb_build_object('phone', v_tel, 'message', v_texto) END;
    codigo := r.codigo;
    papel := r.papel_destino;
    redirecionado := v_redir;
    RETURN NEXT;
  END LOOP;
END;
$function$;

COMMIT;
