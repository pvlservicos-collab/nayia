-- 308 (07/10/2026): a captação só fala com PROPRIETÁRIO. Corretor e parceiro ficam de fora.
--
-- Pedro, 07/10: "vê lá na lista de captação, está sendo disparado mensagem para corretor, e não proprietário, não é
-- para sair nada para corretor nem parceiro".
--
-- O QUE HAVIA. Os 365 leads vieram do cadastro de proprietários (09/09), e corretor parceiro aparece nele como
-- "proprietário" do imóvel que anunciou conosco. 21 leads têm o telefone na lista de corretores dos grupos
-- (`corretores`, 1.548 números). 14 já tinham recebido o disparo (3 em 07/10, 1 em 05/10, 1 em 03/10) e 16 ainda
-- estavam expostos: 7 na fila, 3 esperando o lembrete e 6 conversando com a IA da captação.
--
-- A PAREDE, no banco (nenhum nó do n8n muda):
-- 1. `captacao_fora_da_campanha(lead)`: o motivo de a pessoa não ser alvo da captação, ou NULL. Telefone na lista
--    de corretores; nome de corretor, imobiliária ou parceria; imóvel de parceiro. O telefone de teste da campanha
--    (`captacao_config.telefone_teste`) passa sempre.
-- 2. Gatilho `captacao_so_proprietario`: quando o fluxo RESERVA o lead (o disparo e o lembrete fazem
--    `status = 'reservado'`), o lead que está fora não é reservado: ganha a marca `humano_assumiu_em` e o comando
--    devolve zero linhas, então nada é montado nem enviado. A conferência é na hora, com a lista de corretores
--    daquele momento: quem entrar nos grupos na semana que vem também fica de fora.
-- 3. `captacao_ainda_e_da_ia`: a IA da captação não responde quem está fora (a conversa fica para gente, no CRM).
-- 4. Os que já estavam expostos ganham a marca agora.
BEGIN;

CREATE OR REPLACE FUNCTION public.captacao_fora_da_campanha(p_lead bigint)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE
    -- o número de teste da campanha conversa sempre
    WHEN right(l.telefone, 8) = right(regexp_replace(coalesce((SELECT c.valor FROM captacao_config c
                                                             WHERE c.chave = 'telefone_teste'), ''), '\D', '', 'g'), 8)
      THEN NULL
    WHEN EXISTS (SELECT 1 FROM corretores k
                  WHERE right(regexp_replace(coalesce(k.telefone, ''), '\D', '', 'g'), 8) = right(l.telefone, 8))
      THEN 'corretor (está na lista de corretores dos grupos)'
    WHEN nai_dono_e_parceiro(l.nome) OR coalesce(l.nome, '') ~* 'parceri'
      THEN 'nome de corretor, imobiliária ou parceria'
    WHEN EXISTS (SELECT 1 FROM imoveis i
                  WHERE coalesce(i.e_parceiro, false)
                    AND (i.codigo::text = l.codigo
                         OR i.codigo::text IN (SELECT x ->> 'codigo'
                                                 FROM jsonb_array_elements(coalesce(l.imoveis_prop, '[]'::jsonb)) x)))
      THEN 'imóvel de parceiro'
  END
    FROM captacao_leads l WHERE l.id = p_lead;
$function$;

COMMENT ON FUNCTION public.captacao_fora_da_campanha(bigint) IS
  '308: por que este lead não é alvo da captação (corretor, parceiro), ou NULL. Quem usa: o gatilho da reserva e captacao_ainda_e_da_ia.';

CREATE OR REPLACE FUNCTION public.captacao_so_proprietario()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_motivo text := captacao_fora_da_campanha(OLD.id);
BEGIN
  IF v_motivo IS NULL THEN
    RETURN NEW;
  END IF;
  -- não reserva: marca como conversa de gente (a mesma marca que tira o lead do disparo, do lembrete e da IA) e
  -- devolve NULL, que cancela a reserva. O fluxo recebe zero linhas e não manda nada.
  UPDATE captacao_leads
     SET humano_assumiu_em = coalesce(humano_assumiu_em, now()),
         humano_motivo = coalesce(humano_motivo, left('fora da captação: ' || v_motivo, 200)),
         atualizado_em = now()
   WHERE id = OLD.id;
  RETURN NULL;
END $function$;

DROP TRIGGER IF EXISTS captacao_so_proprietario ON captacao_leads;
CREATE TRIGGER captacao_so_proprietario
  BEFORE UPDATE OF status ON captacao_leads
  FOR EACH ROW WHEN (NEW.status = 'reservado' AND OLD.status IS DISTINCT FROM 'reservado')
  EXECUTE FUNCTION captacao_so_proprietario();

CREATE OR REPLACE FUNCTION public.captacao_ainda_e_da_ia(p_tel text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  -- 308: a IA da captação também não responde corretor nem parceiro
  SELECT NOT EXISTS (SELECT 1 FROM captacao_leads
                      WHERE id = captacao_lead_por_contato(p_tel)
                        AND (humano_assumiu_em IS NOT NULL OR captacao_fora_da_campanha(id) IS NOT NULL));
$function$;

-- os que já estavam expostos (na fila, esperando o lembrete ou conversando com a IA)
UPDATE captacao_leads l
   SET humano_assumiu_em = now(),
       humano_motivo = left('fora da captação: ' || captacao_fora_da_campanha(l.id), 200),
       atualizado_em = now()
 WHERE l.humano_assumiu_em IS NULL
   AND l.status IN ('novo', 'erro', 'reservado', 'enviado', 'respondendo')
   AND captacao_fora_da_campanha(l.id) IS NOT NULL;

COMMIT;
