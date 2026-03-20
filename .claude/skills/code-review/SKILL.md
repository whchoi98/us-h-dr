# Code Review Skill

Review changed code with confidence-based scoring to filter false positives.

## Review Scope

By default, review unstaged changes from `git diff`. The user may specify different files or scope.

## Review Criteria

### Project Guidelines Compliance
- Terraform: `required_providers` in all modules, consistent tagging, no PLAINTEXT ports
- CDK: Stack dependencies wired in app.ts, PascalCase classes, camelCase props
- Security: CloudFront prefix list SG, DSQL PrivateLink, MSK IAM auth (9098 only)
- Naming: snake_case for Terraform, PascalCase for CDK stacks

### Bug Detection
- Terraform circular dependencies or missing outputs
- CDK cross-region reference issues (missing `crossRegionReferences: true`)
- Security group rule gaps (missing ingress/egress)
- Missing provider aliases for cross-region resources

### Code Quality
- DRY violations (duplicated module code)
- Hardcoded values that should be variables
- Missing module outputs needed by downstream modules

## Confidence Scoring

Rate each issue 0-100:
- **0-49**: Do not report.
- **50-74**: Report only if critical.
- **75-89**: Verified real issue. Report with fix suggestion.
- **90-100**: Confirmed critical. Must report.

**Only report issues with confidence >= 75.**

## Output Format

For each issue:
```
### [CRITICAL|IMPORTANT] <issue title> (confidence: XX)
**File:** `path/to/file.ext:line`
**Issue:** Clear description
**Fix:** Concrete code suggestion
```

## Usage
Run with `/code-review` command
