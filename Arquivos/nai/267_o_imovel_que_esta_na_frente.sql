-- 267 (02/10/2026): O IMÓVEL QUE ESTÁ NA FRENTE DELE, E O QUE A PALAVRA "CASA" NÃO É.
-- Pedro, sobre duas conversas de 01/10:
--   Raquel: "ela já tinha dito casa e a Nay perguntou 'Seu cliente procura casa ou
--   apartamento?', e depois a mulher pediu fotos e ela mandou sem esperar a
--   resposta... e ela ainda enviou fotos de outra casa".
--   Maycon: "ela mandou o card e ele disse 'Manda aí', era para ela ter mandado as
--   fotos... tipo um gatilho duplo: se ela já mandou o card e o cara disse para
--   ela mandar, é porque ele quer as fotos".
--
-- O QUE ACONTECEU, pelo registro (turnos 12915 a 13024 e 12891/12892):
--
-- 1. 09:07 "Procuro casa Tarumã... Até 700 mil... Que aceite financiamento" ->
--    SILÊNCIO de 1h36. A conferência do pagamento (191) leu "que aceite
--    financiamento" como pergunta sobre a forma de pagamento DE UM IMÓVEL, não
--    achou ficha, subiu ao Tel e parou o chat. Era um filtro de busca. A mensagem
--    dela das 09:34 nem abriu turno; às 10:42 alguém reentregou pelo CRM.
--
-- 2. 10:43 "Seu cliente procura casa ou apartamento?" -- o bairro e o valor
--    mudaram (400 mil, "nessa mesma redondeza"), o que abre perfil novo (223), e
--    em perfil novo o tipo só vale se dito na própria mensagem (241). A 241 foi
--    feita para a troca de NEGÓCIO (venda -> locação, outro cliente). Aqui o
--    negócio era o mesmo e o pedido anterior tinha 1h36.
--
-- 3. 10:43 "Casa" -> imóvel 1360. O 1360 tem `condominio_nome = 'Casa'` (58
--    imóveis têm; são 75 com nome de tipo: Casa, Apartamento, Flat, Prédio,
--    LIVRE). O passo "ele chamou pelo nome" procurava a PRIMEIRA PALAVRA do nome
--    do condomínio dentro da fala -- e a palavra "casa" está em todo pedido de
--    casa. Do mesmo jeito, "Flores, Parque 10" virou o 9004 (Parque dos
--    Ingleses): primeira palavra "parque".
--
-- 4. 21:52 "Quero as fotos" -> 7 fotos do 1360 E a pergunta "do La Villette ou do
--    Village Park?". O "imóvel do último turno" era o 1360 do passo 3, que nunca
--    foi mostrado a ela; os dois cards mandados 6 minutos antes não contavam.
--
-- 5. Maycon, 08:41 "Top manda aí", com o card do 5739 mandado 2 minutos antes ->
--    o card de novo, sem foto. O portão de fotos (224) só abre com a palavra
--    "foto" ou com pedido que cita o imóvel.
--
-- O CONSERTO, uma ideia só: O QUE ESTÁ NA FRENTE DELE. Os imóveis do último
-- lote que a Nay pôs na conversa (card, lista, envio) nas últimas 2 horas.
--   * um só na frente  -> é dele que ele fala ("manda aí", "quero as fotos");
--   * dois ou mais     -> ela pergunta qual, e NÃO manda foto de nenhum enquanto
--                         ele não responder -- nem de outro imóvel;
--   * "as duas", "os dois", "todas" depois da pergunta -> as fotos dos que estão
--     na frente.
-- E o nome do condomínio só identifica imóvel pelo núcleo do nome, na borda da
-- palavra, nunca por palavra de tipo ou genérica (casa, apartamento, parque,
-- jardim, residencial...).
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION pg_temp.trocar(p_fn regprocedure, p_de text, p_para text, p_vezes int DEFAULT 1)
 RETURNS void LANGUAGE plpgsql AS $$
DECLARE d text := pg_get_functiondef(p_fn); n int := (length(d) - length(replace(d, p_de, ''))) / length(p_de);
BEGIN
  IF n <> p_vezes THEN RAISE EXCEPTION 'trocar em %: esperava % vez(es), achei % -- %', p_fn, p_vezes, n, left(p_de, 50); END IF;
  EXECUTE replace(d, p_de, p_para);
END $$;

-- ------------------------------------------------ o que está na frente dele
CREATE OR REPLACE FUNCTION public.nai_imoveis_na_frente(p_contato bigint)
 RETURNS integer[]
 LANGUAGE sql
 STABLE
AS $function$
  -- O ÚLTIMO LOTE de imóveis que a Nay pôs na conversa, nas últimas 2 horas:
  -- card ("Código: 5739"), lista ("*La Villette #5640*"), saída com código (sem
  -- contar as fotos: foto mandada não é oferta nova) e envio registrado. "Lote" é
  -- o que saiu junto: até 3 minutos antes do mais recente.
  WITH k AS (
    SELECT coalesce(nai_contato_irmaos(p_contato), ARRAY[p_contato]) AS ids,
           right(regexp_replace((SELECT telefone FROM nai_contato WHERE id = p_contato), '\D', '', 'g'), 8) AS fim8
  ),
  ev AS (
    SELECT s.criado_em AS em, s.codigo AS c
      FROM nai_saida s, k
     WHERE s.contato_id = ANY (k.ids) AND s.codigo IS NOT NULL AND s.tipo <> 'imagem'
       AND s.papel_destino <> 'tel' AND s.estado IN ('enviado', 'enviando', 'pendente', 'simulado')
       AND s.criado_em > now() - interval '2 hours'
    UNION ALL
    SELECT s.criado_em, m[1]::int
      FROM nai_saida s, k,
           regexp_matches(s.texto, '(?:C[óo]digo:\s*|\*[^*\n]{1,80}#)(\d{3,5})', 'gi') m
     WHERE s.contato_id = ANY (k.ids) AND s.tipo = 'texto' AND s.texto IS NOT NULL
       AND s.papel_destino <> 'tel' AND s.estado IN ('enviado', 'enviando', 'pendente', 'simulado')
       AND s.criado_em > now() - interval '2 hours'
    UNION ALL
    SELECT e.enviado_em, e.codigo::int
      FROM envios e, k
     WHERE k.fim8 <> '' AND right(regexp_replace(coalesce(e.telefone, ''), '\D', '', 'g'), 8) = k.fim8
       AND e.enviado_em > now() - interval '2 hours' AND e.codigo ~ '^[0-9]{3,5}$'
  )
  SELECT coalesce(array_agg(DISTINCT ev.c), '{}')
    FROM ev
   WHERE ev.em >= (SELECT max(em) FROM ev) - interval '3 minutes'
     AND EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = ev.c);
$function$;
COMMENT ON FUNCTION nai_imoveis_na_frente(bigint) IS
  '267: os imóveis do último lote que a Nay pôs na conversa (card, lista, envio) nas últimas 2 h. É deles que ele fala quando diz "manda aí" ou "quero as fotos".';

-- ------------------------------------------------------ 1. o silêncio das 09:07
-- "Que aceite financiamento" num PEDIDO DE PERFIL é filtro da busca, não
-- pergunta sobre o pagamento de um imóvel: não sobe ao Tel nem para o chat. A
-- afirmação sem ficha continua saindo do texto; se não sobrar nada, fica a
-- resposta da busca como veio.
SELECT pg_temp.trocar('nai_conferir_resposta(bigint,text,jsonb,text,jsonb)'::regprocedure,
$de$      v_texto := v_pg.texto;
      IF nai_assunto_sensivel(coalesce(p_escreveu, '')) IN ('pagamento', 'fgts', 'permuta') OR btrim(v_texto) = '' THEN$de$,
$para$      -- 267: pedido de perfil ("procuro casa... que aceite financiamento") não é
      -- pergunta de pagamento. Em 01/10 isso calou a Nay por 1h36 com a Raquel.
      IF 'buscar_por_perfil' = ANY (coalesce(t.ferramentas, '{}'))
         OR coalesce((nai_pedido_de_perfil(coalesce(p_escreveu, '')) ->> 'e_pedido')::boolean, false) THEN
        IF btrim(coalesce(v_pg.texto, '')) <> '' THEN v_texto := v_pg.texto; END IF;
      ELSE
        v_texto := v_pg.texto;
      END IF;
      IF (nai_assunto_sensivel(coalesce(p_escreveu, '')) IN ('pagamento', 'fgts', 'permuta')
          AND NOT ('buscar_por_perfil' = ANY (coalesce(t.ferramentas, '{}'))
                   OR coalesce((nai_pedido_de_perfil(coalesce(p_escreveu, '')) ->> 'e_pedido')::boolean, false)))
         OR btrim(v_texto) = '' THEN$para$);

-- ------------------------------------------- 2. "casa ou apartamento?" de novo
-- Perfil novo com o MESMO negócio, aberto até 3 horas depois do anterior: o tipo
-- continua, a não ser que ele diga outro. Trocou de negócio (venda -> locação),
-- continua valendo a 241: tipo novo, e ela pergunta.
SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)'::regprocedure,
$de$  v_tipo    := CASE WHEN v_pedido_novo
                    THEN nai_tipo_pedido(concat_ws(' ', t.texto, p_bairro))$de$,
$para$  v_tipo    := CASE WHEN v_pedido_novo
                    THEN coalesce(nai_tipo_pedido(concat_ws(' ', t.texto, p_bairro)),
                                  -- 267: mesmo negócio, pedido de até 3 h atrás: é o mesmo tipo
                                  CASE WHEN v_perfil.tipo IS NOT NULL
                                        AND v_perfil.negocio IS NOT DISTINCT FROM v_negocio
                                        AND v_perfil.atualizado_em > now() - interval '3 hours'
                                       THEN v_perfil.tipo END)$para$);

-- e, no MESMO pedido, o tipo que o perfil já guardou vale quando as falas da
-- janela não o repetem (no ensaio: perfil com "Casa" gravado e a busca perguntando
-- "casa ou apartamento?")
SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)'::regprocedure,
$de$                    ELSE nai_tipo_da_conversa(k.id, concat_ws(' ', t.texto, p_bairro)) END;$de$,
$para$                    ELSE coalesce(nai_tipo_da_conversa(k.id, concat_ws(' ', t.texto, p_bairro)), v_perfil.tipo) END;$para$);

-- ------------------------------------- 3 e 4. de qual imóvel ele está falando
SELECT pg_temp.trocar('nai_imovel_da_conversa(bigint,text)'::regprocedure,
$de$  v_dele  int[];  -- 190$de$,
$para$  v_dele  int[];  -- 190
  v_frente int[]; -- 267: o último lote que a Nay pôs na conversa$para$);

-- a frente entra na mesa (a lista "#5640" não tinha "Código:" e ficava de fora)
SELECT pg_temp.trocar('nai_imovel_da_conversa(bigint,text)'::regprocedure,
$de$  v_cods := ARRAY(SELECT c FROM unnest(v_cods) c WHERE nai_finalidade_serve(c, v_neg) OR c = ANY (v_dele));  -- 190$de$,
$para$  v_cods := ARRAY(SELECT c FROM unnest(v_cods) c WHERE nai_finalidade_serve(c, v_neg) OR c = ANY (v_dele));  -- 190
  -- 267: a frente NÃO passa pelo filtro de finalidade. Foi a Nay que pôs esses
  -- imóveis ali; numa conversa ainda sem negócio definido o filtro esvaziava a
  -- frente e voltava a valer "o único da mesa" -- outro imóvel (visto no ensaio).
  -- A parede de venda x locação continua no portão de fotos e na caixa de saída.
  v_frente := nai_imoveis_na_frente(p_contato);
  v_cods := v_cods || ARRAY(SELECT c FROM unnest(v_frente) c WHERE NOT (c = ANY (v_cods)));$para$);

-- o nome: pelo NÚCLEO, na borda da palavra, e nunca por palavra de tipo/genérica
SELECT pg_temp.trocar('nai_imovel_da_conversa(bigint,text)'::regprocedure,
$de$    SELECT i.codigo INTO v_cod FROM imoveis i
     WHERE i.codigo = ANY (v_cods)
       AND coalesce(nai_condominio_ok(i.condominio_nome), '') <> ''
       AND position(lower(unaccent(split_part(nai_condominio_ok(i.condominio_nome), ' ', 1))) IN q) > 0
     LIMIT 1;
    IF v_cod IS NOT NULL THEN RETURN v_cod; END IF;
  END IF;$de$,
$para$    -- 267: era a PRIMEIRA PALAVRA do nome, solta, em qualquer lugar da fala. O
    -- imóvel 1360 tem o condomínio gravado como "Casa", e "Casa" (o tipo que a
    -- Raquel pediu) virou o 1360; "Parque 10" virou o Parque dos Ingleses (9004).
    -- Agora: a primeira palavra do núcleo, se for um nome de verdade; se ela for
    -- genérica, o núcleo inteiro. Sempre na borda da palavra, e nunca palavra de tipo.
    SELECT i.codigo INTO v_cod
      FROM imoveis i
      CROSS JOIN LATERAL (SELECT nai_condominio_nucleo(nai_condominio_ok(i.condominio_nome)) AS nucleo) n
      CROSS JOIN LATERAL (SELECT CASE
                 WHEN length(split_part(n.nucleo, ' ', 1)) >= 4
                  AND split_part(n.nucleo, ' ', 1) NOT IN ('parque', 'jardim', 'jardins', 'vila', 'village', 'villa', 'solar',
                        'morada', 'reserva', 'portal', 'porto', 'ilha', 'ilhas', 'torre', 'torres', 'life', 'smart', 'grand',
                        'green', 'park', 'alto', 'novo', 'nova', 'santa', 'santo', 'saint', 'ponta', 'vista', 'bela', 'belo')
                 THEN split_part(n.nucleo, ' ', 1) ELSE n.nucleo END AS p) w
     WHERE i.codigo = ANY (v_cods)
       AND coalesce(n.nucleo, '') <> ''
       AND length(w.p) >= 4
       AND w.p NOT IN ('casa', 'casas', 'apartamento', 'apartamentos', 'apto', 'flat', 'predio', 'livre', 'lote',
                       'terreno', 'sala', 'loja', 'kitnet', 'sobrado', 'galpao', 'cobertura', 'imovel')
       AND q ~ ('\m' || regexp_replace(w.p, '([.^$*+?()\[\]{}|\\-])', '\\\1', 'g') || '\M')
     LIMIT 1;
    IF v_cod IS NOT NULL THEN RETURN v_cod; END IF;
  END IF;

  -- 3b. 267: O QUE ESTÁ NA FRENTE DELE. O último lote que a Nay pôs na conversa
  -- (2 h) manda mais que "o imóvel do último turno": um só, é dele que ele fala;
  -- dois ou mais, ela pergunta qual -- a não ser que ele já viesse falando de um
  -- deles. Em 01/10 a Raquel recebeu dois cards, pediu "as fotos" e saíram 7 fotos
  -- de um terceiro imóvel, o do "último turno", que ela nunca tinha visto.
  IF coalesce(array_length(v_frente, 1), 0) = 1 THEN
    RETURN v_frente[1];
  ELSIF coalesce(array_length(v_frente, 1), 0) >= 2 THEN
    SELECT t.codigo INTO v_cod FROM nai_turno t
     WHERE t.contato_id = p_contato AND t.codigo IS NOT NULL AND t.criado_em > now() - interval '2 hours'
     ORDER BY t.id DESC LIMIT 1;
    RETURN CASE WHEN v_cod = ANY (v_frente) THEN v_cod END;
  END IF;$para$);

-- ------------------------------------------------ 5. o gatilho duplo das fotos
CREATE OR REPLACE FUNCTION public.nai_deve_mandar_fotos(p_contato bigint, p_telefone text, p_escreveu text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE v_txt text := lower(unaccent(btrim(coalesce(p_escreveu, ''))));
BEGIN
  -- 224: FOTO SÓ QUANDO ELE PEDE (Pedro, 30/09). De 16/09 a 30/09 a foto ia
  -- SEMPRE atrás do card, e saía foto de imóvel que ele não pediu -- inclusive
  -- de locação numa conversa de venda. Agora sem pedido vai só o card, que já
  -- tem todas as informações. Pedido é: falar em foto (nai_menciona_foto), pedir
  -- um imóvel claro com "me manda/envia/passa" (nai_pede_envio_do_imovel), ou
  -- dizer "sim" à pergunta dela sobre as fotos.
  IF v_txt = '' THEN
    RETURN false;
  END IF;

  IF (v_txt ~ ('(ja\s+(tenho|recebi|vi|peguei)|nao\s+precisa|voce\s+ja\s+'
               || '(me\s+)?(mandou|enviou))[^.,;!?]{0,30}\m(foto|fotos|imagem|imagens|fachada|material)\M')
      OR v_txt ~ ('\m(foto|fotos|imagem|imagens|fachada|material)\M[^.,;!?]{0,30}'
                  || '(ja\s+(tenho|recebi|vi|peguei)|nao\s+precisa)'))
     AND v_txt !~ '\m(manda|mande|envia|envie|me\s+passa|por\s+favor)\M' THEN
    RETURN false;
  END IF;

  -- a oferta ou o anúncio DELE não é pedido de foto nossa
  IF nai_fala_e_dele(p_escreveu) THEN
    RETURN false;
  END IF;

  IF nai_menciona_foto(p_escreveu) OR nai_pede_envio_do_imovel(p_escreveu, p_telefone) THEN
    RETURN true;
  END IF;

  -- 267: O GATILHO DUPLO (Pedro, 02/10: "se ela já mandou o card e o cara disse
  -- para ela mandar, é porque ele quer as fotos"). O card acabou de sair e a
  -- resposta é um "manda aí": o que falta mandar são as fotos. Só vale com imóvel
  -- na frente dele (2 h), em fala curta, e nunca num pedido de busca ("me manda
  -- uma casa no Flores" é pedido de imóvel, não de foto).
  IF p_contato IS NOT NULL AND length(v_txt) <= 40
     AND v_txt ~ '\m(manda|mande|mandar|envia|envie|enviar|encaminha|encaminhe|encaminhar)\M'
     AND v_txt !~ '\m(nao|depois|amanha|mais tarde|outr[oa]s?|opc(ao|oes)|mais)\M'
     -- pedido novo dentro da fala ("me manda uma casa no Flores até 500 mil") não é
     -- "manda aí": tem tipo, número ou é pedido de perfil
     AND v_txt !~ '[0-9]' AND nai_tipo_pedido(p_escreveu) IS NULL
     AND NOT coalesce((nai_pedido_de_perfil(p_escreveu) ->> 'e_pedido')::boolean, false)
     AND coalesce(array_length(nai_imoveis_na_frente(p_contato), 1), 0) >= 1 THEN
    RETURN true;
  END IF;

  -- "sim" à pergunta dela sobre as fotos -- e, desde a 267, a ESCOLHA quando ela
  -- perguntou de qual ("as duas", "os dois", "todas", ou o nome do condomínio)
  IF p_contato IS NOT NULL
     AND (nai_e_sim_curto(p_escreveu)
          OR (length(v_txt) <= 60
              AND (v_txt ~ '\m(as duas|os dois|ambas|ambos|todas|todos|as 2|os 2)\M'
                   OR coalesce(array_length(nai_imovel_pelo_condominio(p_escreveu, coalesce(p_telefone, '')), 1), 0) >= 1))) THEN
    RETURN coalesce((SELECT lower(unaccent(coalesce(s.texto, ''))) ~ '\m(fotos?|imagens?|videos?)\M[^?]*\?'
                       FROM nai_saida s
                      WHERE s.contato_id = ANY (nai_contato_irmaos(p_contato))
                        AND s.tipo = 'texto' AND s.estado = 'enviado'
                        AND s.criado_em > now() - interval '2 hours'
                      ORDER BY s.id DESC LIMIT 1), false);
  END IF;

  RETURN false;
END;
$function$;

-- "as duas", "os dois", "todas": as fotos dos que estão na frente dele (até 3)
SELECT pg_temp.trocar('nai_conferir_resposta(bigint,text,jsonb,text,jsonb)'::regprocedure,
$de$    v_cods := array_remove(ARRAY[coalesce(v_alvo, nai_imovel_da_conversa(t.contato_id, p_escreveu))], NULL);
  END IF;$de$,
$para$    v_cods := array_remove(ARRAY[coalesce(v_alvo, nai_imovel_da_conversa(t.contato_id, p_escreveu))], NULL);
    -- 267: ela perguntou "de qual?" e ele respondeu "as duas": os que estão na frente
    IF coalesce(array_length(v_cods, 1), 0) = 0
       AND lower(unaccent(coalesce(p_escreveu, ''))) ~ '\m(as duas|os dois|ambas|ambos|todas|todos|as 2|os 2)\M' THEN
      v_cods := (nai_imoveis_na_frente(t.contato_id))[1:3];
    END IF;
  END IF;$para$);
COMMIT;
