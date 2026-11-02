-- 560 (Pedro, 02/11/2026): "5180, vê lá no Mario Feitosa, a Nay de Parceria enviou imóvel de parceiro, ela nunca deve
-- enviar esses imóveis, nem de parceiro antigo nem de novos, só a Nay Leads pode enviar imóveis de parceiros novos".
--
-- O 5180 (casa no Alvorada, Conjunto Ajuricaba) saiu ao Mario em 28/10 numa lista "dos bairros ao redor" e com card e
-- fotos. A Nay da Parceria barra todo imóvel com e_parceiro (core_imovel_busca, card, visita, resposta), mas o 5180 não
-- tinha a marca: no site antigo o parceiro está em "indicado por = Imob corretor parceiro", e a regra só olhava o
-- "captado por" (SECRETARIA 5). O mesmo com o 1442 (Alphaville 3: "indicado por = Parceiro imob easy").
--   1. o gatilho imoveis_parceiro_pelo_captador passa a ler também o "indicado por" (a importação do site antigo de amanhã
--      já marca);
--   2. 5180 e 1442 viram parceiro e parceiro ANTIGO (os dois vieram do site antigo em 10/08): saem da Parceria, do Leads e
--      do site, como os outros 909 antigos (413).
-- O 2206 (Viver Melhor 4) tem dono cujo telefone é de corretor, mas nada diz parceria: fica como está (perguntado).
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION public.imoveis_parceiro_pelo_captador()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_manual text := lower(coalesce(NEW.extras, '{}'::jsonb)->>'parceiro_manual');
BEGIN
  -- 400: quem marcou à mão no admin (Situação > Parceiros) manda, nos dois sentidos
  IF v_manual = 'nao' THEN
    NEW.e_parceiro := false;
    RETURN NEW;
  END IF;
  -- `administrado` e parceiro ao mesmo tempo viola chk_parceiro_nao_administrado:
  -- nesse caso nao mexe (e o humano quem resolve).
  IF NOT coalesce(NEW.administrado, false)
     AND (v_manual = 'sim'
          OR nai_captador_e_parceiro(NEW.captado_por)
          OR nai_captador_e_parceiro(coalesce(NEW.extras, '{}'::jsonb)->>'captado por')
          -- 560: no site antigo o parceiro pode estar só no "indicado por" ("Imob corretor parceiro", o 5180)
          OR coalesce(NEW.extras, '{}'::jsonb)->>'indicado por' ~* 'parceir') THEN
    NEW.e_parceiro := true;
  END IF;
  RETURN NEW;
END;
$function$;

UPDATE imoveis SET e_parceiro = true,
       extras = coalesce(extras, '{}'::jsonb) || jsonb_build_object('parceiro_antigo', 'sim')
 WHERE codigo IN (5180, 1442) AND NOT coalesce(administrado, false);

COMMIT;
