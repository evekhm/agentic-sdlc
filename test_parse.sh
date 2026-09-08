#!/usr/bin/env bash
PR_JSON=$(gh pr view 257 --json number,body -q '.' 2>/dev/null || echo "[]")
echo $PR_JSON
