-- 215 (revisão de 30/09/2026, pedido do Pedro: "revisa tudo que foi implementado
-- para nada dar errado, a Nay desobedecer regras ou esquecer do fluxo de
-- identificação antes de mandar um imóvel"). Os achados da revisão do código:
--
-- A. O FILTRO NÃO PULA PERGUNTA (nai_buscar_por_perfil)
--    1. Tirado o "sem bairro na chamada, vale o lugar do texto" da 206: um card
--       colado do grupo com "Eldorado Park", ou "moro no conjunto Kissia", virava
--       região e pulava a pergunta do bairro (e, com poucos imóveis, a do valor).
--    2. "TANTO FAZ" VALE SÓ PARA A PERGUNTA QUE ELA FEZ. Respondendo "tanto faz" a
--       "casa ou apartamento?", a mesma frase marcava também "sem valor" e "qualquer
--       bairro" -- e a Nay listava a cidade inteira sem perguntar valor nem região.
--       Agora a última pergunta do filtro (24 h) diz a que o "tanto faz" responde.
--       Frase explícita continua valendo sempre: "sem valor", "o cliente não disse
--       o valor", "qualquer bairro", "tanto faz casa ou apartamento", "os dois".
-- B. A BIBLIOTECA DE LUGARES NÃO EMPURRA A BUSCA (nai_giria_explica): só explica
--    o lugar quando a mensagem é pedido de imóvel (nai_pedido_de_perfil), e o texto
--    diz que citar lugar não é pedido.
-- C. NOME DE GENTE NÃO É AVENIDA: João Machado, Pedro Teixeira, Rodrigo Otávio,
--    André Araújo, João Valério, Cosme Ferreira, Nathan Xavier, Max Teixeira só com
--    "av./avenida/na/pela/perto da" antes; "viver melhor", "águas claras",
--    "galileia", "canaranas" só com "conjunto/residencial/no/do" antes.
-- D. A NAY NÃO FALA POR CIMA DA RAYSSA NEM DO TEL
--    1. crm_etapa_manual 'tel'/'rayssa' marca as DUAS linhas da pessoa (telefone e
--       @lid), não só a do número.
--    2. nai_tel_com_a_conversa: basta UMA linha com marca valendo para calar (antes
--       valia só a mais recente, e o eco de 30 min numa linha vencia a marca do CRM
--       na outra). Tudo o que solta (DEVOLVER, Todos, soltar, voltar) já limpa as duas.
-- E. crm_fechamento_do_contato (211): o checklist é o DESTE fechamento; search_path
--    com pg_temp; só o nay_disparo executa.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION pg_temp.trocar(p_fn regprocedure, p_de text, p_para text, p_vezes int DEFAULT 1)
 RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  d text := pg_get_functiondef(p_fn);
  n int := (length(d) - length(replace(d, p_de, ''))) / length(p_de);
BEGIN
  IF n <> p_vezes THEN
    RAISE EXCEPTION 'trocar em %: esperava % vez(es), achei % -- %', p_fn, p_vezes, n, left(p_de, 60);
  END IF;
  EXECUTE replace(d, p_de, p_para);
END $$;

-- A.1 --------------------------------------------------------------------
SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$  -- bairros dela). Sem bairro nenhum na chamada, vale o que ele escreveu.
  v_lug_bairros := nai_bairros_do_lugar(p_bairro);
  IF v_lug_bairros IS NULL AND nullif(btrim(coalesce(p_bairro, '')), '') IS NULL THEN
    p_bairro := (SELECT string_agg(l.nome, ' e ' ORDER BY l.tipo, l.nome) FROM nai_lugar_citado(t.texto) l);
    v_lug_bairros := nai_bairros_do_lugar(p_bairro);
  END IF;$a$,
$b$  -- bairros dela). Só o bairro que a CHAMADA trouxe (215): o texto da mensagem
  -- pode ser um card colado ou um endereço, e isso não é resposta de região.
  v_lug_bairros := nai_bairros_do_lugar(p_bairro);$b$);

-- A.2 --------------------------------------------------------------------
SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$  v_lug_rotulo   text;     -- 206: "Parque 10 de Novembro (bairro do Conjunto Eldorado)"
$a$, $b$  v_lug_rotulo   text;     -- 206: "Parque 10 de Novembro (bairro do Conjunto Eldorado)"
  v_ultima       text;     -- 215: a última pergunta do filtro que ela fez (24 h)
$b$);

SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$  -- POR ONDE ELE ENTROU (Tel, 15/09: "ou a pessoa vem pelo grupo ou a pessoa$a$,
$b$  -- 215: A QUE O "TANTO FAZ" RESPONDE -- a última pergunta do filtro, 24 h.
  SELECT CASE WHEN s.texto ~* 'alugar ou para comprar' THEN 'negocio'
              WHEN s.texto ~* 'casa ou apartamento\?' THEN 'tipo'
              WHEN s.texto ~* 'at[eé] que valor' THEN 'valor'
              ELSE 'regiao' END
    INTO v_ultima
    FROM nai_saida s
   WHERE s.contato_id = ANY (coalesce(nai_contato_irmaos(k.id), ARRAY[k.id])) AND s.tipo = 'texto'
     AND s.estado IN ('enviado', 'enviando', 'simulado') AND s.criado_em > now() - interval '24 hours'
     AND s.texto ~* '(alugar ou para comprar|casa ou apartamento\?|at[eé] que valor|regi[aã]o ou bairro|em qual bairro)'
   ORDER BY s.criado_em DESC LIMIT 1;

  -- POR ONDE ELE ENTROU (Tel, 15/09: "ou a pessoa vem pelo grupo ou a pessoa$b$);

SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$  v_livre := nai_e_a_cidade(p_bairro)
             OR nai_sem_preferencia_de_bairro(concat_ws(' ', p_bairro, t.texto));$a$,
$b$  v_livre := nai_e_a_cidade(p_bairro)
             OR nai_sem_preferencia_de_bairro(p_bairro)
             -- 215: "tanto faz" solto vale para a região só se a última pergunta
             -- foi a da região, ou se ele falou de bairro ("qualquer bairro")
             OR (nai_sem_preferencia_de_bairro(t.texto)
                 AND (v_ultima = 'regiao' OR lower(unaccent(coalesce(t.texto, ''))) ~ '(bairro|regiao|lugar|local|zona)'));$b$);

SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$  v_sem_valor := lower(unaccent(concat_ws(' ', p_teto, t.texto))) ~
    '(nao\s+(disse|sabe|informou|falou|definiu|passou|me\s+disse)|sem\s+valor|qualquer\s+valor|tanto\s+faz|valor\s+(livre|aberto)|nao\s+tem\s+(um\s+)?valor)';$a$,
$b$  -- 215: a frase que FALA de valor vale sempre; "tanto faz"/"não sabe" soltos só
  -- valem quando a última pergunta foi a do valor (ou vieram no teto da chamada)
  v_sem_valor := lower(unaccent(concat_ws(' ', p_teto, t.texto))) ~
      '(sem\s+valor|qualquer\s+valor|valor\s+(livre|aberto)|nao\s+tem\s+(um\s+)?valor|nao\s+(disse|sabe|informou|falou|definiu|passou)\s+(o\s+|um\s+)?(valor|preco|orcamento|quanto))'
    OR lower(unaccent(coalesce(p_teto, ''))) ~
      '(nao\s+(disse|sabe|informou|falou|definiu|passou|me\s+disse)|tanto\s+faz|indiferente|nao\s+importa|qualquer)'
    OR (v_ultima = 'valor' AND lower(unaccent(coalesce(t.texto, ''))) ~
      '(nao\s+(disse|sabe|informou|falou|definiu|passou|me\s+disse)|tanto\s+faz|indiferente|nao\s+importa|qualquer)');$b$);

SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$    v_tanto_faz := lower(unaccent(concat_ws(' ', t.texto, (
        SELECT string_agg(m.texto, ' ') FROM mensagens m
         WHERE nai_chave(m.telefone) IN (SELECT c.chave FROM nai_contato c WHERE c.id = ANY (nai_contato_irmaos(k.id)))
           AND m.direcao = 'recebida' AND m.criada_em > now() - interval '24 hours'))))
      ~ '(tanto faz|qualquer (um|uma|tipo|coisa|imovel)|os dois|as duas|ambos|indiferente|nao importa|nao tem preferencia|sem preferencia)';$a$,
$b$    -- 215: o "tanto faz" é a RESPOSTA a "casa ou apartamento?" (o que ele escreveu
    -- depois dessa pergunta), ou uma frase que fala do tipo ("tanto faz casa ou apto")
    v_tanto_faz := lower(unaccent(concat_ws(' ',
        CASE WHEN v_ultima = 'tipo' THEN t.texto END,
        (SELECT string_agg(m.texto, ' ') FROM mensagens m
          WHERE nai_chave(m.telefone) IN (SELECT c.chave FROM nai_contato c WHERE c.id = ANY (nai_contato_irmaos(k.id)))
            AND m.direcao = 'recebida'
            AND m.criada_em > (SELECT max(s.criado_em) FROM nai_saida s
                                WHERE s.contato_id = ANY (nai_contato_irmaos(k.id)) AND s.tipo = 'texto'
                                  AND s.texto ILIKE '%casa ou apartamento?%' AND s.criado_em > now() - interval '24 hours')))))
      ~ '(tanto faz|qualquer (um|uma|tipo|coisa|imovel)|os dois|as duas|ambos|indiferente|nao importa|nao tem preferencia|sem preferencia)'
      OR lower(unaccent(coalesce(t.texto, ''))) ~
      '((casa|apartamento|apto).{0,25}(tanto faz|os dois|ambos|qualquer um)|(tanto faz|os dois|ambos|qualquer um).{0,25}(casa|apartamento|apto))';$b$);

-- B ----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.nai_giria_explica(p_texto text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT coalesce(
    ' COMO ELE FALA: ' || string_agg('"' || g.exemplo_curto || '" = ' || g.significado, ' ' ORDER BY g.id),
    '')
    -- 206/215: conjuntos e avenidas -- só quando a mensagem é PEDIDO de imóvel
    || CASE WHEN coalesce((nai_pedido_de_perfil(p_texto)->>'e_pedido')::boolean, false) THEN
         coalesce((SELECT ' LUGARES (referência; citar lugar não é pedir imóvel): ' || string_agg(
           CASE WHEN l.tipo = 'conjunto'
                THEN '"' || l.nome || '" é um conjunto do bairro ' || l.bairros[1] || '.'
                ELSE '"' || l.nome || '" passa ' || CASE WHEN cardinality(l.bairros) = 1 THEN 'pelo bairro ' ELSE 'pelos bairros ' END
                     || nai_lista_pt(l.bairros) || '.' END
           || ' Se ele está pedindo imóvel lá, ao chamar buscar_por_perfil passe bairro "' || l.nome
           || '" em vez de perguntar o bairro; o resto do filtro segue igual.',
           ' ' ORDER BY l.tipo, l.nome)
         FROM (SELECT * FROM nai_lugar_citado(p_texto) LIMIT 4) l), '')
       ELSE '' END
    FROM (
      SELECT id, significado,
             -- a expressao inteira que ele escreveu: a regex vai entre
             -- parenteses para o grupo 1 ser o casamento todo, e nao o
             -- primeiro pedaco dela ("ta" em vez de "ta valendo").
             coalesce((regexp_match(lower(unaccent(coalesce(p_texto, ''))), '(' || expressao || ')'))[1],
                      expressao) AS exemplo_curto
        FROM nai_giria
       WHERE ativo
         AND lower(unaccent(coalesce(p_texto, ''))) ~ expressao
       LIMIT 6            -- teto: gíria e ajuda, nao um dicionario no contexto
    ) g;
$function$;

-- C ----------------------------------------------------------------------
UPDATE nai_lugar_avenida SET expressao = CASE nome
  WHEN 'Av. Desembargador João Machado' THEN '\m(av|avenida|na|pela|perto da|proximo da|proximo a) ((desembargador|des) )?joao machado\M'
  WHEN 'Av. Pedro Teixeira'   THEN '\m(av|avenida|na|pela|perto da|proximo da|proximo a) pedro teixeira\M'
  WHEN 'Av. Rodrigo Otávio'   THEN '\m(av|avenida|na|pela|perto da|proximo da|proximo a) (general )?rodrigo otavio\M'
  WHEN 'Av. André Araújo'     THEN '\m(av|avenida|na|pela|perto da|proximo da|proximo a) andre araujo\M'
  WHEN 'Av. João Valério'     THEN '\m(av|avenida|na|pela|perto da|proximo da|proximo a) joao valerio\M'
  WHEN 'Av. Cosme Ferreira'   THEN '\m(av|avenida|na|pela|perto da|proximo da|proximo a) cosme ferreira\M'
  WHEN 'Av. Nathan Xavier'    THEN '\m(av|avenida|na|pela|perto da|proximo da|proximo a) nath?an xavier\M'
  WHEN 'Av. Max Teixeira'     THEN '\m(av|avenida|na|pela|perto da|proximo da|proximo a) max teixeira\M'
  ELSE expressao END
 WHERE nome IN ('Av. Desembargador João Machado', 'Av. Pedro Teixeira', 'Av. Rodrigo Otávio', 'Av. André Araújo',
                'Av. João Valério', 'Av. Cosme Ferreira', 'Av. Nathan Xavier', 'Av. Max Teixeira');
UPDATE nai_lugar_conjunto SET expressao = CASE nome
  WHEN 'Residencial Viver Melhor' THEN '\m(conjunto|conj|cjto|cj|residencial|condominio|no|do) viver melhor\M'
  WHEN 'Conjunto Águas Claras'    THEN '\m(conjunto|conj|cjto|cj|residencial|no|do) aguas claras\M'
  WHEN 'Conjunto Galileia'        THEN '\m(conjunto|conj|cjto|cj|no|do) galileia\M'
  WHEN 'Conjunto Canaranas'       THEN '\m(conjunto|conj|cjto|cj|no|do) canaranas?\M'
  ELSE expressao END
 WHERE nome IN ('Residencial Viver Melhor', 'Conjunto Águas Claras', 'Conjunto Galileia', 'Conjunto Canaranas');

-- D.1 --------------------------------------------------------------------
SELECT pg_temp.trocar('crm_etapa_manual(text,text,text)',
$a$    UPDATE nai_contato SET humano_assumiu_em = now(), humano_motivo = left('CRM: ' || v_quem || ' mandou para o Tel', 200)
     WHERE id = v_contato;$a$,
$b$    UPDATE nai_contato SET humano_assumiu_em = now(), humano_motivo = left('CRM: ' || v_quem || ' mandou para o Tel', 200)
     WHERE id = ANY (v_ids);  -- 215: as duas linhas da pessoa$b$);
SELECT pg_temp.trocar('crm_etapa_manual(text,text,text)',
$a$                           humano_motivo = left('Rayssa: CRM: ' || v_quem || ' mandou para a Rayssa', 200)
     WHERE id = v_contato;$a$,
$b$                           humano_motivo = left('Rayssa: CRM: ' || v_quem || ' mandou para a Rayssa', 200)
     WHERE id = ANY (v_ids);  -- 215: as duas linhas da pessoa$b$);
ALTER FUNCTION crm_etapa_manual(text, text, text) SET search_path = public, pg_temp;

-- D.2 --------------------------------------------------------------------
SELECT pg_temp.trocar('nai_tel_com_a_conversa(bigint)',
$a$  SELECT c.humano_assumiu_em, c.humano_motivo
    INTO v_em, v_motivo
    FROM nai_contato c
   WHERE c.id = ANY (nai_contato_irmaos(p_contato))
     AND c.humano_assumiu_em IS NOT NULL
   ORDER BY c.humano_assumiu_em DESC
   LIMIT 1;

  IF v_em IS NULL THEN RETURN false; END IF;

  IF v_motivo = 'o Tel escreveu pelo celular' THEN
    v_gap := greatest(nai_cfg_int('gap_tel_min', 30), 0);
    RETURN v_em > now() - make_interval(mins => v_gap);
  END IF;
$a$, $b$  -- 215: QUALQUER linha da pessoa com marca valendo cala. Antes valia só a mais
  -- recente: o eco de 30 min ("o Tel escreveu pelo celular") numa linha vencia a
  -- marca do CRM (Tel/Rayssa) na outra, e 30 min depois a Nay falava por cima.
  -- Cada marca expira pela regra dela; tudo o que solta limpa as duas linhas.
  v_gap := greatest(nai_cfg_int('gap_tel_min', 30), 0);
  v_horas := nai_cfg_int('escalacao_expira_horas', 0);
  RETURN EXISTS (
    SELECT 1 FROM nai_contato c
     WHERE c.id = ANY (nai_contato_irmaos(p_contato)) AND c.humano_assumiu_em IS NOT NULL
       AND CASE WHEN c.humano_motivo = 'o Tel escreveu pelo celular'
                  THEN c.humano_assumiu_em > now() - make_interval(mins => v_gap)
                WHEN c.humano_motivo ~ '^(duvida fora da base|midia)' AND v_horas > 0
                  THEN c.humano_assumiu_em > now() - make_interval(hours => v_horas)
                ELSE true END);
$b$);

-- E ----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm_fechamento_do_contato(p_telefone text)
 RETURNS TABLE(fechamento_id bigint, tipo text, iniciado_em timestamptz, concluido_em timestamptz,
               checklist_tipo text, checklist_em timestamptz)
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT f.id, f.tipo, f.iniciado_em, f.concluido_em, ck.tipo, ck.criado_em
    FROM crm_pessoas(ARRAY[p_telefone]) pe
    LEFT JOIN LATERAL (SELECT * FROM nai_fechamento f WHERE f.contato_id = ANY (pe.ids)
                        ORDER BY (f.concluido_em IS NULL) DESC, f.id DESC LIMIT 1) f ON true
    -- 215: o checklist DESTE fechamento (não um de um fechamento antigo)
    LEFT JOIN LATERAL (SELECT s.criado_em,
                              CASE WHEN s.texto ~* 'venda|vendedor|comprador' THEN 'venda' ELSE 'locacao' END AS tipo
                         FROM nai_saida s
                        WHERE s.contato_id = ANY (pe.ids) AND s.motivo = 'checklist'
                          AND s.estado IN ('enviado', 'enviando', 'simulado')
                          AND (f.id IS NULL OR s.criado_em >= f.iniciado_em - interval '10 minutes')
                        ORDER BY s.criado_em DESC LIMIT 1) ck ON true
   LIMIT 1;
$$;
REVOKE ALL ON FUNCTION crm_fechamento_do_contato(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION crm_fechamento_do_contato(text) TO nay_disparo;
COMMIT;
