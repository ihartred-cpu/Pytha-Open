#!/usr/bin/env python3
r"""
pymat_from_textures.py  --  build PYTHA material libraries (.pymat) from folders of textures
==========================================================================================

UNOFFICIAL community script. Not made by or affiliated with PYTHA Lab. The .pymat layout was worked
out by inspecting V26 files; it opened and showed thumbnails correctly in V26, but is untested on other
versions. USE AT YOUR OWN RISK: work on copies, keep backups, close PYTHA before swapping a library in.

WHY
  PYTHA's built-in "New from Textures" (materials dialog > right-click > pick folder) makes one bare
  material per image: no roughness/bump wiring, no thumbnail. A .pymat is plain XML, so the whole job
  can be generated, including the preview sphere PYTHA shows in the palette.

REQUIREMENTS
  Python 3.8+, plus:  pip install pillow numpy      (only used to draw the thumbnails)

WHAT IT READS  (never modifies these)
  * Texture images (.jpg .jpeg .png .tif .tiff .bmp) under the folder you point it at, any depth.
  * MODE 1 only: your existing library, e.g.  C:\PATH\TO\TEXTURES\MY MATERIALS.pymat

WHAT IT WRITES  (new files only - it refuses nothing but also overwrites nothing of yours)
  * MODE 1:  <library>_NEW.pymat     next to the library you gave it  (original is left alone)
  * MODE 2:  <folder>\<foldername>.pymat   inside the texture folder (or wherever --out says)
  Nothing is written unless you pass --write. Without it you get a dry-run report.

SUGGESTED FOLDER LAYOUT  (links are RELATIVE to the .pymat, so keep the .pymat and its textures together)
  C:\PATH\TO\TEXTURES\
      MY MATERIALS.pymat                 <- main library (MODE 1)
      OAK\   oak_basecolor.png  oak_roughness.png        <- one folder per material (colour + maps)
      STONE\ marble_diffuse.jpg
      VendorName\                                          <- vendor folder, one swatch image each (MODE 2)
          1234 Some Colour.jpg
          1235 Another Colour.jpg
          VendorName.pymat               <- written by MODE 2

MODE 1 - sync: add materials for texture sets the library doesn't link yet
  python pymat_from_textures.py "C:\PATH\TO\TEXTURES\MY MATERIALS.pymat"            (dry run)
  python pymat_from_textures.py "C:\PATH\TO\TEXTURES\MY MATERIALS.pymat" --write
  - Existing materials untouched; new ones appended. Warns about absolute links and missing files.
  - Images whose names contain no map word (colour/basecolor/diffuse/albedo/roughness/bump/height/...)
    are ignored in this mode (they are usually previews or strays).
  - Then: back up the original, rename MY MATERIALS_NEW.pymat over it.

MODE 2 - folder: standalone library from ONE folder (handy for vendor swatch collections)
  python pymat_from_textures.py --folder "C:\PATH\TO\TEXTURES\VendorName" --write
  - Every image becomes one material named from its filename. Colour + roughness/bump/height maps that
    sit together are linked as one material.
  - --strip REGEX   remove text from names, e.g.  --strip " ?540 x 540| ?swatch"
  - --out FILE      write somewhere else (must be in or above the texture folder so links stay relative)

OTHER OPTIONS
  --bump auto|rough|height   which map feeds the bump slot (auto = bump, then height, then roughness)
  --no-preview               skip the embedded thumbnails (faster)
  --textures DIR             MODE 1: scan a different folder than the library's own

WHAT NEW MATERIALS GET
  Grey colour, diffuse 0.8, texture size 0 (set the real size in the material editor), the colour map
  as texture, the chosen map as bump, and a textured-sphere thumbnail drawn by this script (PYTHA draws
  its own when you edit the material). Units header is inch - edit SKELETON below for mm.

KNOWN LIMITS
  * Material IDs in a standalone file start at 1001; merging libraries with clashing IDs is untested.
  * Name guessing is filename-based: check the dry-run list before --write.
"""
import argparse, os, re, sys, datetime
from urllib.parse import quote, unquote

IMG = {'.jpg', '.jpeg', '.png', '.tif', '.tiff', '.bmp'}
KINDS = [
    ('normal', re.compile(r'normal(gl|dx)?|nrm', re.I)),
    ('ao',     re.compile(r'ambientocclusion|(^|[_\-. ])ao($|[_\-. ])|occlusion', re.I)),
    ('metal',  re.compile(r'metal(ness|lic)?($|[_\-. ])', re.I)),
    ('rough',  re.compile(r'rough(ness)?', re.I)),
    ('height', re.compile(r'displacement|height|disp($|[_\-. ])', re.I)),
    ('bump',   re.compile(r'bump', re.I)),
    ('color',  re.compile(r'base[_\-. ]?colou?r|albedo|diffuse|colou?r|(^|[_\-. ])d($|[_\-. ])', re.I)),
]

def classify(stem):
    for k, rx in KINDS:
        if rx.search(stem):
            return k, rx
    return None, None

def clean(s):
    return re.sub(r'\s+', ' ', re.sub(r'[_\-. ]+', ' ', s)).strip()

def scan(tex_dir, plain=False):
    """-> {(reldir, key): {'maps': {kind: rel}, 'stem': original stem of colour map}}"""
    sets = {}
    for root, dirs, files in os.walk(tex_dir):
        dirs[:] = [d for d in dirs if not d.startswith('.')]
        for f in sorted(files):
            stem, ext = os.path.splitext(f)
            if ext.lower() not in IMG:
                continue
            kind, rx = classify(stem)
            rel = os.path.relpath(os.path.join(root, f), tex_dir).replace(os.sep, '/')
            d = os.path.dirname(rel)
            if kind is None:
                if not plain:
                    continue                      # sync mode: ignore previews/stray images
                kind, key = 'color', stem         # vendor swatch: one image = one material
            else:
                key = clean(rx.sub(' ', stem, count=1)).lower()
            s = sets.setdefault((d, key), {'maps': {}, 'stem': stem})
            s['maps'][kind] = rel
            if kind == 'color':
                s['stem'] = stem
    return sets

def used_urls(xml, base_dir):
    out = set()
    for u in re.findall(r'<source url="([^"]+)"', xml):
        if u.startswith('file:///'):
            out.add(('abs', unquote(u[8:]).replace('\\', '/')))
        else:
            out.add(('rel', os.path.normpath(os.path.join(base_dir, unquote(u))).replace(os.sep, '/')))
    return out

def url_for(rel):
    return './' + '/'.join(quote(p, safe='') for p in rel.split('/'))

def material_xml(name, mid, color_aid, bump_aid, preview=None):
    L = []; a = L.append
    a(f'    <material name="{name}" id="{mid}">')
    a('      <a:attributes>')
    a('        <a:color-srgb id="1000001" t="c">')
    for _ in range(3): a('          <a:f r="0" t="d">0.5</a:f>')
    a('        </a:color-srgb>')
    a('        <a:diffuse id="1000002" t="d">0.80000000000000004</a:diffuse>')
    a('        <a:texture-size id="1000009" t="c">')
    a('          <a:f r="0" t="d" i="4">0</a:f>'); a('          <a:f r="0" t="d" i="4">0</a:f>')
    a('        </a:texture-size>')
    a('        <a:texture-asset id="1000010" t="c">')
    a('          <a:f r="0" t="i" i="1">33</a:f>'); a(f'          <a:f r="0" t="i" i="1">{color_aid}</a:f>'); a('          <a:f r="0" t="i" i="1">0</a:f>')
    a('        </a:texture-asset>')
    if bump_aid:
        a('        <a:bumpmap-asset id="1000012" t="c">')
        a('          <a:f r="0" t="i" i="1">33</a:f>'); a(f'          <a:f r="0" t="i" i="1">{bump_aid}</a:f>'); a('          <a:f r="0" t="i" i="1">0</a:f>')
        a('        </a:bumpmap-asset>')
        a('        <a:bumpmap-angle id="1000013" t="d">0.10000000000000001</a:bumpmap-angle>')
    for aid in ('1000014', '1000015'):
        a(f'        <a:attribute id="{aid}" t="c">')
        a('          <a:f r="0" t="i" i="1">28</a:f>'); a(f'          <a:f r="0" t="i" i="1">{mid}</a:f>'); a('          <a:f r="0" t="i" i="1">0</a:f>')
        a('        </a:attribute>')
    a('      </a:attributes>')
    L.extend(preview_xml(preview))
    a('    </material>')
    return L


# ---------------------------------------------------------------- preview thumbnails
PREVIEW = True
def render_preview(tex_path, N=135, SS=3):
    """Textured sphere on a checkerboard floor, like PYTHA's own material preview. -> base64 PNG text"""
    import io, base64
    import numpy as np
    from PIL import Image
    try:
        im = Image.open(tex_path)
        im.draft('RGB', (512, 512))
        im = im.convert('RGB')
        w, h = im.size; m = min(w, h)                       # centre square crop, then small
        im = im.crop(((w - m) // 2, (h - m) // 2, (w - m) // 2 + m, (h - m) // 2 + m)).resize((256, 256))
        tex = np.asarray(im, dtype=np.float32) / 255.0
    except Exception:
        return None
    n = N * SS
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float32)
    # floor: gently tilted checkerboard
    ang = 0.45
    px, py = xs / n - 0.5, ys / n - 0.5
    rx = px * np.cos(ang) - py * np.sin(ang)
    ry = px * np.sin(ang) + py * np.cos(ang)
    depth = 1.0 + 0.5 * (ry + 0.5)                  # mild perspective, no flip
    fu, fv = rx / depth * 7.0, ry / depth * 7.0
    chk = (np.floor(fu).astype(int) + np.floor(fv).astype(int)) % 2
    bg = np.where(chk[..., None] == 0, 0.92, 0.22).astype(np.float32) * np.ones((n, n, 3), np.float32)
    # sphere
    cx, cy, r = n * 0.5, n * 0.52, n * 0.40
    dx, dy = (xs - cx) / r, (ys - cy) / r
    d2 = dx * dx + dy * dy
    inside = d2 < 1.0
    dz = np.sqrt(np.clip(1.0 - d2, 0, 1))
    # texture: orthographic wrap, one tile across the sphere
    u = ((dx * 0.5 + 0.5) * 255).astype(int).clip(0, 255)
    v = ((dy * 0.5 + 0.5) * 255).astype(int).clip(0, 255)
    col = tex[v, u]
    L = np.array([-0.45, -0.55, 0.70], np.float32); L /= np.linalg.norm(L)
    lam = np.clip(dx * L[0] + dy * L[1] + dz * L[2], 0, 1)
    spec = np.clip(2 * lam * dz - L[2], 0, 1) ** 24 * 0.25
    lit = col * (0.35 + 0.75 * lam[..., None]) + spec[..., None]
    out = np.where(inside[..., None], lit, bg).clip(0, 1)
    img = Image.fromarray((out * 255).astype(np.uint8), 'RGB').resize((N, N), Image.LANCZOS)
    buf = io.BytesIO(); img.save(buf, 'PNG', optimize=True)
    b64 = base64.b64encode(buf.getvalue()).decode()
    return '\n'.join(b64[i:i + 76] for i in range(0, len(b64), 76))

def preview_xml(b64):
    if not b64:
        return []
    return ['      <preview>', '        <image size="135" type="image/png">', b64 + '</image>', '      </preview>']

SKELETON = '''<?xml version="1.0" encoding="UTF-8"?>
<pymat xmlns="http://xmlns.pytha.com/materials/1.0" xmlns:a="http://xmlns.pytha.com/attributes/1.0">
  <header>
    <unit-system>
      <length>inch</length>
    </unit-system>
    <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns:xmp="http://ns.adobe.com/xap/1.0/">
      <rdf:Description rdf:about="">
        <xmp:CreatorTool>PYTHA V26</xmp:CreatorTool>
        <xmp:CreateDate>%s</xmp:CreateDate>
      </rdf:Description>
    </rdf:RDF>
  </header>
  <extension-attributes></extension-attributes>
  <materials>
  </materials>
  <assets>
  </assets>
</pymat>
'''

def plan_materials(sets, used, names, nxt, bump_pref, standalone, strip, base_dir):
    by_dir = {}
    for (d, key), s in sets.items():
        by_dir.setdefault(d, []).append((key, s))
    order = {'rough': ['rough', 'bump', 'height'], 'height': ['height', 'bump', 'rough']}.get(bump_pref, ['bump', 'height', 'rough'])
    new_assets, new_mats, plan = [], [], []
    for d in sorted(by_dir):
        group = [(k, s) for k, s in sorted(by_dir[d]) if 'color' in s['maps']]
        for key, s in group:
            maps = s['maps']
            if ('rel', maps['color'].lower()) in used:
                continue
            bkind = next((k for k in order if k in maps), None)
            if standalone:
                base = os.path.basename(d) if d else ''
                label = re.sub(r'\s+', ' ', s['stem'].replace('_', ' ')).strip() if (key == s['stem'] or not key) else clean(key).title()
                if d and len(group) == 1:   name = base                    # folder-per-material layout
                elif d:                     name = f'{base} - {label}'
                else:                       name = label
                if strip: name = re.sub(strip, '', name).strip()
            else:
                base = os.path.basename(d) if d else 'ROOT'
                name = base if len(group) == 1 else f'{base} - {key.title()}'
            name = re.sub(r'[<>&"]', '', name) or 'Material'
            i, n0 = 2, name
            while name in names:
                name = f'{n0} ({i})'; i += 1
            names.add(name)
            caid = nxt; nxt += 1; new_assets.append((caid, maps['color']))
            baid = None
            if bkind:
                baid = nxt; nxt += 1; new_assets.append((baid, maps[bkind]))
            mid = nxt; nxt += 1
            pv = render_preview(os.path.join(base_dir, maps['color'])) if PREVIEW else None
            new_mats.append(material_xml(name, mid, caid, baid, pv))
            plan.append((name, maps['color'], maps.get(bkind) if bkind else None))
    return plan, new_mats, new_assets

def assets_xml(new_assets):
    return ''.join(f'    <asset id="{aid}">\n      <source url="{url_for(rel)}" />\n      <a:attributes></a:attributes>\n    </asset>\n' for aid, rel in new_assets)

def report(plan, where):
    print(f'\n{len(plan)} new material(s) from {where}:')
    for n, c, b in plan[:60]:
        print(f'  + {n:50.50s} colour={c}' + (f'  bump={b}' if b else ''))
    if len(plan) > 60: print(f'  ... and {len(plan) - 60} more')

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('pymat', nargs='?')
    ap.add_argument('--folder'); ap.add_argument('--out'); ap.add_argument('--strip')
    ap.add_argument('--textures'); ap.add_argument('--write', action='store_true')
    ap.add_argument('--no-preview', action='store_true', help='skip the embedded sphere thumbnails')
    ap.add_argument('--bump', default='auto', choices=['auto', 'rough', 'height'])
    args = ap.parse_args()
    global PREVIEW
    PREVIEW = args.write and not args.no_preview

    if args.folder:                                              # ---- MODE 2: standalone
        folder = os.path.abspath(args.folder)
        dest = os.path.abspath(args.out) if args.out else os.path.join(folder, os.path.basename(folder) + '.pymat')
        base_dir = os.path.dirname(dest)
        if os.path.commonpath([folder, base_dir]) != base_dir:
            sys.exit('--out must be in or above the texture folder so links stay relative')
        sets = scan(folder, plain=True)
        # file paths are relative to the folder; links must be relative to the pymat
        pre = os.path.relpath(folder, base_dir).replace(os.sep, '/')
        if pre != '.':
            for s in sets.values():
                s['maps'] = {k: f'{pre}/{v}' for k, v in s['maps'].items()}
        plan, mats, assets = plan_materials(sets, set(), set(), 1001, args.bump, True, args.strip, base_dir)
        report(plan, folder)
        if not plan: return print('No images found.')
        if not args.write: return print(f'\nDry run. --write creates {dest}')
        out = SKELETON % datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.000Z')
        out = out.replace('  <materials>\n', '  <materials>\n' + '\n'.join('\n'.join(m) for m in mats) + '\n', 1)
        out = out.replace('  <assets>\n', '  <assets>\n' + assets_xml(assets), 1)
        with open(dest, 'wb') as f: f.write(out.replace('\n', '\r\n').encode('utf-8'))
        return print(f'\nWrote {dest}')

    if not args.pymat: ap.error('give a .pymat to sync, or --folder DIR')
    pymat = os.path.abspath(args.pymat)                          # ---- MODE 1: sync
    tex_dir = os.path.abspath(args.textures or os.path.dirname(pymat))
    raw = open(pymat, 'rb').read()
    bom, text = raw.startswith(b'\xef\xbb\xbf'), raw.decode('utf-8-sig')
    crlf, xml = '\r\n' in text, text.replace('\r\n', '\n')
    nxt = max(int(i) for i in re.findall(r'<(?:material|asset) [^>]*?id="(\d+)"', xml)) + 1
    names = set(re.findall(r'<material name="([^"]+)"', xml))
    used_raw = used_urls(xml, tex_dir)
    for kind, p in sorted(used_raw):
        if kind == 'abs': print(f'WARN absolute link (only works on one PC): {p}')
        elif not os.path.exists(p): print(f'WARN missing file: {p}')
    used = {(k, os.path.relpath(p, tex_dir).replace(os.sep, '/').lower()) for k, p in used_raw if k == 'rel'}
    plan, mats, assets = plan_materials(scan(tex_dir), used, names, nxt, args.bump, False, None, tex_dir)
    report(plan, tex_dir)
    if not plan: return print('Nothing new - library already covers every texture set.')
    if not args.write: return print('\nDry run. Add --write to create the _NEW.pymat file.')
    out = xml.replace('  </materials>', '\n'.join('\n'.join(m) for m in mats) + '\n  </materials>', 1)
    out = out.replace('  </assets>', assets_xml(assets) + '  </assets>', 1)
    if crlf: out = out.replace('\n', '\r\n')
    dest = os.path.splitext(pymat)[0] + '_NEW.pymat'
    with open(dest, 'wb') as f: f.write((b'\xef\xbb\xbf' if bom else b'') + out.encode('utf-8'))
    print(f'\nWrote {dest}')

if __name__ == '__main__':
    main()
