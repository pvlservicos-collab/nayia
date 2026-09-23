-- =====================================================================
-- NAI -- 74: o padrao de atendimento vai junto com o card (Tel, 21/09/2026)
--
-- Ele: 'sempre que ela mandar o card e para ja mandar as fotos e aquela
-- mensagem depois perguntando... isso e o padrao de atendimento ao se
-- enviar um imovel, nao deve mudar e sim se manter sempre'.
--
-- CARD + FOTOS JA FUNCIONAVA: 9 dos 10 cards enviados a corretor de verdade
-- desde 15/09 sairam com foto. O que ele viu sem foto foi a rodada 3 do
-- treino, onde a trava de 24h (nai_fotos_ja_mandadas) fechou o portao
-- porque a rodada 2 ja tinha mandado as mesmas fotos ao mesmo espelho.
--
-- O QUE FALTAVA ERA O FECHAMENTO. Ele so saia quando ela nao tinha mais
-- nada a dizer depois do card. Se escrevesse uma frase a mais, o ELSIF
-- levava a frase dela E DESCARTAVA o padrao. Em 19/09, dois dos quatro
-- cards do dia sairam assim.
--
-- Funcao copiada VIVA do pg_proc e remendada -- o .sql antigo do repo esta
-- atras do banco.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

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

COMMIT;
