-- 264 (02/10/2026): O CADASTRO AVISA O BOT QUANDO O IMÓVEL VEM SEM FOTO.
-- Pedro: "quando eu clicar em Aprovar (vira pré-cadastro), ele já baixa as fotos
-- do link".
--
-- O QUE DÁ E O QUE NÃO DÁ: o nosso servidor NÃO consegue ler a página do anúncio
-- -- a OLX responde 403 (bloqueio da Cloudflare dela) para servidor; medido de
-- novo em 02/10, nas duas VPS, enquanto do PC do Pedro a mesma página abre. O
-- que o servidor baixa sem problema é a FOTO em si (img.olx.com.br). Então as
-- fotos só entram sozinhas no Aprovar quando o bot manda os links delas no
-- campo `fotos` -- e isso a aba já faz desde a 260.
--
-- O furo era o bot mandar o imóvel sem `fotos` e ninguém dizer nada: o envio
-- entrava "ok" e a pessoa só descobria na hora de aprovar. Agora a resposta traz
-- `fotos_guardadas` (quantas o cadastro tem, somando os reenvios) e `avisos`
-- (lista; vazia quando está tudo certo). Sem foto, o aviso pede o reenvio do
-- MESMO link com a lista -- reenvio completa o cadastro pendente, não duplica.
--
-- Não virou recusa de propósito: imóvel com autorização e sem foto ainda vale a
-- fila (a pessoa traz as fotos pelo favorito da Captação OLX).
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION pg_temp.trocar(p_fn regprocedure, p_de text, p_para text, p_vezes int DEFAULT 1)
 RETURNS void LANGUAGE plpgsql AS $$
DECLARE d text := pg_get_functiondef(p_fn); n int := (length(d) - length(replace(d, p_de, ''))) / length(p_de);
BEGIN
  IF n <> p_vezes THEN RAISE EXCEPTION 'trocar em %: esperava % vez(es), achei % -- %', p_fn, p_vezes, n, left(p_de, 50); END IF;
  EXECUTE replace(d, p_de, p_para);
END $$;

SELECT pg_temp.trocar('crm_olx_bot_receber(jsonb)'::regprocedure,
$de$    'fotos_recebidas', coalesce(array_length(v_fotos, 1), 0),
$de$,
$para$    'fotos_recebidas', coalesce(array_length(v_fotos, 1), 0),
    -- 264: quantas fotos o cadastro TEM (com os reenvios) e o que falta
    'fotos_guardadas', (SELECT coalesce(array_length(o.fotos, 1), 0) FROM privado.olx_bot_imovel o WHERE o.id = v_novo),
    'avisos', (SELECT CASE WHEN coalesce(array_length(o.fotos, 1), 0) = 0
                 THEN jsonb_build_array('Veio sem fotos. Reenvie o MESMO link com a lista "fotos" (os links https das imagens do anúncio, em img.olx.com.br): o cadastro que já está na fila é completado, não duplica.')
                 ELSE '[]'::jsonb END
                 FROM privado.olx_bot_imovel o WHERE o.id = v_novo),
$para$);
COMMIT;
