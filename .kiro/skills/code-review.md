---
name: code-review
description: Review changed code with confidence-based scoring. Use when asked to review code, check for issues, or audit changes.
---

# Code Review

Review unstaged changes from `git diff` (or user-specified scope).

## Criteria

### Project Guidelines
- Terraform: `required_providers` in all modules, consistent tagging, no PLAINTEXT ports
- CDK: Stack dependencies in app.ts, PascalCase classes, camelCase props
- Security: CloudFront prefix list SG, DSQL PrivateLink, MSK IAM auth (9098 only)

### Bug Detection
- Terraform circular dependencies or missing outputs
- CDK cross-region issues (missing `crossRegionReferences: true`)
- Security group rule gaps
- Missing provider aliases for cross-region resources

### Code Quality
- DRY violations, hardcoded values, missing module outputs

## Confidence Scoring (0-100)
- **0-49**: Do not report
- **50-74**: Report only if critical
- **75-89**: Verified real issue, report with fix
- **90-100**: Confirmed critical, must report

**Only report issues with confidence >= 75.**

## Output Format
```
### [CRITICAL|IMPORTANT] <title> (confidence: XX)
**File:** `path:line`
**Issue:** Description
**Fix:** Concrete suggestion
```
