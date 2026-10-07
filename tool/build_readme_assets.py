"""Builds the animated SVGs the README uses (docs/assets/*.svg).

GitHub shows an SVG inside <img> with its CSS/SMIL animations but no scripts or web fonts, so everything here is
plain SVG and uses a system font stack. The screenshots from docs/screenshots are embedded as JPEG.

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
MONO = "'Cascadia Mono', Consolas, Menlo, 'DejaVu Sans Mono', monospace"
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

BRAND = f'<linearGradient id="brand" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="{ORANGE}"/><stop offset="1" stop-color="{PINK}"/></linearGradient>'


def write(name, svg):
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / name).write_text(svg, encoding='utf-8', newline='\n')
    print(f'{name}: {len(svg) / 1024:.0f} KB')


def kf(name, stops):
    """@keyframes from [(percent, css), ...]."""
    return '@keyframes %s{%s}' % (name, ''.join('%s%%{%s}' % (f'{p:.3f}'.rstrip('0').rstrip('.'), css) for p, css in stops))


_jpeg_cache = {}


def jpeg_b64(name, width):
    key = (name, width)
    if key not in _jpeg_cache:
        im = Image.open(SHOTS / name).convert('RGB')
        im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
        buf = io.BytesIO()
        im.save(buf, 'JPEG', quality=82, optimize=True, progressive=True)
        _jpeg_cache[key] = (base64.b64encode(buf.getvalue()).decode(), im.height)
    return _jpeg_cache[key]


# --------------------------------------------------------------------------------------------------------------------
def banner():
    chips = ['Odoo Studio', 'Flutter + Dart codegen', 'Git-native teams', 'Production lock', 'CLI + MCP for AI agents']
    hold = 2.6
    total = hold * len(chips)
    chip_svg = []
    for i, text in enumerate(chips):
        w = int(len(text) * 12.6 + 44)
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


# --------------------------------------------------------------------------------------------------------------------
def showcase():
    slides = [
        ('hero.png', 'Request builder with live response'),
        ('command-palette.png', 'Command palette: every tool, request and environment'),
        ('odoo-studio.png', 'Odoo Studio: visual domain builder'),
        ('dart-api-layer.png', 'Dart Studio: a whole API layer from a collection'),
        ('production-lock.png', 'Production lock: asks before it changes real data'),
        ('run-triage.png', 'Run triage: failures grouped by cause'),
        ('response-tools.png', 'Response tools: JSON tree, "use as variable", "add test"'),
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
        b64, ih = jpeg_b64(file, w)
        delay = (i * s - 2) / 100 * total
        style = f'animation-delay:{delay:.2f}s'
        base = 1 if i == 0 else 0
        images.append(f'<image class="s" style="{style};opacity:{base}" x="0" y="{bar_top}" width="{w}" height="{ih}" href="data:image/jpeg;base64,{b64}"/>')
        caps.append(f'<text class="s" style="{style};opacity:{base}" x="22" y="{bar_top + ih + 28}" font-size="17" fill="#C9CEDC">{caption}</text>')
        cx = w - 22 - (n - 1 - i) * 18
        cy = bar_top + ih + bar_bottom / 2
        dots.append(
            f'<circle cx="{cx}" cy="{cy:.0f}" r="4.5" fill="#fff" fill-opacity=".18"/>'
            f'<circle class="d" style="{style}" cx="{cx}" cy="{cy:.0f}" r="4.5" fill="url(#brand)" opacity="{base}"/>'
        )
    h = bar_top + ih + bar_bottom
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}" role="img" aria-label="PostPilot screenshots">
<defs>
{BRAND}
<clipPath id="win"><rect width="{w}" height="{h}" rx="16"/></clipPath>
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


# --------------------------------------------------------------------------------------------------------------------
def spotlight(name, title, slides, hold=5.2):
    """A guided tour of one feature: each slide cross-fades in, the rest of the window dims, the screen zooms to
    the area that matters and a pulsing outline marks it. slides = [(png, (x, y, w, h) in the 1440x900 shot, caption)]."""
    W, H, bar_top, bar_bottom = 960, 600, 36, 46
    d = W / 1440
    n = len(slides)
    total = hold * n
    s = 100 / n
    fade = 0.6 / total * 100
    css, body, caps, dots = [], [], [], []
    for i, (file, (rx, ry, rw, rh), caption) in enumerate(slides):
        b64, _ = jpeg_b64(file, W)
        x, y, w, h = rx * d, ry * d, rw * d, rh * d
        zoom = max(1.3, min(2.4, 0.8 * min(W / w, H / h)))
        tx = min(0, max(W - zoom * W, W / 2 - zoom * (x + w / 2)))
        ty = min(0, max(H - zoom * H, H / 2 - zoom * (y + h / 2)))
        t0 = i * s
        a, b, c, e = t0 + .12 * s, t0 + .32 * s, t0 + .80 * s, t0 + .94 * s
        ease = 'animation-timing-function:cubic-bezier(.45,0,.2,1)'
        ident, zoomed = 'transform:translate(0,0) scale(1)', f'transform:translate({tx:.1f}px,{ty:.1f}px) scale({zoom:.3f})'
        # opacity: cross-fade into the slot, hold, cross-fade out (the next slide fades in over the same instant)
        if n == 1:
            op = [(0, 'opacity:1'), (100, 'opacity:1')]
        elif i == 0:
            op = [(0, 'opacity:1'), (s - fade, 'opacity:1'), (s, 'opacity:0'), (100 - fade, 'opacity:0'), (100, 'opacity:1')]
        elif i == n - 1:
            op = [(0, 'opacity:0'), (t0 - fade, 'opacity:0'), (t0, 'opacity:1'), (100 - fade, 'opacity:1'), (100, 'opacity:0')]
        else:
            op = [(0, 'opacity:0'), (t0 - fade, 'opacity:0'), (t0, 'opacity:1'), (t0 + s - fade, 'opacity:1'), (t0 + s, 'opacity:0'), (100, 'opacity:0')]
        zm = [(0, ident)] if t0 > 0 else []
        zm += [(t0, ident)] if t0 > 0 else []
        zm += [(a, ident + ';' + ease), (b, zoomed), (c, zoomed + ';' + ease), (e, ident), (100, ident)]
        if t0 == 0:
            zm[0] = (0, ident + ';' + ease)
        dim = [(0, 'opacity:0'), (a, 'opacity:0'), (b, 'opacity:1'), (c, 'opacity:1'), (e, 'opacity:0'), (100, 'opacity:0')]
        css += [kf(f'o{i}', op), kf(f'z{i}', zm), kf(f'd{i}', dim)]
        pad, r = 7, 10
        hx, hy, hw, hh = x - pad, y - pad, w + 2 * pad, h + 2 * pad
        cut = (f'M{hx + r:.1f} {hy:.1f}h{hw - 2 * r:.1f}a{r} {r} 0 0 1 {r} {r}v{hh - 2 * r:.1f}a{r} {r} 0 0 1 -{r} {r}h-{hw - 2 * r:.1f}'
               f'a{r} {r} 0 0 1 -{r} -{r}v-{hh - 2 * r:.1f}a{r} {r} 0 0 1 {r} -{r}Z')
        base = 1 if i == 0 else 0
        dur = f'{total}s linear infinite'
        body.append(
            f'<g style="opacity:{base};animation:o{i} {dur}"><g style="animation:z{i} {dur}">'
            f'<image x="0" y="0" width="{W}" height="{H}" href="data:image/jpeg;base64,{b64}"/>'
            f'<path style="opacity:0;animation:d{i} {dur}" fill-rule="evenodd" fill="#05060B" fill-opacity=".62" d="M0 0H{W}V{H}H0Z{cut}"/>'
            f'<rect x="{hx:.1f}" y="{hy:.1f}" width="{hw:.1f}" height="{hh:.1f}" rx="{r}" fill="none" stroke="url(#brand)" stroke-width="2.5" vector-effect="non-scaling-stroke"/>'
            f'<rect class="ring" x="{hx:.1f}" y="{hy:.1f}" width="{hw:.1f}" height="{hh:.1f}" rx="{r}" fill="none" stroke="url(#brand)" stroke-width="2" vector-effect="non-scaling-stroke"/>'
            f'</g></g>'
        )
        caps.append(f'<text style="opacity:{base};animation:o{i} {dur}" x="22" y="{bar_top + H + 29}" font-size="17" fill="#D7DBE8">{caption}</text>')
        cx, cy = W - 22 - (n - 1 - i) * 18, bar_top + H + bar_bottom / 2
        dots.append(f'<circle cx="{cx}" cy="{cy:.0f}" r="4.5" fill="#fff" fill-opacity=".18"/>'
                    f'<circle style="opacity:{base};animation:o{i} {dur}" cx="{cx}" cy="{cy:.0f}" r="4.5" fill="url(#brand)"/>')
    hh_total = bar_top + H + bar_bottom
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {hh_total}" width="{W}" height="{hh_total}" role="img" aria-label="{title}">
<defs>
{BRAND}
<clipPath id="win"><rect width="{W}" height="{hh_total}" rx="16"/></clipPath>
<clipPath id="view"><rect width="{W}" height="{H}"/></clipPath>
</defs>
<style>
.ring{{transform-box:fill-box;transform-origin:center;animation:ring 1.8s ease-out infinite}}
@keyframes ring{{from{{transform:scale(1);stroke-opacity:.9}}to{{transform:scale(1.07,1.12);stroke-opacity:0}}}}
{''.join(css)}
text{{font-family:{FONT}}}
{CALM}
</style>
<g clip-path="url(#win)">
<rect width="{W}" height="{hh_total}" fill="#0E1018"/>
<rect width="{W}" height="{bar_top}" fill="#171A26"/>
<circle cx="22" cy="18" r="6" fill="#FF5F57"/><circle cx="42" cy="18" r="6" fill="#FEBC2E"/><circle cx="62" cy="18" r="6" fill="#28C840"/>
<text x="{W / 2}" y="23" text-anchor="middle" font-size="13" fill="#7C849A">{title}</text>
<g transform="translate(0,{bar_top})"><g clip-path="url(#view)">{''.join(body)}</g></g>
<rect y="{bar_top + H}" width="{W}" height="{bar_bottom}" fill="#12141E"/>
{''.join(caps)}
{''.join(dots)}
</g>
<rect x=".75" y=".75" width="{W - 1.5}" height="{hh_total - 1.5}" rx="15.5" fill="none" stroke="#fff" stroke-opacity=".12" stroke-width="1.5"/>
</svg>
'''
    write(name, svg)


def spotlights():
    spotlight('spot-odoo.svg', 'PostPilot: Odoo Studio', [
        ('odoo-studio.png', (216, 300, 596, 490), 'Build a domain visually, copy it as JSON or Python'),
        ('odoo-migrate.png', (727, 222, 497, 545), 'Old XML-RPC call in, JSON-2 request out'),
    ])
    spotlight('spot-flutter.svg', 'PostPilot: Flutter and Dart', [
        ('dart-models.png', (684, 254, 520, 530), 'JSON to Dart models: plain, json_serializable or freezed'),
        ('dart-api-layer.png', (246, 570, 948, 215), 'A whole API layer from a collection: 24 files, optional state layer'),
        ('env-export.png', (525, 185, 711, 600), 'Environments to .env, env.json, AppConfig and launch configs'),
    ])
    spotlight('spot-git.svg', 'PostPilot: Git sync', [
        ('git-connect.png', (480, 455, 480, 190), 'Connect a workspace to your own GitHub repository'),
    ])
    spotlight('spot-safety.svg', 'PostPilot: Safety', [
        ('production-lock.png', (506, 290, 428, 320), 'Production environments ask before they change real data'),
        ('safety.png', (527, 275, 570, 220), 'Production lock covers Odoo writes and GraphQL mutations too'),
        ('safety.png', (527, 418, 570, 78), 'Secrets stay on your device, never in the Git file'),
    ])
    spotlight('spot-ci.svg', 'PostPilot: CI and run triage', [
        ('run-triage.png', (388, 380, 664, 165), 'Failures grouped by cause, with a one-click re-run of the failed ones'),
        ('ci-setup.png', (557, 240, 707, 300), 'The CI workflow is written for you: GitHub Actions, GitLab CI or a script'),
    ])
    spotlight('spot-everyday.svg', 'PostPilot: the everyday client', [
        ('hero.png', (1170, 180, 260, 45), 'Status, time and size at a glance'),
        ('response-tools.png', (236, 735, 968, 50), 'Turn any value in a response into a variable or a test'),
        ('collection-runner.png', (376, 240, 688, 230), 'Run a whole collection and see every result'),
        ('import-curl.png', (460, 352, 520, 260), 'Paste cURL, Postman, OpenAPI, Insomnia or HAR: the format is detected'),
        ('command-palette.png', (390, 90, 660, 330), 'One search finds every tool, request and environment'),
    ])


# --------------------------------------------------------------------------------------------------------------------
def terminal():
    """A real session (output copied from the command line), typed out line by line."""
    cw, lh, pad, top = 7.8, 23, 28, 74
    cycle = 24.0
    bg = '#0C0F16'
    cmd1 = 'dart run bin/postpilot.dart run workspace.json --env Staging'
    cmd2 = 'dart run bin/postpilot.dart run workspace.json --env Production'

    def ok(method, status, ms, name, tests):
        mc = {'GET': '#5BD98A', 'POST': '#FFC24B'}[method]
        pad_m = method + ' ' * (5 - len(method))
        return (f'<tspan fill="#5BD98A">✔</tspan> <tspan fill="{mc}" font-weight="700">{pad_m}</tspan> '
                f'<tspan fill="#5BD98A">{status}</tspan> <tspan fill="#7C849A">{str(ms).rjust(5, chr(160))} ms</tspan>  '
                f'<tspan fill="#D7DBE8">{name}</tspan>  <tspan fill="#7C849A">({tests} tests)</tspan>')

    def plain(text, color='#D7DBE8'):
        return f'<tspan fill="{color}">{text}</tspan>'

    sp = ' '
    lines = [
        ('type', cmd1, 0.5, 3.0),
        ('out', ok('GET', 200, 104, 'Shop API / Orders / List posts', '2/2'), 3.8),
        ('out', ok('GET', 200, 36, 'Shop API / Orders / Get a post', '2/2'), 4.15),
        ('out', ok('POST', 201, 341, 'Shop API / Orders / Create a post', '1/1'), 4.5),
        ('out', ok('GET', 200, 28, 'Shop API / Orders / Get a user', '2/2'), 4.85),
        ('out', '<tspan fill="#5BD98A" font-weight="700">4 requests, 4 passed, 0 failed</tspan><tspan fill="#7C849A"> in 0.54 s</tspan>', 5.6),
        ('gap',),
        ('type', cmd2, 7.4, 3.2),
        ('out', plain('Production lock: 1 selected request would change data in production, so nothing was sent.', '#FF7B7B'), 10.9),
        ('out', plain(f'{sp}{sp}POST{sp}{sp}{sp}Shop API / Orders / Create a post: environment "Production" looks like production', '#FFC24B'), 11.3),
        ('out', plain('Pass --allow-production to send them anyway, or select only read-only requests', '#9AA3B8'), 11.7),
        ('out', plain('with --collection or --folder.', '#9AA3B8'), 12.0),
        ('out', '<tspan fill="#FF7B7B" font-weight="700">exit code 2</tspan><tspan fill="#7C849A">  (nothing was sent)</tspan>', 12.7),
    ]
    rows, css = [], []
    row = 0
    pct = lambda t: t / cycle * 100
    fade_end = [(pct(cycle - 1.2), 'opacity:1'), (pct(cycle - .6), 'opacity:0'), (100, 'opacity:0')]
    for ln in lines:
        if ln[0] == 'gap':
            row += 1
            continue
        y = top + row * lh
        idx = len(rows)
        if ln[0] == 'type':
            _, cmd, t0, dur = ln
            n = len(cmd) + 2
            tw = n * cw
            end_x = f'transform:translateX({(n - 2) * cw:.1f}px)'
            css.append(kf(f'l{idx}', [(0, 'opacity:0'), (pct(t0), 'opacity:0'), (pct(t0) + .01, 'opacity:1')] + fade_end))
            css.append(kf(f'c{idx}', [(0, 'transform:translateX(0)'), (pct(t0), f'transform:translateX(0);animation-timing-function:steps({n - 2},end)'),
                                      (pct(t0 + dur), end_x), (100, end_x)]))
            css.append(kf(f'k{idx}', [(0, 'opacity:0'), (pct(t0), 'opacity:1'), (pct(t0 + dur) + .01, 'opacity:0'), (100, 'opacity:0')]))
            rows.append(
                f'<g style="opacity:0;animation:l{idx} {cycle}s linear infinite">'
                f'<text x="{pad}" y="{y}" font-size="13" textLength="{tw:.1f}" lengthAdjust="spacing"><tspan fill="{PINK}" font-weight="700">$</tspan> <tspan fill="#EDEFF6">{cmd}</tspan></text>'
                f'<g style="animation:c{idx} {cycle}s linear infinite"><rect x="{pad + 2 * cw:.1f}" y="{y - 15}" width="{(n - 2) * cw + 6:.1f}" height="21" fill="{bg}"/>'
                f'<rect style="opacity:0;animation:k{idx} {cycle}s linear infinite" x="{pad + 2 * cw:.1f}" y="{y - 14}" width="8" height="18" fill="{ORANGE}"/></g></g>'
            )
        else:
            _, spans, t0 = ln
            hide = 'opacity:0;transform:translateY(5px)'
            css.append(kf(f'l{idx}', [(0, hide), (pct(t0), hide), (pct(t0) + .6, 'opacity:1;transform:none')] + [(p, c + ';transform:none') for p, c in fade_end]))
            rows.append(f'<g style="opacity:0;animation:l{idx} {cycle}s ease-out infinite"><text x="{pad}" y="{y}" font-size="13" xml:space="preserve">{spans}</text></g>')
        row += 1
    w, h = 940, top + row * lh + 28
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}" role="img" aria-label="PostPilot command line: a passing run, then the production lock refusing a write">
<defs>
{BRAND}
<clipPath id="win"><rect width="{w}" height="{h}" rx="14"/></clipPath>
</defs>
<style>
text{{font-family:{MONO}}}
{''.join(css)}
{CALM}
</style>
<g clip-path="url(#win)">
<rect width="{w}" height="{h}" fill="{bg}"/>
<rect width="{w}" height="38" fill="#171A26"/>
<circle cx="22" cy="19" r="6" fill="#FF5F57"/><circle cx="42" cy="19" r="6" fill="#FEBC2E"/><circle cx="62" cy="19" r="6" fill="#28C840"/>
<text x="{w / 2}" y="24" text-anchor="middle" font-size="13" fill="#7C849A" style="font-family:{FONT}">postpilot: command line</text>
{''.join(rows)}
</g>
<rect x=".75" y=".75" width="{w - 1.5}" height="{h - 1.5}" rx="13.5" fill="none" stroke="#fff" stroke-opacity=".12" stroke-width="1.5"/>
</svg>
'''
    write('terminal.svg', svg)


# --------------------------------------------------------------------------------------------------------------------
def flow():
    """How the pieces fit: dots travel along the connections."""
    paths = {
        'p1': 'M246 118 C 290 118 300 118 344 118',
        'p2': 'M344 142 C 300 142 290 142 246 142',
        'p3': 'M560 108 C 610 90 640 70 690 70',
        'p4': 'M690 92 C 640 110 610 126 560 128',
        'p5': 'M780 100 C 780 130 780 150 780 176',
        'p6': 'M560 152 C 610 170 640 196 690 206',
        'p7': 'M452 244 C 452 224 452 206 452 180',
    }
    dots = [('p1', ORANGE, 0, 2.4), ('p1', ORANGE, 1.2, 2.4), ('p2', PINK, .6, 2.4), ('p2', PINK, 1.8, 2.4), ('p3', ORANGE, 0, 3), ('p4', PINK, 1.5, 3),
            ('p5', ORANGE, .5, 2.6), ('p6', PINK, 1, 3), ('p7', ORANGE, 0, 2.4), ('p7', PINK, 1.2, 2.4)]
    dot_svg = ''.join(
        f'<circle r="4.5" fill="{c}"><animateMotion dur="{d}s" begin="{b}s" repeatCount="indefinite" path="{paths[p]}"/></circle>' for p, c, b, d in dots)
    path_svg = ''.join(f'<path d="{p}" fill="none" stroke="#fff" stroke-opacity=".16" stroke-width="2" stroke-dasharray="2 7" stroke-linecap="round"/>' for p in paths.values())

    def node(x, y, w, h, title, sub, accent=False):
        fill = 'url(#brand)' if accent else '#1B1F33'
        return (f'<g class="node"><rect x="{x}" y="{y}" width="{w}" height="{h}" rx="16" fill="{fill}" stroke="#fff" stroke-opacity="{.28 if accent else .12}"/>'
                f'<text x="{x + w / 2}" y="{y + h / 2 - 2}" text-anchor="middle" font-size="19" font-weight="700" fill="#fff">{title}</text>'
                f'<text x="{x + w / 2}" y="{y + h / 2 + 18}" text-anchor="middle" font-size="13" fill="{"#FFE6DA" if accent else "#9AA3B8"}">{sub}</text></g>')

    def label(x, y, text):
        return f'<text x="{x}" y="{y}" text-anchor="middle" font-size="12" fill="#8890A6">{text}</text>'

    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 900 300" width="900" height="300" role="img" aria-label="How PostPilot fits: your API or Odoo server, the app, a Git repository, CI and AI agents">
<defs>
{GRADIENTS}
<linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#171A2B"/><stop offset="1" stop-color="#150F26"/></linearGradient>
<pattern id="dots" width="24" height="24" patternUnits="userSpaceOnUse"><circle cx="2" cy="2" r="1.2" fill="#fff" fill-opacity=".06"/></pattern>
<filter id="glow" x="-40%" y="-40%" width="180%" height="180%"><feGaussianBlur stdDeviation="12"/></filter>
<clipPath id="card"><rect width="900" height="300" rx="20"/></clipPath>
</defs>
<style>
text{{font-family:{FONT}}}
.halo{{animation:halo 3.2s ease-in-out infinite}}
.node{{animation:bob 5s ease-in-out infinite}}
.n2 .node{{animation-delay:-1.2s}} .n3 .node{{animation-delay:-2.4s}} .n4 .node{{animation-delay:-3.6s}}
@keyframes halo{{0%,100%{{opacity:.35}}50%{{opacity:.8}}}}
@keyframes bob{{0%,100%{{transform:translateY(0)}}50%{{transform:translateY(-3px)}}}}
{CALM}
</style>
<g clip-path="url(#card)">
<rect width="900" height="300" fill="url(#bg)"/><rect width="900" height="300" fill="url(#dots)"/>
<rect class="halo" x="346" y="96" width="212" height="76" rx="30" fill="url(#brand)" filter="url(#glow)"/>
{path_svg}
<g class="n2">{node(46, 96, 200, 68, 'Your API', 'REST, GraphQL, Odoo')}</g>
<g>{node(344, 90, 216, 88, 'PostPilot', 'desktop, mobile, web, CLI', True)}</g>
<g class="n3">{node(690, 40, 180, 60, 'Git repository', 'workspace.json')}</g>
<g class="n4">{node(690, 176, 180, 60, 'CI pipeline', 'JUnit, Markdown, triage')}</g>
<g class="n2">{node(364, 244, 176, 44, 'AI agent', 'over MCP')}</g>
{label(296, 104, 'requests')}{label(296, 164, 'responses')}
{label(628, 66, 'pull / push')}{label(826, 146, 'every push')}{label(612, 214, 'headless run')}{label(500, 222, 'MCP')}
{dot_svg}
</g>
<rect x=".75" y=".75" width="898.5" height="298.5" rx="19.5" fill="none" stroke="#fff" stroke-opacity=".12" stroke-width="1.5"/>
</svg>
'''
    write('flow.svg', svg)


# --------------------------------------------------------------------------------------------------------------------
def stats():
    items = [(17, 'code snippet targets'), (7, 'auth methods'), (5, 'import formats'), (5, 'platforms')]
    cell_w, gap, h = 270, 20, 124
    w = len(items) * cell_w + (len(items) - 1) * gap
    lh = 62
    css, cells = [], []
    cycle = 9.0
    for i, (n, label) in enumerate(items):
        x = i * (cell_w + gap)
        roll = 1.6
        t0 = i * .25
        p0, p1 = t0 / cycle * 100, (t0 + roll) / cycle * 100
        css.append(kf(f'r{i}', [(0, 'transform:translateY(0)'), (p0, f'transform:translateY(0);animation-timing-function:steps({n},end)'),
                                (p1, f'transform:translateY({-n * lh}px)'), (100, f'transform:translateY({-n * lh}px)')]))
        digits = ''.join(f'<text x="{cell_w / 2}" y="{lh * k + 50}" text-anchor="middle" font-size="54" font-weight="800" fill="url(#brand)">{k}</text>' for k in range(n + 1))
        cells.append(
            f'<g transform="translate({x},0)"><rect width="{cell_w}" height="{h}" rx="18" fill="#1B1F33" stroke="#fff" stroke-opacity=".10"/>'
            f'<clipPath id="c{i}"><rect x="0" y="6" width="{cell_w}" height="{lh}"/></clipPath>'
            f'<g clip-path="url(#c{i})"><g style="animation:r{i} {cycle}s linear infinite">{digits}</g></g>'
            f'<text x="{cell_w / 2}" y="{h - 22}" text-anchor="middle" font-size="16" fill="#A7AEC3">{label}</text></g>'
        )
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}" role="img" aria-label="17 code snippet targets, 7 auth methods, 5 import formats, 5 platforms">
<defs>{BRAND}</defs>
<style>
text{{font-family:{FONT}}}
{''.join(css)}
{CALM}
</style>
{''.join(cells)}
</svg>
'''
    write('stats.svg', svg)


# --------------------------------------------------------------------------------------------------------------------
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
{BRAND}
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
<text x="162" y="76" font-size="40" font-weight="800" fill="#fff" letter-spacing="-.5">Download Latest Release</text>
<text x="164" y="114" font-size="20" fill="#A7AEC3">One click. No account. Pick your platform below.</text>
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
    spotlights()
    terminal()
    flow()
    stats()
    download()
    divider()
