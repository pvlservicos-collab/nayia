-- 516: O PEDIDO ORIGINAL DO CORRETOR NA CONVERSA DO CRM (Pedro, 29/10: "nos grupos quando a nay vai fazer uma sugestão no
-- crm não aparece qual era a busca original do corretor, precisa aparecer").
--
-- A sugestão do radar dos grupos ("Oi, Lily! Vi seu pedido lá no grupo ... Tenho um apartamento no Vision") chega ao
-- PV do corretor, mas o pedido dele está só no banco (privado.grupo_pedido). Cada oferta (privado.grupo_pedido_oferta,
-- automática ou pelo botão) passa a gerar uma NOTA da Nay (aviso tipo 'nota', 511) com o grupo, a data e o texto do
-- pedido; o CRM (levarNotasDaNay) grava como nota interna amarela na conversa do telefone, um segundo ANTES da sugestão.
-- Os últimos 3 dias são preenchidos aqui (o CRM só olha as notas dos últimos 3 dias).
BEGIN;

CREATE OR REPLACE FUNCTION privado.grupo_pedido_oferta_nota()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  p record;
BEGIN
  SELECT q.grupo_nome, q.remetente_nome, q.enviada_em, q.texto INTO p FROM privado.grupo_pedido q WHERE q.id = NEW.pedido_id;
  IF NOT FOUND THEN RETURN NEW; END IF;
  INSERT INTO privado.aviso_equipe (fonte, tipo, titulo, texto, telefone, criado_em)
  VALUES ('nay-grupos', 'nota', 'Pedido original no grupo',
          'Pedido original' || coalesce(' de ' || nullif(btrim(p.remetente_nome), ''), '') || ' no grupo '
          || coalesce(nullif(btrim(p.grupo_nome), ''), '(sem nome)') || ' (' || to_char(p.enviada_em AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI')
          || '):' || E'\n' || left(btrim(p.texto), 1500) || E'\n\nA Nay sugeriu o imóvel #' || NEW.codigo || '.',
          nullif(regexp_replace(coalesce(NEW.telefone, ''), '\D', '', 'g'), ''),
          NEW.enviado_em - interval '1 second');
  RETURN NEW;
END
$function$;

DROP TRIGGER IF EXISTS grupo_pedido_oferta_nota_tg ON privado.grupo_pedido_oferta;
CREATE TRIGGER grupo_pedido_oferta_nota_tg AFTER INSERT ON privado.grupo_pedido_oferta
  FOR EACH ROW EXECUTE FUNCTION privado.grupo_pedido_oferta_nota();

-- as sugestões dos últimos 3 dias
INSERT INTO privado.aviso_equipe (fonte, tipo, titulo, texto, telefone, criado_em)
SELECT 'nay-grupos', 'nota', 'Pedido original no grupo',
       'Pedido original' || coalesce(' de ' || nullif(btrim(q.remetente_nome), ''), '') || ' no grupo '
       || coalesce(nullif(btrim(q.grupo_nome), ''), '(sem nome)') || ' (' || to_char(q.enviada_em AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI')
       || '):' || E'\n' || left(btrim(q.texto), 1500) || E'\n\nA Nay sugeriu o imóvel #' || o.codigo || '.',
       nullif(regexp_replace(coalesce(o.telefone, ''), '\D', '', 'g'), ''),
       o.enviado_em - interval '1 second'
  FROM privado.grupo_pedido_oferta o JOIN privado.grupo_pedido q ON q.id = o.pedido_id
 WHERE o.enviado_em > now() - interval '3 days' AND o.telefone IS NOT NULL;

COMMIT;
