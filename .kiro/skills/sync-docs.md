---
name: sync-docs
description: Synchronize project documentation with current code state. Use when asked to update docs, audit documentation, or check doc freshness.
---

# Sync Docs

## Actions

1. **Quality Assessment**: Score each doc file (0-100) across commands/workflows (20), architecture clarity (20), non-obvious patterns (15), conciseness (15), currency (15), actionability (15). Grade A-F.

2. **Architecture Sync**: Update `docs/architecture.md` to reflect current system

3. **Module Doc Audit**: Scan `terraform/modules/` and `cdk/lib/` for missing documentation

4. **ADR Audit**: Check recent commits (`git log --oneline -20`), suggest new ADRs for undocumented decisions

5. **README Sync**: Update project structure section to match actual layout

6. **Report**: Output before/after quality scores and list of changes
