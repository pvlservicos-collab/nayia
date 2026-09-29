-- 184 -- o comando do checklist no roteamento e no comando da Nay (Pedro,
-- 29/09/2026). GERADO das funções vivas (pg_proc) por patch_184.py -- não
-- reaplicar um .sql antigo destas funções. Ver a 183.

BEGIN;
SET LOCAL lock_timeout = '5s';

-- "checklist venda" sozinho (sem verbo nem número) também é pedido: vira pergunta
CREATE OR REPLACE FUNCTION nai_ler_pedido_de_checklist(p text)
RETURNS TABLE(telefone text, tipo text)
LANGUAGE plpgsql IMMUTABLE AS $f$
DECLARE
  s      text := lower(unaccent(btrim(coalesce(p, ''))));
  v_fone text := '(?:55[\s.-]*)?\(?[0-9]{2}\)?[\s.-]*[0-9]{4,5}[\s.-]*[0-9]{4}';
  m      text[];
BEGIN
  IF s !~ '(che(ck|k|c|q)u?e?[\s-]*li?st|lista\s+de\s+documentos|check\s*-?\s*list)' THEN
    RETURN;
  END IF;
  -- é pedido de envio, não conversa: curto, e com verbo de mandar, número, ou
  -- começando pela palavra do checklist
  IF length(s) > 160 OR (s !~ '(envi|mand|repass|encaminh)' AND s !~ v_fone
                         AND s !~ '^(@?nay[\s,;:.!-]*)?(o\s+|a\s+)?(che(ck|k|c|q)u?e?[\s-]*li?st|lista\s+de\s+documentos)') THEN
    RETURN;
  END IF;
  m := regexp_match(s, '(' || v_fone || ')');
  RETURN QUERY SELECT
    CASE WHEN m IS NOT NULL THEN m[1] END,
    CASE WHEN s ~ '(alug|loca[cç]|inquilin|locat)' AND s !~ '(vend|compr)' THEN 'locacao'
         WHEN s ~ '(vend|compr)' AND s !~ '(alug|loca[cç]|inquilin|locat)' THEN 'venda' END;
END;
$f$;

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
    'contexto', CASE WHEN v_papel = 'corretor' THEN nai_etapa_para_o_modelo(v_contato) || E'\n' ELSE '' END
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

  -- 142: o lembrete da equipe ("me lembra as 15h de ...", "meus lembretes",
  -- "cancela lembrete 12").
  IF nai_e_pedido_lembrete(s) AND nai_e_da_equipe_contato(t.contato_id) THEN
    v_msg := nai_comando_lembrete(p_turno, s);
    PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_msg, 'comando_lembrete', 1);
    RETURN QUERY SELECT v_msg; RETURN;
  END IF;

  -- 141: SIM <n> / NAO <n> / TELEFONE <n> <numero> -- a aprovacao da visita.
  IF nai_resposta_aprovacao_valida(t.contato_id, s) THEN
    v_msg := nai_aprovar_visita(p_turno, s);
    PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_msg, 'comando_aprovacao', 1);
    RETURN QUERY SELECT v_msg; RETURN;
  END IF;

  -- 184: CHECKLIST (Pedro, 29/09/2026: "como ela pode pedir para a Nay
  -- mandar para algum contato"). "checklist aluguel para 92 ...", "manda o
  -- cheklist de venda pra 92 ..." -- do Tel e da equipe. Faltou o tipo ou o
  -- número: ela pergunta, não chuta.
  IF nai_e_comando_checklist(s) AND (t.papel = 'tel' OR nai_e_da_equipe_contato(t.contato_id)) THEN
    v_msg := (SELECT nai_enviar_checklist_para(p_turno, c.tipo, c.telefone) FROM nai_ler_pedido_de_checklist(s) c);
    PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_msg, 'comando_checklist', 1);
    RETURN QUERY SELECT v_msg; RETURN;
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

COMMIT;
