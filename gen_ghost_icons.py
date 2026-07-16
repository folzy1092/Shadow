#!/usr/bin/env python3
# Generates two 30x30 template PDF glyphs for the Ghost Mode navbar toggle:
#   ghost.pdf         - plain ghost (solid body, eye holes)
#   ghost_active.pdf  - ghost with a checkmark cut into the belly (enabled state)
# Both are single-color (black) template images; the app tints them with the
# system navbar control color via generateTintedImage.
import math

K = 0.5522847498  # circle bezier constant

def circle(cx, cy, r):
    # 4-curve bezier approximation of a circle, returns PDF path ops
    ops = []
    ops.append(f"{cx+r:.3f} {cy:.3f} m")
    ops.append(f"{cx+r:.3f} {cy+r*K:.3f} {cx+r*K:.3f} {cy+r:.3f} {cx:.3f} {cy+r:.3f} c")
    ops.append(f"{cx-r*K:.3f} {cy+r:.3f} {cx-r:.3f} {cy+r*K:.3f} {cx-r:.3f} {cy:.3f} c")
    ops.append(f"{cx-r:.3f} {cy-r*K:.3f} {cx-r*K:.3f} {cy-r:.3f} {cx:.3f} {cy-r:.3f} c")
    ops.append(f"{cx+r*K:.3f} {cy-r:.3f} {cx+r:.3f} {cy-r*K:.3f} {cx+r:.3f} {cy:.3f} c")
    ops.append("h")
    return "\n".join(ops)

def ghost_body():
    L, R, C = 6.0, 24.0, 15.0
    yS = 17.0      # where dome meets the vertical sides
    Yt = 26.5      # top of head
    yB = 8.0       # bottom baseline (scallop peaks)
    kdome = 6.0
    kbump = 3.4    # control offset to reach the scallop depth
    ops = []
    ops.append(f"{L:.3f} {yS:.3f} m")
    # dome: left half then right half
    ops.append(f"{L:.3f} {yS+kdome:.3f} {C-kdome:.3f} {Yt:.3f} {C:.3f} {Yt:.3f} c")
    ops.append(f"{C+kdome:.3f} {Yt:.3f} {R:.3f} {yS+kdome:.3f} {R:.3f} {yS:.3f} c")
    # right side down
    ops.append(f"{R:.3f} {yB:.3f} l")
    # bottom scallops right -> left (3 downward bumps, centers 21,15,9)
    ops.append(f"{R:.3f} {yB-kbump:.3f} {R-6:.3f} {yB-kbump:.3f} {R-6:.3f} {yB:.3f} c")
    ops.append(f"{R-6:.3f} {yB-kbump:.3f} {R-12:.3f} {yB-kbump:.3f} {R-12:.3f} {yB:.3f} c")
    ops.append(f"{R-12:.3f} {yB-kbump:.3f} {L:.3f} {yB-kbump:.3f} {L:.3f} {yB:.3f} c")
    # left side up
    ops.append(f"{L:.3f} {yS:.3f} l")
    ops.append("h")
    return "\n".join(ops)

def check_outline():
    # Checkmark ribbon (closed outline) cut as an even-odd hole in the belly.
    pts = [(9.8, 12.4), (12.7, 9.6), (19.8, 15.4)]  # centerline: left, vertex, right (in belly, below eyes)
    h = 1.3  # half thickness
    # per-segment unit normals
    def seg_normal(a, b):
        dx, dy = b[0]-a[0], b[1]-a[1]
        l = math.hypot(dx, dy)
        return (-dy/l, dx/l)
    n0 = seg_normal(pts[0], pts[1])
    n1 = seg_normal(pts[1], pts[2])
    # miter normal at vertex
    mx, my = n0[0]+n1[0], n0[1]+n1[1]
    ml = math.hypot(mx, my)
    nv = (mx/ml, my/ml)
    scale = 1.0 / max(0.5, (nv[0]*n0[0] + nv[1]*n0[1]))  # miter length
    top = [
        (pts[0][0]+n0[0]*h, pts[0][1]+n0[1]*h),
        (pts[1][0]+nv[0]*h*scale, pts[1][1]+nv[1]*h*scale),
        (pts[2][0]+n1[0]*h, pts[2][1]+n1[1]*h),
    ]
    bot = [
        (pts[2][0]-n1[0]*h, pts[2][1]-n1[1]*h),
        (pts[1][0]-nv[0]*h*scale, pts[1][1]-nv[1]*h*scale),
        (pts[0][0]-n0[0]*h, pts[0][1]-n0[1]*h),
    ]
    ring = top + bot
    ops = [f"{ring[0][0]:.3f} {ring[0][1]:.3f} m"]
    for p in ring[1:]:
        ops.append(f"{p[0]:.3f} {p[1]:.3f} l")
    ops.append("h")
    return "\n".join(ops)

def build_pdf(content_stream):
    objs = []
    objs.append("<< /Type /Catalog /Pages 2 0 R >>")
    objs.append("<< /Type /Pages /MediaBox [0 0 30 30] /Count 1 /Kids [ 3 0 R ] >>")
    objs.append("<< /Type /Page /Parent 2 0 R /Resources << >> /Contents 4 0 R >>")
    stream = content_stream.encode("latin-1")
    objs.append(f"<< /Length {len(stream)} >>\nstream\n" + content_stream + "\nendstream")
    out = b"%PDF-1.7\n"
    offsets = []
    for i, o in enumerate(objs, start=1):
        offsets.append(len(out))
        out += f"{i} 0 obj\n".encode("latin-1") + o.encode("latin-1") + b"\nendobj\n"
    xref_pos = len(out)
    out += f"xref\n0 {len(objs)+1}\n".encode("latin-1")
    out += b"0000000000 65535 f \n"
    for off in offsets:
        out += f"{off:010d} 00000 n \n".encode("latin-1")
    out += f"trailer\n<< /Size {len(objs)+1} /Root 1 0 R >>\nstartxref\n{xref_pos}\n%%EOF".encode("latin-1")
    return out

eye_l = circle(11.7, 18.5, 2.0)
eye_r = circle(18.3, 18.5, 2.0)

plain = "0 0 0 rg\n" + ghost_body() + "\n" + eye_l + "\n" + eye_r + "\nf*\n"
active = "0 0 0 rg\n" + ghost_body() + "\n" + eye_l + "\n" + eye_r + "\n" + check_outline() + "\nf*\n"

base = "/Users/matvej/Desktop/iphone app/Telegram-iOS/submodules/TelegramUI/Images.xcassets/Chat List"
with open(f"{base}/GhostIcon.imageset/ghost.pdf", "wb") as f:
    f.write(build_pdf(plain))
with open(f"{base}/GhostActiveIcon.imageset/ghost_active.pdf", "wb") as f:
    f.write(build_pdf(active))
print("wrote ghost.pdf and ghost_active.pdf")
