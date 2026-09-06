#!/bin/sh
set -eu

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cp "$DIR/vim" "$HOME/.vimrc"
vim -Nu "$HOME/.vimrc" -n -es +'source ~/.vimrc' +qa
