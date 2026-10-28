"""Fold a loose glTF 2.0 (a .gltf beside its .bin and textures) into one .glb.

Textures are re-encoded: resized so the long side is at most MAX_SIDE, written
as JPEG when they carry no alpha and PNG when they do. Buffers and images
become buffer views in the single binary chunk. Nothing else in the document
changes. Usage: pack-glb.py in.gltf out.glb [max_side] [jpeg_quality]
"""
import json, os, struct, sys, io, base64
from PIL import Image

src = sys.argv[1]; dst = sys.argv[2]
MAX_SIDE = int(sys.argv[3]) if len(sys.argv) > 3 else 1024
QUALITY = int(sys.argv[4]) if len(sys.argv) > 4 else 85
base = os.path.dirname(os.path.abspath(src))
g = json.load(open(src))

def read_uri(uri):
    if uri.startswith('data:'):
        return base64.b64decode(uri.split(',', 1)[1])
    from urllib.parse import unquote
    return open(os.path.join(base, unquote(uri)), 'rb').read()

blob = bytearray()
def append(data):
    off = len(blob)
    blob.extend(data)
    while len(blob) % 4: blob.append(0)
    return off, len(data)

# 1. Buffers: concatenate every buffer, remapping each bufferView's offset.
buffer_offsets = []
for b in g.get('buffers', []):
    data = read_uri(b['uri']) if 'uri' in b else b''
    off, _ = append(data)
    buffer_offsets.append(off)
for bv in g.get('bufferViews', []):
    bv['byteOffset'] = bv.get('byteOffset', 0) + buffer_offsets[bv['buffer']]
    bv['buffer'] = 0

# 2. Images: re-encode, store as buffer views.
report = []
for im in g.get('images', []):
    if 'bufferView' in im:
        bv = g['bufferViews'][im['bufferView']]
        raw = bytes(blob[bv['byteOffset']:bv['byteOffset'] + bv['byteLength']])
    else:
        raw = read_uri(im['uri'])
    pil = Image.open(io.BytesIO(raw))
    w0, h0 = pil.size
    has_alpha = pil.mode in ('RGBA', 'LA') or (pil.mode == 'P' and 'transparency' in pil.info)
    if max(pil.size) > MAX_SIDE:
        s = MAX_SIDE / max(pil.size)
        pil = pil.resize((max(1, round(w0 * s)), max(1, round(h0 * s))), Image.LANCZOS)
    out = io.BytesIO()
    if has_alpha:
        pil.convert('RGBA').save(out, 'PNG', optimize=True); mime = 'image/png'
    else:
        pil.convert('RGB').save(out, 'JPEG', quality=QUALITY, optimize=True, subsampling=0); mime = 'image/jpeg'
    data = out.getvalue()
    off, n = append(data)
    g['bufferViews'].append({'buffer': 0, 'byteOffset': off, 'byteLength': n})
    im.pop('uri', None)
    im['bufferView'] = len(g['bufferViews']) - 1
    im['mimeType'] = mime
    report.append((im.get('name', '?'), (w0, h0), pil.size, mime, n))

g['buffers'] = [{'byteLength': len(blob)}]

# 3. Write the GLB container.
js = json.dumps(g, separators=(',', ':')).encode('utf-8')
while len(js) % 4: js += b' '
total = 12 + 8 + len(js) + 8 + len(blob)
with open(dst, 'wb') as f:
    f.write(struct.pack('<III', 0x46546C67, 2, total))
    f.write(struct.pack('<II', len(js), 0x4E4F534A)); f.write(js)
    f.write(struct.pack('<II', len(blob), 0x004E4942)); f.write(bytes(blob))
print(f'{dst}: {total/1e6:.2f} MB')
for name, before, after, mime, n in report:
    print(f'  {name}: {before[0]}x{before[1]} -> {after[0]}x{after[1]} {mime} {n/1e3:.0f} KB')
