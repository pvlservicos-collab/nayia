-- Passos de uma resposta rápida em sequência (ex: áudio de apresentação + foto do
-- produto, mandados em mensagens separadas com um único atalho). Uma quick_reply sem
-- nenhuma linha aqui continua funcionando exatamente como antes — usa o próprio
-- content/media_url dela como sequência implícita de 1 passo.
CREATE TABLE "quick_reply_steps" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "quick_reply_id" uuid NOT NULL REFERENCES "quick_replies"("id") ON DELETE CASCADE,
  "position" integer NOT NULL,
  "content" text NOT NULL DEFAULT '',
  "media_url" text,
  "media_type" text,
  "media_mimetype" text,
  "media_filename" text,
  "created_at" timestamptz DEFAULT now()
);

CREATE UNIQUE INDEX "quick_reply_steps_position_unique" ON "quick_reply_steps" ("quick_reply_id", "position");
