#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
make_wood_texture.py — 生成鲁班锁用的程序化木纹贴图（纯 Python，无第三方依赖）

输出 luban/assets/wood.png：
  - 横向是年轮/纹理走向，纵向是木纤维，
  - 亮度区间 0.62..0.95，整体接近中性，方便 QML 里用 baseColor 给每件木料染色。
"""

import math
import os
import struct
import random
import zlib

W, H = 512, 512


def lerp(a, b, t):
    return a + (b - a) * t


def value_noise(x, y, seed=0):
    """廉价的确定性噪声（双线性插值的格点哈希）。"""
    xi, yi = int(math.floor(x)), int(math.floor(y))
    fx, fy = x - xi, y - yi
    fx = fx * fx * (3 - 2 * fx)
    fy = fy * fy * (3 - 2 * fy)

    def h(a, b):
        n = (a * 374761393 + b * 668265263 + seed * 1442695040888963407) & 0xFFFFFFFF
        n = (n ^ (n >> 13)) * 1274126177 & 0xFFFFFFFF
        return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0

    v00, v10 = h(xi, yi), h(xi + 1, yi)
    v01, v11 = h(xi, yi + 1), h(xi + 1, yi + 1)
    return lerp(lerp(v00, v10, fx), lerp(v01, v11, fx), fy)


def fbm(x, y, seed=0, octaves=4):
    total, amp, freq, norm = 0.0, 1.0, 1.0, 0.0
    for o in range(octaves):
        total += amp * value_noise(x * freq, y * freq, seed + o * 17)
        norm += amp
        amp *= 0.5
        freq *= 2.0
    return total / norm


def wood_value(u, v, seed=0):
    """u 横向（年轮方向），v 纵向（纤维方向）。"""
    # 年轮：沿 u 的周期性弧线，被低频噪声扰动成不规则形状
    warp = fbm(u * 1.6, v * 0.35, seed, 3) * 2.4
    rings = math.sin((u * 9.0 + warp) * math.pi * 2.0 * 0.55)
    rings = 0.5 + 0.5 * rings
    rings = rings ** 1.6                      # 让暗纹更窄、更像年轮

    # 纤维：沿 v 拉长的细纹
    fiber = fbm(u * 26.0, v * 2.2, seed + 91, 3)

    # 零星木节/瑕疵
    fleck = 1.0 if fbm(u * 5.0, v * 5.0, seed + 311, 2) > 0.82 else 0.0

    val = 0.80 + 0.11 * (rings - 0.5) + 0.07 * (fiber - 0.5) - 0.05 * fleck
    return max(0.0, min(1.0, val))


def build_png(path, seed=20261103):
    rnd = random.Random(seed)
    rows = []
    for y in range(H):
        v = y / H
        row = bytearray()
        row.append(0)  # filter type 0
        for x in range(W):
            u = x / W
            val = wood_value(u, v, seed)
            # 极轻微的整体色偏：暖木色，但整体接近中性，便于染色
            r = int(max(0, min(255, val * 255 * 1.00)))
            g = int(max(0, min(255, val * 255 * 0.93)))
            b = int(max(0, min(255, val * 255 * 0.84)))
            row += bytes((r, g, b))
        rows.append(bytes(row))

    raw = b"".join(rows)

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0)  # 8bit RGB
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", ihdr)
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(png)
    return len(png)


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.join(here, "..", "luban", "assets", "wood.png")
    size = build_png(os.path.abspath(out))
    print("wood.png ->", os.path.abspath(out), size, "bytes")
