#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""svg2png.py — Minimal pure-Python SVG rasterizer for our game assets.

Supports exactly the subset used by traffic/luban assets:
  rect(round rx), line, circle, ellipse, path(M/L/Q/q/T/t/Z),
  linearGradient, radialGradient, <g> style inheritance, opacity,
  stop-color/stop-opacity. <text> is skipped (only a 10px decoration label).
Rendering: 2x2 supersampling, alpha compositing in document order.
PNG output: zlib + struct, RGBA8.
"""
import sys, os, math, zlib, struct, re
import xml.etree.ElementTree as ET

S = 2  # supersample per axis

# ---------- color / gradient parsing ----------

def parse_color(s):
    s = (s or '').strip()
    if s.startswith('#'):
        h = s[1:]
        if len(h) == 3:
            h = ''.join(c * 2 for c in h)
        return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
    named = {'black': (0, 0, 0), 'white': (255, 255, 255), 'none': None}
    if s in named:
        return named[s]
    return (0, 0, 0)

def parse_float(s, default=0.0):
    try:
        return float(str(s).strip())
    except (TypeError, ValueError):
        return default

# ---------- path flattening ----------

NUM = re.compile(r'[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?')

def parse_path(d):
    """Return list of subpaths; each subpath = (fillpoints, strokepolylines)."""
    tokens = re.findall(r'[MmLlQqTtZz]|[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?', d)
    subs = []
    cur = []          # current subpath points
    strokes = []      # polyline list for stroking (all subpaths)
    fillpts = []
    i = 0
    cmd = None
    cx = cy = 0.0
    sx = sy = 0.0
    prev_ctrl = None  # for T/t reflection (quadratic)
    def flush():
        nonlocal fillpts, cur
        if len(fillpts) >= 3:
            subs.append(list(fillpts))
        if len(cur) >= 2:
            strokes.append(list(cur))
        fillpts = []
        cur = []
    start = None
    while i < len(tokens):
        t = tokens[i]
        if re.match(r'^[A-Za-z]$', t):
            cmd = t
            i += 1
            if cmd in 'Zz':
                if fillpts:
                    fillpts.append(fillpts[0])
                if cur and start:
                    cur.append(start)
                flush()
                cx, cy = (start[0], start[1]) if start else (cx, cy)
                prev_ctrl = None
                continue
        def nums(n):
            nonlocal i
            vals = []
            while len(vals) < n and i < len(tokens) and not re.match(r'^[A-Za-z]$', tokens[i]):
                vals.append(float(tokens[i])); i += 1
            return vals
        if cmd in 'Mm':
            x, y = nums(2)
            if cmd == 'm': x += cx; y += cy
            flush()
            cx, cy = x, y; start = (x, y)
            fillpts.append((x, y)); cur.append((x, y))
            cmd = 'L' if cmd == 'M' else 'l'
        elif cmd in 'Ll':
            x, y = nums(2)
            if cmd == 'l': x += cx; y += cy
            cx, cy = x, y
            fillpts.append((x, y)); cur.append((x, y))
            prev_ctrl = None
        elif cmd in 'Qq':
            qcx, qcy, x, y = nums(4)
            if cmd == 'q': qcx += cx; qcy += cy; x += cx; y += cy
            N = 12
            for k in range(1, N + 1):
                u = k / N
                px = (1-u)**2*cx + 2*(1-u)*u*qcx + u*u*x
                py = (1-u)**2*cy + 2*(1-u)*u*qcy + u*u*y
                fillpts.append((px, py)); cur.append((px, py))
            cx, cy = x, y
            prev_ctrl = (qcx, qcy)
        elif cmd in 'Tt':
            x, y = nums(2)
            if cmd == 't': x += cx; y += cy
            qcx, qcy = (2*cx - prev_ctrl[0], 2*cy - prev_ctrl[1]) if prev_ctrl else (cx, cy)
            N = 12
            for k in range(1, N + 1):
                u = k / N
                px = (1-u)**2*cx + 2*(1-u)*u*qcx + u*u*x
                py = (1-u)**2*cy + 2*(1-u)*u*qcy + u*u*y
                fillpts.append((px, py)); cur.append((px, py))
            cx, cy = x, y
            prev_ctrl = (qcx, qcy)
        else:
            i += 1
    flush()
    return subs

def flatten_path_polys(d):
    subs = parse_path(d)
    return subs  # each is closed polygon approximation

# ---------- geometry membership ----------

def in_round_rect(px, py, x, y, w, h, rx, ry):
    if not (x <= px <= x + w and y <= py <= y + h):
        return False
    if rx <= 0 or ry <= 0:
        return True
    rx = min(rx, w / 2); ry = min(ry, h / 2)
    cxx = [x + rx, x + w - rx]; cyy = [y + ry, y + h - ry]
    for ccx in cxx:
        for ccy in cyy:
            corner = (px < x + rx or px > x + w - rx) and (py < y + ry or py > y + h - ry)
            if corner and abs(px - ccx) < 1e9:
                pass
    # simpler explicit corner check
    for ccx, xsign in ((x + rx, -1), (x + w - rx, 1)):
        for ccy, ysign in ((y + ry, -1), (y + h - ry, 1)):
            in_x = (px < x + rx) if xsign < 0 else (px > x + w - rx)
            in_y = (py < y + ry) if ysign < 0 else (py > y + h - ry)
            if in_x and in_y:
                return (px - ccx) ** 2 / rx ** 2 + (py - ccy) ** 2 / ry ** 2 <= 1.0
    return True

def in_ellipse(px, py, cx, cy, rx, ry):
    if rx <= 0 or ry <= 0:
        return False
    return (px - cx) ** 2 / rx ** 2 + (py - cy) ** 2 / ry ** 2 <= 1.0

def seg_dist(px, py, ax, ay, bx, by):
    vx, vy = bx - ax, by - ay
    L2 = vx * vx + vy * vy
    if L2 <= 1e-12:
        return math.hypot(px - ax, py - ay)
    u = max(0.0, min(1.0, ((px - ax) * vx + (py - ay) * vy) / L2))
    return math.hypot(px - (ax + u * vx), py - (ay + u * vy))

def in_polygon(px, py, pts):
    inside = False
    n = len(pts)
    j = n - 1
    for i in range(n):
        xi, yi = pts[i]; xj, yj = pts[j]
        if (yi > py) != (yj > py):
            xint = xi + (py - yi) * (xj - xi) / (yj - yi)
            if px < xint:
                inside = not inside
        j = i
    return inside

def poly_stroke_hit(px, py, pts, half):
    if half <= 0:
        return False
    for k in range(len(pts) - 1):
        if seg_dist(px, py, pts[k][0], pts[k][1], pts[k + 1][0], pts[k + 1][1]) <= half:
            return True
    return False

# ---------- renderer ----------

class Renderer:
    def __init__(self, tree, out_w, out_h):
        root = tree.getroot()
        self.vb_w = parse_float(root.get('width'), out_w)
        self.vb_h = parse_float(root.get('height'), out_h)
        vb = root.get('viewBox')
        if vb:
            p = [parse_float(v) for v in vb.split()]
            self.vb_w, self.vb_h = p[2], p[3]
        self.out_w, self.out_h = out_w, out_h
        self.sx = self.vb_w / out_w
        self.sy = self.vb_h / out_h
        self.canvas = [[(0.0, 0.0, 0.0, 0.0)] * out_w for _ in range(out_h)]
        self.gradients = {}
        self.collect_defs(root)
        self.walk(root, {})

    def collect_defs(self, node):
        for el in node.iter():
            tag = el.tag.split('}')[-1]
            gid = el.get('id')
            if gid and tag in ('linearGradient', 'radialGradient'):
                stops = []
                for st in el:
                    if st.tag.split('}')[-1] == 'stop':
                        col = parse_color(st.get('stop-color', '#000'))
                        a = parse_float(st.get('stop-opacity', 1), 1)
                        stops.append((parse_float(st.get('offset'), 0), col, a))
                stops.sort(key=lambda s: s[0])
                self.gradients[gid] = (tag, el.attrib, stops)

    def grad_color(self, gid, bbox, px, py):
        typ, attrs, stops = self.gradients[gid]
        x0, y0, x1, y1 = bbox
        w = max(x1 - x0, 1e-6); h = max(y1 - y0, 1e-6)
        if typ == 'linearGradient':
            fx1 = parse_float(attrs.get('x1'), 0); fy1 = parse_float(attrs.get('y1'), 0)
            fx2 = parse_float(attrs.get('x2'), 0); fy2 = parse_float(attrs.get('y2'), 1)
            ax, ay = x0 + fx1 * w, y0 + fy1 * h
            bx, by = x0 + fx2 * w, y0 + fy2 * h
            vx, vy = bx - ax, by - ay
            L2 = vx * vx + vy * vy
            t = 0.5 if L2 <= 1e-12 else ((px - ax) * vx + (py - ay) * vy) / L2
        else:
            fcx = parse_float(attrs.get('cx'), 0.5); fcy = parse_float(attrs.get('cy'), 0.5)
            fr = parse_float(attrs.get('r'), 0.5)
            t = math.hypot((px - (x0 + fcx * w)) / w, (py - (y0 + fcy * h)) / h) / max(fr, 1e-6)
        t = max(0.0, min(1.0, t))
        for k in range(len(stops) - 1):
            o0, c0, a0 = stops[k]; o1, c1, a1 = stops[k + 1]
            if o0 <= t <= o1:
                u = 0 if o1 <= o0 else (t - o0) / (o1 - o0)
                return (c0[0] + (c1[0] - c0[0]) * u,
                        c0[1] + (c1[1] - c0[1]) * u,
                        c0[2] + (c1[2] - c0[2]) * u,
                        a0 + (a1 - a0) * u)
        return (*stops[-1][1], stops[-1][2])

    def paint_of(self, val, bbox, px, py):
        if val is None or val == 'none':
            return None
        if isinstance(val, str) and val.startswith('url('):
            gid = val[5:val.index(')')]
            if gid not in self.gradients:
                return None
            return self.grad_color(gid, bbox, px, py)
        c = parse_color(val)
        return (c[0], c[1], c[2], 1.0)

    def alpha_color(self, col, op):
        def f(ux, uy):
            c = col(ux, uy)
            if c is None:
                return (0, 0, 0, 0)
            return (c[0], c[1], c[2], c[3] * op)
        return f

    def composite(self, ox0, oy0, ox1, oy1, cover_fn, color_fn):
        """cover_fn(ux, uy)->0/1 in user units; color_fn(ux, uy)->(r,g,b,a)."""
        cw, ch = self.out_w, self.out_h
        for py in range(max(0, int(oy0)), min(ch, int(oy1) + 1)):
            row = self.canvas[py]
            for px in range(max(0, int(ox0)), min(cw, int(ox1) + 1)):
                hit = 0
                col_acc = None
                for syi in range(S):
                    for sxi in range(S):
                        ux = (px + (sxi + 0.5) / S) * self.sx
                        uy = (py + (syi + 0.5) / S) * self.sy
                        if cover_fn(ux, uy):
                            hit += 1
                            col_acc = (ux, uy)
                if hit and col_acc:
                    cov = hit / (S * S)
                    r, g, b, a = color_fn(*col_acc)
                    if a <= 0:
                        continue
                    sa = a * cov
                    old = row[px]
                    oa = old[3]
                    outa = sa + oa * (1 - sa)
                    if outa <= 0:
                        continue
                    row[px] = ((r * sa + old[0] * oa * (1 - sa)) / outa,
                               (g * sa + old[1] * oa * (1 - sa)) / outa,
                               (b * sa + old[2] * oa * (1 - sa)) / outa,
                               outa)

    def walk(self, node, style):
        tag = node.tag.split('}')[-1]
        st = dict(style)
        for k in ('fill', 'stroke', 'stroke-width', 'opacity', 'stroke-linecap', 'fill-opacity', 'stroke-opacity'):
            if node.get(k) is not None:
                st[k] = node.get(k)
        if tag == 'defs':
            return
        if tag in ('g', 'svg'):
            for ch in node:
                self.walk(ch, st)
            return
        if tag == 'text':
            return  # decoration only (10px label in city bg)
        op = parse_float(st.get('opacity', 1), 1)
        if op <= 0:
            return
        sw = parse_float(st.get('stroke-width'), 1)
        fill = st.get('fill', 'black')
        stroke = st.get('stroke', 'none')

        if tag == 'rect':
            x = parse_float(node.get('x')); y = parse_float(node.get('y'))
            w = parse_float(node.get('width')); h = parse_float(node.get('height'))
            rx = parse_float(node.get('rx')); ry = parse_float(node.get('ry'))
            if ry <= 0: ry = rx
            if rx <= 0: ry2 = ry; rx = ry2
            bbox = (x, y, x + w, y + h)
            pad = sw
            ox0 = x / self.sx - pad - 1; oy0 = y / self.sy - pad - 1
            ox1 = (x + w) / self.sx + pad + 1; oy1 = (y + h) / self.sy + pad + 1

            def cov(ux, uy, x=x, y=y, w=w, h=h, rx=rx, ry=ry):
                return in_round_rect(ux, uy, x, y, w, h, rx, ry)

            def col(ux, uy):
                return self.paint_of(fill, bbox, ux, uy)
            if fill != 'none':
                self.composite(ox0, oy0, ox1, oy1, cov, self.alpha_color(col, op))
            if stroke not in (None, 'none'):
                def bcov(ux, uy, x=x, y=y, w=w, h=h, rx=rx, ry=ry, half=sw / 2):
                    inner = in_round_rect(ux, uy, x + half, y + half, w - 2 * half, h - 2 * half, max(rx - half, 0), max(ry - half, 0))
                    outer = in_round_rect(ux, uy, x - half, y - half, w + 2 * half, h + 2 * half, rx + half, ry + half)
                    return outer and not inner
                self.composite(ox0 - 1, oy0 - 1, ox1 + 1, oy1 + 1, bcov,
                               self.alpha_color(lambda a, b, bbox=bbox: self.paint_of(stroke, bbox, a, b), op))
            return

        if tag == 'circle' or tag == 'ellipse':
            cx = parse_float(node.get('cx')); cy = parse_float(node.get('cy'))
            rx = parse_float(node.get('r'), parse_float(node.get('rx')))
            ry = parse_float(node.get('r'), parse_float(node.get('ry')))
            if tag == 'ellipse':
                rx = parse_float(node.get('rx')); ry = parse_float(node.get('ry'))
            bbox = (cx - rx, cy - ry, cx + rx, cy + ry)
            pad = sw + 1
            ox0 = (cx - rx) / self.sx - pad; oy0 = (cy - ry) / self.sy - pad
            ox1 = (cx + rx) / self.sx + pad; oy1 = (cy + ry) / self.sy + pad
            if fill != 'none':
                self.composite(ox0, oy0, ox1, oy1,
                               lambda ux, uy, cx=cx, cy=cy, rx=rx, ry=ry: in_ellipse(ux, uy, cx, cy, rx, ry),
                               self.alpha_color(lambda a, b, bbox=bbox: self.paint_of(fill, bbox, a, b), op))
            if stroke not in (None, 'none'):
                half = sw / 2
                def ring(ux, uy, cx=cx, cy=cy, rx=rx, ry=ry, half=half):
                    inner = in_ellipse(ux, uy, cx, cy, max(rx - half, 0), max(ry - half, 0))
                    outer = in_ellipse(ux, uy, cx, cy, rx + half, ry + half)
                    return outer and not inner
                self.composite(ox0 - 1, oy0 - 1, ox1 + 1, oy1 + 1, ring,
                               self.alpha_color(lambda a, b, bbox=bbox: self.paint_of(stroke, bbox, a, b), op))
            return

        if tag == 'line':
            x1 = parse_float(node.get('x1')); y1 = parse_float(node.get('y1'))
            x2 = parse_float(node.get('x2')); y2 = parse_float(node.get('y2'))
            half = sw / 2 + 0.5
            bbox = (min(x1, x2), min(y1, y2), max(x1, x2), max(y1, y2))
            self.composite(min(x1, x2) / self.sx - half - 1, min(y1, y2) / self.sy - half - 1,
                           max(x1, x2) / self.sx + half + 1, max(y1, y2) / self.sy + half + 1,
                           lambda ux, uy, x1=x1, y1=y1, x2=x2, y2=y2, half=half: seg_dist(ux, uy, x1, y1, x2, y2) <= half,
                           self.alpha_color(lambda a, b, bbox=bbox: self.paint_of(stroke, bbox, a, b), op))
            return

        if tag == 'path':
            d = node.get('d', '')
            if d.startswith('url(') or d in ('bgGrad', 'roadGrad', 'shadowGrad', 'skyGrad', 'spot', 'tableGrad'):
                return
            subs = flatten_path_polys(d)
            if not subs:
                return
            allpts = [p for sub in subs for p in sub]
            xs = [p[0] for p in allpts]; ys = [p[1] for p in allpts]
            bbox = (min(xs), min(ys), max(xs), max(ys))
            pad = sw + 2
            ox0 = bbox[0] / self.sx - pad; oy0 = bbox[1] / self.sy - pad
            ox1 = bbox[2] / self.sx + pad; oy1 = bbox[3] / self.sy + pad
            if fill != 'none':
                def fcov(ux, uy, subs=subs):
                    return any(in_polygon(ux, uy, sub) for sub in subs)
                self.composite(ox0, oy0, ox1, oy1, fcov,
                               self.alpha_color(lambda a, b, bbox=bbox: self.paint_of(fill, bbox, a, b), op))
            if stroke not in (None, 'none'):
                half = sw / 2 + 0.25
                def scov(ux, uy, subs=subs, half=half):
                    return any(poly_stroke_hit(ux, uy, sub, half) for sub in subs)
                self.composite(ox0 - 1, oy0 - 1, ox1 + 1, oy1 + 1, scov,
                               self.alpha_color(lambda a, b, bbox=bbox: self.paint_of(stroke, bbox, a, b), op))
            return

# ---------- PNG writer ----------

def write_png(path, w, h, rows_rgba):
    raw = b''.join(b'\x00' + bytes(row) for row in rows_rgba)
    def chunk(typ, data):
        c = struct.pack('>I', len(data)) + typ + data
        return c + struct.pack('>I', zlib.crc32(typ + data) & 0xffffffff)
    png = b'\x89PNG\r\n\x1a\n'
    png += chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
    png += chunk(b'IDAT', zlib.compress(raw, 6))
    png += chunk(b'IEND', b'')
    with open(path, 'wb') as f:
        f.write(png)

def render_file(svg_path, png_path, out_w=None, out_h=None):
    tree = ET.parse(svg_path)
    root = tree.getroot()
    if out_w is None:
        out_w = int(round(parse_float(root.get('width'), 700)))
    if out_h is None:
        out_h = int(round(parse_float(root.get('height'), 450)))
    r = Renderer(tree, out_w, out_h)
    rows = []
    for y in range(out_h):
        row = bytearray()
        for x in range(out_w):
            c = r.canvas[y][x]
            a = c[3]
            if a >= 1:
                row += bytes((int(c[0] + 0.5), int(c[1] + 0.5), int(c[2] + 0.5), 255))
            elif a <= 0:
                row += b'\x00\x00\x00\x00'
            else:
                row += bytes((int(c[0] + 0.5), int(c[1] + 0.5), int(c[2] + 0.5), int(a * 255 + 0.5)))
        rows.append(row)
    write_png(png_path, out_w, out_h, rows)
    return out_w, out_h

if __name__ == '__main__':
    jobs = [
        ('traffic/assets/traffic_city_bg.svg',      'traffic/assets/traffic_city_bg.png',      700, 450),
        ('traffic/assets/traffic_pedestrian.svg',   'traffic/assets/traffic_pedestrian.png',    90, 115),
        ('traffic/assets/traffic_car_blue.svg',     'traffic/assets/traffic_car_blue.png',     195,  90),
        ('traffic/assets/traffic_car_coral.svg',    'traffic/assets/traffic_car_coral.png',    195,  90),
        ('luban/assets/luban_workbench_bg.svg',     'luban/assets/luban_workbench_bg.png',     700, 450),
        ('luban/assets/beam_A.svg',                 'luban/assets/beam_A.png',                 700, 450),
        ('luban/assets/beam_B.svg',                 'luban/assets/beam_B.png',                 700, 450),
        ('luban/assets/beam_C.svg',                 'luban/assets/beam_C.png',                 700, 450),
        ('luban/assets/beam_D.svg',                 'luban/assets/beam_D.png',                 700, 450),
    ]
    os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    for svg, png, w, h in jobs:
        ow, oh = render_file(svg, png, w, h)
        print(f'[OK] {png}  {ow}x{oh}  {os.path.getsize(png)} bytes')
