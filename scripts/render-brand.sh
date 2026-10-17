#!/bin/zsh
# Renders GitHub brand images from brand/card.html with headless Chrome:
#   brand/social-preview.png  1280×640  (repo Settings → Social preview)
#   brand/banner.png          1600×600  (organization profile README)
#   brand/avatar.png          1024×1024 (organization picture)
set -euo pipefail
cd "${0:A:h:h}"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
render() { # name width height extra-css
  local html="brand/.render-$1.html"
  sed "s#</style>#:root { $4 }</style>#" brand/card.html > "$html"
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=2 \
    --virtual-time-budget=4000 --window-size="$2,$3" --screenshot="$PWD/brand/$1@2x.png" "file://$PWD/$html" >/dev/null 2>&1
  magick "brand/$1@2x.png" -resize "${2}x${3}" "brand/$1.png" && rm "brand/$1@2x.png" "$html"
  print "brand/$1.png"
}
render social-preview 1280 640 "--title: 18.5vh; --lead: 4.6vh; --window: 54vw;"
render banner 1600 600 "--title: 21vh; --lead: 4.4vh; --window: 52vw;"
[[ -x dist/Hyena.app/Contents/MacOS/Hyena ]] || zsh scripts/build-app.sh >/dev/null
dist/Hyena.app/Contents/MacOS/Hyena --render-avatar brand/avatar.png && print "brand/avatar.png"
