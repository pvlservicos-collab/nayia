-- 305 (07/10/2026): a porta reconhece a conversa que a Nay NOVA já está atendendo.
--
-- Pedro, 07/10 08:40: "na conversa com 92 9 9223-1994 a nay não enviou as fotos, o tel teve que responder,
-- verifica bugs".
--
-- O QUE ACONTECEU. 08:19 a corretora marcou o card e perguntou "Ainda disponível essa unidade?". A Nay nova
-- respondeu "Sim, está disponível. Quer que eu te mande as informações e as fotos?". 08:21 ela escreveu "Isso, por
-- favor", e a porta (`nai_deve_atender`) julgou a mensagem SOZINHA: "contato novo, assunto que nao e de corretor".
-- O turno não foi entregue ao núcleo, ninguém respondeu, e o Tel mandou o imóvel à mão.
--
-- A CAUSA. A regra "conversa que ela já estava atendendo" (a que deixa passar o "pode mandar" de quem está no meio
-- da conversa) só olha `nai_saida`, a caixa da Nay VELHA. Quem responde o corretor desde 02/10 é o núcleo, que
-- grava em `core_saida`: para a porta, a Nay nunca tinha falado com aquela pessoa.
--
-- O TAMANHO. De 02/10 14:13 a 07/10 08:21, 24 turnos de 16 corretores foram barrados assim até 2 h depois de uma
-- mensagem da Nay nova: "Sim", "Sim, por favor", "Nas proximidades", "Adrianópolis ou adjacências", "Você pode me
-- mandar as fotos?", "3078", "Aluguel amiga".
--
-- O CONSERTO. A mesma regra, com a caixa do núcleo: se a Nay nova já mandou mensagem para a pessoa (qualquer
-- linha dela, telefone ou @lid) desde o carimbo da regra, a conversa é dela. O motivo devolvido é o mesmo texto
-- de sempre, para nada adiante ver frase nova. A pausa do Tel, a lista curta e a lista de corretores continuam
-- vindo ANTES, como já vinham.
BEGIN;

DO $patch$
DECLARE
  v_def  text := pg_get_functiondef('public.nai_deve_atender(text,text,integer)'::regprocedure);
  v_alvo text := '  -- MARCOU UMA MENSAGEM (o card do grupo, o imovel que ela mandou): e imovel,';
  v_novo text;
BEGIN
  IF (length(v_def) - length(replace(v_def, v_alvo, ''))) / length(v_alvo) <> 1 THEN
    RAISE EXCEPTION '305: a linha "MARCOU UMA MENSAGEM" em nai_deve_atender não aparece exatamente uma vez';
  END IF;
  v_novo := replace(v_def, v_alvo,
       '  -- 305: A CONVERSA QUE A NAY NOVA (nay-core) JA ESTA ATENDENDO tambem e dela. A regra de cima so' || E'\n'
    || '  -- olha a caixa da velha; quem responde o corretor desde 02/10 e o nucleo, em core_saida. Em 07/10' || E'\n'
    || '  -- o "Isso, por favor" de quem tinha acabado de ouvir "Quer que eu te mande as fotos?" caiu em' || E'\n'
    || '  -- "assunto que nao e de corretor" (24 turnos de 16 corretores em 5 dias).' || E'\n'
    || '  IF v_id IS NOT NULL AND EXISTS (' || E'\n'
    || '       SELECT 1 FROM core_saida s' || E'\n'
    || '        WHERE s.chave_destino IN (SELECT k.chave FROM nai_contato k' || E'\n'
    || '                                   WHERE k.id = ANY (coalesce(nai_contato_irmaos(v_id), ARRAY[v_id])))' || E'\n'
    || '          AND s.papel_destino = ''turno''' || E'\n'
    || '          AND s.estado IN (''enviado'', ''enviando'', ''pendente'')' || E'\n'
    || '          AND s.criado_em > v_desde) THEN' || E'\n'
    || '    RETURN QUERY SELECT true, ''conversa que ela ja estava atendendo''::text; RETURN;' || E'\n'
    || '  END IF;' || E'\n'
    || E'\n'
    || v_alvo);
  EXECUTE v_novo;
END
$patch$;

COMMIT;
