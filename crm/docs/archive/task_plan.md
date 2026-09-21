# Project Task Plan

This document outlines the development tasks for the project, structured around the database schema modules.

## 1. Organizations & Plans
- [x] Implement `organizations` table (UUID pk, tier_id, timezone).
- [x] Implement `tiers` table (max_users, custom_fields, permissions).
- [ ] Set up Tenant Isolation (organization_id checks).

## 2. Users & Access Matrix
- [x] Implement `profiles` (basic user info).
- [x] Implement `organization_roles` (RBAC, permissions jsonb).
- [x] Implement `organization_members` (link users to orgs & roles).

## 3. Pipelines & Stages
- [x] Implement `pipelines` (ordered stages).
- [x] Implement `pipeline_stages` (ranking system).
- [ ] Ensure safe ordering updates.

## 4. Channels & Integrations
- [x] Implement `integrations` (config jsonb, types).
- [ ] Secure storage for integration secrets (if not in config).

## 5. CRM Core (Leads)
- [x] Implement `leads` table.
- [ ] Set up FK relationships (stage, integration, owner).
- [x] Implement AI flags (interest level, next action).
- [x] Implement Custom Attributes (JSONB).

## 6. AI Agent
- [x] Implement `lead_ai_insights` (1:1 with leads).
- [ ] Design AI summary generation workflow.

## 7. History & Activities
- [x] Implement `lead_stage_history` (audit trail for stage changes).
- [x] Implement `lead_activities` (timeline of interactions).

## 8. Custom Fields
- [x] Implement `custom_field_definitions` (schema definition).
- [x] Implement `custom_field_index_values` (for search/filtering).

## 9. Tags
- [x] Implement `tags` logic.
- [x] Implement `lead_tags` association.

## 10. UI, Security, Notifications
- [x] Implement `ui_state_drafts` (save unsaved work).
- [x] Implement `audit_logs` (security trail).
- [x] Implement `notifications` system.

## 11. Preferences & Automations
- [x] Implement `user_notification_settings`.
- [x] Implement `automation_settings`.
