-- 428 (Pedro, 20/10/2026): CADASTRO DE IMÓVEL PELO WHATSAPP.
-- "CADASTRO DE IMÓVEL IMOBEASY: criei esse grupo e deixei a nay parceria cuidando dele. Nesse grupo o tel vai
-- encaminhar os imóveis e a nay vai montar um checklist de cadastro ... além do imóvel vai pedir o número da corretora
-- para salvar lá como proprietário (corretor = imóvel parceiro, proprietário = imóvel proprietário) ... as fotos que o
-- tel mandar ela vai cadastrar no nosso servidor, e as informações que faltar ela vai listar no grupo e perguntar ela
-- mesma pelo número da parceria ... qualquer erro ela vai avisar no grupo."
-- Quem faz é o serviço nay-cadastro (nay-cadastro/README.md). Aqui: o grupo fora do radar, a ficha de cada imóvel, a
-- fila das respostas no privado, a porta (nai_abrir_turno) e o telefone do cartão de contato no grupo.
BEGIN;

-- 1. O GRUPO É NOSSO: o radar e a captação ativa não leem os imóveis que o Tel encaminha (418).
INSERT INTO privado.grupo_fora (grupo_id, grupo_nome, motivo)
SELECT '120363414621414957-group', 'CADASTRO DE IMÓVEL IMOBEASY', 'o grupo do cadastro pelo WhatsApp (Pedro, 20/10)'
 WHERE NOT EXISTS (SELECT 1 FROM privado.grupo_fora WHERE grupo_id = '120363414621414957-group');

-- a chave do serviço: 'nao' para tudo na hora (o que chegar fica esperando)
INSERT INTO nai_config (chave, valor, descricao)
VALUES ('cadastro_whats', 'sim', '428: a Nay do cadastro pelo WhatsApp (serviço nay-cadastro). nao = para tudo na hora.')
ON CONFLICT (chave) DO NOTHING;

-- 2. A FICHA: um imóvel por leva de mensagens encaminhadas no grupo
CREATE TABLE IF NOT EXISTS privado.cadastro_whats (
  id             bigserial PRIMARY KEY,
  grupo_id       text NOT NULL,
  mensagens      text[] NOT NULL DEFAULT '{}',
  texto          text,
  fotos          jsonb NOT NULL DEFAULT '[]'::jsonb,
  contato_tel    text,
  contato_nome   text,
  papel          text CHECK (papel IN ('corretor', 'proprietario')),
  codigo         integer,
  condominio_id  integer,
  condominio_novo jsonb,
  ficha          jsonb NOT NULL DEFAULT '{}'::jsonb,
  faltam         text[] NOT NULL DEFAULT '{}',
  pergunta       text,
  perguntas_feitas integer NOT NULL DEFAULT 0,
  pergunta_em    timestamptz,
  cobrada_em     timestamptz,
  estado         text NOT NULL DEFAULT 'juntando'
                 CHECK (estado IN ('juntando', 'sem_contato', 'na_fila', 'perguntando', 'concluido', 'sem_resposta',
                                   'cancelado', 'erro')),
  erro           text,
  criado_em      timestamptz NOT NULL DEFAULT now(),
  atualizado_em  timestamptz NOT NULL DEFAULT now(),
  concluido_em   timestamptz
);
COMMENT ON TABLE privado.cadastro_whats IS
  '428: o imóvel que o Tel encaminhou no grupo CADASTRO DE IMÓVEL IMOBEASY, do texto até o cadastro concluído. ficha = o que já se sabe (chaves da API do site); faltam = as perguntas, na ordem; pergunta = a que está no ar no privado.';
COMMENT ON COLUMN privado.cadastro_whats.condominio_novo IS
  'o condomínio que ainda não existe: {nome, ...o que ele respondeu}; vira condominios + condominio_ficha quando as perguntas dele acabam';
CREATE INDEX IF NOT EXISTS cadastro_whats_aberto ON privado.cadastro_whats (estado, atualizado_em)
  WHERE estado NOT IN ('concluido', 'cancelado');

-- as mensagens do grupo que o serviço já leu (as que entraram numa ficha e as que não eram imóvel)
CREATE TABLE IF NOT EXISTS privado.cadastro_whats_lida (
  message_id  text PRIMARY KEY,
  cadastro_id bigint,
  lida_em     timestamptz NOT NULL DEFAULT now()
);

-- o que o serviço postou no grupo (o eco volta com de_mim e não pode virar imóvel)
CREATE TABLE IF NOT EXISTS privado.cadastro_whats_postada (
  message_id  text PRIMARY KEY,
  cadastro_id bigint,
  texto       text,
  em          timestamptz NOT NULL DEFAULT now()
);

-- 3. A FILA DAS RESPOSTAS: o que o corretor/proprietário responde no privado enquanto a ficha dele está aberta
CREATE TABLE IF NOT EXISTS privado.cadastro_whats_entrada (
  id          bigserial PRIMARY KEY,
  cadastro_id bigint NOT NULL REFERENCES privado.cadastro_whats (id),
  texto       text,
  midias      text[] NOT NULL DEFAULT '{}',
  ids         bigint[] NOT NULL DEFAULT '{}',
  status      text NOT NULL DEFAULT 'Recebido' CHECK (status IN ('Recebido', 'Processando', 'Feito')),
  criada_em   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS cadastro_whats_entrada_fila ON privado.cadastro_whats_entrada (status, criada_em)
  WHERE status <> 'Feito';

-- 4. QUEM ESTÁ RESPONDENDO: a ficha aberta (perguntando) deste número ou de um irmão dele (@lid, 2 linhas por pessoa)
CREATE OR REPLACE FUNCTION public.cadastro_whats_da_parceria(p_tel text, p_contato bigint DEFAULT NULL)
RETURNS bigint LANGUAGE sql STABLE SET search_path TO 'public', 'privado' AS $f$
  SELECT c.id FROM privado.cadastro_whats c
   WHERE c.estado = 'perguntando' AND c.contato_tel IS NOT NULL
     AND (nai_chave(c.contato_tel) = nai_chave(p_tel)
          OR nai_chave(c.contato_tel) IN (SELECT nai_chave(k.telefone) FROM nai_contato k
                                           WHERE k.id = ANY (coalesce(nai_contato_irmaos(p_contato), ARRAY[p_contato]))))
   ORDER BY c.pergunta_em DESC NULLS LAST, c.id DESC
   LIMIT 1
$f$;

-- 5. A BUSCA DO CONDOMÍNIO, flexível (Pedro, 20/10: "se ela digitar o nome do condomínio errado ela entenda que é o
-- certo, faz um regex bom"). O nome sem as palavras genéricas (condominio_nome_nucleo), sem acento, e quatro faixas:
-- 1 igual; 2 um contém o outro (palavras inteiras); 3 parecença forte (erro de digitação: "Life Parque Dês"); 4 fraca.
-- Só a faixa 1 a 3 casa sozinha; a 4 vira pergunta ("é o X?").
CREATE OR REPLACE FUNCTION public.cadastro_whats_condominio(p_texto text, p_bairro text DEFAULT NULL)
RETURNS TABLE (id integer, nome text, bairro text, faixa integer, parecenca numeric)
LANGUAGE sql STABLE SET search_path TO 'public', 'privado' AS $f$
  WITH alvo AS (
    SELECT condominio_nome_nucleo(p_texto) AS n,
           nullif(lower(nay_sem_acento(btrim(coalesce(p_bairro, '')))), '') AS b
  ), c AS (
    SELECT x.id, x.nome, x.bairro, condominio_nome_nucleo(x.nome) AS n,
           lower(nay_sem_acento(coalesce(x.bairro, ''))) AS b
      FROM condominios x
  ), f AS (
    SELECT c.id, c.nome, c.bairro,
           CASE WHEN c.n = a.n THEN 1
                WHEN (' ' || a.n || ' ') LIKE ('% ' || c.n || ' %') AND length(c.n) >= 4 THEN 2
                WHEN (' ' || c.n || ' ') LIKE ('% ' || a.n || ' %') AND length(a.n) >= 5 THEN 2
                WHEN similarity(c.n, a.n) >= 0.55 OR (word_similarity(a.n, c.n) >= 0.75 AND length(a.n) >= 5) THEN 3
                WHEN similarity(c.n, a.n) >= 0.35 OR word_similarity(a.n, c.n) >= 0.6 THEN 4 END AS faixa,
           round(greatest(similarity(c.n, a.n), word_similarity(a.n, c.n))::numeric, 2) AS parecenca,
           (a.b IS NOT NULL AND c.b = a.b) AS mesmo_bairro
      FROM c CROSS JOIN alvo a
     WHERE a.n IS NOT NULL AND c.n IS NOT NULL AND length(a.n) >= 3
  )
  SELECT f.id, f.nome, f.bairro, f.faixa, f.parecenca FROM f
   WHERE f.faixa IS NOT NULL
   ORDER BY f.faixa, f.mesmo_bairro DESC, f.parecenca DESC, f.id
   LIMIT 5
$f$;

-- 6. O CARTÃO DE CONTATO NO GRUPO GUARDA O TELEFONE. Antes ficava só "👤 Contato: NOME" e o número se perdia: o Tel
-- encaminha o contato do corretor junto do imóvel. A Z-API manda os números em contact.phones e no vCard (waid=).
CREATE OR REPLACE FUNCTION public.nai_grupo_guardar(p jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_tipo text; v_texto text; v_midia text; v_quando timestamptz;
BEGIN
  IF p IS NULL OR NOT coalesce((p->>'isGroup')::boolean, false)
     OR coalesce(btrim(p->>'messageId'), '') = '' OR coalesce(btrim(p->>'phone'), '') = '' THEN
    RETURN false;
  END IF;
  -- 338: AVISO (entrou, saiu, apagou), REAÇÃO e "aguardando mensagem" não são mensagem. Não entram: viravam balão
  -- vazio na aba, e o "aguardando" ocupava o id e barrava a mensagem de verdade que vinha depois.
  IF nullif(btrim(coalesce(p->>'notification', '')), '') IS NOT NULL
     OR jsonb_typeof(p->'reaction') = 'object'
     OR coalesce((p->>'waitingMessage')::boolean, false) THEN
    RETURN false;
  END IF;
  SELECT x.tipo, x.texto, x.midia INTO v_tipo, v_texto, v_midia FROM (VALUES
      ('texto',     'text',     p->'text'->>'message',        NULL),
      ('imagem',    'image',    p->'image'->>'caption',       p->'image'->>'imageUrl'),
      ('video',     'video',    p->'video'->>'caption',       p->'video'->>'videoUrl'),
      ('audio',     'audio',    NULL,                         p->'audio'->>'audioUrl'),
      ('documento', 'document', coalesce(p->'document'->>'caption', p->'document'->>'fileName'), p->'document'->>'documentUrl'),
      ('figurinha', 'sticker',  NULL,                         p->'sticker'->>'stickerUrl'),
      -- o que a aba não tem desenho próprio entra como texto, dizendo o que é
      ('texto',     'poll',     '📊 Enquete: ' || coalesce(p->'poll'->>'question', ''), NULL),
      -- 428: o telefone vai junto ("👤 Contato: NOME — 5592..."); sem ele o Tel não tinha como mandar o corretor
      ('texto',     'contact',  '👤 Contato: ' || coalesce(p->'contact'->>'displayName', '')
                               || coalesce(' — ' || coalesce(
                                    (SELECT string_agg(regexp_replace(t, '\D', '', 'g'), ' / ')
                                       FROM jsonb_array_elements_text(CASE WHEN jsonb_typeof(p->'contact'->'phones') = 'array'
                                                                           THEN p->'contact'->'phones' ELSE '[]'::jsonb END) t
                                      WHERE regexp_replace(t, '\D', '', 'g') <> ''),
                                    (SELECT string_agg(m[1], ' / ')
                                       FROM regexp_matches(coalesce(p->'contact'->>'vCard', ''), 'waid=(\d{8,15})', 'g') m)), ''),
                       NULL),
      ('texto',     'location', '📍 Localização: ' || coalesce(nullif(p->'location'->>'name', ''), p->'location'->>'address', ''), NULL)
    ) x(tipo, chave, texto, midia)
   WHERE jsonb_typeof(p->x.chave) = 'object'
   LIMIT 1;
  -- nada que a gente saiba ler: não guarda linha vazia
  IF v_tipo IS NULL OR (v_tipo = 'texto' AND nullif(btrim(coalesce(v_texto, '')), '') IS NULL) THEN
    RETURN false;
  END IF;
  v_quando := CASE WHEN coalesce(p->>'momment', '') ~ '^\d{12,14}$' THEN to_timestamp((p->>'momment')::bigint / 1000.0) ELSE now() END;
  INSERT INTO privado.grupo_conversa (message_id, grupo_id, grupo_nome, de_mim, remetente, remetente_nome,
                                      tipo, texto, midia_url, citado_id, enviada_em)
  VALUES (p->>'messageId', p->>'phone', nullif(btrim(coalesce(p->>'chatName', '')), ''),
          coalesce((p->>'fromMe')::boolean, false),
          nullif(regexp_replace(coalesce(p->>'participantPhone', ''), '\D', '', 'g'), ''),
          nullif(btrim(coalesce(p->>'senderName', '')), ''),
          v_tipo, left(v_texto, 8000), v_midia, nullif(p->>'referenceMessageId', ''), v_quando)
  -- a linha vazia que um evento antigo deixou com este id dá lugar à mensagem de verdade
  ON CONFLICT (message_id) DO UPDATE
     SET tipo = excluded.tipo, texto = excluded.texto, midia_url = excluded.midia_url, grupo_nome = excluded.grupo_nome,
         remetente = excluded.remetente, remetente_nome = excluded.remetente_nome, de_mim = excluded.de_mim,
         citado_id = excluded.citado_id, enviada_em = excluded.enviada_em
   WHERE privado.grupo_conversa.tipo = 'outro' AND privado.grupo_conversa.texto IS NULL AND privado.grupo_conversa.midia_url IS NULL;
  RETURN FOUND;
EXCEPTION WHEN OTHERS THEN
  RETURN false;     -- guardar mensagem de grupo nunca derruba o fluxo que chamou
END;
$function$;

-- 7. A PORTA: a resposta de quem está no cadastro vai para o serviço (bloco 428, logo depois do da OLX)
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
  v_rayssa  text;       -- 197: a conversa é da Rayssa (visita, fechamento, proprietário)
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
  -- 240: A DÚVIDA ERA DE OUTRO IMÓVEL. Chat pausado por "dúvida fora da base" e ele
  -- MARCA ou CITA um imóvel diferente do que foi escalado: a pausa cai e a Nay
  -- atende (a base pode saber a resposta do imóvel certo). O Tel é avisado.
  DECLARE
    v_irmaos bigint[] := coalesce(nai_contato_irmaos(v_contato), ARRAY[v_contato]);
    v_cit    int;
    v_esc    int;
  BEGIN
    IF EXISTS (SELECT 1 FROM nai_contato c WHERE c.id = ANY (v_irmaos) AND c.humano_motivo ~ '^duvida fora da base') THEN
      v_cit := coalesce(
        nullif(regexp_replace(coalesce(nay_imovel_da_citacao(p_citado_id), ''), '\D', '', 'g'), '')::int,
        (SELECT x::int FROM unnest(coalesce(nay_codigos_citados(v_texto), '{}'::text[])) x
          WHERE x ~ '^[0-9]{3,5}$' AND EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = x::int) LIMIT 1));
      SELECT t.codigo INTO v_esc FROM nai_turno t
       WHERE t.contato_id = ANY (v_irmaos) AND 'escalar' = ANY (coalesce(t.ferramentas, '{}'))
       ORDER BY t.id DESC LIMIT 1;
      -- 303: GENTE RESPONDEU HÁ POUCO: os 30 min de quem escreveu à mão valem mais que a 240.
      -- Em 04/10 "100% mobiliado" foi lido como o imóvel 100 e a Nay falou 1,5 min depois da equipe.
      IF v_cit IS NOT NULL AND v_cit IS DISTINCT FROM v_esc
         AND NOT nai_gente_escreveu_ha_pouco(v_irmaos) THEN
        UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL WHERE id = ANY (v_irmaos);
        BEGIN
          PERFORM nai_avisar_tel(NULL, NULL,
            'Tel, pode desconsiderar a dúvida de ' || coalesce(nullif(btrim(p_nome), ''), 'um corretor')
            || coalesce(' sobre o ' || nai_ref_imovel(v_esc), '') || ': ela falava de outro imóvel ('
            || coalesce(nai_ref_imovel(v_cit), 'código ' || v_cit) || '), marcou o card e eu voltei a atender.',
            'duvida_era_de_outro_imovel');
        EXCEPTION WHEN others THEN NULL;   -- o aviso nunca derruba o atendimento
        END;
      END IF;
    END IF;
  END;

  IF nai_tel_com_a_conversa(v_contato)
     AND NOT (v_teste AND v_texto ~* '^\s*(t|tel)\s*[:\-–]') THEN
    UPDATE mensagens SET status = 'Com o Tel' WHERE id = ANY (coalesce(p_ids, '{}')) AND status IN ('Recebido', 'Processando');
    RETURN jsonb_build_object('ok', false, 'motivo', 'tel_assumiu', 'contato_id', v_contato);
  END IF;

  -- 374 (Pedro, 15/10/2026): O DONO DA OLX NA PARCERIA. Quem conversa com a Nay proprietários da OLX pela Parceria
  -- não é corretor: a mensagem vai para a fila dela (captacao_mensagens, 'Recebido py', o serviço nay-captacao
  -- responde) e a NAI não atende. Depois do "o Tel assumiu", de propósito: gente no chat cala as duas.
  DECLARE v_olx bigint := captacao_olx_da_parceria(p_tel, v_contato);
  BEGIN
    IF v_olx IS NOT NULL THEN
      INSERT INTO captacao_mensagens (lead_id, telefone, direcao, origem, texto, status, criada_em)
      SELECT v_olx, l.telefone, 'recebida', 'texto', coalesce(p_texto, ''), 'Recebido py', now() - interval '20 seconds'
        FROM captacao_leads l WHERE l.id = v_olx AND btrim(coalesce(p_texto, '')) <> '';
      UPDATE captacao_leads SET status = CASE WHEN status IN ('enviado', 'reservado', 'erro') THEN 'respondendo' ELSE status END,
             respondeu_em = coalesce(respondeu_em, now()), atualizado_em = now()
       WHERE id = v_olx;
      RETURN jsonb_build_object('ok', false, 'motivo', 'olx_proprietario', 'contato_id', v_contato, 'lead_captacao', v_olx);
    END IF;
  END;

  -- 428 (Pedro, 20/10/2026): O CADASTRO PELO WHATSAPP. Enquanto a Nay do cadastro pergunta a este corretor (ou
  -- proprietário) o que falta do imóvel que o Tel mandou no grupo CADASTRO DE IMÓVEL IMOBEASY, a resposta é dela: vai
  -- para a fila do serviço nay-cadastro (privado.cadastro_whats_entrada) e a NAI não atende. Depois do "o Tel assumiu",
  -- como a OLX: gente no chat cala as duas. A ficha fechada (concluída, sem resposta) devolve a pessoa à Nay sozinha.
  DECLARE v_cad bigint := cadastro_whats_da_parceria(p_tel, v_contato);
  BEGIN
    IF v_cad IS NOT NULL THEN
      INSERT INTO privado.cadastro_whats_entrada (cadastro_id, texto, midias, ids)
      SELECT v_cad, nullif(btrim(coalesce(p_texto, '')), ''),
             coalesce((SELECT array_agg(m.midia_url ORDER BY m.id) FROM mensagens m
                        WHERE m.id = ANY (coalesce(p_ids, '{}')) AND m.midia_url IS NOT NULL
                          AND m.origem IN ('imagem', 'image', 'foto')), '{}'),
             coalesce(p_ids, '{}');
      UPDATE privado.cadastro_whats SET atualizado_em = now() WHERE id = v_cad;
      RETURN jsonb_build_object('ok', false, 'motivo', 'cadastro_whats', 'contato_id', v_contato, 'cadastro', v_cad);
    END IF;
  END;

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
    -- 28/09: `nai_e_voz_do_tel` no lugar da igualdade com `tel_telefone`.
    -- O Tel pediu um SEGUNDO número "como se fosse ele", e a regra de quem
    -- é o Tel passou a morar numa função só -- repetida nos quatro pontos,
    -- divergiria e daria comando aceito num caminho e recusado no outro.
    IF v_papel = 'corretor' AND nai_e_voz_do_tel(v_chave) AND nai_e_comando_tel(v_texto) THEN
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
    IF v_papel = 'corretor' AND NOT nai_e_voz_do_tel(v_chave)
       AND nai_e_comando_envio(v_texto) AND nai_e_da_equipe_contato(v_contato) THEN
      v_papel := 'tel';
    END IF;
    -- 184: "checklist aluguel para 92 ..." da equipe também é comando
    IF v_papel = 'corretor' AND nai_e_comando_checklist(v_texto) AND nai_e_da_equipe_contato(v_contato) THEN
      v_papel := 'tel';
    END IF;
    -- 141: o SIM/NAO da Rayssa (ou "SIM 123" de quem e da equipe) e comando.
    IF v_papel = 'corretor' AND (nai_resposta_aprovacao_valida(v_contato, v_texto)
                                 -- 142: o lembrete da equipe
                                 OR (nai_e_pedido_lembrete(v_texto) AND nai_e_da_equipe_contato(v_contato))) THEN
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
    IF nai_e_voz_do_tel(v_chave)
       OR (nai_e_comando_extra(v_texto) AND nai_pode_comandar(v_chave))
       -- o pedido de envio da equipe (135)
       OR (nai_e_comando_envio(v_texto) AND nai_e_da_equipe_contato(v_contato))
       -- 184: o checklist da equipe
       OR (nai_e_comando_checklist(v_texto) AND nai_e_da_equipe_contato(v_contato))
       -- 334: o SIM/NAO do Tel à pergunta "aviso no grupo que o imóvel saiu?"
       OR nay_saida_resposta_valida(v_contato, v_texto, p_citado_id)
       -- 141: a aprovacao da visita
       OR nai_resposta_aprovacao_valida(v_contato, v_texto)
       -- 142: o lembrete da equipe
       OR (nai_e_pedido_lembrete(v_texto) AND nai_e_da_equipe_contato(v_contato)) THEN
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
      -- 193: sem o sufixo @lid, nos dois formatos (o grupo grava so digitos).
      SELECT telefone INTO v_tel_lid FROM identidade_lid
       WHERE lid IN (regexp_replace(p_tel, '@lid$', ''), regexp_replace(p_tel, '@lid$', '') || '@lid')
       LIMIT 1;
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
  -- 287 (03/10): A LISTA DO GRUPO TAMBEM E MENSAGEM DE IMOVEL. O Osmar marcou a
  -- lista das 07:00 e escreveu "Bom dia Colega": contato novo, a citacao nao
  -- virava codigo (a lista tem 24) e a porta respondeu "assunto que nao e de
  -- corretor" -- silencio. Aqui a lista so ABRE A PORTA: o codigo do turno
  -- continua vindo de `nay_imovel_da_citacao`, que nao escolhe um imovel
  -- qualquer da lista. Quem escolhe e a Nay nova, pelo nome ou perguntando.
  SELECT * INTO v_porta FROM nai_deve_atender(
    p_tel, v_texto,
    coalesce(
      nullif(regexp_replace(coalesce(nay_imovel_da_citacao(p_citado_id), ''), '\D', '', 'g'), '')::int,
      (SELECT x.codigo FROM envios_lista_grupo x
        WHERE x.message_id = nullif(btrim(coalesce(p_citado_id, '')), '')
        ORDER BY x.posicao LIMIT 1)));
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

  -- 186 (Pedro, 29/09/2026: "diz para a Nay parar de responder o André, ele é
  -- da equipe, ela só manda avisos para ele, não atende"). O acompanhante só
  -- RECEBE aviso: a mensagem dele fica gravada (o turno e a resposta à visita,
  -- logo acima) e a Nay não responde -- o roteador do fluxo não manda nada com
  -- ok falso. Comando dele (envia/checklist) já virou papel 'tel' lá em cima.
  IF v_papel = 'motoboy' THEN
    -- 187 (Pedro, 29/09/2026: "continua avisando o Tel as conversas depois de
    -- alguém agendar uma visita, só para depois que é marcado visita
    -- finalizada"). Com visita dele agendada e ainda não finalizada, o que ele
    -- escreve vai para o Tel (a Nay continua sem responder); sem visita, silêncio.
    PERFORM nai_avisar_tel(NULL, x.id,
      'Tel, o ' || coalesce((SELECT e.nome FROM equipe e
                               WHERE right(regexp_replace(coalesce(e.telefone, ''), '[^0-9]', '', 'g'), 8)
                                   = right(regexp_replace(coalesce((SELECT telefone FROM nai_contato WHERE id = v_contato), ''), '[^0-9]', '', 'g'), 8)
                               LIMIT 1), nai_acompanhante())
      || ' (acompanhante) escreveu sobre a visita #' || x.id || ' (' || nai_ref_imovel(x.codigo) || ', '
      || nai_hora_exata(x.quando) || E'):\n"' || left(coalesce(v_texto, ''), 800) || '"',
      'acompanhante_escreveu')
      FROM nai_visita x
     WHERE x.motoboy_id = ANY (nai_contato_irmaos(v_contato))
       AND nai_visita_aberta(x.estado) AND x.estado <> 'realizada'
     ORDER BY x.quando NULLS LAST
     LIMIT 1;
    UPDATE nai_turno SET fechado_em = now() WHERE id = v_turno;
    RETURN jsonb_build_object('ok', false, 'motivo', 'acompanhante_so_recebe_aviso', 'turno_id', v_turno,
                              'contato_id', v_contato, 'papel', v_papel);
  END IF;

  -- 197 (Pedro, 30/09/2026): corretor com a visita confirmada (até ela acabar), em
  -- fechamento, ou proprietário: quem responde é a Rayssa, pelo CRM. A mensagem
  -- fica gravada e a Nay não responde (o mesmo "ok falso" do 186).
  IF v_papel IN ('corretor', 'proprietario') THEN
    v_rayssa := nai_com_a_rayssa(v_contato, v_papel);
    IF v_rayssa IS NOT NULL THEN
      UPDATE nai_turno SET fechado_em = now() WHERE id = v_turno;
      RETURN jsonb_build_object('ok', false, 'motivo', v_rayssa, 'turno_id', v_turno,
                                'contato_id', v_contato, 'papel', v_papel);
    END IF;
  END IF;

  -- 213: a RESPOSTA AUTOMÁTICA do WhatsApp Business do corretor ("estou ausente",
  -- "retornarei seu contato") não é mensagem dele: fica gravada e a Nay não responde.
  -- Em 30/09 uma delas ("Que 2026 seja um ano...") fez a Nay mandar um imóvel.
  IF v_papel = 'corretor' AND nai_e_resposta_automatica(v_texto) THEN
    UPDATE nai_turno SET fechado_em = now() WHERE id = v_turno;
    RETURN jsonb_build_object('ok', false, 'motivo', 'resposta_automatica', 'turno_id', v_turno,
                              'contato_id', v_contato, 'papel', v_papel);
  END IF;

  -- 269: O NÚCLEO NOVO (nay-core) ATENDE ESTE TURNO. Só o turno que ia para o agente
  -- do corretor (as mesmas condições do "Rotear pelo cabeçalho"), sem imagem nem
  -- documento, e que nai_core_atende() não segura aqui (visita, cadastro, teste).
  -- ok falso = o fluxo não manda nada; quem responde é o núcleo, lendo nai_core_turno.
  IF v_papel = 'corretor' AND NOT v_pausado
     AND (CASE WHEN lower(coalesce(nai_cfg('regra_publico', 'nao'), 'nao')) = 'sim' THEN v_porta.atende END) IS DISTINCT FROM false
     AND ((CASE WHEN lower(coalesce(nai_cfg('regra_publico', 'nao'), 'nao')) = 'sim' THEN v_porta.atende END) IS TRUE
          OR v_aprov IS TRUE)
     -- 306: foto, documento e vídeo também vão para o núcleo (ele responde "Recebi" e avisa o Tel)
     AND nai_core_atende(v_contato, v_texto) THEN
    INSERT INTO nai_core_turno (turno_id) VALUES (v_turno) ON CONFLICT DO NOTHING;
    UPDATE nai_turno SET fechado_em = now() WHERE id = v_turno;
    RETURN jsonb_build_object('ok', false, 'motivo', 'core_atende', 'turno_id', v_turno,
                              'contato_id', v_contato, 'papel', v_papel);
  END IF;

  -- 223: a resposta dele à pergunta do perfil ("só serve com elevador?") vai para o perfil
  IF v_papel = 'corretor' THEN
    PERFORM nai_perfil_resposta(v_contato, v_texto, v_turno);
  END IF;

  -- 141b: a etapa e atualizada ANTES de montar o cabecalho. Dentro do
  -- jsonb_build_object a ordem de avaliacao nao e garantida, e o contexto
  -- saiu com a etapa velha ("recebeu o imovel") no turno do "sim" da visita.
  IF v_papel = 'corretor' THEN
    PERFORM nai_etapa_atualizar(v_contato);
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
    -- 233: imagem, documento e vídeo do turno inteiro, para o ramo "Mídia para o Tel"
    'midias', nai_midias_do_turno(v_turno),
    'tem_midia_visual', jsonb_array_length(nai_midias_do_turno(v_turno)) > 0,
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
                        AND NOT nai_e_voz_do_tel(v_chave))
                    -- 184: o checklist, do Tel e da equipe
                    OR nai_e_comando_checklist(v_texto)
                    -- 334: SIM/NAO do Tel à pergunta do aviso de saída
                    OR nay_saida_resposta_valida(v_contato, v_texto, p_citado_id)
                    -- 391: a resposta do Tel à pergunta da fila (PV dele, uma por vez)
                    OR pergunta_fila_resposta_valida(v_contato, v_texto, p_citado_id)
                    -- 141: SIM/NAO da aprovacao da visita
                    OR nai_resposta_aprovacao_valida(v_contato, v_texto)
                    -- 142: o lembrete da equipe
                    OR (nai_e_pedido_lembrete(v_texto) AND nai_e_da_equipe_contato(v_contato)))),
    -- A BIBLIOTECA DE PALAVRAS (96, Tel 22/09) entra colada no contexto: so a
    -- explicacao da giria que ELE escreveu nesta mensagem, e nada quando nao
    -- ha giria nenhuma.
    -- 141: A ETAPA vem na frente do contexto (identificacao / recebeu o
    -- imovel / agendamento de visita) -- e o que a mantem no fio da conversa.
    'etapa', CASE WHEN v_papel = 'corretor' THEN (SELECT e.etapa FROM nai_etapa_contato e WHERE e.contato_id = v_contato) END,
    -- 235: a instrução da equipe (CRM) vem na frente de tudo, enquanto vale
    'contexto', CASE WHEN v_papel = 'corretor' THEN coalesce(nai_instrucao_texto(v_contato), '') END
                || CASE WHEN v_papel = 'corretor' THEN nai_etapa_para_o_modelo(v_contato) || E'\n' || coalesce(nai_retomada_texto(v_contato), '')
                        || coalesce(E'\n' || nai_perfil_texto(v_contato), '') ELSE '' END
                || nai_contexto(v_papel, v_contato, v_visita, v_teste)
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

COMMIT;
