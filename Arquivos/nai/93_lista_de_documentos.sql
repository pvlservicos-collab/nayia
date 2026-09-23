-- =====================================================================
-- NAI -- 93: a lista de documentos do inquilino (Tel, 22/09/2026)
--
-- Ele: "quando pedir lista de documentacao, envia essa" -- e colou a lista.
--
-- VAI PARA O BANCO, NAO PARA O PROMPT. Texto que tem que sair palavra por
-- palavra mora em `nai_config` e e enfileirado pelo sistema; no prompt o
-- modelo reescreveria ("...e tambem o comprovante de renda, ok?") e mudaria
-- a lista a cada vez. E a mesma decisao do card e das mensagens de visita.
--
-- COMO FUNCIONA: quando o corretor PEDE documentacao, a resposta dele sai
-- normal e o sistema manda a lista logo atras, uma vez por turno. A frase
-- fica editavel em `nai_config.documentos_locacao`, sem deploy.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO nai_config (chave, valor, descricao)
VALUES ('documentos_locacao',
E'✅ INQUILINO (LOCATÁRIO) — de CADA pessoa que vai assinar\n\n'
 || E'- RG e CPF ou CNH (frente e verso, legível)\n'
 || E'- Nacionalidade, profissão, estado civil\n'
 || E'- Telefone/WhatsApp e e-mail\n'
 || E'- Endereço completo com CEP (se for comercial, avisar)\n'
 || E'- Comprovante de renda: 3 contracheques, 3 extratos ou IR\n'
 || E'- Comprovante de residência\n'
 || E'- Se PJ: contrato social, CNPJ e documentos do sócios\n'
 || E'- Comprovante de renda: 3 últimos contracheques ou, se autônomo, 6 últimos extratos bancários\n'
 || E'- Data de início da locação',
 'A lista de documentos que sai quando o corretor pede a documentação. Texto do Tel (22/09).')
ON CONFLICT (chave) DO UPDATE SET valor = EXCLUDED.valor, atualizado_em = now();

-- Quem esta pedindo a lista? Exige a PALAVRA documento/documentacao junto de
-- um pedido -- assim "ja mandei os documentos para o proprietario" nao dispara.
CREATE OR REPLACE FUNCTION public.nai_pede_documentos(p_texto text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  -- PEDIDO, e nao mencao. "manda" precisa terminar ali (senao "mandei os
  -- documentos para o proprietario" dispararia), e "document..." pega
  -- documento, documentos e documentacao de uma vez.
  WITH s AS (SELECT lower(unaccent(coalesce(p_texto, ''))) AS x)
  SELECT
      (x ~ '\m(quais|qual|que|lista|relacao|manda|mande|envia|envie|passa|preciso|precisa|necessari\w*|pede|pedir|exige|exigem|falta|faltam)\M[^.?!]{0,40}\m(document\w*|docs)\M'
       OR x ~ '\m(document\w*|docs)\M[^.?!]{0,40}\m(quais|qual|precisa|preciso|necessari\w*|pede|exige)\M'
       OR x ~ '^\s*(documenta[cç][aã]o|documentos)\s*[?!.]*\s*$')
  FROM s;
$function$;

COMMIT;

-- Prova: o que pede a lista e o que so fala de documento.
SELECT t AS mensagem, nai_pede_documentos(t) AS manda_a_lista
  FROM unnest(ARRAY[
    'Nay, quais documentos precisa pra alugar?',
    'me manda a lista de documentos por favor',
    'qual a documentação necessária?',
    'documentação?',
    'Preciso dos documentos do inquilino',
    'ja mandei os documentos para o proprietario assinar',
    'o cliente vai levar os documentos na visita',
    'tem apartamento de 2 quartos no Aleixo?'
  ]) t;
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

  RETURN jsonb_build_object('ok', true, 'textos', v_textos, 'fotos', v_fotos, 'guarda', d->>'guarda',
                            'mandou_fotos', v_gate, 'codigos', to_jsonb(v_cods));
END;
$function$;
