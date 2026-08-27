#!/usr/bin/env bash
# Converts an HTML report (e.g. pdf/01_lpg_rvp_soft_sensor.html, produced by
# tools/render_01_lpg_rvp_report.jl) into a PDF using headless Chromium.
#
# Usage: tools/render_pdf.sh pdf/01_lpg_rvp_soft_sensor.html pdf/01_lpg_rvp_soft_sensor.pdf
set -euo pipefail

if [ $# -ne 2 ]; then
	echo "Usage: $0 <input.html> <output.pdf>" >&2
	exit 1
fi

IN_HTML=$(realpath "$1")
OUT_PDF="$2"

CHROME=$(command -v chromium || command -v chromium-browser || command -v google-chrome || echo "/opt/pw-browsers/chromium-1194/chrome-linux/chrome")

"$CHROME" --headless --disable-gpu --no-sandbox \
	--run-all-compositor-stages-before-draw \
	--virtual-time-budget=5000 \
	--print-to-pdf="$OUT_PDF" \
	"file://$IN_HTML"

echo "Wrote $OUT_PDF"
