-- 313 (08/10/2026): A ABA "CHAT OLX" DO CRM LÊ O QUE O BOT DA OLX CONSULTOU.
-- Pedro: "coloca uma nova aba chamada Chat OLX". O que existe hoje sobre o chat
-- da OLX é o que a consulta do bot grava (309): cada anúncio, a decisão (abordar
-- ou fechar), o motivo e a MENSAGEM entregue para ele mandar ao anunciante. É
-- isso que a aba mostra, como uma lista de conversas: o anúncio à esquerda, a
-- mensagem à direita.
--
-- A tabela mora no schema `privado` (tem nome e telefone de anunciante) e o CRM
-- entra no banco da Nay pelo papel `nay_disparo`, que só EXECUTA função. Por
-- isso a leitura é uma função com dono, e não um GRANT na tabela.
--
-- Só leitura. Nada do que o anunciante responde na OLX chega aqui ainda: o bot
-- não manda as respostas de volta.
BEGIN;

CREATE OR REPLACE FUNCTION public.crm_olx_abordagens(p_limite integer DEFAULT 500)
 RETURNS TABLE(id bigint, link text, titulo text, tipo text, finalidade text, preco numeric, bairro text,
               condominio text, anunciante text, telefone text, acao text, motivo text, codigo integer,
               mensagem text, entregue_em timestamptz, recebido_em timestamptz, pedidos integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT c.id, c.link,
         nullif(btrim(c.dados ->> 'titulo'), ''), nullif(btrim(c.dados ->> 'tipo'), ''),
         nullif(btrim(c.dados ->> 'finalidade'), ''), crm_anuncio_numero(c.dados -> 'preco'),
         nullif(btrim(c.dados ->> 'bairro'), ''), nullif(btrim(c.dados ->> 'condominio_nome'), ''),
         c.anunciante_nome, c.telefone, c.acao, c.motivo, c.codigo, c.mensagem,
         c.entregue_em, c.recebido_em, c.pedidos
    FROM privado.anuncio_consulta c
   ORDER BY coalesce(c.entregue_em, c.recebido_em) DESC, c.id DESC
   LIMIT least(greatest(coalesce(p_limite, 500), 1), 2000)
$function$;

REVOKE ALL ON FUNCTION crm_olx_abordagens(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION crm_olx_abordagens(integer) TO nay_disparo;
COMMIT;
