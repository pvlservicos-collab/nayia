CREATE OR REPLACE FUNCTION public.crm_olx_abordagens(p_limite integer DEFAULT 500)
 RETURNS TABLE(id bigint, link text, titulo text, tipo text, finalidade text, preco numeric, bairro text, condominio text, anunciante text, telefone text, acao text, motivo text, codigo integer, mensagem text, entregue_em timestamp with time zone, recebido_em timestamp with time zone, pedidos integer)
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
