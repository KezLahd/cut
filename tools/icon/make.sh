#!/bin/zsh
# Renders the app icon (light, dark, tinted) from the Sliced [ ] mark. Needs rsvg-convert (brew install librsvg).
set -euo pipefail
cd "$(dirname "$0")"
out=../../Resources/Assets.xcassets/AppIcon.appiconset
mark() { # $1 = colour
  cat <<SVG
<defs>
 <clipPath id="a"><polygon points="-40,-100 120,-100 120,11.4 -40,35.4"/></clipPath>
 <clipPath id="b"><polygon points="-40,38.6 120,14.6 120,200 -40,200"/></clipPath>
 <g id="m" fill="none" stroke="$1" stroke-width="13" stroke-linecap="round" stroke-linejoin="round">
  <path d="M24 6 H4 Q0 6 0 10 V40 Q0 44 4 44 H24"/><path d="M50 6 H70 Q74 6 74 10 V40 Q74 44 70 44 H50"/>
 </g>
</defs>
<g transform="translate(254.6 347) scale(6.6)">
 <g clip-path="url(#a)"><use href="#m" transform="translate(4 0)"/></g>
 <g clip-path="url(#b)"><use href="#m"/></g>
</g>
SVG
}
icon() { # name bg mark
  { echo '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="1024" height="1024" viewBox="0 0 1024 1024">'
    echo "$2"; mark "$3"; echo '</svg>'; } > "$1.svg"
  rsvg-convert -w 1024 -h 1024 "$1.svg" -o "$out/$1.png"
}
icon light '<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FF5A48"/><stop offset="1" stop-color="#FF3B2F"/></linearGradient></defs><rect width="1024" height="1024" fill="url(#g)"/>' '#FFFFFF'
# Dark: the mark alone on transparency; iOS paints its own dark backdrop behind it.
icon dark '' '#FF3B2F'
icon tinted '<rect width="1024" height="1024" fill="#000000"/>' '#FFFFFF'
echo done
