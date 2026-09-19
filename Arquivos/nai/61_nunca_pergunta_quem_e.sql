-- =====================================================================
-- NAI -- 61: ela nunca pergunta com quem esta falando (Tel, 16/09/2026)
--
-- Ele: "ainda ficou perguntando quem era que estava falando, sendo que tem o
-- nome no cadastro -- e mesmo se nao tiver, nao precisamos desse dado, so
-- saber do imovel da pessoa. Eu quero que isso esteja como regra fundamental."
--
-- A FRASE, as 15:06 no chat do 92 9412-8057:
--   "Boa tarde! Entendi, ele esta alugado, mas ha flexibilidade para visita.
--    Antes de combinarmos o dia e o horario, COM QUEM EU FALO e qual e o
--    codigo do imovel?"
-- e a pessoa respondeu "Meu nome e Andresa".
--
-- Com esta parede, a mesma resposta sai assim:
--   "...Antes de combinarmos o dia e o horario, qual e o codigo do imovel?"
--
-- POR QUE UMA PAREDE E NAO SO UMA LINHA NO PROMPT: instrucao o modelo cumpre
-- quase sempre, e "quase" e o que chega ao corretor. Esta funcao roda no mesmo
-- ponto em que o emoji e retirado da resposta -- `nai_enfileirar_resposta` --,
-- entao a pergunta nao chega ao WhatsApp nem quando ele escorrega.
--
-- O NOME DO VISITANTE CONTINUA SENDO PEDIDO: o fluxo da visita precisa dele,
-- do CPF e do CRECI. Frase que fale de visitante, cliente, locatario, CPF ou
-- CRECI passa inteira.
--
-- CUIDADO QUE A BATERIA ENSINOU: a costura do texto usa so espaco e tab. A
-- primeira versao usava `\s`, que inclui o fim de linha, e amassava a ficha do
-- imovel num paragrafo so -- tres testes de formato caíram de uma vez.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.nai_sem_pergunta_de_identidade(p text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
  t text := coalesce(p, '');
  -- A PERGUNTA QUE ELA NUNCA FAZ (Tel, 16/09): "ficou perguntando quem era que
  -- estava falando, sendo que tem o nome no cadastro -- e mesmo se nao tiver,
  -- nao precisamos desse dado, so saber do imovel da pessoa. Quero que isso
  -- esteja como regra fundamental."
  --
  -- A frase que ele viu, as 15:06: "Antes de combinarmos o dia e o horario,
  -- com quem eu falo e qual e o codigo do imovel?" -- e a pessoa respondeu
  -- "Meu nome e Andresa", que e o dado que nao interessa a ninguem.
  --
  -- Os acentos entram nos padroes porque o texto dela vem acentuado: sem isso,
  -- "Qual E o seu nome?" passava batido enquanto "Qual e o seu nome?" saia.
  quem text := '(com quem (eu |eu estou |estou )?(falo|falando)'
            || '|quem (esta|está|ta|tá) (falando|ai|aí)'
            || '|quem (e|é|eh) que (esta|está|ta|tá) falando'
            || '|posso saber com quem (falo|estou falando))';
  nome text := '((qual|que) (e|é|eh)?\s*(o )?(seu|teu) nome'
            || '|como (e|é|eh)?\s*(o )?(seu|teu) nome'
            || '|(me )?(diz|diga|informa|fala|passa|manda) (o |qual )?(seu|teu) nome'
            || '|posso saber (o )?(seu|teu) nome'
            || '|(seu|teu) nome( completo)?,? por favor)';
BEGIN
  IF btrim(t) = '' THEN RETURN t; END IF;

  -- O NOME DO VISITANTE E OUTRA COISA: o fluxo da visita pede, de proposito, o
  -- nome e o CPF de quem vai entrar no imovel, e o CRECI do corretor. Se a
  -- frase fala disso, ela passa inteira.
  IF lower(unaccent(t)) ~ '(visitante|cliente|locatari|inquilin|quem vai (visitar|entrar)|acompanha|creci|cpf)' THEN
    RETURN t;
  END IF;

  -- 1) "Me diz SEU NOME e o codigo" -- o verbo fica, so o nome sai. Vem
  --    PRIMEIRO: se as regras de baixo rodassem antes, levariam o "Me diz"
  --    junto e sobraria "Certo! o codigo do imovel."
  t := regexp_replace(t, '(?i)\s*(o |qual )?(seu|teu) nome\s*,?\s+e\s+', ' ', 'g');

  -- 2) A pergunta com o conectivo que vem depois: "..., com quem eu falo E
  --    qual e o codigo?" -> "..., qual e o codigo?"
  --    A virgula da frente NAO e consumida -- ela separa o que fica.
  t := regexp_replace(t, '(?i)\s*' || quem || '\s*,?\s+e\s+', ' ', 'g');
  t := regexp_replace(t, '(?i)\s*' || nome || '\s*,?\s+e\s+', ' ', 'g');

  -- 3) A pergunta depois de um conectivo: "me diz o codigo e seu nome"
  t := regexp_replace(t, '(?i)\s*,?\s+e\s+' || quem, '', 'g');
  t := regexp_replace(t, '(?i)\s*,?\s+e\s+' || nome, '', 'g');

  -- 4) A pergunta sozinha, com o ponto de interrogacao dela.
  t := regexp_replace(t, '(?i)\s*,?\s*' || quem || '\s*[?.!]*', '', 'g');
  t := regexp_replace(t, '(?i)\s*,?\s*' || nome || '\s*[?.!]*', '', 'g');

  -- 5) Costura: o que sobrou de pontuacao e espaco.
  --
  -- SO ESPACO E TAB, NUNCA QUEBRA DE LINHA. A primeira versao usava `\s`, que
  -- inclui o fim de linha -- e a bateria pegou na hora: a ficha do imovel, que
  -- o Tel quer em linhas separadas ("Tem 3 quartos." / "Tem 2 banheiros."),
  -- virava um paragrafo so. Tres testes de formato cairam de uma vez.
  t := regexp_replace(t, '(?i)^[ \t]*,?[ \t]*(por favor|por gentileza)[ \t]*[?.!]*[ \t]*$', '', 'n');
  t := regexp_replace(t, '[ \t]{2,}', ' ', 'g');
  t := regexp_replace(t, '[ \t]+([,.!?])', '\1', 'g');
  t := regexp_replace(t, ',[ \t]*([.!?])', '\1', 'g');
  t := regexp_replace(t, '(?m)^[ \t]*[,;:][ \t]*', '', 'g');
  t := regexp_replace(t, '(?m)^[ \t]+', '', 'g');
  t := regexp_replace(t, '\n{3,}', chr(10) || chr(10), 'g');

  RETURN btrim(t);
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
  SELECT coalesce(array_agg(x::int), '{}') INTO v_cods FROM jsonb_array_elements_text(coalesce(d->'cods', '[]'::jsonb)) x;

  -- COM CARD: cada bloco termina no seu "Código: NNNN" e leva as fotos dele.
  IF v_texto ~* 'C[óo]digo:\s*\d{3,5}' AND (v_gate OR position('📍' IN v_texto) > 0) THEN
    FOR m IN SELECT (regexp_matches(v_texto, '(C[óo]digo:\s*(\d{3,5}))', 'gi')) AS g LOOP
      v_cod := m.g[2]::int;
      v_bloco := substr(v_texto, v_ini, strpos(substr(v_texto, v_ini), m.g[1]) + length(m.g[1]) - 1);
      v_ini := v_ini + length(v_bloco);
      v_ordem := v_ordem + 1;
      PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_bloco, 'resposta', v_ordem);
      v_textos := v_textos + 1;
      IF v_gate THEN
        FOR f IN SELECT * FROM nai_imagens_do_envio(v_cod) LOOP
          v_ordem := v_ordem + 1;
          INSERT INTO nai_saida (turno_id, contato_id, papel_destino, chave_destino, tipo, imagem_url, codigo, ordem, motivo)
               VALUES (p_turno, t.contato_id, 'turno', '', 'imagem', f.url, v_cod, v_ordem,
                       CASE WHEN f.e_colagem THEN 'colagem' ELSE 'foto' END);
          v_fotos := v_fotos + 1;
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
                     CASE WHEN f.e_colagem THEN 'colagem' ELSE 'foto' END);
        v_fotos := v_fotos + 1;
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
        'De qual imóvel o Sr. quer as fotos? Me passa o código que eu já mando.', 'foto_sem_imovel', v_ordem + 1);
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

  PERFORM nai_anotar(p_turno, 20, 'montagem', 'passou', v_textos || ' mensagens e ' || v_fotos || ' fotos na caixa de saída');

  RETURN jsonb_build_object('ok', true, 'textos', v_textos, 'fotos', v_fotos, 'guarda', d->>'guarda',
                            'mandou_fotos', v_gate, 'codigos', to_jsonb(v_cods));
END;
$function$;
