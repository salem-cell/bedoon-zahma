// يولّد أيقونة التطبيق 1024×1024 PNG بهوية «بوابة الوصول» (الرمز من تصميم Claude Design) بلا أي مكتبات خارجية.
// الاستخدام: node scripts/make-app-icon.mjs [خرج.png]
import { deflateSync } from "node:zlib";
import { writeFileSync } from "node:fs";

const SIZE = 1024;
const BG = [0x0e, 0x1c, 0x22];       // ليل
const FG = [0x15, 0xb9, 0x8f];       // أخضر المسار
const out = process.argv[2] ?? "BedoonZahma/App/Assets.xcassets/AppIcon.appiconset/AppIcon.png";

// الرمز في فضاء 100×100 (كما في SVG الهوية): قوس 270° حول (50,50) نصف قطر 32 مفتوح أسفل اليسار، ذيل من (12,88) إلى (50,50)، نقطة r=7.
const scale = SIZE / 100 * 0.78;         // الرمز يشغل 78% من الأيقونة
const offset = (SIZE - 100 * scale) / 2 + 0;
const P = (x, y) => [offset + x * scale, offset + y * scale];
const STROKE = 10 * scale;

// قوس: من زاوية 195° إلى 75° (اتجاه عقارب الساعة في إحداثيات الشاشة) → نُمثّله بنقاط كثيفة
const segments = [];
const cx = 50, cy = 50, r = 32;
const start = Math.atan2(58.3 - cy, 19.1 - cx);   // ≈ 165°
const end = Math.atan2(80.9 - cy, 41.7 - cx);     // ≈ 105°
// large-arc + sweep=1 ⇒ نذهب من start بزيادة الزاوية (في إحداثيات الشاشة y لأسفل) حتى end بعد دورة شبه كاملة
let a0 = start, a1 = end;
if (a1 <= a0) a1 += Math.PI * 2;
const steps = 400;
let prev = null;
for (let i = 0; i <= steps; i++) {
  const t = a0 + (a1 - a0) * (i / steps);
  const pt = P(cx + r * Math.cos(t), cy + r * Math.sin(t));
  if (prev) segments.push([prev, pt]);
  prev = pt;
}
segments.push([P(12, 88), P(50, 50)]);
const dot = { c: P(50, 50), r: 7 * scale };

function segDist(px, py, [[ax, ay], [bx, by]]) {
  const dx = bx - ax, dy = by - ay;
  const l2 = dx * dx + dy * dy || 1;
  const t = Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / l2));
  const qx = ax + t * dx, qy = ay + t * dy;
  return Math.hypot(px - qx, py - qy);
}

// تسريع: صندوق إحاطة لكل قطعة
const boxes = segments.map(([[ax, ay], [bx, by]]) => [Math.min(ax, bx) - STROKE, Math.min(ay, by) - STROKE, Math.max(ax, bx) + STROKE, Math.max(ay, by) + STROKE]);

const raw = Buffer.alloc((SIZE * 3 + 1) * SIZE);
for (let y = 0; y < SIZE; y++) {
  raw[y * (SIZE * 3 + 1)] = 0; // filter none
  for (let x = 0; x < SIZE; x++) {
    const px = x + 0.5, py = y + 0.5;
    let d = Infinity;
    for (let i = 0; i < segments.length; i++) {
      const b = boxes[i];
      if (px < b[0] || px > b[2] || py < b[1] || py > b[3]) continue;
      const dd = segDist(px, py, segments[i]);
      if (dd < d) d = dd;
    }
    let cov = Math.max(0, Math.min(1, (STROKE / 2 - d) + 0.5)); // تنعيم حواف بعرض بكسل
    const dd = Math.hypot(px - dot.c[0], py - dot.c[1]);
    cov = Math.max(cov, Math.max(0, Math.min(1, (dot.r - dd) + 0.5)));
    const o = y * (SIZE * 3 + 1) + 1 + x * 3;
    raw[o] = Math.round(BG[0] + (FG[0] - BG[0]) * cov);
    raw[o + 1] = Math.round(BG[1] + (FG[1] - BG[1]) * cov);
    raw[o + 2] = Math.round(BG[2] + (FG[2] - BG[2]) * cov);
  }
}

// PNG
const crcTable = new Int32Array(256).map((_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c; });
const crc32 = (buf) => { let c = -1; for (const b of buf) c = crcTable[(c ^ b) & 0xff] ^ (c >>> 8); return (c ^ -1) >>> 0; };
const chunk = (type, data) => {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
};
const ihdr = Buffer.alloc(13);
ihdr.writeUInt32BE(SIZE, 0); ihdr.writeUInt32BE(SIZE, 4); ihdr[8] = 8; ihdr[9] = 2; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0; // 8-bit RGB (بلا ألفا كما تشترط App Store)
const png = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  chunk("IHDR", ihdr),
  chunk("IDAT", deflateSync(raw, { level: 9 })),
  chunk("IEND", Buffer.alloc(0)),
]);
writeFileSync(out, png);
console.log(`wrote ${out} (${png.length} bytes, ${SIZE}x${SIZE} RGB)`);
