#!/bin/bash
# Usage: finish.sh <project_dir> <name> — renders the HF project and writes <name>.mp4 (-14 LUFS, two-pass loudnorm) + <name>-silent.mp4
set -euo pipefail
cd "$1"; N="$2"
npx hyperframes render . --skill=motion-graphics -q high -o ./renders/video.mp4 2>&1 | grep -E "MB ·|rror" || true
cd renders
M=$(ffmpeg -hide_banner -nostats -i video.mp4 -af loudnorm=I=-14:TP=-1.5:LRA=7:print_format=json -f null - 2>&1 | sed -n '/^{/,/^}/p')
g() { echo "$M" | python3 -c "import json,sys;print(json.load(sys.stdin)['$1'])"; }
ffmpeg -hide_banner -loglevel error -y -i video.mp4 -c:v copy -af "loudnorm=I=-14:TP=-1.5:LRA=7:measured_I=$(g input_i):measured_TP=$(g input_tp):measured_LRA=$(g input_lra):measured_thresh=$(g input_thresh):offset=$(g target_offset):linear=true" -ar 48000 -c:a aac -b:a 320k "$N.mp4"
ffmpeg -hide_banner -loglevel error -y -i video.mp4 -c:v copy -an "$N-silent.mp4"
rm video.mp4
echo "$N: $(ffmpeg -hide_banner -nostats -i "$N.mp4" -af ebur128=peak=true -f null - 2>&1 | grep -E '^ +I:' | xargs) · $(ffprobe -v error -show_entries format=duration -of csv=p=0 "$N.mp4")s"
