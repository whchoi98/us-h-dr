#!/bin/bash
# Detect documentation sync needs after file changes.
# Triggered by PostToolUse (Write|Edit) events.

FILE_PATH="${1:-}"
[ -z "$FILE_PATH" ] && exit 0

# Detect missing CLAUDE.md in terraform/modules/ subdirectories
if [[ "$FILE_PATH" == terraform/modules/* ]]; then
    DIR=$(dirname "$FILE_PATH")
    if [ ! -f "$DIR/CLAUDE.md" ] && [[ "$DIR" != "terraform/modules" ]]; then
        echo "[doc-sync] $DIR/CLAUDE.md is missing. Create module documentation."
    fi
fi

# Detect missing CLAUDE.md in cdk/lib/ for new stacks
if [[ "$FILE_PATH" == cdk/lib/*-stack.ts ]]; then
    if [ ! -f "cdk/lib/CLAUDE.md" ]; then
        echo "[doc-sync] cdk/lib/CLAUDE.md is missing. Create CDK stack documentation."
    fi
fi

# Alert if no ADRs exist when infrastructure files change
if [[ "$FILE_PATH" == terraform/* ]] || [[ "$FILE_PATH" == cdk/* ]] || [[ "$FILE_PATH" == docs/architecture.md ]]; then
    ADR_COUNT=$(find docs/decisions -name 'ADR-*.md' 2>/dev/null | wc -l)
    if [ "$ADR_COUNT" -eq 0 ]; then
        echo "[doc-sync] No ADRs found. Record architectural decisions in docs/decisions/."
    fi
fi
