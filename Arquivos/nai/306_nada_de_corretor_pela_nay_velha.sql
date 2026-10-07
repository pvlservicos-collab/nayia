-- 306 (07/10/2026): nenhuma conversa de corretor passa mais pela Nay velha.
--
-- Pedro, 07/10: "a visita a nay só pede um horário e depois passa para a etapa visita no crm e se cala, não tem
-- que passar mais nada pela antiga ... só os comandos do tel, mas isso é separado".
--
-- O QUE AINDA SEGURAVA O CORRETOR NA VELHA (medido de 02 a 07/10):
--
-- 1. A PALAVRA "VISITA" NA MENSAGEM (`nai_core_atende`). 29 turnos de 17 corretores foram para a velha só por
--    citar visita; 11 viraram visita, 9 terminaram sem resposta ou escalados. Em 07/10 "se ele desejar agendar a
--    visita eu já marco contigo" fez a velha escalar ao Tel, não responder e parar a conversa por 24 h.
-- 2. A VISITA "EM ANDAMENTO" (`nai_core_atende`). As 13 visitas abertas estão todas em `com_rayssa`; em 11 a
--    janela da visita já passou e ninguém as fechou. Os 10 corretores delas ficavam com a velha em TUDO, sem prazo.
-- 3. A MENSAGEM COM FOTO, DOCUMENTO OU VÍDEO (`nai_abrir_turno`). 6 turnos em 5 dias.
--
-- COMO FICA. A Nay nova (nay-core) conduz a visita: pergunta o dia e a hora, confirma os dados e, no "sim", a
-- ponte `nai_core_visita_confirmada` (302) cria a visita já com a Rayssa. A etapa Visitas do CRM e a Nay calada
-- continuam sendo de `nai_com_a_rayssa`, na porta, ANTES do núcleo: enquanto a visita está na janela, ninguém
-- responde pelo WhatsApp além da Rayssa. Passou a janela, quem atende de novo é o núcleo. Foto, documento e vídeo
-- vão para o núcleo, que responde "Recebi" e avisa o Tel com os links (decisão de 01/10).
--
-- O QUE NÃO MUDA: o privado do Tel e da equipe (comandos), proprietário, acompanhante e os contatos de teste
-- continuam no caminho antigo. A ficha de cadastro aberta com a secretária também (hoje não há nenhuma).
-- Refeito antes de aplicar: os 54 turnos que a velha atendeu por esses três motivos desde 04/10, pelo código do
-- núcleo, só leitura (o pedido de visita sai "Qual horário...", a confirmação e o "Certo! Anotei a sua visita").
BEGIN;

-- 1 e 2. `nai_core_atende`: saem as duas regras de visita
DO $patch$
DECLARE
  v_def text := pg_get_functiondef('public.nai_core_atende(bigint,text)'::regprocedure);
  v_de  text := '    -- visita é do sistema velho: a mensagem fala de visita...';
  v_ate text := '    -- ficha de cadastro de imóvel aberta com a secretária';
  v_i   int  := position(v_de IN v_def);
  v_f   int  := position(v_ate IN v_def);
BEGIN
  IF v_i = 0 OR v_f = 0 OR v_f < v_i
     OR (length(v_def) - length(replace(v_def, v_de, ''))) / length(v_de) <> 1
     OR (length(v_def) - length(replace(v_def, v_ate, ''))) / length(v_ate) <> 1 THEN
    RAISE EXCEPTION '306: não achei o trecho das regras de visita em nai_core_atende';
  END IF;
  EXECUTE left(v_def, v_i - 1)
       || '    -- 306: a visita é do núcleo. Ele pergunta o dia e a hora, confirma e, no "sim", a ponte' || E'\n'
       || '    -- nai_core_visita_confirmada (302) cria a visita com a Rayssa. Quem cala a Nay durante a visita' || E'\n'
       || '    -- é nai_com_a_rayssa, na porta; passou a janela, quem atende de novo é o núcleo.' || E'\n'
       || substr(v_def, v_f);
END
$patch$;

-- 3. `nai_abrir_turno`: a mídia não segura mais o turno na velha
DO $patch$
DECLARE
  v_def  text := pg_get_functiondef('public.nai_abrir_turno(text,text,text,text,bigint[])'::regprocedure);
  v_alvo text := '     AND jsonb_array_length(nai_midias_do_turno(v_turno)) = 0' || E'\n';
BEGIN
  IF (length(v_def) - length(replace(v_def, v_alvo, ''))) / length(v_alvo) <> 1 THEN
    RAISE EXCEPTION '306: a condição da mídia em nai_abrir_turno não aparece exatamente uma vez';
  END IF;
  EXECUTE replace(v_def, v_alvo,
       '     -- 306: foto, documento e vídeo também vão para o núcleo (ele responde "Recebi" e avisa o Tel)' || E'\n');
END
$patch$;

COMMIT;
