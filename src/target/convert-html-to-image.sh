#!/usr/bin/env sh

set -e

wkhtmltoimage --width 600 --height 800 ./input.html output.png

# Seems to add some rotation metadata that eips needs to display the image properly.
# ¯\_(ツ)_/¯
convert output.png -rotate 0 output.png

