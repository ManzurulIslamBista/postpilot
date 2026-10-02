"""Renders tool/logo.svg into the PNG masters under assets/logo/.

Needs Pillow-free headless Edge/Chrome only for the SVG -> PNG step:
    python tool/build_logo.py "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe"
Then run `dart run flutter_launcher_icons` to fan the masters out to every platform.
"""
import pathlib, re, subprocess, sys, tempfile

browser = sys.argv[1]
root = pathlib.Path(__file__).resolve().parent
out = root.parent / "assets" / "logo"
out.mkdir(parents=True, exist_ok=True)
svg = (root / "logo.svg").read_text(encoding="utf-8")

# Full-bleed square: the OS (iOS) or a mask (Android/PWA) supplies the corner shape.
square = svg.replace('rx="232"', 'rx="0"')
square = re.sub(r'<rect x="1.5".*?/>', '', square)

# Plane only, shrunk into the adaptive-icon safe zone, on a transparent canvas.
fg = re.sub(r'<rect width="1024" height="1024" fill="url\(#bg\)"/>', '', svg)
fg = re.sub(r'<rect width="1024" height="1024" fill="url\(#halo\)"/>', '', fg)
fg = re.sub(r'<rect width="1024" height="560" fill="url\(#sheen\)"/>', '', fg)
fg = re.sub(r'<rect x="1.5".*?/>', '', fg)
fg = fg.replace('<g clip-path="url(#tile)">', '<g transform="translate(512,512) scale(0.62) translate(-518,-523)">')

def render(name, source):
    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        (tmp / "logo.svg").write_text(source, encoding="utf-8")
        (tmp / "page.html").write_text(
            '<!doctype html><style>html,body{margin:0;background:transparent}</style>'
            '<img src="logo.svg" width="1024" height="1024" style="display:block">', encoding="utf-8")
        subprocess.run([browser, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                        "--default-background-color=00000000", "--window-size=1024,1024",
                        f"--screenshot={out / name}", (tmp / "page.html").as_uri()],
                       check=True, capture_output=True)
    print("wrote", out / name)

render("logo.png", svg)
render("logo_square.png", square)
render("logo_foreground.png", fg)
