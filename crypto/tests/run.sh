#!/bin/bash
# Builds and runs the pdcrypto tests (macOS or Linux): crypto/tests/run.sh
set -euo pipefail
cd "$(dirname "$0")/.."
cc -std=c99 -D_DEFAULT_SOURCE -O2 -Wall -Wextra -Werror -fsanitize=address,undefined \
  -I. tests/test.c pdcrypto.c monocypher.c -o /tmp/pdcrypto-tests
/tmp/pdcrypto-tests
