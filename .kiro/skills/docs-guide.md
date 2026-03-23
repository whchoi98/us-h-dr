---
name: docs-guide
description: Documentation conventions for the us-h-dr project. Use when working with docs/ directory or creating ADRs/runbooks.
---

# Docs Guide

## Structure
- `architecture.md` — System overview, components, data flows
- `decisions/` — Architecture Decision Records (ADR-NNN-title.md)
- `runbooks/` — Operational procedures and troubleshooting
- `superpowers/` — Design specs and implementation plans

## Rules
- ADR numbering: find highest `ADR-NNN` and increment by 1
- Use `.template.md` files as starting point for new documents
- Update `architecture.md` when infrastructure changes
