CREATE OR REPLACE FUNCTION public.nai_campo_do_tipo(p_tipo text, p_campo text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE p_campo
           -- de prédio: apartamento e sala
           WHEN 'andar'           THEN p_tipo ~ '^(apartamento|sala)'
           WHEN 'andares_predio'  THEN p_tipo ~ '^(apartamento|sala)'
           WHEN 'aptos_por_andar' THEN p_tipo ~ '^apartamento'
           WHEN 'elevador'        THEN p_tipo ~ '^(apartamento|sala)'
           -- de condomínio: só quem está num
           WHEN 'torres'          THEN p_tipo ~ '_condominio$'
           WHEN 'lazer'           THEN p_tipo ~ '_condominio$'
           -- de casa e terreno
           WHEN 'terreno'         THEN p_tipo ~ '^(casa|terreno)'
           WHEN 'numero_casa'     THEN p_tipo ~ '^casa'
           ELSE true
         END
$function$;
