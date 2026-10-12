-- 350 -- A observação do imóvel é só o que a equipe escrever; e as listas já disparadas entram na barra lateral
--
-- Pedro, 12/10/2026: "ficou confuso descrição com observação do imóvel: a descrição é o texto de anúncio; as
-- observações você não vai preencher com nada, quem vai preencher somos nós, e quando preenchermos aí sim vai com o
-- card" e "faltou na lista de listas as que a gente já tinha disparado: a da captação e a dos 94".
--
-- 1. O que a 345 tinha posto em `imoveis.observacao` (o bloco OBS do anúncio ou a descrição curta, 541 imóveis) sai.
--    O OBS do anúncio continua na ficha do anúncio (imovel_ficha.observacoes), que a Nay já lê para responder. O card
--    só leva a observação quando alguém escrever no cadastro (nai_card_do_banco e o núcleo já são assim: vazio = nada).
-- 2. site_publicos_disparo ganha as listas já disparadas: 9 = a captação pelo número oficial (os proprietários da
--    campanha); 10 = a retomada pelo oficial (quem recebeu a abertura pela Z-API e nunca respondeu, 323).
BEGIN;
SET LOCAL lock_timeout = '3s';

UPDATE imoveis SET observacao = NULL WHERE observacao IS NOT NULL;

CREATE FUNCTION pg_temp.remendar(p_fn regprocedure, p_de text, p_para text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v text := pg_get_functiondef(p_fn); n int;
BEGIN
  n := (length(v) - length(replace(v, p_de, ''))) / length(p_de);
  IF n <> 1 THEN RAISE EXCEPTION 'remendo em %: o trecho aparece % vez(es), esperava 1: %', p_fn, n, left(p_de, 60); END IF;
  EXECUTE replace(v, p_de, p_para);
END $$;
SELECT pg_temp.remendar('site_publicos_disparo()',
$de$    SELECT 8, 'Donos da planilha antiga que nunca viraram imóvel', 'mais imóveis', chave FROM planilha
  )$de$,
$para$    SELECT 8, 'Donos da planilha antiga que nunca viraram imóvel', 'mais imóveis', chave FROM planilha
    UNION ALL
    -- as que já foram disparadas (350): a campanha da captação e a retomada pelo oficial
    SELECT 9, 'Captação: proprietários pelo número oficial', 'a campanha da situação do imóvel (modelo com os botões)', l.telefone_chave
      FROM captacao_leads l WHERE coalesce(l.telefone_chave, '') <> ''
    UNION ALL
    SELECT 10, 'Captação: retomada pelo oficial', 'quem recebeu a abertura pela Z-API e nunca respondeu (323)', l.telefone_chave
      FROM captacao_leads l JOIN captacao_retomada_oficial r ON r.lead_id = l.id
  )$para$);
SELECT pg_temp.remendar('site_publicos_disparo()',
$de$      (8, 'Donos da planilha antiga que nunca viraram imóvel', 'mais imóveis')) AS v(n, nome, descricao))$de$,
$para$      (8, 'Donos da planilha antiga que nunca viraram imóvel', 'mais imóveis'),
      (9, 'Captação: proprietários pelo número oficial', 'a campanha da situação do imóvel (modelo com os botões)'),
      (10, 'Captação: retomada pelo oficial', 'quem recebeu a abertura pela Z-API e nunca respondeu (323)')) AS v(n, nome, descricao))$para$);
-- para a captação, "já recebeu" inclui o que saiu pela Z-API (a abertura antiga) e pelo oficial
SELECT pg_temp.remendar('site_publicos_disparo()',
$de$     WHERE m.direcao = 'enviada' AND m.status <> 'Falhou' AND (m.message_id LIKE 'wamid%' OR m.origem = 'disparo')$de$,
$para$     WHERE m.direcao = 'enviada' AND m.status <> 'Falhou' AND (m.message_id LIKE 'wamid%' OR m.origem = 'disparo')
    UNION
    SELECT l.telefone_chave FROM captacao_leads l WHERE l.ultimo_envio_em IS NOT NULL AND coalesce(l.telefone_chave, '') <> ''$para$);

COMMIT;
