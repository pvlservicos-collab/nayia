-- Despesas / Contas a Pagar: base para o dashboard Financeiro (entradas x saídas, passivo do mês)

CREATE TABLE "expenses" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "organization_id" uuid NOT NULL REFERENCES "organizations"("id"),
  "description" text NOT NULL,
  "category" text NOT NULL DEFAULT 'outros',
  "amount" numeric(15,2) NOT NULL,
  "due_date" timestamptz NOT NULL,
  "status" text NOT NULL DEFAULT 'pending',
  "paid_at" timestamptz,
  "payee" text,
  "notes" text,
  "is_recurring" boolean NOT NULL DEFAULT false,
  "recurrence_interval" text,
  "recurrence_day" integer,
  "recurrence_end_date" timestamptz,
  "parent_expense_id" uuid REFERENCES "expenses"("id") ON DELETE SET NULL,
  "created_by_member_id" uuid,
  "created_at" timestamptz DEFAULT now(),
  "updated_at" timestamptz DEFAULT now(),
  "deleted_at" timestamptz
);

CREATE INDEX "expenses_org_due_date_idx" ON "expenses" ("organization_id", "due_date");
CREATE INDEX "expenses_org_status_idx" ON "expenses" ("organization_id", "status");

-- Impede gerar a mesma parcela de uma despesa recorrente duas vezes
CREATE UNIQUE INDEX "expenses_parent_due_date_unique" ON "expenses" ("parent_expense_id", "due_date")
  WHERE "parent_expense_id" IS NOT NULL AND "deleted_at" IS NULL;
