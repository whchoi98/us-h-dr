#!/bin/bash
# Detect documentation sync needs after file writes.
# Triggered by postToolUse (fs_write) hook.

# Read hook event from stdin
EVENT=$(cat)
FILE_PATH=$(echo "$EVENT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('path',''))" 2>/dev/null)

[ -z "$FILE_PATH" ] && exit 0

# Detect missing docs in terraform/modules/ subdirectories
if [[ "$FILE_PATH" == *terraform/modules/* ]]; then
    DIR=$(dirname "$FILE_PATH")
    MODULE_NAME=$(basename "$DIR")
    if [ ! -f "$DIR/README.md" ] && [[ "$MODULE_NAME" != "modules" ]]; then
        echo "[doc-sync] $DIR/ has no README.md. Consider adding module documentation." >&2
    fi
fi

# Detect CDK stack without docs
if [[ "$FILE_PATH" == *cdk/lib/*-stack.ts ]]; then
    STACK_NAME=$(basename "$FILE_PATH" .ts)
    echo "[doc-sync] CDK stack $STACK_NAME modified. Verify bin/app.ts imports." >&2
fi

# Alert if no ADRs exist when infrastructure files change
if [[ "$FILE_PATH" == *terraform/* ]] || [[ "$FILE_PATH" == *cdk/* ]]; then
    ADR_COUNT=$(find docs/decisions -name 'ADR-*.md' 2>/dev/null | wc -l)
    if [ "$ADR_COUNT" -eq 0 ]; then
        echo "[doc-sync] No ADRs found. Record architectural decisions in docs/decisions/." >&2
    fi
fi

exit 0
