#!/bin/zsh
set -eu

HERE="${0:A:h}"
exec "$HERE/AntigravityProxy" --agy-cli-exec
