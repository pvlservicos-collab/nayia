-- 365 -- OLX: dois buracos da 364, achados ao escrever o serviço (antes de qualquer anúncio subir)
--
-- 1. A EDIÇÃO QUE FALHA VOLTAVA EM LAÇO. Um anúncio publicado cujo cadastro mudou vai de novo à OLX ("atualizar").
--    Se a OLX recusasse essa edição na validação, `olx_anuncio_falhou` mantinha o anúncio como publicado (certo) mas
--    com o hash antigo: o plano mandaria a mesma edição a cada 5 minutos, e cada falha cancela a importação INTEIRA
--    dos outros anúncios. Agora o hash da edição que falhou fica guardado: só vai de novo quando o cadastro mudar.
--
-- 2. O QUE ESTÁ NO AR E FICOU "RECUSADO" NÃO SAÍA. A moderação pode recusar a EDIÇÃO de um anúncio que continua
--    publicado na versão antiga. Ele ficava com estado 'recusado', e a remoção só olhava 'enviado' e 'publicado':
--    se o imóvel fosse vendido depois, o anúncio ficaria na OLX. Agora sai tudo o que já teve list_id e não foi removido.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE FUNCTION pg_temp.remendar(p_fn regprocedure, p_de text, p_para text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v text := pg_get_functiondef(p_fn); n int;
BEGIN
  n := (length(v) - length(replace(v, p_de, ''))) / length(p_de);
  IF n <> 1 THEN RAISE EXCEPTION 'remendo em %: o trecho aparece % vez(es), esperava 1: %', p_fn, n, left(p_de, 60); END IF;
  EXECUTE replace(v, p_de, p_para);
END $$;

SELECT pg_temp.remendar('olx_anuncio_falhou(text,integer,text,text,jsonb,text,text)',
$de$         mensagem = left(p_mensagem, 500), enviado_em = now(), tentativas = a.tentativas + 1, atualizado_em = now();$de$,
$para$         -- 365: a edição que falhou não volta sozinha (só quando o cadastro mudar de novo)
         conteudo_hash = CASE WHEN a.estado IN ('publicado', 'removendo') THEN excluded.conteudo_hash ELSE a.conteudo_hash END,
         mensagem = left(p_mensagem, 500), enviado_em = now(), tentativas = a.tentativas + 1, atualizado_em = now();$para$);

SELECT pg_temp.remendar('olx_anuncios_plano(integer)',
$de$FOR r IN SELECT a.* FROM privado.olx_anuncio a WHERE a.estado IN ('enviado', 'publicado') ORDER BY a.id LOOP$de$,
$para$FOR r IN SELECT a.* FROM privado.olx_anuncio a
            WHERE a.estado IN ('enviado', 'publicado')
               -- 365: a edição foi recusada mas a versão antiga continua no ar
               OR (a.estado IN ('recusado', 'erro') AND a.list_id IS NOT NULL AND a.removido_em IS NULL)
            ORDER BY a.id LOOP$para$);

COMMIT;
