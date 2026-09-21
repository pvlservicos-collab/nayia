# Findings & Architectural Notes

## Database Schema Analysis
Based on the review of `schema.md`, the following key architectural decisions and patterns have been identified:

### 1. Tenant Isolation
- **Pattern**: Almost every table includes `organization_id`.
- **Constraint**: Foreign keys are often composite `(organization_id, id)` to ensure strict tenant isolation and prevent cross-tenant data leaks.
- **Action Item**: Ensure application-level queries always include `organization_id` in `WHERE` clauses (or use RLS).

### 2. Primary Keys & IDs
- **Format**: UUIDs are used universally for primary keys.
- **Benefit**: easier merging, obfuscation vs iterating integers.

### 3. PostgreSQL Specifics
- **Timestamps**: Uses `timestamptz`. Comments suggest using triggers for `updated_at`.
- **JSONB**: Extensive use of `jsonb` for flexible data (`custom_attributes`, `config`, `permissions`, `ai_metadata`).
- **Indexing**: explicit GIN indexes recommended for JSONB fields.
- **Soft Deletes**: `deleted_at` column present. Unique constraints need to be partial indexes (`WHERE deleted_at IS NULL`).

### 4. Module Dependencies
- **Core**: Organizations and Users/Members are the foundation.
- **CRM**: Leads depend on Pipelines, Integrations, and Members.
- **AI**: Insights are a satellite table to Leads (1:1).

### 5. Performance Considerations
- **Denormalization**: `leads` table includes `last_activity_at` and `last_activity_type` to avoid expensive joins for sorting/filtering.
- **Indexing**: Custom fields have a dedicated index table (`custom_field_index_values`) to support performant filtering on user-defined fields.

## TODOs / Risks
- [ ] **Secrets Management**: `integrations.config` comment says "não guardar segredos aqui" (do not store secrets here). Need a strategy for secure credential storage.
- [ ] **Ordering**: `pipeline_stages` uses `numeric(20, 6)` for ranking. Need a robust fractional indexing strategy or rebalancing logic in the app.
