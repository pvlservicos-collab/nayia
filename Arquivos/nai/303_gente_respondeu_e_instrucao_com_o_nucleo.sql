-- 303 (07/10/2026): duas ligações que faltavam para a Nay nova (nay-core) atender todo mundo.
--
-- Pedro, 07/10: "pode ativar a nova nay para produção ... só dá uma conferida se as outras funções do crm estão
-- ligadas com essa nova nay ... as instruções ... e também se ela está respeitando a regra de que quando um
-- humano responde ela para por 30 minutos". Depois da conferência: "aplica tudo, quero tudo funcionando na nova".
--
-- O QUE A CONFERÊNCIA ACHOU (02 a 06/10, 1.212 mensagens de gente para 172 pessoas):
--
-- 1. A PAUSA DE 30 MIN CAÍA PELA 240. Em 04/10 a equipe respondeu o Sérgio às 12:04:05; às 12:05:39 ele escreveu
--    "Você só tem um 100% mobiliado e climatizado?" e às 12:06:15 a Nay respondeu por cima. A 240 ("a dúvida era de
--    outro imóvel") leu o "100" como o imóvel 100, viu que era diferente do escalado e LIMPOU a marca de humano de
--    todas as linhas da pessoa, inclusive o carimbo de "o Tel escreveu pelo celular" de um minuto e meio antes.
--    Em 03/10 15:22 foi igual com a Natália (a equipe tinha escrito às 15:08). Agora a 240 só solta se GENTE não
--    escreveu para a pessoa dentro do `gap_tel_min`: quem responde à mão tem os 30 minutos dele.
--
-- 2. A INSTRUÇÃO DO CRM NÃO CHEGAVA AO NÚCLEO. "Instruir a Nay" (235) grava em `nai_instrucao` e entra no cabeçalho
--    do turno, que só a Nay velha lê. O turno entregue ao núcleo sai da porta antes disso: das 2 instruções dadas
--    depois de 02/10, 3 dos 4 turnos seguintes foram para o núcleo, que respondeu sem saber dela. O núcleo responde
--    por regra e modelo de frase, não segue texto livre. Então, enquanto a instrução vale (48 h), o corretor fica com
--    a Nay velha, que é quem a lê. Acabou o prazo, volta para o núcleo sozinho. É a ponte: a leitura da instrução
--    pelo próprio núcleo vem depois, no nay-core.
BEGIN;

-- Gente (não robô) escreveu para esta pessoa há pouco? Olha todas as linhas dela (telefone e @lid).
-- Quem é robô é decidido num lugar só: `crm_quem_mandou` (290).
CREATE OR REPLACE FUNCTION public.nai_gente_escreveu_ha_pouco(p_ids bigint[])
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT EXISTS (
    SELECT 1
      FROM crm_quem_mandou(ARRAY(
             SELECT m.message_id
               FROM mensagens m
              WHERE m.direcao = 'enviada'
                AND m.criada_em > now() - make_interval(mins => greatest(nai_cfg_int('gap_tel_min', 30), 0))
                AND nullif(m.message_id, '') IS NOT NULL
                AND nai_chave(m.telefone) IN (SELECT c.chave FROM nai_contato c WHERE c.id = ANY (p_ids)))) q
     WHERE q.origem = 'gente');
$function$;

COMMENT ON FUNCTION public.nai_gente_escreveu_ha_pouco(bigint[]) IS
  '303: alguém da equipe escreveu à mão para a pessoa dentro do gap_tel_min. A 240 não solta a conversa nesse tempo.';

-- 1. a porta: patch na função VIVA (o banco está à frente dos .sql)
DO $patch$
DECLARE
  v_def  text := pg_get_functiondef('public.nai_abrir_turno(text,text,text,text,bigint[])'::regprocedure);
  v_alvo text := '      IF v_cit IS NOT NULL AND v_cit IS DISTINCT FROM v_esc THEN';
  v_novo text;
BEGIN
  IF (length(v_def) - length(replace(v_def, v_alvo, ''))) / length(v_alvo) <> 1 THEN
    RAISE EXCEPTION '303: a linha da 240 em nai_abrir_turno não aparece exatamente uma vez';
  END IF;
  v_novo := replace(v_def, v_alvo,
       '      -- 303: GENTE RESPONDEU HÁ POUCO: os 30 min de quem escreveu à mão valem mais que a 240.' || E'\n'
    || '      -- Em 04/10 "100% mobiliado" foi lido como o imóvel 100 e a Nay falou 1,5 min depois da equipe.' || E'\n'
    || '      IF v_cit IS NOT NULL AND v_cit IS DISTINCT FROM v_esc' || E'\n'
    || '         AND NOT nai_gente_escreveu_ha_pouco(v_irmaos) THEN');
  EXECUTE v_novo;
END
$patch$;

-- 2. quem tem instrução da equipe valendo fica com a Nay velha
DO $patch$
DECLARE
  v_def  text := pg_get_functiondef('public.nai_core_atende(bigint,text)'::regprocedure);
  v_alvo text := '    WHEN btrim(coalesce(public.nai_cfg(''core_atende_so'', ''''), '''')) <> '''' THEN';
  v_novo text;
BEGIN
  IF (length(v_def) - length(replace(v_def, v_alvo, ''))) / length(v_alvo) <> 1 THEN
    RAISE EXCEPTION '303: a linha do canário em nai_core_atende não aparece exatamente uma vez';
  END IF;
  v_novo := replace(v_def, v_alvo,
       '    -- 303: instrução da equipe valendo (CRM, "instruir a Nay", 235): quem a lê é a Nay velha' || E'\n'
    || '    WHEN EXISTS (SELECT 1 FROM public.nai_instrucao i' || E'\n'
    || '                  WHERE i.contato_id = ANY (coalesce(public.nai_contato_irmaos(p_contato), ARRAY[p_contato]))' || E'\n'
    || '                    AND i.valido_ate > now()) THEN false' || E'\n'
    || v_alvo);
  EXECUTE v_novo;
END
$patch$;

COMMIT;
