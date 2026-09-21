-- Prints das funções na tela Início (Chat, Pipeline, Funis, Logística, Financeiro,
-- Métricas, Configurações) — globais, não por organização, só o superadmin edita.
CREATE TABLE "feature_screenshots" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"feature_key" text NOT NULL,
	"image_url" text NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now(),
	CONSTRAINT "feature_screenshots_feature_key_unique" UNIQUE("feature_key")
);
