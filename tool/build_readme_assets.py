"""Builds the animated SVGs the README uses (docs/assets/*.svg).

GitHub shows an SVG inside <img> with its CSS animations but no scripts or web fonts, so everything here is plain
SVG + CSS and uses a system font stack. The screenshot slideshow embeds the PNGs from docs/screenshots as JPEG.

    python tool/build_readme_assets.py
"""
import base64
import io
import pathlib

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
SHOTS = ROOT / 'docs' / 'screenshots'
OUT = ROOT / 'docs' / 'assets'

ORANGE, PINK = '#FF7A45', '#FF4D8D'
FONT = "'Segoe UI', system-ui, -apple-system, 'Helvetica Neue', Arial, sans-serif"
CALM = '@media (prefers-reduced-motion: reduce){*{animation:none!important}}'

# The paper plane of tool/logo.svg (1024 space; the plane spans 236..800 x 236..810).
PLANE = '''<polygon points="800,236 236,486 446,586" fill="url(#wing)"/>
<polygon points="800,236 446,586 592,810" fill="url(#body)"/>
<polygon points="446,586 592,810 396,742" fill="url(#tail)"/>
<polyline points="800,236 446,586" fill="none" stroke="#fff" stroke-opacity=".35" stroke-width="5" stroke-linecap="round"/>'''

GRADIENTS = f'''<linearGradient id="wing" x1="0" y1="1" x2="1" y2="0"><stop offset="0" stop-color="#FF4D8D"/><stop offset="1" stop-color="#FF8A3D"/></linearGradient>
<linearGradient id="body" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FF6C37"/><stop offset="1" stop-color="#E0306F"/></linearGradient>
<linearGradient id="tail" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#C21F66"/><stop offset="1" stop-color="#8E1A5B"/></linearGradient>
<linearGradient id="brand" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="{ORANGE}"/><stop offset="1" stop-color="{PINK}"/></linearGradient>'''


def write(name, svg):
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / name).write_text(svg, encoding='utf-8', newline='\n')
    print(f'{name}: {len(svg) / 1024:.0f} KB')


def banner():
    chips = ['Odoo Studio', 'Flutter + Dart codegen', 'Git-native teams', 'Production lock', 'CLI + MCP for AI agents']
    hold = 2.6
    total = hold * len(chips)
    chip_svg = []
    for i, text in enumerate(chips):
        w = int(len(text) * 12.6 + 44)
        # visible for one slot, fading in and out on the edges
        chip_svg.append(
            f'<g class="chip" style="animation-delay:{i * hold - 0.3:.2f}s;opacity:{1 if i == 0 else 0}">'
            f'<rect x="300" y="244" width="{w}" height="40" rx="20" fill="#fff" fill-opacity=".07" stroke="url(#brand)" stroke-opacity=".7"/>'
            f'<text x="{300 + w / 2:.0f}" y="270" text-anchor="middle" font-size="19" font-weight="600" fill="#ffd9c7">{text}</text></g>'
        )
    s = 100 / len(chips)
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 330" width="1200" height="330" role="img" aria-label="PostPilot: the API client for Odoo, Flutter and Git teams">
<defs>
{GRADIENTS}
<linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#1B1F33"/><stop offset=".6" stop-color="#12141E"/><stop offset="1" stop-color="#1C1230"/></linearGradient>
<filter id="blur" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="55"/></filter>
<filter id="soft" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="14"/></filter>
<pattern id="dots" width="26" height="26" patternUnits="userSpaceOnUse"><circle cx="2" cy="2" r="1.3" fill="#fff" fill-opacity=".07"/></pattern>
<clipPath id="card"><rect width="1200" height="330" rx="26"/></clipPath>
</defs>
<style>
.blob1{{animation:drift1 11s ease-in-out infinite alternate}}
.blob2{{animation:drift2 13s ease-in-out infinite alternate}}
.plane{{transform-box:fill-box;transform-origin:center;animation:float 4.2s ease-in-out infinite}}
.trail{{stroke-dasharray:3 13;animation:flow 1.6s linear infinite}}
.title{{animation:rise 1.1s cubic-bezier(.2,.8,.2,1) both}}
.tag{{animation:rise 1.1s .25s cubic-bezier(.2,.8,.2,1) both}}
.chip{{animation:chip {total}s ease-in-out infinite}}
@keyframes drift1{{to{{transform:translate(-90px,60px)}}}}
@keyframes drift2{{to{{transform:translate(70px,-50px)}}}}
@keyframes float{{0%,100%{{transform:translateY(-8px) rotate(-3deg)}}50%{{transform:translateY(10px) rotate(3deg)}}}}
@keyframes flow{{to{{stroke-dashoffset:-16}}}}
@keyframes rise{{from{{opacity:0;transform:translateY(14px)}}to{{opacity:1;transform:none}}}}
@keyframes chip{{0%{{opacity:0;transform:translateY(8px)}}2%,{s - 2:.1f}%{{opacity:1;transform:none}}{s:.1f}%,100%{{opacity:0;transform:translateY(-8px)}}}}
{CALM}
</style>
<g clip-path="url(#card)">
<rect width="1200" height="330" fill="url(#bg)"/>
<rect width="1200" height="330" fill="url(#dots)"/>
<circle class="blob1" cx="1010" cy="70" r="150" fill="#FF6C37" fill-opacity=".30" filter="url(#blur)"/>
<circle class="blob2" cx="1110" cy="300" r="170" fill="#FF4D8D" fill-opacity=".26" filter="url(#blur)"/>
<circle class="blob2" cx="120" cy="300" r="120" fill="#FF6C37" fill-opacity=".16" filter="url(#blur)"/>
<path class="trail" d="M-10 292 C 70 330 120 300 150 258" fill="none" stroke="url(#brand)" stroke-width="3" stroke-linecap="round"/>
<g transform="translate(68,64) scale(.34) translate(-236,-236)"><g class="plane">
<g filter="url(#soft)" opacity=".55"><polygon points="800,236 236,486 446,586" fill="#FF6C37"/><polygon points="800,236 446,586 592,810" fill="#FF4D8D"/></g>
{PLANE}
</g></g>
<text class="title" x="296" y="170" font-family="{FONT}" font-size="92" font-weight="800" fill="url(#brand)" letter-spacing="-2">PostPilot</text>
<text class="tag" x="300" y="216" font-family="{FONT}" font-size="26" fill="#C9CEDC">The API client for Odoo, Flutter and Git teams.</text>
<g font-family="{FONT}">
{''.join(chip_svg)}
</g>
</g>
<rect x=".75" y=".75" width="1198.5" height="328.5" rx="25.5" fill="none" stroke="#fff" stroke-opacity=".10" stroke-width="1.5"/>
</svg>
'''
    write('banner.svg', svg)


def jpeg_b64(path, width=1000):
    im = Image.open(path).convert('RGB')
    im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, 'JPEG', quality=84, optimize=True, progressive=True)
    return base64.b64encode(buf.getvalue()).decode(), im.height


def showcase():
    slides = [
        ('hero.png', 'Request builder with live response'),
        ('command-palette.png', 'Command palette: every tool, request and environment'),
        ('response-tools.png', 'Response tools: JSON tree, "use as variable", "add test"'),
        ('dart-models.png', 'JSON to Dart models: plain, json_serializable, freezed'),
        ('odoo-studio.png', 'Odoo Studio: visual domain builder'),
        ('collection-runner.png', 'Collection runner with triage'),
        ('safety.png', 'Production lock and device-only secrets'),
        ('light-theme.png', 'Light and dark themes'),
    ]
    hold = 3.6
    n = len(slides)
    total = hold * n
    s = 100 / n
    w, bar_top, bar_bottom = 1000, 36, 44
    images, caps, dots = [], [], []
    ih = 625
    for i, (file, caption) in enumerate(slides):
        b64, ih = jpeg_b64(SHOTS / file, w)
        # fade in over the last 2% of the previous slot so the cross-fade has no dip
        delay = (i * s - 2) / 100 * total
        style = f'animation-delay:{delay:.2f}s'
        base = 1 if i == 0 else 0
        images.append(f'<image class="s" style="{style};opacity:{base}" x="0" y="{bar_top}" width="{w}" height="{ih}" href="data:image/jpeg;base64,{b64}"/>')
        caps.append(f'<text class="s" style="{style};opacity:{base}" x="22" y="{bar_top + ih + 28}" font-size="17" fill="#C9CEDC">{caption}</text>')
        dots.append(
            f'<circle cx="{w - 22 - (n - 1 - i) * 18}" cy="{bar_top + ih + bar_bottom / 2:.0f}" r="4.5" fill="#fff" fill-opacity=".18"/>'
            f'<circle class="d" style="{style}" cx="{w - 22 - (n - 1 - i) * 18}" cy="{bar_top + ih + bar_bottom / 2:.0f}" r="4.5" fill="url(#brand)" opacity="{base}"/>'
        )
    h = bar_top + ih + bar_bottom
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 {w} {h}" width="{w}" height="{h}" role="img" aria-label="PostPilot screenshots">
<defs>
<linearGradient id="brand" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="{ORANGE}"/><stop offset="1" stop-color="{PINK}"/></linearGradient>
<clipPath id="win"><rect width="{w}" height="{h}" rx="16"/></clipPath>
<filter id="shadow" x="-5%" y="-5%" width="110%" height="115%"><feDropShadow dx="0" dy="10" stdDeviation="14" flood-color="#000" flood-opacity=".35"/></filter>
</defs>
<style>
.s,.d{{animation:slot {total}s ease-in-out infinite}}
@keyframes slot{{0%{{opacity:0}}2%,{s:.2f}%{{opacity:1}}{s + 2:.2f}%,100%{{opacity:0}}}}
text{{font-family:{FONT}}}
{CALM}
</style>
<g clip-path="url(#win)">
<rect width="{w}" height="{h}" fill="#0E1018"/>
<rect width="{w}" height="{bar_top}" fill="#171A26"/>
<circle cx="22" cy="18" r="6" fill="#FF5F57"/><circle cx="42" cy="18" r="6" fill="#FEBC2E"/><circle cx="62" cy="18" r="6" fill="#28C840"/>
<text x="{w / 2}" y="23" text-anchor="middle" font-size="13" fill="#7C849A">PostPilot</text>
{''.join(images)}
<rect y="{bar_top + ih}" width="{w}" height="{bar_bottom}" fill="#12141E"/>
{''.join(caps)}
{''.join(dots)}
</g>
<rect x=".75" y=".75" width="{w - 1.5}" height="{h - 1.5}" rx="15.5" fill="none" stroke="#fff" stroke-opacity=".12" stroke-width="1.5"/>
</svg>
'''
    write('showcase.svg', svg)


def download():
    platforms = ['Windows', 'macOS', 'Linux', 'Android']
    chips = []
    x = 700
    for i, name in enumerate(platforms):
        w = int(len(name) * 11.5 + 38)
        chips.append(
            f'<g class="chip" style="animation-delay:{i * .35:.2f}s"><rect x="{x}" y="58" width="{w}" height="36" rx="18" fill="#fff" fill-opacity=".08" stroke="url(#brand)" stroke-opacity=".8"/>'
            f'<text x="{x + w / 2:.0f}" y="82" text-anchor="middle" font-size="17" font-weight="600" fill="#ffe1d3">{name}</text></g>'
        )
        x += w + 10
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 150" width="1200" height="150" role="img" aria-label="Download the latest PostPilot release">
<defs>
<linearGradient id="brand" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="{ORANGE}"/><stop offset="1" stop-color="{PINK}"/></linearGradient>
<linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#1B1F33"/><stop offset="1" stop-color="#1C1230"/></linearGradient>
<linearGradient id="sheen" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#fff" stop-opacity="0"/><stop offset=".5" stop-color="#fff" stop-opacity=".16"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>
<clipPath id="card"><rect width="1200" height="150" rx="24"/></clipPath>
</defs>
<style>
.ring{{transform-box:fill-box;transform-origin:center;animation:ring 2.4s ease-out infinite backwards}}
.ring2{{animation-delay:1.2s}}
.arrow{{animation:bob 1.5s ease-in-out infinite}}
.base{{animation:base 1.5s ease-in-out infinite;transform-box:fill-box;transform-origin:center}}
.sweep{{animation:sweep 4.5s ease-in-out infinite}}
.chip{{animation:hop 3s ease-in-out infinite}}
text{{font-family:{FONT}}}
@keyframes ring{{from{{transform:scale(1);opacity:.55}}to{{transform:scale(1.9);opacity:0}}}}
@keyframes bob{{0%,100%{{transform:translateY(-5px)}}50%{{transform:translateY(6px)}}}}
@keyframes base{{0%,100%{{transform:scaleX(.9);opacity:.55}}50%{{transform:scaleX(1.05);opacity:1}}}}
@keyframes sweep{{from{{transform:translateX(-420px) skewX(-20deg)}}60%,to{{transform:translateX(1300px) skewX(-20deg)}}}}
@keyframes hop{{0%,100%{{transform:translateY(0)}}50%{{transform:translateY(-5px)}}}}
{CALM}
</style>
<g clip-path="url(#card)">
<rect width="1200" height="150" fill="url(#bg)"/>
<circle class="ring" cx="92" cy="75" r="40" fill="none" stroke="url(#brand)" stroke-width="3"/>
<circle class="ring ring2" cx="92" cy="75" r="40" fill="none" stroke="url(#brand)" stroke-width="3"/>
<circle cx="92" cy="75" r="40" fill="url(#brand)"/>
<g class="arrow" fill="none" stroke="#fff" stroke-width="6" stroke-linecap="round" stroke-linejoin="round"><path d="M92 55 V87"/><path d="M77 73 L92 88 L107 73"/></g>
<rect class="base" x="76" y="97" width="32" height="5" rx="2.5" fill="#fff"/>
<text x="162" y="76" font-family="{FONT}" font-size="40" font-weight="800" fill="#fff" letter-spacing="-.5">Download Latest Release</text>
<text x="164" y="114" font-family="{FONT}" font-size="20" fill="#A7AEC3">One click. No account. Pick your platform below.</text>
{''.join(chips)}
<rect class="sweep" x="0" y="-20" width="260" height="200" fill="url(#sheen)"/>
</g>
<rect x=".75" y=".75" width="1198.5" height="148.5" rx="23.5" fill="none" stroke="url(#brand)" stroke-opacity=".55" stroke-width="1.5"/>
</svg>
'''
    write('download.svg', svg)


def divider():
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 28" width="1200" height="28" role="presentation">
<defs>
{GRADIENTS}
<linearGradient id="line" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="{ORANGE}" stop-opacity="0"/><stop offset=".25" stop-color="{ORANGE}"/><stop offset=".75" stop-color="{PINK}"/><stop offset="1" stop-color="{PINK}" stop-opacity="0"/></linearGradient>
</defs>
<style>
.fly{{animation:fly 9s linear infinite}}
@keyframes fly{{from{{transform:translateX(-50px)}}to{{transform:translateX(1230px)}}}}
{CALM}
</style>
<rect x="0" y="13" width="1200" height="2" rx="1" fill="url(#line)" opacity=".75"/>
<g class="fly"><g transform="translate(0,14) rotate(43) scale(.05) translate(-518,-523)">{PLANE}</g></g>
</svg>
'''
    write('divider.svg', svg)


if __name__ == '__main__':
    banner()
    showcase()
    download()
    divider()
