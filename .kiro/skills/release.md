---
name: release
description: Automate release process with validation checks. Use when asked to create a release, tag a version, or prepare changelog.
---

# Release

## Procedure
1. **Pre-checks**: Clean tree (`git status`), `terraform validate`, `npx tsc --noEmit`
2. **Version**: Review `git log $(git describe --tags --abbrev=0)..HEAD --oneline`, apply semver:
   - MAJOR: Breaking infra changes (VPC CIDR, TGW removal)
   - MINOR: New modules/stacks/scripts
   - PATCH: Bug fixes, config, docs
3. **Changelog**: Group by Added/Changed/Fixed/Removed with commit refs
4. **Tag**: `git tag -a vX.Y.Z -m "Release vX.Y.Z"`
5. **Summary**: Version bump, key changes, next steps
