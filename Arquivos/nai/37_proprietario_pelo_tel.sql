-- =====================================================================
-- NAI -- 37: MENSAGEM DE PROPRIETARIO VAI PARA O TEL (Tel, 19/09/2026)
--
-- Nas palavras dele: "so as mensagens para proprietarios estao
-- temporariamente bloqueadas, entao elas vao para o tel no formato
-- 'Visita agendada, pergunte ao proprietario {nome} de numero {numero} se a
-- visita em tal hora pode ser realizada'".
--
-- ONDE: no `nai_liberar_saida`, encostado no desvio que o modo teste ja faz.
-- E a camada 2 (a liberacao), nao o gatilho da insercao: assim o desvio vale
-- para QUALQUER mensagem de proprietario, venha de onde vier, e as paredes do
-- gatilho (o destino tem que ser o dono daquela visita) continuam de pe.
--
-- TEMPORARIO: `nai_config.proprietario_pelo_tel`. Voltar ao normal e
--   UPDATE nai_config SET valor = 'nao' WHERE chave = 'proprietario_pelo_tel';
--
-- ESTE ARQUIVO FOI GERADO A PARTIR DA FUNCAO QUE ESTAVA NO BANCO, nao do
-- 03_saida.sql: o banco estava a frente do repositorio (o `v_cmd` e o
-- `nai_tel_com_a_conversa`, de 16/09, nunca voltaram para o arquivo).
-- Reaplicar o 03_saida.sql DEPOIS deste arquivo desfaz as duas coisas.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO nai_config (chave, valor, descricao, atualizado_em)
VALUES ('proprietario_pelo_tel', 'sim',
        'sim = a NAI nao manda nada para proprietario; o que iria para ele vai para o Tel, com o nome e o numero de quem ligar. Temporario (Tel, 19/09).',
        now())
ON CONFLICT (chave) DO UPDATE SET valor = 'sim', descricao = EXCLUDED.descricao, atualizado_em = now();

CREATE OR REPLACE FUNCTION public.nai_liberar_saida(p_turno bigint)
 RETURNS TABLE(id bigint, rota text, telefone text, chave_esperada text, corpo jsonb, codigo integer, papel text, redirecionado boolean)
 LANGUAGE plpgsql
AS $function$
#variable_conflict use_column
DECLARE
  r          record;
  v_modo     text := nai_cfg('modo', 'desligado');
  v_pausada  boolean := nai_cfg('pausada', 'sim') <> 'nao';
  v_simulado boolean := nai_cfg('envio_simulado', 'nao') = 'sim';
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
BEGIN
  FOR r IN
    SELECT s.* FROM nai_saida s
     WHERE s.estado = 'pendente'
       AND s.enviar_apos <= now()
       AND ((p_turno IS NOT NULL AND s.turno_id = p_turno)
         OR (p_turno IS NULL AND (s.turno_id IS NULL OR s.criado_em < now() - interval '3 minutes')
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
          AND NOT (r.papel_destino = 'turno' AND (SELECT t2.papel FROM nai_turno t2 WHERE t2.id = r.turno_id) = 'tel') THEN
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
             WHERE s2.contato_id = r.contato_id AND s2.estado IN ('enviado', 'simulado')
               AND s2.tipo = 'texto' AND s2.texto = r.texto
               AND s2.visita_id IS NOT DISTINCT FROM r.visita_id
               AND s2.enviado_em > greatest(now() - interval '10 minutes',
                     coalesce((SELECT k3.zerado_em FROM nai_contato k3 WHERE k3.id = r.contato_id), '-infinity'::timestamptz))) THEN
      v_bloq := 'repetida';
    ELSIF r.tipo = 'imagem' AND EXISTS (
            SELECT 1 FROM nai_saida s2
             WHERE s2.contato_id = r.contato_id AND s2.estado IN ('enviado', 'simulado')
               AND s2.tipo = 'imagem' AND s2.imagem_url = r.imagem_url
               AND s2.enviado_em > greatest(now() - interval '10 minutes',
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

    IF v_simulado THEN
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
$function$

;

COMMIT;
