-- =====================================================================
-- 138 — A FALA NOVA DA NAY DE LOCAÇÃO (28/09/2026)
--
-- Pedido do Tel (ideia colada pelo Pedro), primeira parte -- o que muda na
-- fala, antes da religação das 7h:
--
--   * "Retire o SR e SRA das mensagens e só cita o nome do corretor":
--     `nai_vocativo` devolve só o primeiro nome; `nay_qual_imovel` e a frase
--     de foto dizem "você"; e o gatilho da caixa de saída limpa qualquer
--     "Sr./Sra." que escape (`nai_sem_senhor`).
--
--   * STATUS: "quando o cliente mande uma solicitação do status do imóvel ela
--     mande um card pequeno antes do card do imóvel... qualquer status além
--     desse ela diz que está indisponível e nem manda o card e fotos". Com a
--     resposta do Pedro para o alugado: "diz a situação já pedindo se ele
--     quer informação de outros imóveis perto, se tiver outros no mesmo
--     condomínio já lista eles".
--       disponível -> "📌 Status: Disponível" (balão próprio) + card + fotos
--       alugado    -> "Hmmm, vi aqui que o X está alugado no momento..."
--       o resto    -> "...está indisponível no momento..."
--     Disponível = no mercado (a mesma régua do site): 15 imóveis marcados
--     "Disponível" na planilha estão bloqueados ou fora do site.
--     Três camadas: `nai_o_que_sei_do_imovel` responde; a montagem da resposta
--     põe o status na frente do card; o gatilho barra card e foto de imóvel
--     indisponível venha de onde vier.
--
--   * PARCERIA: "Sim, aceitamos parceria em todos os nossos imóveis, o que
--     precisar pode contar com a gente" -- `nai_config.resposta_parceria`.
--     "Como funciona a parceria / é 50/50?" é outra pergunta e fica fora.
--
--   * FILTRO DE IDENTIFICAÇÃO: quem chega pedindo imóvel começa por "Eu vou
--     fazer um filtro com você... Até que valor o seu cliente quer?" e depois
--     "E quais os bairros que atendem?". Quem veio do grupo segue o site.
--
--   * FOTOS 2 VEZES (caso do Paulo Victor, 23/09: 15 fotos do 5718 duas vezes,
--     30 s de diferença): a trava de 24h da 131/132 já barra as fotos; faltava
--     a montagem parar de contar a foto barrada -- ela puxava o "Aqui as
--     fotos, quer fazer uma visita?" logo depois de "já te mandei".
-- =====================================================================
\set ON_ERROR_STOP on

BEGIN;

INSERT INTO nai_config (chave, valor)
VALUES ('resposta_parceria', 'Sim, aceitamos parceria em todos os nossos imóveis, o que precisar pode contar com a gente!')
ON CONFLICT (chave) DO NOTHING;

-- ---------------------------------------------------------------------
-- Tira "Sr." e "Sra." de um texto, deixando o nome ou "você".
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION nai_sem_senhor(p text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
           coalesce(p, ''),
           '\mSra?\.?\s+(?=[[:upper:]])', '', 'g'),              -- "Sr. Carlos" -> "Carlos"
           '\m(do|da)\s+Sra?\M\.?', 'de você', 'g'),
           '\m(ao|à)\s+Sra?\M\.?', 'a você', 'g'),
           '\m(pro|pra|para o|para a)\s+Sra?\M\.?', 'pra você', 'g'),
           '\m(o|a|O|A)\s+Sra?\M\.?', 'você', 'g'),
           '\mSra?\M\.', 'você', 'g');
$fn$;

-- O nome, e só o nome (Tel, 28/09).
CREATE OR REPLACE FUNCTION nai_vocativo(p_nome text)
RETURNS text
LANGUAGE sql
STABLE
AS $fn$
  -- SEM SR. E SRA. (Tel, 28/09/2026): "só cita o nome do corretor, porque os
  -- nomes no BR variam muito". Até aqui vinha "Sr./Sra." + primeiro nome, com
  -- o gênero adivinhado pelo nome. O resto continua: sem nome de verdade
  -- (til, número, emoji, nome de empresa), não chama de nada.
  SELECT CASE
    WHEN coalesce(btrim(p_nome), '') = '' THEN NULL
    WHEN btrim(p_nome) !~ '[[:alpha:]]{2}' THEN NULL
    WHEN nay_primeiro_nome(p_nome) IS NOT NULL AND nay_primeiro_nome(p_nome) ~ '[[:alpha:]]{2}'
      THEN nay_primeiro_nome(p_nome)
    ELSE NULL
  END;
$fn$;

-- ---------------------------------------------------------------------
-- Disponível = no mercado (a mesma régua do site).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION nai_imovel_disponivel(p_codigo integer)
RETURNS boolean
LANGUAGE sql
STABLE
AS $fn$
  SELECT coalesce((SELECT nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
                     FROM imoveis i WHERE i.codigo = p_codigo), false);
$fn$;

-- ---------------------------------------------------------------------
-- Ele perguntou a SITUAÇÃO do imóvel? ("ainda está disponível?", "foi
-- alugado?", "status"). Pessoa disponível ("a cliente tá disponível em
-- qualquer horário") não conta.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION nai_pergunta_status(p text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT lower(unaccent(coalesce(p, ''))) ~ ('(\mainda\s+(ta|esta|tem|disponivel|livre|vago)\M'
            || '|\mdisponive(l|is)\M'
            || '|\mfoi\s+(alugad|vendid)'
            || '|\mja\s+(alugou|vendeu|foi\s+(alugad|vendid))'
            || '|\m(esta|ta)\s+(alugad|vendid|livre|vag[oa]|ocupad)'
            || '|\mstatus\M|\msituacao\s+d[oa]\M'
            || '|\mcontinua\s+(disponivel|livre|vago)'
            || '|\msegue\s+disponivel)')
     AND lower(unaccent(coalesce(p, ''))) !~ ('\m(cliente|estou|estamos|ele|ela|voce|vc|eu|fico|ficamos)\s+'
            || '(ta|esta|fica|ficou)?\s*disponive'
            || '|disponivel\s+(em\s+qualquer|qualquer|amanha|hoje|a\s+partir|pra\s+visit|para\s+visit|de\s+manha|a\s+tarde|a\s+noite)'
            || '|\m(horario|hora|dia)s?\s+disponive');
$fn$;

-- ---------------------------------------------------------------------
-- A resposta de SITUAÇÃO de um imóvel.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION nai_status_do_imovel(p_codigo integer)
RETURNS TABLE (texto_pronto text, disponivel boolean, instrucao_para_voce text)
LANGUAGE plpgsql
STABLE
AS $fn$
DECLARE
  i      record;
  v_card text;
  v_cond text;
  v_alt  text;
  v_n    int;
  v_situ text;
BEGIN
  SELECT im.codigo, im.status, im.bairro, nai_condominio_ok(im.condominio_nome) AS cond
    INTO i FROM imoveis im WHERE im.codigo = p_codigo;
  IF i.codigo IS NULL THEN
    RETURN QUERY SELECT ('Não achei o imóvel ' || p_codigo || '. Confere o código pra mim?')::text, false,
                        'mande o texto_pronto exatamente como veio.'::text;
    RETURN;
  END IF;

  IF nai_imovel_disponivel(p_codigo) THEN
    SELECT c.texto_pronto INTO v_card FROM nai_card_do_imovel(p_codigo) c;
    RETURN QUERY SELECT ('📌 Status: Disponível' || E'\n\n' || v_card)::text, true,
      ('mande o texto_pronto EXATAMENTE como veio: a linha de status e o card, com as quebras de linha. '
       || 'As fotos e a pergunta saem sozinhas atrás. Não escale.')::text;
    RETURN;
  END IF;

  v_situ := CASE WHEN i.status = 'Alugado' THEN 'está alugado' ELSE 'está indisponível' END;
  v_cond := nullif(btrim(coalesce(i.cond, '')), '');

  IF v_cond IS NOT NULL THEN
    SELECT count(*),
           string_agg('• ' || x.codigo || ' — ' || coalesce(x.tipo, 'Imóvel')
                      || CASE WHEN coalesce(x.quartos, 0) > 0
                              THEN ', ' || x.quartos || CASE WHEN x.quartos = 1 THEN ' quarto' ELSE ' quartos' END ELSE '' END
                      || CASE WHEN coalesce(x.valor_aluguel, 0) > 0
                              THEN ', aluguel R$ ' || replace(to_char(x.valor_aluguel, 'FM999,999,990'), ',', '.')
                              WHEN coalesce(x.valor_venda, 0) > 0
                              THEN ', venda R$ ' || replace(to_char(x.valor_venda, 'FM999,999,990'), ',', '.') ELSE '' END,
                      E'\n' ORDER BY coalesce(x.valor_aluguel, x.valor_venda, 0))
      INTO v_n, v_alt
      FROM imoveis x
     WHERE x.codigo <> p_codigo
       AND NOT coalesce(x.e_parceiro, false)
       AND nai_condominio_ok(x.condominio_nome) = v_cond
       AND nai_imovel_disponivel(x.codigo);
  END IF;

  IF coalesce(v_n, 0) > 0 THEN
    RETURN QUERY SELECT
      ('Hmmm, vi aqui que o ' || p_codigo || ' ' || v_situ || ' no momento. Mas no ' || v_cond
       || ' eu tenho ' || CASE WHEN v_n = 1 THEN 'este disponível' ELSE 'estes disponíveis' END || ':'
       || E'\n' || v_alt || E'\n\n'
       || CASE WHEN v_n = 1 THEN 'Quer que eu te mande as fotos dele?'
               ELSE 'Qual deles te interessa? Te mando as fotos.' END)::text,
      false,
      'mande o texto_pronto EXATAMENTE como veio. Não mande card nem fotos agora: elas saem quando ele escolher.'::text;
    RETURN;
  END IF;

  RETURN QUERY SELECT
    ('Hmmm, vi aqui que o ' || p_codigo || ' ' || v_situ || ' no momento, quer que eu veja mais opções perto '
     || 'para o seu cliente? Basta me informar os bairros, ou a faixa de preço que eu já vejo aqui, ok?')::text,
    false,
    'mande o texto_pronto EXATAMENTE como veio. Não mande card nem fotos.'::text;
END;
$fn$;

-- ---------------------------------------------------------------------
-- Parceria: ele perguntou se aceitamos? E foi SÓ isso?
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION nai_pergunta_parceria(p text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT lower(unaccent(coalesce(p, ''))) ~ ('\m(aceit\w*|faz|fazem|fazemos|fazendo|fazer|faco|faria|fariam|trabalh\w*|vamos|bora|rola|topa|tem|teem|disponive\w*\s+(para|pra))'
                                              || '(\s+\w+){0,2}\s+parcerias?\M'
                                              || '|\mparcerias?\s*\?')
     AND lower(unaccent(coalesce(p, ''))) !~ '(como\s+(funciona|e|seria|fica)|50\s*/\s*50|50\s*%|porcent|divis|comiss|quanto|60\s*/\s*40)'
     AND lower(unaccent(coalesce(p, ''))) !~ '^\s*(resposta|responde|descarta|devolver|assumir)\M';
$fn$;

CREATE OR REPLACE FUNCTION nai_so_parceria(p text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT length(btrim(regexp_replace(regexp_replace(lower(unaccent(coalesce(p, ''))),
           '(\m(aceit\w*|faz|fazem|fazemos|fazendo|faco|gostaria|estar|faria|fariam|trabalh\w*|vamos|bora|rola|topa|tem|teem|disponive\w*|para|pra|com|essa|a|de|fazer|voce|voces|vc|vcs|sou|corretora?|eu|nay|nayara|oi|ola|bom|boa|dia|tarde|noite|tudo|bem|amiga|amigo|por|favor|nos|imoveis|seus|suas|de|locacao|locacoes|alugueis|sim|ai|aqui|tambem|tbm|ja|estou|la|no|easy)\M|parcerias?)', ' ', 'g'),
           '[^[:alpha:]]', '', 'g'))) < 3;
$fn$;

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
  v_ind int;
BEGIN
  SELECT chave INTO v_chave FROM nai_contato WHERE id = NEW.contato_id;
  IF v_chave IS NULL THEN
    RAISE EXCEPTION 'NAI saida: contato % nao existe', NEW.contato_id;
  END IF;
  -- O destino e SEMPRE a chave do contato. Quem enfileira nao escolhe.
  NEW.chave_destino := v_chave;

  -- SEM SR. E SRA. (Tel, 28/09/2026): "retire o SR e SRA das mensagens e so
  -- cita o nome do corretor, porque os nomes no BR variam muito". Aqui e a
  -- ultima parede: o tratamento vinha do nome (`nai_vocativo`), do prompt, de
  -- frase pronta de funcao e ate da dica dentro do no do n8n -- qualquer um
  -- que escape sai limpo daqui.
  IF NEW.tipo = 'texto' AND NEW.texto ~ '\mSra?\M' THEN
    NEW.texto := nai_sem_senhor(NEW.texto);
  END IF;

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

  -- IMOVEL INDISPONIVEL NAO VAI (Tel, 28/09/2026): "qualquer status alem de
  -- disponivel ela diz que esta indisponivel e nem manda o card e fotos". A
  -- foto fica 'bloqueado'; o CARD vira a resposta de situacao
  -- (`nai_status_do_imovel`): diz que esta alugado/indisponivel e ja lista os
  -- disponiveis do mesmo condominio. Vale para qualquer caminho da NAI, venha
  -- do modelo, da busca ou de regra nova. O Tel continua recebendo tudo.
  IF NEW.papel_destino <> 'tel' THEN
    v_ind := NEW.codigo;
    IF v_ind IS NULL AND NEW.tipo = 'texto'
       AND position('📍' IN coalesce(NEW.texto, '')) > 0
       AND (SELECT count(*) FROM regexp_matches(NEW.texto, 'C[óo]digo:\s*\d{3,5}', 'gi')) = 1 THEN
      v_ind := (regexp_match(NEW.texto, 'C[óo]digo:\s*(\d{3,5})', 'i'))[1]::int;
    END IF;
    IF v_ind IS NOT NULL AND EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = v_ind)
       AND NOT nai_imovel_disponivel(v_ind) THEN
      IF NEW.tipo = 'imagem' THEN
        NEW.estado   := 'bloqueado';
        NEW.bloqueio := 'imovel indisponivel: nem card nem foto';
        RETURN NEW;
      END IF;
      NEW.texto := coalesce((SELECT s.texto_pronto FROM nai_status_do_imovel(v_ind) s), NEW.texto);
    END IF;
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

CREATE OR REPLACE FUNCTION public.nai_enfileirar_resposta(p_turno bigint, p_texto text, p_codigos jsonb, p_escreveu text, p_fotos_site jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  t        nai_turno;
  d        jsonb;
  v_texto  text;
  v_cods   int[];
  v_gate   boolean;
  v_cod    int;
  v_ordem  int := 0;
  v_ini    int := 1;
  v_bloco  text;
  v_resto  text;
  m        record;
  f        record;
  v_fotos  int := 0;
  v_textos int := 0;
  v_est    text;
  v_status text;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL THEN RETURN jsonb_build_object('ok', false, 'motivo', 'turno_inexistente'); END IF;

  d := nai_conferir_resposta(p_turno, p_texto, p_codigos, p_escreveu, p_fotos_site);
  IF d->>'acao' <> 'responder' THEN
    RETURN jsonb_build_object('ok', d->>'acao' <> 'parou' OR (d->>'motivo') IS NULL,
                              'textos', 0, 'fotos', 0, 'guarda', d->>'guarda',
                              'motivo', d->>'motivo');
  END IF;

  v_texto := d->>'texto';
  v_gate  := coalesce((d->>'gate')::boolean, false);
  -- ELA PERGUNTOU QUAL, ENTAO ESPERA (Tel, 22/09, caso 161: "ela perguntou se
  -- queria fotos mas depois mandou as fotos, nesse caso espera o cliente
  -- responder"). Resposta com dois ou mais imoveis que termina perguntando
  -- qual deles: vai o texto, e nenhuma foto -- as fotos saem quando ele
  -- escolher.
  IF v_gate
     AND coalesce(array_length(nay_codigos_citados(coalesce(d->>'texto', '')), 1), 0) >= 2
     AND lower(unaccent(coalesce(d->>'texto', ''))) ~
         '(qual|quais) (dos|das|deles|delas|desses|dessas|dois|duas|imove|interessa|prefere|o sr|a sra|voce)' THEN
    v_gate := false;
  END IF;
  SELECT coalesce(array_agg(x::int), '{}') INTO v_cods FROM jsonb_array_elements_text(coalesce(d->'cods', '[]'::jsonb)) x;

  -- COM CARD: cada bloco termina no seu "Código: NNNN" e leva as fotos dele.
  IF v_texto ~* 'C[óo]digo:\s*\d{3,5}' AND (v_gate OR position('📍' IN v_texto) > 0) THEN
    FOR m IN SELECT (regexp_matches(v_texto, '(C[óo]digo:\s*(\d{3,5}))', 'gi')) AS g LOOP
      v_cod := m.g[2]::int;
      v_bloco := substr(v_texto, v_ini, strpos(substr(v_texto, v_ini), m.g[1]) + length(m.g[1]) - 1);
      v_ini := v_ini + length(v_bloco);
      v_ordem := v_ordem + 1;
      -- O STATUS VEM ANTES, NUM BALAO SO DELE (Tel, 28/09): "quando o cliente
      -- mande uma solicitacao do status do imovel ela mande um card pequeno
      -- antes do card do imovel". Vem pronto de `nai_status_do_imovel` na
      -- frente do card, ou -- se ele perguntou do status e o modelo mandou so
      -- o card -- e posto aqui.
      v_status := substring(v_bloco FROM '^\s*(📌 Status:[^\n]*)');
      IF v_status IS NOT NULL THEN
        v_bloco := btrim(substr(v_bloco, strpos(v_bloco, v_status) + length(v_status)), E' \n\t\r');
      ELSIF nai_pergunta_status(coalesce(p_escreveu, '')) AND nai_imovel_disponivel(v_cod)
            AND position('📍' IN v_bloco) > 0
            AND NOT EXISTS (SELECT 1 FROM nai_saida s WHERE s.turno_id = p_turno AND s.motivo = 'status') THEN
        v_status := '📌 Status: Disponível';
      END IF;
      IF v_status IS NOT NULL THEN
        PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_status, 'status', v_ordem);
        v_ordem := v_ordem + 1;
        v_textos := v_textos + 1;
      END IF;
      PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_bloco, 'resposta', v_ordem);
      v_textos := v_textos + 1;
      IF v_gate THEN
        FOR f IN SELECT * FROM nai_imagens_do_envio(v_cod) LOOP
          v_ordem := v_ordem + 1;
          INSERT INTO nai_saida (turno_id, contato_id, papel_destino, chave_destino, tipo, imagem_url, codigo, ordem, motivo)
               VALUES (p_turno, t.contato_id, 'turno', '', 'imagem', f.url, v_cod, v_ordem,
                       CASE WHEN f.e_colagem THEN 'colagem' ELSE 'foto' END)
          RETURNING estado INTO v_est;
          -- 138: so conta a foto que vai sair (a barrada nao puxa "Aqui as fotos")
          IF v_est = 'pendente' THEN v_fotos := v_fotos + 1; END IF;
        END LOOP;
      END IF;
    END LOOP;
    v_resto := btrim(substr(v_texto, v_ini), ' ' || chr(9) || chr(10) || chr(13));
    IF v_fotos > 0 AND (v_resto = '' OR nai_so_anuncia_fotos(v_resto) OR nai_pergunta_qual_imovel(v_resto)) THEN
      PERFORM nai_depois_das_fotos(p_turno, v_ordem);
      v_textos := v_textos + 2;
    ELSIF v_resto <> '' THEN
      PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', nai_sem_pergunta_de_identidade(nai_sem_emoji_resposta(v_resto)), 'resposta', v_ordem + 1);
      v_textos := v_textos + 1;
      -- O PADRAO DE ATENDIMENTO VAI JUNTO (Tel, 21/09). Mandou card com foto,
      -- o fechamento sai SEMPRE -- depois da frase dela, nao no lugar dela.
      -- Antes so saia quando ela nao tinha mais nada a dizer, e bastava ela
      -- escrever uma linha a mais para o padrao sumir: em 19/09, dois dos
      -- quatro cards do dia sairam sem fechamento por causa disso.
      IF v_fotos > 0 THEN
        PERFORM nai_depois_das_fotos(p_turno, v_ordem + 1);
        v_textos := v_textos + 2;
      END IF;
    END IF;
  ELSE
    -- SEM CARD: as fotos primeiro, a frase depois (pedido do Tel em 31/08).
    IF v_gate THEN
      FOR f IN SELECT g.* FROM unnest(v_cods) WITH ORDINALITY AS c(cod, i)
                CROSS JOIN LATERAL nai_imagens_do_envio(c.cod) g
                ORDER BY c.i LOOP
        v_ordem := v_ordem + 1;
        INSERT INTO nai_saida (turno_id, contato_id, papel_destino, chave_destino, tipo, imagem_url, codigo, ordem, motivo)
             VALUES (p_turno, t.contato_id, 'turno', '', 'imagem', f.url, f.codigo, v_ordem,
                     CASE WHEN f.e_colagem THEN 'colagem' ELSE 'foto' END)
        RETURNING estado INTO v_est;
        IF v_est = 'pendente' THEN v_fotos := v_fotos + 1; END IF;
      END LOOP;
    END IF;
    IF v_fotos > 0 AND (nai_so_anuncia_fotos(v_texto) OR nai_pergunta_qual_imovel(v_texto)) THEN
      PERFORM nai_depois_das_fotos(p_turno, v_ordem);
      v_textos := 2;
    -- ELE pediu foto e nao se sabe o imovel: a pergunta certa, UMA vez. Antes
    -- isto se apoiava no portao (`v_gate`), que agora esta sempre aberto e e
    -- fechado de volta quando nao ha imovel -- entao a condicao passa a olhar
    -- o que ELE escreveu, que e o que de fato importa aqui.
    ELSIF v_fotos = 0 AND coalesce(nai_pede_foto(p_escreveu), false)
          AND coalesce(array_length(v_cods, 1), 0) = 0
          AND (v_texto = '' OR nai_so_anuncia_fotos(v_texto) OR nai_pergunta_qual_imovel(v_texto)) THEN
      -- Pediu foto e NENHUM imóvel foi identificado: a pergunta certa, UMA vez.
      PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno',
        'De qual imóvel você quer as fotos? Me passa o código que eu já mando.', 'foto_sem_imovel', v_ordem + 1);
      v_textos := 1;
    ELSIF v_fotos = 0 AND v_gate AND coalesce(array_length(v_cods, 1), 0) > 0
          AND (v_texto = '' OR nai_so_anuncia_fotos(v_texto) OR nai_pergunta_qual_imovel(v_texto)) THEN
      -- 14/09 (teste do Tel): ele marcou o card do 5737, o imóvel FOI
      -- identificado, mas estava sem foto -- e ela perguntou "de qual imóvel o
      -- Sr. quer as fotos?". Imóvel conhecido e sem foto: não se pergunta de qual
      -- imóvel, não se promete foto. O Tel já foi avisado na conferência 17.
      v_textos := 0;
    ELSIF v_texto <> '' THEN
      PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', nai_sem_pergunta_de_identidade(nai_sem_emoji_resposta(v_texto)), 'resposta', v_ordem + 1);
      v_textos := 1;
    END IF;
  END IF;

  -- A sugestão do Tel, sozinha, depois de tudo. Nunca junto de foto e NUNCA num
  -- pedido de foto (14/09: "sugeriu visita e outros imóveis antes de mandar as
  -- fotos, sendo que isso é só depois"). Depois das fotos quem convida é o
  -- "depois das fotos".
  IF coalesce((d->>'sugerir')::boolean, false) THEN
    IF v_fotos > 0 THEN
      -- AS FOTOS FORAM JUNTO (Tel, 16/09). Antes a sugestao so saia quando NAO
      -- havia foto, porque foto so saia a pedido e o texto era so o anuncio
      -- ("aqui estao as fotos") -- e ali quem convidava era o "depois das
      -- fotos". Agora que a foto acompanha a ficha, sem esta linha o convite
      -- nunca mais sairia: o texto tem conteudo, entao nao entra no caminho do
      -- anuncio, e o `v_fotos = 0` fechava o outro.
      IF NOT EXISTS (SELECT 1 FROM nai_saida s
                      WHERE s.turno_id = p_turno AND s.motivo = 'depois_das_fotos') THEN
        PERFORM nai_depois_das_fotos(p_turno, v_ordem + 5);
        v_textos := v_textos + 2;
      END IF;
    ELSIF NOT v_gate THEN
      PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno',
        'Quer fazer uma visita? Só me informar um horário', 'sugere_visita', v_ordem + 5);
      PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno',
        'Ou se tiver alguma dúvida ou quiser mais imóveis me fala o que está procurando, que já vejo aqui para você, ok?',
        'sugere_visita', v_ordem + 6);
      UPDATE nai_contato SET visita_sugerida_em = now() WHERE id = t.contato_id;
      v_textos := v_textos + 2;
    END IF;
  END IF;

  -- A LISTA DE DOCUMENTOS (93, Tel 22/09): ele pediu a documentacao, a lista
  -- sai atras da resposta dela, palavra por palavra como o Tel escreveu. Vem
  -- daqui e nao do prompt para nao ser reescrita a cada vez. Uma vez por turno.
  IF nai_pede_documentos(coalesce(p_escreveu, ''))
     AND btrim(coalesce(nai_cfg('documentos_locacao', ''), '')) <> ''
     AND NOT EXISTS (SELECT 1 FROM nai_saida s
                      WHERE s.turno_id = p_turno AND s.motivo = 'documentos') THEN
    PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno',
      nai_cfg('documentos_locacao', ''), 'documentos', v_ordem + 20);
    v_textos := v_textos + 1;
  END IF;

  PERFORM nai_anotar(p_turno, 20, 'montagem', 'passou', v_textos || ' mensagens e ' || v_fotos || ' fotos na caixa de saída');

  -- O TEXTO ESPERA AS FOTOS (113). Tem que ser aqui, com a caixa ja
  -- montada: so agora da para saber quantas fotos estao na frente de
  -- cada mensagem.
  -- A FILA DOS OUTROS IMOVEIS (114): ele pediu dois, recebe dois.
  -- Vem ANTES do espacamento de proposito -- assim o card do segundo
  -- tambem espera as fotos do primeiro terminarem.
  PERFORM nai_fila_dos_outros_imoveis(p_turno, p_escreveu);

  -- A REDE EMBAIXO DE TUDO (116): imovel que nao bate com o pedido nao
  -- vira mensagem, venha o erro da busca, do modelo ou de uma regra nova.
  PERFORM nai_conferir_imoveis_da_saida(p_turno);
  -- ...e a mesma rede no TEXTO (120f): imovel de parceiro citado dentro
  -- de uma lista escrita passava por baixo da parede do card.
  PERFORM nai_conferir_texto_da_saida(p_turno);

  PERFORM nai_espacar_depois_das_fotos(p_turno);

  RETURN jsonb_build_object('ok', true, 'textos', v_textos, 'fotos', v_fotos, 'guarda', d->>'guarda',
                            'mandou_fotos', v_gate, 'codigos', to_jsonb(v_cods));
END;
$function$;

CREATE OR REPLACE FUNCTION public.nai_conferir_resposta(p_turno bigint, p_texto text, p_codigos jsonb, p_escreveu text, p_fotos_site jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  t        nai_turno;
  k        nai_contato;
  v_texto  text := btrim(coalesce(p_texto, ''));
  v_guarda text;
  v_alvo   int;
  v_cods   int[];
  v_sem    int[] := '{}';
  v_gate   boolean := false;
  v_sugerir boolean := false;
  v_base   text;
  v_novo   text;
  v_corretor boolean;
  v_calada boolean;
  c_ok     int;
  c_card   text;
  v_n      int;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL THEN RETURN jsonb_build_object('acao', 'parou', 'motivo', 'turno_inexistente'); END IF;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;
  v_corretor := t.papel = 'corretor';
  v_calada := v_texto = '' OR upper(v_texto) ~ '^\W*SIL[EÊ]NCIO\W*$';

  -- 00p ------------------------------------------ PARCERIA (Tel, 28/09/2026)
  -- "Quando o corretor perguntar se aceitamos parceria, ela dizer 'Sim,
  -- aceitamos parceria em todos os nossos imoveis o que precisar pode contar
  -- com a gente'". Vem antes da secretaria de proposito: seja quem for que
  -- respondeu, a frase sai igual. Mensagem so de parceria = so a frase; com
  -- outro assunto junto, a frase vai na frente da resposta dela.
  IF t.papel = 'corretor' AND nai_pergunta_parceria(coalesce(p_escreveu, ''))
     AND v_texto !~* 'aceitamos parceria' THEN
    v_texto := nai_cfg('resposta_parceria', 'Sim, aceitamos parceria em todos os nossos imóveis, o que precisar pode contar com a gente!')
               || CASE WHEN v_calada OR nai_so_parceria(coalesce(p_escreveu, '')) THEN ''
                       ELSE E'\n\n' || v_texto END;
    PERFORM nai_anotar(p_turno, 0, 'parceria', 'mudou', 'resposta fixa de parceria');
    IF v_calada OR nai_so_parceria(coalesce(p_escreveu, '')) THEN
      RETURN jsonb_build_object('acao', 'responder', 'texto', v_texto, 'guarda', 'parceria', 'codigo', NULL);
    END IF;
    v_calada := false;
  END IF;

  -- 00 ------------------------------------------- A SECRETARIA (99)
  -- Turno da secretaria nao passa pelas guardas de locacao: elas cobram card,
  -- código e consulta à base, que é o fluxo da outra. Aqui vale o silêncio
  -- quando não há o que dizer, e nada mais.
  IF t.atendente = 'secretaria' THEN
    IF v_calada THEN
      RETURN jsonb_build_object('acao', 'silencio', 'guarda', 'secretaria_calada');
    END IF;
    RETURN jsonb_build_object('acao', 'responder', 'texto', v_texto,
                              'guarda', 'secretaria', 'codigo', NULL);
  END IF;

  -- 01 -------------------------------------------------- DE QUAL IMÓVEL É
  -- O código do turno (card marcado, card da resposta, o que ele escreveu) e,
  -- faltando esse, o imóvel da CONVERSA. O turno guarda o que achou: é o fio
  -- para a mensagem seguinte ("me manda as fotos dele").
  SELECT CASE WHEN count(DISTINCT x) = 1 THEN min(x)::int END INTO v_alvo
    FROM jsonb_array_elements_text(coalesce(p_codigos, '[]'::jsonb)) x WHERE x ~ '^[0-9]{3,5}$' AND x::int > 0;
  IF v_alvo IS NULL THEN v_alvo := nai_imovel_da_conversa(t.contato_id, p_escreveu); END IF;
  IF v_alvo IS NOT NULL THEN
    UPDATE nai_turno SET codigo = v_alvo WHERE id = p_turno AND codigo IS DISTINCT FROM v_alvo;
  END IF;
  PERFORM nai_anotar(p_turno, 1, 'imovel_da_conversa',
                     CASE WHEN v_alvo IS NULL THEN 'passou' ELSE 'mudou' END,
                     coalesce('imóvel ' || v_alvo, 'nenhum imóvel identificado'));

  -- 02 ------------------------------------------- FOTOS LIDAS NO SITE (camada 2)
  v_n := nai_gravar_fotos_do_site(p_fotos_site);
  PERFORM nai_anotar(p_turno, 2, 'fotos_do_site', CASE WHEN v_n > 0 THEN 'mudou' ELSE 'passou' END,
                     CASE WHEN v_n > 0 THEN v_n || ' fotos gravadas do anúncio' END);

  -- 02a ------------------------- LINK DE CATÁLOGO NÃO DIZ QUAL IMÓVEL É (111)
  -- Sem código na conversa, qualquer imóvel que ela mandasse aqui seria
  -- chute. O Tel recebe o link e responde; ela diz que recebeu, e não cala.
  IF t.papel = 'corretor' AND v_alvo IS NULL
     AND nai_e_link_de_produto(coalesce(p_escreveu, '')) THEN
    v_base := nai_escalar_link_de_catalogo(p_turno, p_escreveu);
    PERFORM nai_anotar(p_turno, 2, 'link_de_catalogo', 'mudou',
                       'link de produto sem código: subiu ao Tel');
    RETURN jsonb_build_object('acao', 'responder', 'texto', v_base,
                              'guarda', 'link_de_catalogo', 'codigo', NULL);
  END IF;

  -- 02b ------------------------------------------ ELA NÃO FAZ CADASTRO (97)
  -- Oferta de imóvel dele é pergunta para o Tel. Tem que ser AQUI, antes de
  -- tudo: o card e as fotos só são enfileirados depois que esta função
  -- devolve 'responder'. O Tel e o Fernando ficam de fora pelo papel.
  IF t.papel IN ('corretor', 'proprietario')
     AND NOT nai_secretaria_ligada()
     AND nai_oferece_imovel(coalesce(p_escreveu, '')) THEN
    PERFORM nai_escalar_cadastro(p_turno, p_escreveu);
    PERFORM nai_anotar(p_turno, 2, 'oferta_de_imovel', 'parou',
                       'ofereceu imóvel: subiu ao Tel e parou o chat');
    RETURN jsonb_build_object('acao', 'parou', 'guarda', 'oferta_de_imovel_foi_ao_tel');
  END IF;

  -- 03 --------------------------------- PERGUNTA SEM RESPOSTA / PROMESSA DE RETORNO
  -- Não existe "vou ver e te aviso": ou responde com a base, ou o Tel responde.
  IF v_corretor AND NOT (coalesce(t.ferramentas, '{}') && ARRAY['escalar', 'visita']::text[])
     AND ((v_calada AND coalesce(p_escreveu, '') ~ '\?') OR v_texto ~* nai_re_promessa()) THEN
    v_base := nai_escalar_calado(p_turno, p_escreveu,
      CASE WHEN v_texto ~* nai_re_promessa() THEN 'prometeu retorno' ELSE 'pergunta sem resposta' END, v_alvo);
    IF v_base IS NULL THEN
      PERFORM nai_anotar(p_turno, 3, 'promessa_ou_sem_resposta', 'parou', 'subiu ao Tel e parou o chat');
      RETURN jsonb_build_object('acao', 'parou', 'guarda', 'sem_resposta_foi_ao_tel');
    END IF;
    v_texto := v_base; v_calada := false; v_guarda := 'respondido_pela_base';
    PERFORM nai_anotar(p_turno, 3, 'promessa_ou_sem_resposta', 'mudou', 'a ficha respondeu no lugar');
  ELSIF v_corretor AND 'escalar' = ANY (coalesce(t.ferramentas, '{}')) AND v_texto ~* nai_re_promessa() THEN
    PERFORM nai_anotar(p_turno, 3, 'promessa_ou_sem_resposta', 'cortou', 'já escalou neste turno: promessa cortada');
    RETURN jsonb_build_object('acao', 'silencio', 'guarda', 'promessa_cortada');
  ELSE
    PERFORM nai_anotar(p_turno, 3, 'promessa_ou_sem_resposta', 'passou', NULL);
  END IF;

  -- 04 ----------------------------------------------- RESPOSTA SEM CONSULTA
  -- Afirmou sobre imóvel sem ter chamado ferramenta nenhuma.
  IF v_corretor AND '_lidas' = ANY (coalesce(t.ferramentas, '{}'))
     AND coalesce(array_length(array_remove(t.ferramentas, '_lidas'), 1), 0) = 0
     AND NOT v_calada
     AND v_texto !~ '\?\s*\S{0,3}\s*$'
     AND (coalesce(p_escreveu, '') ~ '\?' OR coalesce(p_escreveu, '') ~ '\m\d{3,5}\M')
     AND (coalesce(p_escreveu, '') || ' ' || v_texto) ~* nai_re_assunto_imovel()
     AND v_guarda IS DISTINCT FROM 'respondido_pela_base' THEN
    v_base := nai_escalar_calado(p_turno, p_escreveu, 'respondeu sem consultar a base', v_alvo);
    IF v_base IS NULL THEN
      PERFORM nai_anotar(p_turno, 4, 'resposta_sem_consulta', 'parou', 'afirmou sem ferramenta: subiu ao Tel');
      RETURN jsonb_build_object('acao', 'parou', 'guarda', 'resposta_sem_consulta_foi_ao_tel');
    END IF;
    v_texto := v_base; v_guarda := 'respondido_pela_base';
    PERFORM nai_anotar(p_turno, 4, 'resposta_sem_consulta', 'mudou', 'trocada pela resposta da ficha');
  ELSE
    PERFORM nai_anotar(p_turno, 4, 'resposta_sem_consulta', 'passou', NULL);
  END IF;

  -- 05 ------------------------------------------- O FORMATO É DO TEL, NÃO DO MODELO
  IF v_corretor AND v_alvo IS NOT NULL AND coalesce(p_escreveu, '') ~ '\?'
     AND v_texto !~* 'c[óo]digo:'
     AND NOT (coalesce(t.ferramentas, '{}') && ARRAY['escalar', 'visita']::text[]) THEN
    v_base := nai_resposta_da_base(v_alvo, p_escreveu);
    IF v_base IS NOT NULL AND v_texto IS DISTINCT FROM v_base THEN
      v_texto := v_base; v_calada := false;
      v_guarda := coalesce(v_guarda || '+', '') || 'formato_da_base';
      PERFORM nai_anotar(p_turno, 5, 'formato_da_base', 'mudou', 'resposta da ficha, no formato dele');
    ELSE
      PERFORM nai_anotar(p_turno, 5, 'formato_da_base', 'passou', NULL);
    END IF;
  ELSE
    PERFORM nai_anotar(p_turno, 5, 'formato_da_base', 'passou', NULL);
  END IF;

  -- 06 ------------------------------------------------------------- SILÊNCIO
  IF v_texto = '' OR upper(v_texto) ~ '^\W*SIL[EÊ]NCIO\W*$' THEN
    PERFORM nai_anotar(p_turno, 6, 'silencio', 'parou', 'ela não responde nada, de propósito');
    RETURN jsonb_build_object('acao', 'silencio', 'guarda', v_guarda);
  END IF;
  PERFORM nai_anotar(p_turno, 6, 'silencio', 'passou', NULL);

  -- 07 ---------------------------------------------------- A VOZ DE CADA PAPEL
  IF t.papel IN ('proprietario', 'motoboy') THEN
    v_novo := nai_sem_emoji(v_texto);
    PERFORM nai_anotar(p_turno, 7, 'voz_sem_emoji', CASE WHEN v_novo <> v_texto THEN 'mudou' ELSE 'passou' END,
                       'proprietário e ' || nai_acompanhante() || ': voz da captação');
    v_texto := v_novo;
  ELSE
    PERFORM nai_anotar(p_turno, 7, 'voz_sem_emoji', 'passou', NULL);
  END IF;

  -- 08 ------------------------------------------ SUGERIR VISITA (uma vez por dia)
  IF v_corretor AND v_texto !~ '\?'
     AND (v_guarda LIKE '%respondido_pela_base%' OR v_guarda LIKE '%formato_da_base%' OR v_texto ~* '^\s*sobre isso:'
          OR coalesce(t.ferramentas, '{}') && ARRAY['o_que_sei_do_imovel', 'imovel_por_codigo',
                                                    'disponibilidade_no_condominio', 'listar_no_condominio',
                                                    'resumo_do_condominio']::text[])
     AND NOT (coalesce(t.ferramentas, '{}') && ARRAY['escalar', 'visita']::text[])
     AND v_texto !~* nai_re_sugere_visita()
     AND coalesce((k.visita_sugerida_em AT TIME ZONE 'America/Manaus')::date, date '1900-01-01')
         <> (now() AT TIME ZONE 'America/Manaus')::date
     AND NOT EXISTS (SELECT 1 FROM nai_visita x WHERE x.corretor_id = k.id AND nai_visita_aberta(x.estado)) THEN
    v_sugerir := true;
    PERFORM nai_anotar(p_turno, 8, 'sugerir_visita', 'mudou', 'sai em outra mensagem, depois da resposta');
  ELSE
    PERFORM nai_anotar(p_turno, 8, 'sugerir_visita', 'passou', NULL);
  END IF;

  -- 09 ------------------------------------------ SUGESTÃO REPETIDA NO MESMO DIA
  IF v_corretor AND v_texto ~* nai_re_sugere_visita()
     AND NOT coalesce(nay_pede_visita(coalesce(p_escreveu, '')), false)
     AND NOT EXISTS (SELECT 1 FROM nai_visita x WHERE x.corretor_id = k.id AND x.estado IN ('coletando', 'negociando')) THEN
    IF (k.visita_sugerida_em AT TIME ZONE 'America/Manaus')::date = (now() AT TIME ZONE 'America/Manaus')::date THEN
      v_texto := btrim(regexp_replace(v_texto, '(\m(e|se)\s+)?' || nai_re_sugere_visita() || '[^?!\n]*[?!]?', '', 'gi'));
      v_guarda := 'visita_repetida_cortada';
      PERFORM nai_anotar(p_turno, 9, 'sugestao_repetida', 'cortou', 'já sugeriu visita hoje');
      IF v_texto = '' THEN
        RETURN jsonb_build_object('acao', 'silencio', 'guarda', v_guarda);
      END IF;
    ELSE
      UPDATE nai_contato SET visita_sugerida_em = now() WHERE id = k.id;
      PERFORM nai_anotar(p_turno, 9, 'sugestao_repetida', 'passou', 'primeira sugestão do dia, registrada');
    END IF;
  ELSE
    PERFORM nai_anotar(p_turno, 9, 'sugestao_repetida', 'passou', NULL);
  END IF;

  -- 10 --------------------------------------------- NEGOU IMÓVEL QUE EXISTE
  IF v_corretor AND v_texto ~* nai_re_nega_imovel() THEN
    SELECT i.codigo INTO c_ok
      FROM unnest(coalesce(nay_codigos_citados(coalesce(p_escreveu, '')), '{}'::text[])) x
      JOIN imoveis i ON i.codigo::text = x
     WHERE x ~ '^[0-9]{3,5}$'
       AND nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
     ORDER BY i.codigo LIMIT 1;
    IF c_ok IS NOT NULL THEN
      SELECT texto_pronto INTO c_card FROM nai_card_do_imovel(c_ok);
      IF coalesce(c_card, '') <> '' THEN
        v_texto := c_card;
        v_guarda := coalesce(v_guarda || '+', '') || 'negou_imovel_que_existe';
        PERFORM nai_anotar(p_turno, 10, 'negou_imovel_que_existe', 'mudou', 'negativa trocada pelo card do ' || c_ok);
      END IF;
    ELSE
      PERFORM nai_anotar(p_turno, 10, 'negou_imovel_que_existe', 'passou', 'negou, mas o código não é nosso ou não está no ar');
    END IF;
  ELSE
    PERFORM nai_anotar(p_turno, 10, 'negou_imovel_que_existe', 'passou', NULL);
  END IF;

  -- 11 -------------------------------------- FRASE DE VISITA SEM A FERRAMENTA
  IF v_corretor AND NOT ('visita' = ANY (coalesce(t.ferramentas, '{}')))
     AND v_texto ~* nai_re_frase_de_visita() THEN
    v_texto := nai_tirar_frase(v_texto, nai_re_frase_de_visita());
    v_guarda := coalesce(v_guarda || '+', '') || 'visita_sem_ferramenta';
    PERFORM nai_avisar_tel(p_turno, NULL,
      'Tel, o corretor ' || coalesce(k.nome_completo, k.nome_whatsapp, k.telefone) ||
      ' (' || nai_fone_fmt(k.telefone) || ') falou de visita e eu não consegui resolver aqui. Ele disse: "' ||
      left(coalesce(p_escreveu, ''), 300) ||
      E'". Não respondi nada e parei de responder esse chat: quem responde é você. Para eu voltar: DEVOLVER ' || nai_fone_fmt(k.telefone) || '.',
      'visita_sem_ferramenta');
    PERFORM nai_parar_chat(k.id, 'visita que eu nao consegui tratar');
    PERFORM nai_anotar(p_turno, 11, 'visita_sem_ferramenta', 'parou', 'falou de visita sem chamar a ferramenta');
    RETURN jsonb_build_object('acao', 'parou', 'guarda', v_guarda);
  END IF;
  PERFORM nai_anotar(p_turno, 11, 'visita_sem_ferramenta', 'passou', NULL);

  -- 12 ------------------------------------------------------ CITOU O TEL
  IF t.papel IN ('corretor', 'proprietario', 'motoboy') AND v_texto ~* '\mtel\M' THEN
    v_texto := nai_tirar_frase(v_texto, '\mtel\M');
    v_guarda := coalesce(v_guarda || '+', '') || 'citou_o_tel_cortado';
    PERFORM nai_anotar(p_turno, 12, 'citou_o_tel', 'cortou', 'quem sobe para o Tel não conta para ninguém');
    IF v_texto = '' THEN
      RETURN jsonb_build_object('acao', 'silencio', 'guarda', v_guarda);
    END IF;
  ELSE
    PERFORM nai_anotar(p_turno, 12, 'citou_o_tel', 'passou', NULL);
  END IF;

  -- 13 --------------------------------------------- UMA PERGUNTA POR MENSAGEM
  IF v_corretor THEN
    v_novo := nai_uma_pergunta_da_sequencia(v_texto);
    IF v_novo IS NOT NULL THEN
      v_texto := v_novo;
      v_guarda := coalesce(v_guarda || '+', '') || 'sequencia_uma_pergunta';
      PERFORM nai_anotar(p_turno, 13, 'uma_pergunta_por_mensagem', 'mudou', 'juntou duas perguntas: saiu só a primeira');
    ELSE
      PERFORM nai_anotar(p_turno, 13, 'uma_pergunta_por_mensagem', 'passou', NULL);
    END IF;
  ELSE
    PERFORM nai_anotar(p_turno, 13, 'uma_pergunta_por_mensagem', 'passou', NULL);
  END IF;

  -- 14 ------------------------------------------------------------- MARKDOWN
  v_novo := nai_limpar_markdown(v_texto);
  PERFORM nai_anotar(p_turno, 14, 'markdown', CASE WHEN v_novo <> v_texto THEN 'mudou' ELSE 'passou' END, NULL);
  v_texto := v_novo;

  -- 15 ------------------------------------------- DE QUAIS IMÓVEIS SÃO AS FOTOS
  SELECT coalesce(array_agg(DISTINCT x::int), '{}') INTO v_cods
    FROM jsonb_array_elements_text(coalesce(p_codigos, '[]'::jsonb)) x
   WHERE x ~ '^[0-9]{3,5}$' AND x::int > 0;
  IF t.papel IN ('corretor', 'tel') THEN
    -- AS FOTOS VAO SEMPRE (Tel, 16/09): falou de imovel, recebe informacao e
    -- foto na mesma resposta. Antes era preciso pedir "foto" com todas as
    -- letras, e quem escrevia "me encaminha o 5717" recebia so o card.
    v_gate := coalesce(nai_deve_mandar_fotos(t.contato_id, k.telefone, coalesce(p_escreveu, '')), false);
  END IF;
  IF v_gate AND coalesce(array_length(v_cods, 1), 0) = 0 THEN
    v_cods := array_remove(ARRAY[coalesce(v_alvo, nai_imovel_da_conversa(t.contato_id, p_escreveu))], NULL);
  END IF;
  -- SEM IMOVEL NAO HA FOTO. Com o portao sempre aberto, ele continuava "true"
  -- mesmo quando nao se sabe de qual imovel se fala -- e os passos seguintes
  -- tratavam a resposta como se fotos fossem sair. Medido: seis testes de
  -- formato e de sugestao de visita cairam por isso.
  IF v_gate AND coalesce(array_length(v_cods, 1), 0) = 0 THEN
    v_gate := false;
  END IF;

  -- IMOVEL INDISPONIVEL NAO LEVA FOTO (138): a resposta de situacao lista os
  -- disponiveis do mesmo condominio e pergunta qual interessa. As fotos saem
  -- quando ele escolher -- as do indisponivel, nunca (parede no gatilho).
  IF v_gate AND v_texto ~ '^Hmmm, vi aqui que o' THEN
    v_gate := false;
  END IF;

  -- NAO REPETE (Tel, 16/09): "o Tel ja tinha pedido manualmente para ela mandar
  -- as fotos do arezzo, mas ela foi la e mandou novamente". O imovel cujas
  -- fotos ja sairam para esta pessoa hoje sai da lista -- as informacoes
  -- continuam indo, so as fotos e que nao se repetem.
  -- ...A NAO SER QUE ELE PECA (Tel, 22/09: "manda de novo conforme
  -- solicitado"). A trava vale para foto que ele nao pediu.
  IF v_gate AND coalesce(array_length(v_cods, 1), 0) >= 1
     AND NOT nai_pede_foto(coalesce(p_escreveu, '')) THEN
    SELECT coalesce(array_agg(c), '{}') INTO v_cods
      FROM unnest(v_cods) c
     WHERE NOT nai_fotos_ja_mandadas(t.contato_id, c, 24);
    IF coalesce(array_length(v_cods, 1), 0) = 0 THEN
      v_gate := false;
    END IF;
  END IF;

  PERFORM nai_anotar(p_turno, 15, 'portao_de_fotos', CASE WHEN v_gate THEN 'mudou' ELSE 'passou' END,
                     CASE WHEN v_gate THEN 'ele pediu foto; imóveis: ' || coalesce(array_to_string(v_cods, ', '), 'nenhum')
                          ELSE 'ele não pediu foto' END);

  -- 16 ------------------------------- NEGOU FOTO QUE EXISTE / PROMETEU A QUE NÃO
  IF v_gate AND v_texto ~* nai_re_nega_foto() AND coalesce(array_length(v_cods, 1), 0) >= 1 THEN
    SELECT count(*) INTO v_n FROM imovel_fotos WHERE codigo = v_cods[1];
    IF v_n > 0 THEN
      v_texto := regexp_replace(v_texto, '[^.?!\n]*' || nai_re_nega_foto() || '[^.?!\n]*[.?!]?', 'segue as fotos', 'i');
      v_guarda := 'negacao_corrigida';
      PERFORM nai_anotar(p_turno, 16, 'negou_foto_que_existe', 'mudou', 'a foto existe: negativa trocada');
    END IF;
  END IF;
  IF v_gate THEN
    SELECT coalesce(array_agg(c), '{}') INTO v_sem FROM unnest(v_cods) c
     WHERE NOT EXISTS (SELECT 1 FROM imovel_fotos fx WHERE fx.codigo = c);
    IF coalesce(array_length(v_sem, 1), 0) >= 1 THEN
      -- 14/09: antes esta conferência TROCAVA a frase por "as fotos desse eu vou
      -- confirmar com o Tel e já te mando" -- promessa de retorno, que o fluxo
      -- v17 proíbe ("não existe vou ver e te aviso"). Agora a frase de foto
      -- (promessa ou negativa) sai fora e o Tel é avisado; o corretor não recebe
      -- promessa nenhuma.
      v_texto := nai_tirar_frase(v_texto, nai_re_promete_foto() || '|' || nai_re_nega_foto());
      PERFORM nai_avisar_tel(p_turno, NULL,
        'Tel, o corretor ' || coalesce(k.nome_whatsapp, k.telefone) || ' pediu fotos do ' ||
        array_to_string(v_sem, ', ') || ' e não achei foto nem no banco nem no anúncio do site. Pode me mandar?',
        'foto_inexistente');
      v_guarda := coalesce(v_guarda || '+', '') || 'promessa_sem_foto';
      PERFORM nai_anotar(p_turno, 17, 'foto_que_nao_existe', 'mudou', 'imóvel sem foto: o Tel foi avisado');
    ELSE
      PERFORM nai_anotar(p_turno, 17, 'foto_que_nao_existe', 'passou', NULL);
    END IF;
  ELSE
    PERFORM nai_anotar(p_turno, 17, 'foto_que_nao_existe', 'passou', NULL);
  END IF;

  RETURN jsonb_build_object(
    'acao', 'responder',
    'texto', v_texto,
    'guarda', v_guarda,
    'alvo', v_alvo,
    'cods', to_jsonb(v_cods),
    'gate', v_gate,
    'sugerir', v_sugerir);
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
  -- PARCERIA NAO SOBE AO TEL (138): a resposta e fixa.
  IF nai_pergunta_parceria(coalesce(nullif(p_disse, ''), t.texto, ''))
     AND nai_so_parceria(coalesce(nullif(p_disse, ''), t.texto, '')) THEN
    RETURN QUERY SELECT nai_cfg('resposta_parceria', 'Sim, aceitamos parceria em todos os nossos imóveis, o que precisar pode contar com a gente!');
    RETURN;
  END IF;
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

CREATE OR REPLACE FUNCTION public.nai_buscar_por_perfil(p_turno bigint, p_bairro text, p_teto text, p_quartos text, p_mobilia text)
 RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  t        nai_turno;
  k        nai_contato;
  b        record;
  v_teto   numeric := coalesce(nay_maior_valor(p_teto), nay_valor_em_reais(p_teto));
  v_q      int := NULLIF(regexp_replace(coalesce(p_quartos, ''), '[^0-9]', '', 'g'), '')::int;
  v_mob    text := lower(unaccent(btrim(coalesce(p_mobilia, ''))));
  v_sem    boolean;
  v_com    boolean;
  v_viz    text[];
  v_alt    text;
  v_aqui   text;
  v_txt    text;
  v_nome_b text;
  v_direta boolean;   -- entrou PEDINDO imovel, sem vir de um card
  v_negocio text;     -- venda, locacao, ambos (98)
  v_tipo   text;      -- 'Casa%', 'Apartamento%' ... (98)
  v_rotulo text;
  v_nada   text;
  v_diz    text;
  v_mostra_logo boolean;   -- mostrar em vez de peneirar (100)
  v_livre  boolean;        -- procurar na cidade inteira (102)
  v_perto  text;           -- o bairro parecido, quando ele escreve outro (105)
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;

  -- POR ONDE ELE ENTROU (Tel, 15/09: "ou a pessoa vem pelo grupo ou a pessoa
  -- manda msg pedindo imoveis especificos"). Nao precisa de marca nova: quem
  -- veio do grupo tem um imovel na conversa -- o card que colou, o codigo que
  -- escreveu, a foto que pediu. Quem chegou perguntando "tem apartamento de 2
  -- quartos?" nao tem nenhum.
  -- O texto do turno vai junto de proposito: e por ele que a funcao
  -- reconhece o card que ele acabou de colar, na PRIMEIRA mensagem --
  -- sem isso, quem cola o card e pede outras opcoes na mesma mensagem
  -- cairia no caminho de quem chegou do zero.
  v_direta := nai_imovel_da_conversa(k.id, t.texto) IS NULL;

  -- VENDA NAO E ALUGUEL, CASA NAO E APARTAMENTO (98, Tel 22/09). A sequencia
  -- de perguntas gasta tres mensagens: quando a busca roda, o texto do turno e
  -- so "700 mil". O que ele pediu no comeco esta nos turnos de tras -- por
  -- isso a leitura e da CONVERSA, e nao so desta mensagem.
  v_negocio := nai_negocio_da_conversa(k.id, concat_ws(' ', t.texto, p_teto));
  v_tipo    := nai_tipo_da_conversa(k.id, concat_ws(' ', t.texto, p_bairro));
  v_rotulo  := nai_rotulo_do_tipo(v_tipo);
  v_nada    := CASE WHEN v_rotulo IS NULL THEN 'nenhum imóvel'
                    WHEN v_rotulo IN ('casa', 'cobertura', 'sala', 'chácara') THEN 'nenhuma ' || v_rotulo
                    ELSE 'nenhum ' || v_rotulo END;
  v_diz     := CASE WHEN v_negocio = 'venda' THEN 'venda' ELSE 'locação' END;

  -- O TETO E DELE, MAS A LISTA E NOSSA (100, Tel 23/09). Ele pediu os
  -- valores, ou o que existe cabe numa mensagem: mostra, nao peneira.
  -- Com isso a sequencia de perguntas para de rodar em falso -- ela
  -- perguntou a faixa de preco TRES vezes ao Joao Luiz, que so queria ver a
  -- unica casa que temos no Nova Cidade.
  -- SEM PREFERENCIA DE BAIRRO (102, Tel 23/09). "Nao teria preferencia por
  -- bairro" nao era resposta aceita: a sequencia exigia um bairro, entao ela
  -- repetia a pergunta -- e repetiu, duas vezes, para a Deborah. Depois o
  -- modelo mandou "Manaus" como bairro e a busca antiga respondeu que NAO
  -- TRABALHAMOS COM IMOVEL EM MANAUS. A cidade nunca e bairro.
  v_livre := nai_e_a_cidade(p_bairro)
             OR nai_sem_preferencia_de_bairro(concat_ws(' ', p_bairro, t.texto));
  v_mostra_logo := nai_pede_os_valores(concat_ws(' ', t.texto, p_bairro))
                   OR nai_quantos_no_bairro(p_bairro, k.telefone, v_q, v_negocio, v_tipo)
                      BETWEEN 1 AND nai_cfg_int('limite_sem_teto', 5);
  IF v_mostra_logo THEN
    PERFORM nai_anotar(p_turno, 7, 'mostra_sem_peneirar', 'mudou',
                       'ele pediu os valores, ou o bairro tem pouca coisa');
  END IF;

  -- A SEQUENCIA DO FLUXO (cards do Tel): bairro -> faixa de preco -> mobilia,
  -- UMA PERGUNTA POR MENSAGEM. Quem manda a pergunta e esta funcao, nao o
  -- modelo: em 12/09 ele juntou duas perguntas numa mensagem so, duas vezes.
  -- Enquanto faltar resposta, ela devolve a PROXIMA pergunta e nada mais.
  -- O FILTRO DE IDENTIFICACAO (Tel, 28/09/2026): quem chegou pedindo imovel
  -- comeca pelo VALOR e depois os bairros, com a frase de abertura dele: "eu
  -- vou fazer um filtro com voce para poder te enviar as opcoes que mais podem
  -- atender a sua demanda. ate que valor o seu cliente quer? qual os bairros
  -- que atendem?". Uma pergunta por mensagem, como sempre. Quem veio do grupo
  -- segue o fluxo do site (bairro -> faixa -> mobilia), logo abaixo.
  IF v_direta AND nullif(btrim(coalesce(p_teto, '')), '') IS NULL AND NOT v_mostra_logo THEN
    RETURN QUERY SELECT
      CASE WHEN nullif(btrim(coalesce(p_bairro, '')), '') IS NULL AND NOT v_livre
           THEN 'Eu vou fazer um filtro com você para poder te enviar as opções que mais podem atender a sua demanda. Até que valor o seu cliente quer?'
           ELSE 'Até que valor o seu cliente quer?' END::text,
      ('filtro, pergunta 1 de 2. Diga SO isso, sem listar imovel nenhum e sem juntar outra pergunta. '
       || 'Quando ele responder, chame buscar_por_perfil de novo com o teto (e o bairro, se ele ja disse).')::text;
    RETURN;
  END IF;
  IF v_direta AND nullif(btrim(coalesce(p_bairro, '')), '') IS NULL AND NOT v_livre THEN
    RETURN QUERY SELECT 'E quais os bairros que atendem?'::text,
      ('filtro, pergunta 2 de 2. Diga SO essa pergunta. Quando ele responder, chame buscar_por_perfil '
       || 'de novo com o bairro e o teto.')::text;
    RETURN;
  END IF;

  IF nullif(btrim(coalesce(p_bairro, '')), '') IS NULL AND NOT v_livre THEN
    RETURN QUERY SELECT
      CASE WHEN v_direta
           -- ele chegou pedindo: nao existe "tambem", porque ela ainda nao
           -- ofereceu nada.
           THEN 'Claro! Você está procurando imóveis em qual bairro?'
           ELSE 'Eu também tenho outras opções de ' || v_diz || ', você está procurando imóveis em qual bairro?'
      END::text,
      ('etapa 1 de ' || CASE WHEN v_direta THEN '2' ELSE '3' END || ' da sequencia. Diga SO essa pergunta, '
       || 'sem listar imovel nenhum e sem juntar outra pergunta. Quando ele responder, chame '
       || 'buscar_por_perfil de novo com o bairro.')::text;
    RETURN;
  END IF;
  IF nullif(btrim(coalesce(p_teto, '')), '') IS NULL AND NOT v_mostra_logo THEN
    RETURN QUERY SELECT 'E qual a faixa de preço que seus clientes estão buscando?'::text,
      ('etapa 2 de ' || CASE WHEN v_direta THEN '2' ELSE '3' END || ' da sequencia. Diga SO essa pergunta, '
       || 'sem listar imovel nenhum e sem juntar outra pergunta. Quando ele responder, chame '
       || 'buscar_por_perfil de novo com bairro e teto.')::text;
    RETURN;
  END IF;
  -- A MOBILIA e a terceira pergunta SO de quem veio do grupo. Quem chegou
  -- pedindo imovel responde duas e ja ve a lista (Tel, 15/09: "essas 2
  -- perguntas padroes e mais filtros so se o cliente ja pedir"). Se ele falar
  -- de mobilia por conta propria, o filtro entra do mesmo jeito -- o valor
  -- chega em p_mobilia e e usado logo abaixo.
  IF NOT v_direta AND nullif(btrim(coalesce(p_mobilia, '')), '') IS NULL
     AND NOT v_mostra_logo THEN
    RETURN QUERY SELECT 'E eles têm preferência por semimobiliado ou mobiliado?'::text,
      ('etapa 3 de 3 da sequencia. Diga SO essa pergunta, sem listar imovel nenhum, e quando ele '
       || 'responder chame buscar_por_perfil de novo com bairro, teto e mobilia.')::text;
    RETURN;
  END IF;

  v_sem := v_mob ~ '\m(sem|nao|vazio)\M';
  v_com := NOT v_sem AND v_mob ~ '\m(com|mobiliad|semi|modulad|planejad)';

  -- O FORMATO E DO TEL (13/09, depois do teste: "me mandou 2 imoveis de forma
  -- desformatada, quero algo assim bem formatado"). Um bloco por imovel, com o
  -- icone, o nome em negrito do WhatsApp e o codigo com #.
  SELECT string_agg(nai_bloco_oferta(z.c, v_negocio), E'\n\n' ORDER BY z.v) INTO v_aqui FROM (
    SELECT i.codigo AS c,
           CASE WHEN v_negocio = 'venda' THEN i.valor_venda
                ELSE coalesce(i.valor_aluguel, i.valor_venda) END AS v
      FROM imoveis i
     WHERE (v_livre OR nay_normalizar_lugar(i.bairro, true) LIKE '%' || nay_normalizar_lugar(p_bairro, true) || '%')
       AND nai_oferta_serve(i, k.telefone, v_teto, v_q, v_sem, v_com, v_negocio, v_tipo)
     ORDER BY 2 LIMIT 5) z;

  v_viz := CASE WHEN v_livre THEN '{}'::text[]
                ELSE nay_bairros_proximos(btrim(coalesce(p_bairro, ''))) END;
  IF coalesce(array_length(v_viz, 1), 0) > 1 THEN
    SELECT string_agg(nai_bloco_oferta(z.c, v_negocio), E'\n\n' ORDER BY z.v) INTO v_alt FROM (
      SELECT i.codigo AS c,
             CASE WHEN v_negocio = 'venda' THEN i.valor_venda
                  ELSE coalesce(i.valor_aluguel, i.valor_venda) END AS v
        FROM imoveis i
       WHERE i.bairro = ANY (v_viz)
         AND nay_normalizar_lugar(i.bairro, true) NOT LIKE '%' || nay_normalizar_lugar(p_bairro, true) || '%'
         AND nai_oferta_serve(i, k.telefone, v_teto, v_q, v_sem, v_com, v_negocio, v_tipo)
       ORDER BY 2 LIMIT 5) z;
  END IF;

  -- NADA AQUI NEM PERTO (105, Tel 23/09: "nao e para ocorrer esse tipo de
  -- dupla busca, se eu coloco regra e para seguir").
  --
  -- Ate aqui, quando esta busca nao achava nada, quem respondia era a busca
  -- ANTIGA -- que nao conhece tipo, nem finalidade, nem faixa de teto. Era a
  -- unica porta por onde as regras dele nao passavam, e foi por ela que
  -- sairam dois apartamentos para quem pediu casa. Agora quem responde e
  -- aqui, com as mesmas regras do resto da funcao.
  IF v_aqui IS NULL AND v_alt IS NULL THEN

    -- 1. O BAIRRO EXISTE? Pode ser so o jeito de escrever.
    IF NOT v_livre AND NOT EXISTS (
         SELECT 1 FROM imoveis i
          WHERE nay_normalizar_lugar(i.bairro, true)
                LIKE '%' || nay_normalizar_lugar(p_bairro, true) || '%') THEN

      SELECT i.bairro INTO v_perto
        FROM imoveis i
       WHERE i.bairro IS NOT NULL AND btrim(i.bairro) <> ''
       GROUP BY i.bairro
       ORDER BY similarity(lower(unaccent(i.bairro)), lower(unaccent(coalesce(p_bairro, '')))) DESC
       LIMIT 1;

      IF v_perto IS NOT NULL
         AND similarity(lower(unaccent(v_perto)), lower(unaccent(coalesce(p_bairro, '')))) >= 0.45 THEN
        RETURN QUERY SELECT
          ('Você quis dizer ' || v_perto || '?')::text,
          ('o bairro que ele escreveu nao existe no catalogo, mas parece com este. '
           || 'Confirme com ele antes de procurar.')::text;
        RETURN;
      END IF;

      RETURN QUERY SELECT
        ('Não tenho imóvel nesse bairro. Em qual outro o cliente aceita?')::text,
        ('esse bairro nao esta no catalogo. NUNCA diga que nao trabalhamos em Manaus: '
         || 'a imobiliaria e de Manaus.')::text;
      RETURN;
    END IF;

    -- 2. O BAIRRO EXISTE, mas nao ha nada no perfil pedido. Dizer isso e a
    -- resposta certa -- trocar por outro tipo ou outro negocio nao e.
    RETURN QUERY SELECT
      (CASE WHEN v_livre
            THEN 'Não tenho ' || v_nada || ' nesse perfil disponível no momento.'
            ELSE 'No ' || initcap(btrim(coalesce(p_bairro, ''))) || ' não tenho ' || v_nada
                 || ' nesse perfil, nem nos bairros aqui perto.' END
       || CASE WHEN v_teto IS NULL
               THEN ' Me diz até que valor o cliente vai, que eu procuro em toda a cidade.'
               ELSE '' END)::text,
      ('nao existe nada no perfil pedido' || coalesce(' (' || v_rotulo || ')', '')
       || '. NAO ofereca outro tipo nem outra finalidade no lugar. Pergunte outro bairro '
       || 'ou outra faixa de preco.')::text;
    RETURN;
  END IF;

  SELECT coalesce((SELECT i.bairro FROM imoveis i
                    WHERE nay_normalizar_lugar(i.bairro, true) LIKE '%' || nay_normalizar_lugar(p_bairro, true) || '%'
                    LIMIT 1), initcap(btrim(p_bairro))) INTO v_nome_b;

  -- AREA (Tel, 18/09): quem pediu "Vieiralves" ouve "No Vieiralves", e nao o
  -- nome oficial do bairro. A busca ja procurou em Nossa Senhora das Gracas; so
  -- o jeito de falar acompanha a pessoa.
  SELECT coalesce((SELECT a.area FROM nai_area_citada(p_bairro) a LIMIT 1), v_nome_b)
    INTO v_nome_b;

  -- UM SO, em lugar nenhum mais: vai o CARD (Tel, 22/09, caso 162). O card traz
  -- "Codigo:", e e isso que faz o sistema mandar as fotos e o fechamento.
  IF (SELECT count(*) FROM regexp_matches(coalesce(v_aqui, '') || coalesce(v_alt, ''), ' #[0-9]{3,5}\*', 'g')) = 1 THEN
    RETURN QUERY SELECT
      (SELECT cc.texto_pronto FROM nai_card_do_imovel(
         (regexp_match(coalesce(v_aqui, '') || coalesce(v_alt, ''), ' #([0-9]{3,5})\*'))[1]::int) cc),
      ('e um imovel so nesse perfil: mande o card EXATAMENTE como veio. O sistema manda as '
       || 'fotos e a sugestao de visita logo depois.')::text;
    RETURN;
  END IF;

  IF v_aqui IS NOT NULL THEN
    v_txt := CASE WHEN v_livre THEN 'Tenho estas opções:'
                  ELSE 'No ' || v_nome_b || ' eu tenho estas opções:' END
             || E'\n\n' || v_aqui;
    IF v_alt IS NOT NULL THEN
      v_txt := v_txt || E'\n\n' || 'E tenho estas aqui perto:' || E'\n\n' || v_alt;
    END IF;
  ELSE
    v_txt := 'No ' || v_nome_b || ', não tenho ' || v_nada || ' nesse perfil disponível no momento.' || E'\n\n' ||
             'Mas tenho estas opções aqui perto:' || E'\n\n' || v_alt;
  END IF;

  -- DEPOIS DE UMA LISTA, A PERGUNTA E PADRAO (Tel, 22/09, caso 159: "faltou ela
  -- perguntar De qual deles a Sra. quer mais informacoes? isso tem que ser
  -- padrao apos o envio de uma lista"). Vem daqui, e nao do prompt, para nao
  -- depender de ela lembrar.
  v_txt := v_txt || E'\n\n' || 'Qual deles é de seu interesse? Assim, posso lhe enviar mais informações e detalhes.';

  RETURN QUERY SELECT v_txt,
    ('mande o texto_pronto EXATAMENTE como veio: cada imovel no seu bloco, com o icone, o negrito e as linhas com •. '
     || 'NAO resuma, NAO junte tudo numa linha, NAO reescreva e NAO invente imovel que nao esta na lista. '
     || 'Se ele quiser detalhe de um, chame imovel_por_codigo. NAO sugira visita aqui.')::text;
END;
$function$;

CREATE OR REPLACE FUNCTION public.nai_o_que_sei_do_imovel(p_codigo text, p_pergunta text)
 RETURNS TABLE(texto_pronto text, sabe boolean, instrucao_para_voce text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_cod  text := NULLIF(regexp_replace(coalesce(p_codigo, ''), '\D', '', 'g'), '');
  v_base text;
BEGIN
  -- A SITUACAO DO IMOVEL (Tel, 28/09/2026): disponivel -> status + card +
  -- fotos; qualquer outro status -> diz a situacao e ja lista os disponiveis
  -- do mesmo condominio (ou oferece outras opcoes perto). Parceria fica fora:
  -- quem fala de parceria e o Tel.
  IF length(v_cod) BETWEEN 3 AND 5 AND nai_pergunta_status(p_pergunta)
     AND EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = v_cod::int AND NOT coalesce(i.e_parceiro, false)) THEN
    RETURN QUERY SELECT s.texto_pronto, true, s.instrucao_para_voce FROM nai_status_do_imovel(v_cod::int) s;
    RETURN;
  END IF;
  IF length(v_cod) BETWEEN 3 AND 5 THEN
    v_base := nai_resposta_da_base(v_cod::int, p_pergunta);
  END IF;
  IF v_base IS NOT NULL THEN
    RETURN QUERY SELECT v_base, true,
      ('isto esta na ficha do imovel: mande o texto_pronto EXATAMENTE como veio, com as quebras de linha, ' ||
       'sem resumir, sem juntar numa frase so e sem emoji. NAO escale. NAO emende convite de visita: o sistema manda isso sozinho.')::text;
    RETURN;
  END IF;
  RETURN QUERY SELECT x.texto_pronto, x.sabe, x.instrucao_para_voce FROM nay_o_que_sei_do_imovel(p_codigo, p_pergunta) x;
END;
$function$;

CREATE OR REPLACE FUNCTION public.nay_qual_imovel(p_telefone text, p_horas integer DEFAULT 48)
 RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_tel   text := right(regexp_replace(coalesce(p_telefone,''),'[^0-9]','','g'),8);
  v_lista text;
  v_n     int;
  -- CORDIALIDADE (Tel, 16/09): "o Sr." / "a Sra." / "voce", pelo cadastro.
  -- Sem isto a frase saia com "voce" para todo mundo, inclusive para quem ela
  -- trata por Sr. no resto da conversa.
  v_pron  text;
BEGIN
  -- SEM SR. E SRA. (Tel, 28/09/2026): sempre "você".
  SELECT 'você'::text
    INTO v_pron
    FROM nai_contato k
   WHERE k.chave = nai_chave(coalesce(p_telefone, ''));
  v_pron := coalesce(v_pron, 'você');
  SELECT count(*), string_agg(linha, chr(10) ORDER BY quando DESC)
    INTO v_n, v_lista
  FROM (
    SELECT DISTINCT ON (e.codigo)
           '• ' || e.codigo || ' — '
           || coalesce(NULLIF(i.condominio_nome,''), i.tipo, 'imóvel')
           || coalesce(' (' || i.bairro || ')', '') AS linha,
           max(e.enviado_em) AS quando
      FROM envios e
      LEFT JOIN imoveis i ON i.codigo::text = e.codigo
     WHERE e.destino = 'corretor'
       AND right(regexp_replace(e.telefone,'[^0-9]','','g'),8) = v_tel
       AND e.enviado_em > now() - make_interval(hours => greatest(p_horas,1))
     GROUP BY e.codigo, i.condominio_nome, i.tipo, i.bairro
     ORDER BY e.codigo, max(e.enviado_em) DESC
     LIMIT 6
  ) s;

  IF coalesce(v_n,0) = 0 THEN
    RETURN QUERY SELECT
      ('De qual imóvel ' || v_pron || ' fala? Se tiver o código me manda, '
       || 'ou me diz o bairro que eu procuro aqui.')::text,
      ('voce NAO sabe de qual imovel ele fala e NAO mandou card nenhum para ele '
       || 'nas ultimas ' || p_horas || ' horas. PERGUNTE o codigo. NAO CHUTE, NAO '
       || 'use o ultimo imovel que voces conversaram e NAO use o ultimo imovel '
       || 'postado nos grupos -- sao mais de 3 por dia, e mandar informacao de um '
       || 'imovel como se fosse de outro e o pior erro possivel.')::text;
    RETURN;
  END IF;

  RETURN QUERY SELECT
    ('É de algum destes que te mandei?' || chr(10) || v_lista || chr(10)
     || '• nenhum desses — me diz o bairro ou o código')::text,
    ('sao ' || v_n || ' imoveis que voce mandou para ele. Mostre a lista do '
     || 'texto_pronto e deixe ele escolher -- nao peca o codigo seco, ele teria '
     || 'que ir procurar. A opcao "nenhum desses" tem que aparecer: ele pode '
     || 'estar falando de um card que veio de outro corretor, do grupo ou do '
     || 'site, e menu sem saida so empurra ele a escolher errado. '
     || 'NAO ESCOLHA POR ELE. '
     || 'Devolva o cumprimento dele antes da lista, se ele cumprimentou.')::text;
END;
$function$;

COMMIT;

-- ---------------------------------------------------------------------
-- 138b (aplicada logo depois): "você" com maiúscula no começo da frase.
-- "O Sr. quer visitar?" saía "você quer visitar?".
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION nai_sem_senhor(p text)
RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
  -- 138: tira "Sr." e "Sra.", deixando o nome ou "você" (com maiúscula no começo da frase).
  SELECT regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
           coalesce(p, ''),
           '\mSra?\.?\s+(?=[[:upper:]])', '', 'g'),
           '\m(do|da)\s+Sra?\M\.?', 'de você', 'g'),
           '\m(ao|à)\s+Sra?\M\.?', 'a você', 'g'),
           '\m(pro|pra|para o|para a)\s+Sra?\M\.?', 'pra você', 'g'),
           '\m(o|a|O|A)\s+Sra?\M\.?', 'você', 'g'),
           '\mSra?\M\.', 'você', 'g'),
           '(^|[.!?]\s+|\n\s*)você', '\1Você', 'g');
$fn$;
