#!/bin/zsh
# Launch the mascot daemon. Must run under Terminal.app so that macOS grants
# Bluetooth access -- see the note at the top of daemon.py and in ensure.sh.
#
# Normally you don't run this by hand: the hooks call ensure.sh, which starts it
# on demand and lets it exit again after a long idle.
cd "${0:A:h}/.."
./venv/bin/python mascot/daemon.py 2>&1 | tee -a "$HOME/.idotmatrix/daemon.log"
