-- =========================================================
-- Migration 010: Add value field to leads and stage goals table
-- =========================================================

-- Add value field to leads table
ALTER TABLE leads
ADD COLUMN IF NOT EXISTS value numeric(12, 2) DEFAULT 0;

-- Create index for value queries
CREATE INDEX IF NOT EXISTS idx_leads_value ON leads(value) WHERE deleted_at IS NULL;

-- Create stage_goals table for customizable goals per stage
CREATE TABLE IF NOT EXISTS stage_goals (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES organizations(id),
    stage_id uuid NOT NULL,

    -- Goals
    lead_count_goal integer DEFAULT 0, -- Meta de quantidade de leads
    value_goal numeric(12, 2) DEFAULT 0, -- Meta de valor total

    -- Metadata
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),

    -- Composite FK to ensure stage belongs to same org
    CONSTRAINT fk_stage_goals_stage FOREIGN KEY (organization_id, stage_id) REFERENCES pipeline_stages(organization_id, id) ON DELETE CASCADE,

    -- Ensure one goal per stage
    CONSTRAINT uq_stage_goals_stage UNIQUE (stage_id)
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_stage_goals_org_id ON stage_goals(organization_id);
CREATE INDEX IF NOT EXISTS idx_stage_goals_stage_id ON stage_goals(stage_id);

-- Add trigger for updated_at
CREATE TRIGGER update_stage_goals_modtime
BEFORE UPDATE ON stage_goals
FOR EACH ROW
EXECUTE PROCEDURE update_updated_at_column();

-- Insert default goals for existing stages (20 leads, R$ 100k per stage)
INSERT INTO stage_goals (organization_id, stage_id, lead_count_goal, value_goal)
SELECT
    ps.organization_id,
    ps.id,
    20 as lead_count_goal,
    100000.00 as value_goal
FROM pipeline_stages ps
ON CONFLICT (stage_id) DO NOTHING;

-- Update existing leads with random values for testing (R$ 500 to R$ 50000)
-- Comment this out in production if you don't want to modify existing data
UPDATE leads
SET value = (RANDOM() * 49500 + 500)::numeric(12, 2)
WHERE deleted_at IS NULL AND value = 0;

COMMENT ON TABLE stage_goals IS 'Customizable goals (lead count and value) per pipeline stage';
COMMENT ON COLUMN leads.value IS 'Monetary value of the lead opportunity (e.g., deal size)';
COMMENT ON COLUMN stage_goals.lead_count_goal IS 'Target number of leads for this stage';
COMMENT ON COLUMN stage_goals.value_goal IS 'Target total value for all leads in this stage';
