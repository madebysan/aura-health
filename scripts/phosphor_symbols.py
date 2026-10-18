"""Turn Phosphor Light SVGs into custom SF Symbols for Aura's asset catalog.

Usage: python3 -I scripts/phosphor_symbols.py assets/icons/phosphor-light AuraHealth/Resources/Assets.xcassets/Icons

Each <name>.svg (256x256, filled paths only) becomes ph.<name>.symbolset. The same
outline fills all 27 weight and scale slots (Phosphor Light has one stroke weight), so
Image("ph.<name>") sizes with the font like an SF Symbol and toolbars that ask for a
heavier weight still find a glyph.
"""
import json, re, sys
import xml.etree.ElementTree as ET
from pathlib import Path

BOX = 128                    # 256-unit icon box -> 128 units at the 100 pt medium size
WEIGHTS = ["Ultralight", "Thin", "Light", "Regular", "Medium", "Semibold", "Bold", "Heavy", "Black"]
# scale -> (size factor, vertical centre = middle of that row's cap height)
SCALES = {"S": (0.8, (696 + 625.541) / 2), "M": (1.0, (1126 + 1055.54) / 2), "L": (1.3, (1556 + 1485.54) / 2)}
SCALE, LEFT, TOP = 1.0, 0.0, 0.0   # set per variant by main()

NUM = re.compile(r"[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?")
ARGS = {"M": 2, "L": 2, "H": 1, "V": 1, "C": 6, "S": 4, "Q": 4, "T": 2, "A": 7, "Z": 0}


def tokens(d):
    i = 0
    while i < len(d):
        c = d[i]
        if c.isalpha():
            yield c; i += 1
        elif c in " ,\t\n":
            i += 1
        else:
            m = NUM.match(d, i)
            if not m:
                raise ValueError(f"bad path data near {d[i:i+12]!r}")
            yield float(m.group()); i = m.end()


def fmt(v):
    return f"{v:.3f}".rstrip("0").rstrip(".")


def transform(d):
    out, cmd, toks = [], None, list(tokens(d))
    i = 0
    while i < len(toks):
        if isinstance(toks[i], str):
            cmd = toks[i]; i += 1
            if cmd in "Zz":
                out.append("Z"); continue
        n = ARGS[cmd.upper()]
        a = toks[i:i + n]; i += n
        rel = cmd.islower()
        U = cmd.upper()
        sx = lambda x: x * SCALE + (0 if rel else LEFT)
        sy = lambda y: y * SCALE + (0 if rel else TOP)
        if U == "H":
            v = [sx(a[0])]
        elif U == "V":
            v = [sy(a[0])]
        elif U == "A":
            v = [a[0] * SCALE, a[1] * SCALE, a[2], a[3], a[4], sx(a[5]), sy(a[6])]
        else:
            v = [sx(x) if k % 2 == 0 else sy(x) for k, x in enumerate(a)]
        if U == "A":
            v = [fmt(v[0]), fmt(v[1]), fmt(v[2]), str(int(v[3])), str(int(v[4])), fmt(v[5]), fmt(v[6])]
        else:
            v = [fmt(x) for x in v]
        out.append(cmd + " ".join(v))
        if U == "M":  # extra pairs after a moveto are linetos
            cmd = "l" if rel else "L"
    return " ".join(out)


TEMPLATE = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
<svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="3300" height="2200">
 <!--glyph: "ph.{name}", point size: 100.0, Phosphor Icons (MIT), light weight-->
 <g id="Notes">
  <rect height="2200" id="artboard" style="fill:white;opacity:1" width="3300" x="0" y="0"/>
  <text id="template-version" style="stroke:none;fill:black;font-family:sans-serif;font-size:13;" transform="matrix(1 0 0 1 3036 1933)">Template v.3.0</text>
 </g>
 <g id="Guides">
  <line id="Baseline-S" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="696" y2="696"/>
  <line id="Capline-S" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="625.541" y2="625.541"/>
  <line id="Baseline-M" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="1126" y2="1126"/>
  <line id="Capline-M" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="1055.54" y2="1055.54"/>
  <line id="Baseline-L" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="1556" y2="1556"/>
  <line id="Capline-L" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="1485.54" y2="1485.54"/>
{margins}
 </g>
 <g id="Symbols">
{symbols}
 </g>
</svg>
"""


def render(name, ds):
    global SCALE, LEFT, TOP
    margins, symbols = [], []
    style = 'style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;"'
    for row, (factor, centre) in SCALES.items():
        size = BOX * factor
        for col, weight in enumerate(WEIGHTS):
            SCALE, LEFT, TOP = size / 256, 400 + col * 300, centre - size / 2
            vid = f"{weight}-{row}"
            for side, x in (("left", LEFT), ("right", LEFT + size)):
                margins.append(f'  <line id="{side}-margin-{vid}" {style} x1="{fmt(x)}" x2="{fmt(x)}" y1="{fmt(TOP)}" y2="{fmt(TOP + size)}"/>')
            paths = "\n".join(f'   <path d="{transform(d)}"/>' for d in ds)
            symbols.append(f'  <g id="{vid}">\n{paths}\n  </g>')
    return TEMPLATE.format(name=name, margins="\n".join(margins), symbols="\n".join(symbols))


def main(src, dst):
    src, dst = Path(src), Path(dst)
    dst.mkdir(parents=True, exist_ok=True)
    (dst / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    count = 0
    for svg in sorted(src.glob("*.svg")):
        root = ET.parse(svg).getroot()
        ds = [el.get("d") for el in root.iter() if el.tag.endswith("path") and el.get("d")]
        others = {el.tag.split("}")[-1] for el in root.iter()} - {"svg", "path"}
        if not ds or others:
            raise SystemExit(f"{svg.name}: expected only filled paths, found {others or 'nothing'}")
        name = svg.stem
        out = dst / f"ph.{name}.symbolset"
        out.mkdir(exist_ok=True)
        (out / f"ph.{name}.svg").write_text(render(name, ds))
        (out / "Contents.json").write_text(json.dumps({
            "info": {"author": "xcode", "version": 1},
            "symbols": [{"filename": f"ph.{name}.svg", "idiom": "universal"}],
        }, indent=2) + "\n")
        count += 1
    print(f"wrote {count} symbols to {dst}")


if __name__ == "__main__":
    main(*sys.argv[1:3])
