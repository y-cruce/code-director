#!/usr/bin/env bash
# Same tool as code-director's; a wrapper because checkouts may disable symlinks.
exec bash "$(cd -P "$(dirname "$0")" && pwd)/../../code-director/scripts/context.sh" "$@"
