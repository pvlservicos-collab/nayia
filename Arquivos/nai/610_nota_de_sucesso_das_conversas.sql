-- 610 (Pedro, 05/11/2026: "revisa as conversas do atendimento hoje, vê se as Nays estão respondendo certinho, coloca uma
-- taxa de sucesso em cada conversa que só aparece para o meu login e o do Tel, nas que tu revisar").
-- A nota de cada conversa revisada (0 a 100), por número (linha: captacao = Leads 8595, parceria = Parceria 9445) e por dia,
-- com um resumo e os erros. Quem lê é o CRM (crm_sucesso_das_conversas, papel nay_disparo); a rota do CRM só devolve para os logins
-- Pedro e Tel. Uma revisão nova do mesmo dia substitui a anterior.
BEGIN;
CREATE TABLE IF NOT EXISTS privado.nay_nota_conversa (
  fone8        text        NOT NULL,
  linha        text        NOT NULL CHECK (linha IN ('captacao', 'parceria')),
  dia          date        NOT NULL,
  nota         int         NOT NULL CHECK (nota BETWEEN 0 AND 100),
  resumo       text,
  erros        jsonb       NOT NULL DEFAULT '[]'::jsonb,
  revisado_em  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (fone8, linha, dia)
);

CREATE OR REPLACE FUNCTION public.crm_sucesso_das_conversas(p_dias int DEFAULT 3)
 RETURNS TABLE(fone8 text, linha text, dia date, nota int, resumo text, erros jsonb, revisado_em timestamptz)
 LANGUAGE sql STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  -- a revisão mais recente de cada conversa nos últimos p_dias
  SELECT DISTINCT ON (n.fone8, n.linha) n.fone8, n.linha, n.dia, n.nota, n.resumo, n.erros, n.revisado_em
    FROM privado.nay_nota_conversa n
   WHERE n.dia >= (now() AT TIME ZONE 'America/Manaus')::date - greatest(coalesce(p_dias, 3), 1) + 1
   ORDER BY n.fone8, n.linha, n.dia DESC
$function$;
REVOKE ALL ON FUNCTION public.crm_sucesso_das_conversas(int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.crm_sucesso_das_conversas(int) TO nay_disparo;

SELECT count(*) AS notas FROM crm_sucesso_das_conversas(3);
COMMIT;
