-- =====================================================================
-- NAI atendimento locacao -- 05: fotos (com checagem dupla) e a
-- montagem da resposta na caixa de saida
--
-- O CASO QUE MOTIVOU (01/09): a Regiane perguntou "Tem imagens?" do 2014
-- e ouviu "desse imovel nao temos imagens" -- com 24 fotos no anuncio. A
-- tabela `imovel_fotos` estava vazia para ele. Camadas de agora:
--   1. a tabela `imovel_fotos`;
--   2. se ela esta VAZIA para um imovel nosso e no ar, o fluxo le o anuncio
--      AO VIVO no site (no "Buscar fotos no site") e grava aqui antes de
--      responder -- nunca apaga nada;
--   3. se mesmo assim ela NEGAR foto que existe, a frase e trocada e as
--      fotos saem (guarda de negacao);
--   4. se ela PROMETER foto que nao existe em lugar nenhum, a promessa vira
--      "vou confirmar com o Tel" e o Tel e avisado (guarda de promessa).
-- E cada foto sai amarrada ao codigo dela: o gatilho da saida confere no
-- banco que aquela URL e daquele imovel.
-- =====================================================================

-- Imoveis nossos, no ar, sem NENHUMA foto na tabela: esses o fluxo le no site.
CREATE OR REPLACE FUNCTION nai_fotos_faltando(p_codigos int[])
RETURNS int[] LANGUAGE sql STABLE AS $$
  SELECT coalesce(array_agg(i.codigo ORDER BY i.codigo), '{}')
    FROM imoveis i
   WHERE i.codigo = ANY (coalesce(p_codigos, '{}'))
     AND NOT coalesce(i.e_parceiro, false)
     AND coalesce(i.publicado_no_site, false)
     AND NOT EXISTS (SELECT 1 FROM imovel_fotos f WHERE f.codigo = i.codigo);
$$;

-- Grava as fotos lidas no site. So se o imovel AINDA estiver sem foto (a
-- varredura horaria pode ter chegado antes) e so URL do proprio site.
-- p_lote: [{"codigo": 2014, "urls": ["https://imobeasy.com/system/..."]}]
CREATE OR REPLACE FUNCTION nai_gravar_fotos_do_site(p_lote jsonb)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE
  e jsonb; v_cod int; v_urls text[]; n int := 0; i int;
BEGIN
  FOR e IN SELECT * FROM jsonb_array_elements(coalesce(p_lote, '[]'::jsonb)) LOOP
    v_cod := NULLIF(regexp_replace(coalesce(e->>'codigo', ''), '\D', '', 'g'), '')::int;
    -- mantem a ordem do site (a capa primeiro), sem repetir URL
    SELECT array_agg(u ORDER BY ord) INTO v_urls FROM (
      SELECT u, min(ord) AS ord FROM jsonb_array_elements_text(coalesce(e->'urls', '[]'::jsonb)) WITH ORDINALITY x(u, ord)
       WHERE u ~ '^https://imobeasy\.com/system/pictures/' GROUP BY u) y;
    IF v_cod IS NULL OR v_urls IS NULL OR NOT EXISTS (SELECT 1 FROM imoveis WHERE codigo = v_cod) THEN CONTINUE; END IF;
    IF EXISTS (SELECT 1 FROM imovel_fotos WHERE codigo = v_cod) THEN CONTINUE; END IF;
    FOR i IN 1..array_length(v_urls, 1) LOOP
      INSERT INTO imovel_fotos (codigo, ordem, url, e_capa) VALUES (v_cod, i, v_urls[i], i = 1);
      n := n + 1;
    END LOOP;
  END LOOP;
  RETURN n;
END;
$$;

-- Frases de NEGAR foto e de PROMETER foto. Uma funcao so, para o teste e o
-- fluxo lerem a mesma regra.
CREATE OR REPLACE FUNCTION nai_re_nega_foto() RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT '(n[ãa]o (tenho|temos|tem|h[áa]|encontrei|achei|localizei|possuo|consegui|disponho)[^.?!\n]{0,60}(fotos?|imagens?|imagem)'
      || '|sem (as |nenhuma )?(fotos?|imagens?)'
      || '|(fotos?|imagens?)[^.?!\n]{0,40}(n[ãa]o (est[ãa]o|tem|h[áa]|dispon|encontr|cadastr)|indispon))';
$$;
CREATE OR REPLACE FUNCTION nai_re_promete_foto() RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT '((segue|seguem|vou te (mandar|enviar|passar)|te (mando|envio|passo)|mandando|enviando|j[áa] (te )?mando)[^.?!\n]{0,25}(as |umas )?(fotos?|imagens?))';
$$;

-- Frase em que ELA sugere visita ("quer que eu ja veja um horario de visita?",
-- "se quiser agendar uma visita..."). Sempre comeca no verbo, para o corte
-- nao comer o que vem antes (um "4.300" tem ponto no meio).
CREATE OR REPLACE FUNCTION nai_re_sugere_visita() RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT '(quer|quiser|posso|podemos|vamos|bora|gostaria|que tal)[^.?!\n]{0,45}(agendar|agendamento|marcar|visita)';
$$;

-- Tira emoji. Era so do proprietario e do Fernando; desde 13/09 e de TUDO que
-- a Nay escreve (Tel: "diz para nao usar emojis"). O card do imovel nao passa
-- por aqui -- ele sai em bloco proprio, com os simbolos dos grupos.
CREATE OR REPLACE FUNCTION nai_sem_emoji(p text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT btrim(regexp_replace(regexp_replace(coalesce(p, ''),
         '[🀀-🫿☀-➿️‍]', '', 'g'), '[ 	]{2,}', ' ', 'g'));
$$;

-- ----------------------------------------------------- resposta do agente
-- A MONTAGEM DA RESPOSTA MUDOU DE ARQUIVO (14/09/2026).
--
-- `nai_enfileirar_resposta` e a esteira de conferencia que roda antes dela
-- agora moram em `15_conferencia.sql` -- o Tel pediu "checado bonitinho,
-- reorganiza e monta estruturado certinho", e as travas viraram 17 conferencias
-- numeradas, com registro em `nai_conferencia`.
--
-- NAO reponha a versao antiga aqui: um arquivo velho reaplicado apagaria a
-- esteira em silencio. O que sobrou neste arquivo sao as PECAS que a esteira
-- usa (fotos, frases proibidas, card, "depois das fotos").

-- Caminho do codigo puro ("5611" sozinho): card + todas as fotos, como a Nay
-- antiga faz -- mas pela caixa de saida.
CREATE OR REPLACE FUNCTION nai_enfileirar_card(p_turno bigint, p_codigo int)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE t nai_turno; v_card text; v_ordem int := 1; f record; n int := 0;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL OR t.papel NOT IN ('corretor', 'tel') THEN RETURN jsonb_build_object('ok', false); END IF;
  SELECT texto_pronto INTO v_card FROM nai_card_do_imovel(p_codigo);
  IF v_card IS NULL THEN
    PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno',
      'não achei nenhum imóvel com o código ' || p_codigo || '. confere pra mim?', 'codigo_inexistente', 1);
    RETURN jsonb_build_object('ok', true, 'achou', false);
  END IF;
  PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_card, 'card', 1);
  IF NOT EXISTS (SELECT 1 FROM imoveis WHERE codigo = p_codigo AND coalesce(e_parceiro, false)) THEN
    FOR f IN SELECT * FROM nai_imagens_do_envio(p_codigo) LOOP
      v_ordem := v_ordem + 1;
      INSERT INTO nai_saida (turno_id, contato_id, papel_destino, chave_destino, tipo, imagem_url, codigo, ordem, motivo)
           VALUES (p_turno, t.contato_id, 'turno', '', 'imagem', f.url, p_codigo, v_ordem,
                   CASE WHEN f.e_colagem THEN 'colagem' ELSE 'foto' END);
      n := n + 1;
    END LOOP;
  END IF;
  RETURN jsonb_build_object('ok', true, 'achou', true, 'fotos', n);
END;
$$;

-- O QUE SAI DE IMAGEM, e em que ordem (Tel, 12/09/2026): a COLAGEM das 4
-- primeiras fotos na frente, e as fotos soltas depois -- "a colagem na frente
-- e as fotos depois", palavras dele. A colagem e montada por
-- `montar_colagens.py` e mora em `imovel_colagem`; imovel sem colagem (menos
-- de 4 fotos, ou ainda nao montada) sai como sempre saiu.
-- Os tres lugares que enfileiram imagem chamam ESTA funcao: antes eram tres
-- laços iguais, e uma regra nova teria de ser escrita tres vezes.
CREATE OR REPLACE FUNCTION nai_imagens_do_envio(p_codigo int)
RETURNS TABLE(codigo int, url text, e_colagem boolean)
LANGUAGE sql STABLE AS $$
  -- SEM A COLAGEM AQUI (Tel, 14/09): "a foto metadinha e a foto que e mandada
  -- so na divulgacao dos grupos, e nao quando um corretor pede no pv; quando
  -- ele pede vao todas as fotos". A metadinha agora sai no disparo dos grupos,
  -- pelo publicador (`_fotos_para_grupo`) -- menos no grupo do Anunciar Easy,
  -- que leva todas.
  -- E SEM FOTO QUE JA E MOSAICO (Tel, 14/09): a capa do 4159 no site era uma
  -- montagem de 4 fotos, e ele viu isso como "a metadinha no pv". A foto
  -- marcada em `e_mosaico` (por marcar_mosaicos.py) nao sai no privado.
  SELECT x.codigo, x.url, x.e_colagem FROM (
    SELECT f.codigo, f.url, false AS e_colagem, 1 AS pos, coalesce(f.ordem, 999999) AS ordem, f.id
      FROM imovel_fotos f WHERE f.codigo = p_codigo AND f.e_mosaico IS NOT TRUE
  ) x
  WHERE coalesce(x.url, '') <> ''
  ORDER BY x.pos, x.ordem, x.id;
$$;

-- O card do imovel -- o MESMO formato do card que sai nos grupos
-- (`montar_mensagem.py` do publicador), por ordem do Tel em 12/09/2026:
-- titulo, Bairro, area, quartos, banheiros, vagas, sol, mobilia,
-- "Venda: R$", "Locação: R$", "Código:". Sem taxa de condominio e sem
-- endereco -- ele mandou o card de exemplo e disse "igual ao fluxo".
-- A ferramenta imovel_por_codigo usa esta mesma funcao.
CREATE OR REPLACE FUNCTION nai_card_do_imovel(p_codigo int)
RETURNS TABLE(texto_pronto text, qtd_fotos int)
LANGUAGE sql STABLE AS $$
  WITH b AS (
    SELECT i.*,
           CASE WHEN coalesce(nai_condominio_ok(i.condominio_nome), '') <> ''
                THEN nai_condominio_ok(i.condominio_nome)
                WHEN coalesce(i.bairro, '') = '' THEN coalesce(i.tipo, 'Imóvel ' || i.codigo)
                WHEN lower(i.bairro) ~ '^(conjunto|conj\.|cj)' THEN coalesce(i.tipo, 'Imóvel') || ' ' || i.bairro
                ELSE coalesce(i.tipo, 'Imóvel') || ' bairro ' || i.bairro END AS titulo
      FROM imoveis i WHERE i.codigo = p_codigo)
  SELECT
    CASE WHEN coalesce(b.e_parceiro, false) THEN
      '📍 ' || b.titulo || E'
• esse imovel e de parceria, nao da imob easy.'
    ELSE
      '📍 ' || b.titulo
      || CASE WHEN coalesce(b.bairro, '') <> '' AND position(lower(b.bairro) IN lower(b.titulo)) = 0
              THEN E'
• Bairro: ' || b.bairro ELSE '' END
      || CASE WHEN coalesce(b.area_util, 0) > 0 THEN E'
• ' || trim(to_char(b.area_util, 'FM999990')) || 'm2' ELSE '' END
      || CASE WHEN coalesce(b.quartos, 0) > 0 THEN E'
• ' || b.quartos || CASE WHEN b.quartos = 1 THEN ' quarto' ELSE ' quartos' END
              || CASE WHEN coalesce(b.suites, 0) > 0 THEN ' sendo ' || b.suites || CASE WHEN b.suites = 1 THEN ' suíte' ELSE ' suítes' END ELSE '' END ELSE '' END
      || CASE WHEN coalesce(b.banheiros, 0) > 0 THEN E'
• ' || b.banheiros || CASE WHEN b.banheiros = 1 THEN ' banheiro' ELSE ' banheiros' END ELSE '' END
      -- vagas: NULL em vagas_cobertas e "nao sei", nao "nenhuma" (mesma regra do publicador).
      || CASE WHEN coalesce(b.vagas, 0) = 0 AND coalesce(b.vagas_cobertas, 0) > 0
                THEN E'
• ' || b.vagas_cobertas || CASE WHEN b.vagas_cobertas = 1 THEN ' vaga coberta' ELSE ' vagas cobertas' END
              WHEN coalesce(b.vagas, 0) = 0 THEN ''
              WHEN b.vagas_cobertas IS NULL THEN E'
• ' || b.vagas || CASE WHEN b.vagas = 1 THEN ' vaga' ELSE ' vagas' END
              WHEN b.vagas_cobertas = 0 THEN E'
• ' || b.vagas || CASE WHEN b.vagas = 1 THEN ' vaga descoberta' ELSE ' vagas descobertas' END
              WHEN b.vagas_cobertas >= b.vagas THEN E'
• ' || b.vagas || CASE WHEN b.vagas = 1 THEN ' vaga coberta' ELSE ' vagas cobertas' END
              ELSE E'
• ' || b.vagas || CASE WHEN b.vagas = 1 THEN ' vaga' ELSE ' vagas' END
                   || ' sendo ' || b.vagas_cobertas || CASE WHEN b.vagas_cobertas = 1 THEN ' vaga coberta' ELSE ' vagas cobertas' END END
      || CASE WHEN lower(coalesce(b.sol, '')) ~ '^nascente' THEN E'
• nascente'
              WHEN lower(coalesce(b.sol, '')) ~ '^poente' THEN E'
• poente' ELSE '' END
      || CASE WHEN lower(coalesce(b.mobilia, '')) ~ '^semi' THEN E'
• semi-mobiliado'
              WHEN lower(coalesce(b.mobilia, '')) ~ '^mobiliad' THEN E'
• mobiliado'
              WHEN lower(coalesce(b.mobilia, '')) ~ 'ar.condicionado' THEN E'
• climatizado' ELSE '' END
      || CASE WHEN coalesce(b.valor_venda, 0) > 0
              THEN E'
Venda: R$ ' || replace(to_char(b.valor_venda, 'FM999,999,990'), ',', '.') ELSE '' END
      || CASE WHEN coalesce(b.valor_aluguel, 0) > 0
              THEN E'
Locação: R$ ' || replace(to_char(b.valor_aluguel, 'FM999,999,990'), ',', '.')
                   || CASE WHEN coalesce(b.extras->>'incluso no aluguel', '') ~* 'condom' THEN ' (incluso a tx)' ELSE '' END ELSE '' END
      || E'
Código: ' || b.codigo
    END,
    CASE WHEN coalesce(b.e_parceiro, false) THEN 0 ELSE (SELECT count(*)::int FROM imovel_fotos f WHERE f.codigo = b.codigo) END
  FROM b;
$$;

-- Numero fora do cadastro: a mesma cortesia da Nay antiga, e o Tel sabe.
CREATE OR REPLACE FUNCTION nai_enfileirar_cortesia(p_turno bigint, p_texto text)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE t nai_turno; k nai_contato;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;
  PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno',
    'oi! aqui é a Nay, da Imob Easy. por aqui eu atendo os corretores parceiros. se você é corretor e quer se cadastrar, me manda seu nome e CRECI que eu passo pro Tel.',
    'cortesia', 1);
  PERFORM nai_avisar_tel(p_turno, NULL,
    'número fora do cadastro escreveu: ' || coalesce(k.nome_whatsapp || ' ', '') || '(' || k.telefone || ')' ||
    E'\n\n"' || left(coalesce(p_texto, ''), 300) || '"', 'cortesia');
  RETURN jsonb_build_object('ok', true);
END;
$$;

-- Frases de "vou ver e te aviso" (Tel, 13/09: "nao existe isso"). Estreito de
-- proposito: "quer que eu ja veja um horario" e "me informa o dia" NAO entram.
CREATE OR REPLACE FUNCTION nai_re_promessa()
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT '(assim que (eu )?(tiver|souber|receber|ele responder|me responderem)|vou (verificar|confirmar|checar|consultar|perguntar)|(j[áa]|logo) te (retorno|aviso)|te (retorno|aviso) (em seguida|assim que|logo)|est(á|a|ou) verificando|n[ãa]o (tenho|sei|achei|encontrei) (essa|esta|a|nenhuma) informa)';
$$;

-- A mesma subida do escalar_ao_tel, feita pela saida quando a Nay nao escalou:
-- card "Pergunta ao responsavel (Tel)", ninguem mais e avisado e o chat para.
-- 13/09: ANTES de escalar, a ficha -- se `nai_resposta_da_base` responde, devolve
-- a resposta (quem chamou manda ela) e nada sobe. O codigo vem do que ele
-- escreveu; senao, do imovel unico do turno (card marcado / card da resposta).
DROP FUNCTION IF EXISTS nai_escalar_calado(bigint, text, text);
CREATE OR REPLACE FUNCTION nai_escalar_calado(p_turno bigint, p_escreveu text, p_motivo text, p_codigo_alvo int DEFAULT NULL)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE t nai_turno; k nai_contato; v_cod text; v_nome text; v_base text;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;
  IF k.id IS NULL THEN RETURN NULL; END IF;
  SELECT x INTO v_cod FROM unnest(coalesce(nay_codigos_citados(coalesce(p_escreveu, '')), '{}'::text[])) x
   WHERE x ~ '^[0-9]{3,5}$' LIMIT 1;
  IF v_cod IS NULL AND p_codigo_alvo IS NOT NULL THEN v_cod := p_codigo_alvo::text; END IF;
  IF v_cod IS NOT NULL THEN
    v_base := nai_resposta_da_base(v_cod::int, p_escreveu);
    IF v_base IS NOT NULL THEN RETURN v_base; END IF;
  END IF;
  v_nome := coalesce(k.nome_completo, k.nome_whatsapp, k.telefone);
  PERFORM nai_avisar_tel(p_turno, NULL,
    'Tel, o corretor ' || v_nome || ' (' || nai_fone_fmt(k.telefone) || ') perguntou sobre o ' ||
    coalesce(nai_ref_imovel(v_cod::int), 'imóvel') || ': "' || left(coalesce(p_escreveu, ''), 300) ||
    '". Não achei na base, você sabe?' ||
    E'\nNão falei nada com ele e parei de responder esse chat: quem responde é você. Para eu voltar: DEVOLVER ' || nai_fone_fmt(k.telefone) || '.',
    'duvida_fora_da_base');
  PERFORM nai_usou_ferramenta(p_turno, 'escalar');
  PERFORM nai_parar_chat(k.id, 'duvida fora da base (' || coalesce(p_motivo, '') || ')');
  RETURN NULL;
END;
$$;

-- Assunto de imovel (para a trava "resposta sem consulta"). Largo de proposito:
-- so age quando NENHUMA ferramenta rodou e ele perguntou ou citou codigo.
CREATE OR REPLACE FUNCTION nai_re_assunto_imovel()
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT '(mobiliad|quarto|su[ií]te|banheir|vaga|garagem|\mm2\M|metro|[áa]rea|andar|nascente|poente|valor|pre[çc]o|aluguel|loca[çc][ãa]o|condom[ií]nio|iptu|taxa|dispon[ií]vel|\mpet\M|animal|piscina|academia|portaria|endere[çc]o|bairro|aceita|financ|c[óo]digo)';
$$;

-- Porta de entrada do fluxo n8n (13/09): carimba no turno as ferramentas que o
-- modelo REALMENTE chamou (lista do agente) e so entao monta a resposta.
-- p_ferramentas NULL = o fluxo nao sabe (caminho do proprietario/Fernando).
CREATE OR REPLACE FUNCTION nai_enfileirar_resposta_ferramentas(p_turno bigint, p_texto text, p_codigos jsonb,
                                                               p_escreveu text, p_fotos_site jsonb, p_ferramentas jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
  IF p_ferramentas IS NOT NULL AND jsonb_typeof(p_ferramentas) = 'array' THEN
    PERFORM nai_usou_ferramenta(p_turno, '_lidas');
    PERFORM nai_usou_ferramenta(p_turno, x) FROM jsonb_array_elements_text(p_ferramentas) x WHERE btrim(x) <> '';
  END IF;
  RETURN nai_enfileirar_resposta(p_turno, p_texto, p_codigos, p_escreveu, p_fotos_site);
END;
$$;

-- A frase dela so anuncia as fotos ("As fotos ja estao sendo enviadas", "segue as
-- fotos", "as fotos do 4159 estao vindo")? Curta, fala de foto, sem card e sem
-- outra informacao.
CREATE OR REPLACE FUNCTION nai_so_anuncia_fotos(p text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT length(x) < 200
     AND x ~* '(foto|imagem|imagens)'
     AND x ~* '(vindo|segue|seguem|mand|envi|sendo|aqui|chegando|est[ãa]o|já|ja )'
     AND x !~* 'c[óo]digo:'
     AND x !~* '(quarto|vaga|valor|aluguel|condom|m2|bairro|dispon)'
  FROM (SELECT btrim(coalesce(p, '')) AS x) t;
$$;

-- As duas mensagens do Tel depois das fotos (13/09), literais. A primeira sugere
-- a visita: fica registrada como a sugestao do dia.
CREATE OR REPLACE FUNCTION nai_depois_das_fotos(p_turno bigint, p_ordem int)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE t nai_turno;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno',
    'Aqui as fotos, quer fazer uma visita? Só me informar um horário', 'depois_das_fotos', p_ordem + 1);
  PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno',
    'Ou se tiver alguma dúvida ou quiser mais imóveis me fala o que está procurando, que já vejo aqui para você, ok?', 'depois_das_fotos', p_ordem + 2);
  UPDATE nai_contato SET visita_sugerida_em = now() WHERE id = t.contato_id;
END;
$$;
