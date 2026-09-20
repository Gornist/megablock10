#!/bin/bash
# Один раз после клонирования: включить хуки из .githooks (pre-push гоняет scripts/check.sh).
cd "$(dirname "$0")/.." && git config core.hooksPath .githooks && echo "хуки включены: .githooks"
