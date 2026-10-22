-- 476b: a API do site guarda a foto que o CORRETOR da busca manda no número de captação (476). A rota
-- /api/fotos-captacao/whatsapp (chamada pelo n8n-captacao a cada foto recebida) só guardava a do dono da campanha;
-- agora, se o número é de corretor da busca (busca_corretor_e), a foto vai para fotos-captacao/whatsapp-busca/<telefone>/
-- e é registrada aqui. A Nay dos corretores (nay-olx) põe as fotos no pré-cadastro.

BEGIN;

CREATE OR REPLACE FUNCTION public.busca_corretor_foto_guardar(p_telefone text, p_url text, p_message_id text)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  INSERT INTO privado.busca_corretor_foto (telefone8, url, message_id)
  SELECT right(regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g'), 8), p_url, nullif(p_message_id, '')
   WHERE busca_corretor_e(p_telefone)
  ON CONFLICT (message_id) DO NOTHING
  RETURNING true;
$function$;

GRANT EXECUTE ON FUNCTION public.busca_corretor_e(text), public.busca_corretor_foto_guardar(text, text, text) TO nay_site_escrita;

COMMIT;
