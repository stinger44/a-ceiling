/**
 * calculator.js — Room Area Calculator
 * Alpha Ceiling | Frontend-only, localStorage DB
 */

// ─── LABEL GENERATOR ─────────────────────────────────────────────────────────
// Sequence: a,b,...,z, a1,b1,...,z1, a2,b2,...,z2, ...
const LETTERS = 'abcdefghijklmnopqrstuvwxyz';
function getLabel(index) {
  const cycle = Math.floor(index / 26);
  return LETTERS[index % 26] + (cycle > 0 ? cycle : '');
}

// ─── NOMENCLATURE DB (localStorage) ─────────────────────────────────────────
const DB_KEY = 'alpha_ceiling_nomenclature';

const DEFAULT_ITEMS = [
  { id: 1, name: 'Матовый потолок',             unit: 'м²', price: 450  },
  { id: 2, name: 'Глянцевый потолок',           unit: 'м²', price: 490  },
  { id: 3, name: 'Сатиновый потолок',           unit: 'м²', price: 470  },
  { id: 4, name: 'Теневой профиль EuroKRAAB',   unit: 'м²', price: 1200 },
  { id: 5, name: 'Парящий потолок',             unit: 'м²', price: 1500 },
  { id: 6, name: 'Тканевые стены Тихие Стены',  unit: 'м²', price: 850  },
  { id: 7, name: 'Монтаж (работа)',             unit: 'м²', price: 200  },
];

function loadDB() {
  try {
    const raw = localStorage.getItem(DB_KEY);
    return raw ? JSON.parse(raw) : [...DEFAULT_ITEMS];
  } catch { return [...DEFAULT_ITEMS]; }
}
function saveDB(items) {
  localStorage.setItem(DB_KEY, JSON.stringify(items));
}
function nextId(items) {
  return items.length ? Math.max(...items.map(i => i.id)) + 1 : 1;
}

// ─── STATE ───────────────────────────────────────────────────────────────────
const state = {
  vertices: [],       // [{x,y}] in cm (real-world)
  segments: [],       // [{length, dir, label}]
  isClosed: false,
  direction: 'right', // 'right'|'left'|'up'|'down'
  priceLines: [],     // [{id, itemId}]
  nextPriceLineId: 1,
  db: loadDB(),
};

// ─── CANVAS & RENDERING ───────────────────────────────────────────────────────
const canvas  = document.getElementById('roomCanvas');
const ctx     = canvas.getContext('2d');
let   DPR     = window.devicePixelRatio || 1;

// Resize canvas to fill its CSS box
function resizeCanvas() {
  const rect = canvas.parentElement.getBoundingClientRect();
  const w = Math.floor(rect.width);
  // Use remaining height: parent total height minus toolbar ~50px
  const h = Math.max(300, Math.floor(rect.height) - 54);
  canvas.style.width  = w + 'px';
  canvas.style.height = h + 'px';
  canvas.width  = w * DPR;
  canvas.height = h * DPR;
  ctx.scale(DPR, DPR);
  draw();
}

// Compute bounding box of vertices plus padding
function getViewTransform() {
  const W = canvas.width  / DPR;
  const H = canvas.height / DPR;
  const PAD = 60; // px padding

  if (state.vertices.length === 0) {
    // Show empty grid centered at origin
    return { ox: W / 2, oy: H / 2, scale: 2 }; // 2px per cm → 1m=200px
  }

  const xs = state.vertices.map(v => v.x);
  const ys = state.vertices.map(v => v.y);
  const minX = Math.min(...xs), maxX = Math.max(...xs);
  const minY = Math.min(...ys), maxY = Math.max(...ys);
  const rangeX = maxX - minX || 100;
  const rangeY = maxY - minY || 100;

  const scale = Math.min(
    (W - PAD * 2) / rangeX,
    (H - PAD * 2) / rangeY,
    8   // max 8px per cm
  );

  const cx = (minX + maxX) / 2;
  const cy = (minY + maxY) / 2;
  return { ox: W / 2 - cx * scale, oy: H / 2 - cy * scale, scale };
}

function toScreen(x, y, t) {
  return { sx: t.ox + x * t.scale, sy: t.oy + y * t.scale };
}

function draw() {
  const W = canvas.width  / DPR;
  const H = canvas.height / DPR;
  ctx.clearRect(0, 0, W, H);

  // Background
  ctx.fillStyle = getComputedStyle(document.documentElement)
    .getPropertyValue('--canvas-bg').trim() || '#0d0d18';
  ctx.fillRect(0, 0, W, H);

  const t = getViewTransform();
  drawGrid(W, H, t);

  if (state.vertices.length === 0) {
    drawEmptyHint(W, H);
    return;
  }

  drawPolygon(t);
  drawVertexLabels(t);
  updateAreaDisplay();
}

function drawGrid(W, H, t) {
  // Choose a nice grid step: ~50px between lines in real world cm
  const rawStep = 50 / t.scale;  // cm per 50px
  // Round to nice numbers: 10, 25, 50, 100 cm
  const niceSteps = [10, 25, 50, 100, 200, 500];
  const gridStep = niceSteps.reduce((prev, cur) =>
    Math.abs(cur - rawStep) < Math.abs(prev - rawStep) ? cur : prev
  );
  const stepPx = gridStep * t.scale;

  // Compute grid origin aligned to zero
  const startX = t.ox % stepPx;
  const startY = t.oy % stepPx;

  ctx.strokeStyle = 'rgba(108,99,255,0.08)';
  ctx.lineWidth = 1;
  for (let x = startX; x < W; x += stepPx) { ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, H); ctx.stroke(); }
  for (let y = startY; y < H; y += stepPx) { ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(W, y); ctx.stroke(); }

  // Axis through origin
  ctx.strokeStyle = 'rgba(108,99,255,0.22)';
  ctx.lineWidth = 1;
  if (t.ox > 0 && t.ox < W) { ctx.beginPath(); ctx.moveTo(t.ox, 0); ctx.lineTo(t.ox, H); ctx.stroke(); }
  if (t.oy > 0 && t.oy < H) { ctx.beginPath(); ctx.moveTo(0, t.oy); ctx.lineTo(W, t.oy); ctx.stroke(); }

  // Scale label bottom-left
  ctx.fillStyle = 'rgba(108,99,255,0.5)';
  ctx.font = '11px Inter, sans-serif';
  const label = gridStep >= 100 ? `${gridStep/100} м` : `${gridStep} см`;
  ctx.fillText(`· ${label}`, 12, H - 10);
}

function drawEmptyHint(W, H) {
  ctx.fillStyle = 'rgba(108,99,255,0.25)';
  ctx.font = '14px Inter, sans-serif';
  ctx.textAlign = 'center';
  ctx.fillText('Добавьте первый отрезок', W / 2, H / 2 - 12);
  ctx.font = '12px Inter, sans-serif';
  ctx.fillStyle = 'rgba(255,255,255,0.15)';
  ctx.fillText('Введите длину и направление → нажмите «Добавить»', W / 2, H / 2 + 12);
  ctx.textAlign = 'left';
}

function drawPolygon(t) {
  const verts = state.vertices;
  if (verts.length < 1) return;

  // Filled polygon (only if closed)
  if (state.isClosed && verts.length >= 3) {
    ctx.beginPath();
    const { sx, sy } = toScreen(verts[0].x, verts[0].y, t);
    ctx.moveTo(sx, sy);
    for (let i = 1; i < verts.length; i++) {
      const p = toScreen(verts[i].x, verts[i].y, t);
      ctx.lineTo(p.sx, p.sy);
    }
    ctx.closePath();
    ctx.fillStyle = 'rgba(34,211,165,0.10)';
    ctx.fill();
    ctx.strokeStyle = '#22d3a5';
    ctx.lineWidth = 2.5;
    ctx.stroke();
  } else {
    // Draw open polyline
    ctx.beginPath();
    const { sx, sy } = toScreen(verts[0].x, verts[0].y, t);
    ctx.moveTo(sx, sy);
    for (let i = 1; i < verts.length; i++) {
      const p = toScreen(verts[i].x, verts[i].y, t);
      ctx.lineTo(p.sx, p.sy);
    }
    ctx.strokeStyle = '#6c63ff';
    ctx.lineWidth = 2.5;
    ctx.setLineDash([]);
    ctx.stroke();

    // Dashed "close" preview from last to first
    if (verts.length >= 3) {
      const last  = toScreen(verts[verts.length - 1].x, verts[verts.length - 1].y, t);
      const first = toScreen(verts[0].x, verts[0].y, t);
      ctx.beginPath();
      ctx.moveTo(last.sx, last.sy);
      ctx.lineTo(first.sx, first.sy);
      ctx.strokeStyle = 'rgba(108,99,255,0.3)';
      ctx.setLineDash([5, 5]);
      ctx.lineWidth = 1.5;
      ctx.stroke();
      ctx.setLineDash([]);
    }
  }

  // Draw direction arrows on each segment
  drawArrows(t);

  // Vertex dots
  verts.forEach((v, i) => {
    const { sx, sy } = toScreen(v.x, v.y, t);
    ctx.beginPath();
    ctx.arc(sx, sy, i === 0 ? 7 : 5, 0, Math.PI * 2);
    ctx.fillStyle = i === 0 ? '#f59e0b' : (state.isClosed ? '#22d3a5' : '#6c63ff');
    ctx.fill();
    ctx.strokeStyle = '#0d0d18';
    ctx.lineWidth = 2;
    ctx.stroke();
  });
}

function drawArrows(t) {
  const verts = state.vertices;
  const total = verts.length - 1 + (state.isClosed ? 1 : 0);
  for (let i = 0; i < total; i++) {
    const from = verts[i];
    const to   = verts[(i + 1) % verts.length];
    const f = toScreen(from.x, from.y, t);
    const e = toScreen(to.x,   to.y,   t);
    const mx = (f.sx + e.sx) / 2;
    const my = (f.sy + e.sy) / 2;
    const angle = Math.atan2(e.sy - f.sy, e.sx - f.sx);
    const arrowSize = 7;
    ctx.save();
    ctx.translate(mx, my);
    ctx.rotate(angle);
    ctx.fillStyle = 'rgba(108,99,255,0.7)';
    ctx.beginPath();
    ctx.moveTo(arrowSize, 0);
    ctx.lineTo(-arrowSize * .6, -arrowSize * .5);
    ctx.lineTo(-arrowSize * .6,  arrowSize * .5);
    ctx.closePath();
    ctx.fill();
    ctx.restore();
  }
}

function drawVertexLabels(t) {
  const verts = state.vertices;
  verts.forEach((v, i) => {
    const { sx, sy } = toScreen(v.x, v.y, t);
    const label = i === 0 ? 'O' : getLabel(i - 1);
    ctx.font = 'bold 12px Inter, sans-serif';
    ctx.textAlign = 'center';

    // Shadow
    ctx.fillStyle = '#0d0d18';
    ctx.fillText(label, sx + 1, sy - 12 + 1);

    ctx.fillStyle = i === 0 ? '#f59e0b' : '#a78bfa';
    ctx.fillText(label, sx, sy - 12);
  });
  ctx.textAlign = 'left';
}

// ─── SHOELACE AREA ───────────────────────────────────────────────────────────
function calcArea(verts) {
  // Returns area in cm²
  let sum = 0;
  const n = verts.length;
  for (let i = 0; i < n; i++) {
    const j = (i + 1) % n;
    sum += verts[i].x * verts[j].y;
    sum -= verts[j].x * verts[i].y;
  }
  return Math.abs(sum) / 2;
}

function getAreaM2() {
  const verts = state.isClosed ? state.vertices : state.vertices;
  if (verts.length < 3) return 0;
  // For open polygon, use current vertices as approximate
  return calcArea(verts) / 10000; // cm² → m²
}

function updateAreaDisplay() {
  const area = getAreaM2();

  // Canvas toolbar values
  const areaEl  = document.getElementById('displayArea');
  const perimEl = document.getElementById('displayPerim');

  // Right panel values
  const rAreaEl  = document.getElementById('resultArea');
  const rPerimEl = document.getElementById('resultPerim');
  const rSegsEl  = document.getElementById('resultSegs');

  // Perimeter = sum of all segment lengths
  let perim = 0;
  for (const seg of state.segments) perim += seg.length;

  const areaStr  = area.toFixed(2) + ' м²';
  const perimStr = (perim / 100).toFixed(2) + ' м';

  if (areaEl)  areaEl.textContent  = areaStr;
  if (perimEl) perimEl.textContent = perimStr;
  if (rAreaEl)  rAreaEl.textContent  = areaStr;
  if (rPerimEl) rPerimEl.textContent = perimStr;
  if (rSegsEl)  rSegsEl.textContent  = state.segments.length;

  updatePriceLines();
}

// ─── DIRECTION CONTROL ───────────────────────────────────────────────────────
const DIR_MAP = {
  up:    { dx: 0,  dy: -1, icon: '↑' },
  right: { dx: 1,  dy:  0, icon: '→' },
  down:  { dx: 0,  dy:  1, icon: '↓' },
  left:  { dx: -1, dy:  0, icon: '←' },
};

function setDirection(dir) {
  state.direction = dir;
  document.querySelectorAll('.dir-btn[data-dir]').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.dir === dir);
  });
}

// ─── ADD SEGMENT ─────────────────────────────────────────────────────────────
function addSegment() {
  if (state.isClosed) { alert('Фигура уже замкнута. Нажмите «Сбросить» для нового расчёта.'); return; }

  const input  = document.getElementById('segLength');
  const length = parseFloat(input.value);
  if (!length || length <= 0) {
    input.focus(); input.style.borderColor = '#f87171';
    setTimeout(() => input.style.borderColor = '', 1200);
    return;
  }

  const { dx, dy } = DIR_MAP[state.direction];

  // Determine start point
  const start = state.vertices.length === 0
    ? { x: 0, y: 0 }
    : state.vertices[state.vertices.length - 1];

  const end = { x: start.x + dx * length, y: start.y + dy * length };

  // First vertex
  if (state.vertices.length === 0) state.vertices.push({ ...start });
  state.vertices.push(end);

  const segIndex = state.segments.length;
  state.segments.push({
    length,
    dir: state.direction,
    icon: DIR_MAP[state.direction].icon,
    label: getLabel(segIndex),
  });

  // Check auto-close: last vertex == first vertex (tolerance 1 cm)
  if (state.segments.length >= 3) {
    const first = state.vertices[0];
    const last  = state.vertices[state.vertices.length - 1];
    if (Math.abs(last.x - first.x) < 1 && Math.abs(last.y - first.y) < 1) {
      // Snap to first vertex
      state.vertices[state.vertices.length - 1] = { ...first };
      closePolygon();
    }
  }

  input.value = '';
  input.focus();
  renderSegmentsTable();
  resizeCanvas();
}

function closePolygon() {
  if (state.vertices.length < 4) { alert('Нужно минимум 3 отрезка для замыкания фигуры.'); return; }
  if (state.isClosed) return;
  state.isClosed = true;
  // Snap last vertex to first
  state.vertices[state.vertices.length - 1] = { ...state.vertices[0] };
  document.getElementById('closedBadge').classList.add('visible');
  draw();
  updateAreaDisplay();
}

function undoSegment() {
  if (state.isClosed) {
    state.isClosed = false;
    document.getElementById('closedBadge').classList.remove('visible');
  }
  if (state.segments.length === 0) return;
  state.segments.pop();
  state.vertices.pop();
  if (state.vertices.length === 1) state.vertices.pop(); // remove origin too if empty
  renderSegmentsTable();
  resizeCanvas();
}

function resetAll() {
  state.vertices    = [];
  state.segments    = [];
  state.isClosed    = false;
  state.priceLines  = [];
  document.getElementById('closedBadge').classList.remove('visible');
  renderSegmentsTable();
  renderPriceLines();
  updateAreaDisplay();  // обнуляет площадь/периметр в обеих панелях
  resizeCanvas();
}

function manualClose() {
  if (state.segments.length < 3) { alert('Нужно минимум 3 отрезка для замыкания фигуры.'); return; }
  closePolygon();
  renderSegmentsTable();
}

// ─── SEGMENTS TABLE ───────────────────────────────────────────────────────────
function renderSegmentsTable() {
  const tbody = document.getElementById('segTableBody');
  if (!tbody) return;

  if (state.segments.length === 0) {
    tbody.innerHTML = '<tr><td colspan="4" class="seg-table-empty">Отрезки не добавлены</td></tr>';
    return;
  }

  tbody.innerHTML = state.segments.map((seg, i) => `
    <tr>
      <td class="seg-label">${seg.label}</td>
      <td>${(seg.length / 100).toFixed(2)} м</td>
      <td>${seg.icon}</td>
      <td><button class="seg-delete" onclick="deleteSegment(${i})" title="Удалить">×</button></td>
    </tr>
  `).join('');
}

function deleteSegment(index) {
  // Only allow deleting the last segment (to keep geometry consistent)
  if (index !== state.segments.length - 1) {
    alert('Можно удалить только последний отрезок. Используйте «Отменить».'); return;
  }
  undoSegment();
}

// ─── PRICE LINES ─────────────────────────────────────────────────────────────
function addPriceLine() {
  state.priceLines.push({ id: state.nextPriceLineId++, itemId: state.db[0]?.id ?? 1 });
  renderPriceLines();
  updatePriceLines();
}

function removePriceLine(id) {
  state.priceLines = state.priceLines.filter(l => l.id !== id);
  renderPriceLines();
  updatePriceLines();
}

function setPriceLineItem(id, itemId) {
  const line = state.priceLines.find(l => l.id === id);
  if (line) { line.itemId = parseInt(itemId); updatePriceLines(); }
}

function renderPriceLines() {
  const container = document.getElementById('priceLines');
  if (!container) return;

  const options = state.db.map(item =>
    `<option value="${item.id}">${item.name} — ${item.price} ₽/м²</option>`
  ).join('');

  container.innerHTML = state.priceLines.map(line => `
    <div class="price-line" data-id="${line.id}">
      <select onchange="setPriceLineItem(${line.id}, this.value)">
        ${state.db.map(item => `
          <option value="${item.id}" ${item.id === line.itemId ? 'selected' : ''}>
            ${item.name} — ${item.price} ₽/м²
          </option>`).join('')}
      </select>
      <span class="line-price" id="lp-${line.id}">0 ₽</span>
      <button class="line-del" onclick="removePriceLine(${line.id})">×</button>
    </div>
  `).join('');
}

function updatePriceLines() {
  const area = getAreaM2();
  let total = 0;

  state.priceLines.forEach(line => {
    const item = state.db.find(i => i.id === line.itemId);
    const lineTotal = item ? item.price * area : 0;
    total += lineTotal;
    const el = document.getElementById(`lp-${line.id}`);
    if (el) el.textContent = formatRub(lineTotal);
  });

  const totalEl = document.getElementById('totalSum');
  if (totalEl) totalEl.textContent = formatRub(total);
}

function formatRub(num) {
  return num.toLocaleString('ru-RU', { minimumFractionDigits: 0, maximumFractionDigits: 0 }) + ' ₽';
}

// ─── NOMENCLATURE MODAL ─────────────────────────────────────────────────────
function openNomModal() {
  renderNomTable();
  document.getElementById('nomModal').classList.add('open');
}
function closeNomModal() {
  document.getElementById('nomModal').classList.remove('open');
}

function renderNomTable() {
  const tbody = document.getElementById('nomTableBody');
  tbody.innerHTML = state.db.map(item => `
    <tr data-id="${item.id}">
      <td><input type="text" value="${escHtml(item.name)}" onchange="updateNomItem(${item.id}, 'name', this.value)"></td>
      <td>
        <input type="text" value="${escHtml(item.unit)}" style="width:50px"
               onchange="updateNomItem(${item.id}, 'unit', this.value)">
      </td>
      <td>
        <input type="number" value="${item.price}" min="1" style="width:80px"
               onchange="updateNomItem(${item.id}, 'price', parseFloat(this.value))">
      </td>
      <td>
        <button class="btn btn-sm btn-danger" onclick="deleteNomItem(${item.id})">×</button>
      </td>
    </tr>
  `).join('');
}

function updateNomItem(id, field, value) {
  const item = state.db.find(i => i.id === id);
  if (item) {
    item[field] = field === 'price' ? parseFloat(value) || 0 : value;
    saveDB(state.db);
    renderPriceLines();
    updatePriceLines();
  }
}

function deleteNomItem(id) {
  state.db = state.db.filter(i => i.id !== id);
  saveDB(state.db);
  state.priceLines = state.priceLines.filter(l => l.itemId !== id);
  renderNomTable();
  renderPriceLines();
  updatePriceLines();
}

function addNomItem() {
  const nameEl  = document.getElementById('newNomName');
  const unitEl  = document.getElementById('newNomUnit');
  const priceEl = document.getElementById('newNomPrice');
  const name  = nameEl.value.trim();
  const unit  = unitEl.value.trim() || 'м²';
  const price = parseFloat(priceEl.value);
  if (!name || !price || price <= 0) { nameEl.focus(); return; }
  state.db.push({ id: nextId(state.db), name, unit, price });
  saveDB(state.db);
  nameEl.value = ''; priceEl.value = '';
  renderNomTable();
  renderPriceLines();
}

function escHtml(str) {
  return String(str).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

// ─── LEAD FORM MODAL ─────────────────────────────────────────────────────────
function openLeadModal() {
  updateLeadSummary();
  document.getElementById('leadModal').classList.add('open');
}
function closeLeadModal() {
  document.getElementById('leadModal').classList.remove('open');
}

function updateLeadSummary() {
  const area = getAreaM2();
  const el = document.getElementById('leadSummary');
  if (!el) return;
  const lines = state.priceLines.map(line => {
    const item = state.db.find(i => i.id === line.itemId);
    return item ? `${item.name}: ${item.price} ₽/м² × ${area.toFixed(2)} м²` : '';
  }).filter(Boolean);
  el.value = [
    `Площадь помещения: ${area.toFixed(2)} м²`,
    `Периметр: ${(state.segments.reduce((s,seg)=>s+seg.length,0)/100).toFixed(2)} м`,
    ...lines,
  ].join('\n');
}

function submitLead(e) {
  e.preventDefault();
  // In production: send to backend/CRM. Here we just show success.
  document.getElementById('leadFormContent').style.display = 'none';
  document.getElementById('leadSuccess').classList.add('show');
}

// ─── KEYBOARD SHORTCUTS ───────────────────────────────────────────────────────
document.addEventListener('keydown', e => {
  if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') return;
  if (e.key === 'ArrowRight') setDirection('right');
  if (e.key === 'ArrowLeft')  setDirection('left');
  if (e.key === 'ArrowUp')    setDirection('up');
  if (e.key === 'ArrowDown')  setDirection('down');
  if (e.key === 'Enter')      addSegment();
  if (e.key === 'z' && (e.ctrlKey || e.metaKey)) { e.preventDefault(); undoSegment(); }
});

// Enter to add from length input
document.getElementById('segLength')?.addEventListener('keydown', e => {
  if (e.key === 'Enter') addSegment();
});

// ─── INIT ────────────────────────────────────────────────────────────────────
window.addEventListener('resize', resizeCanvas);

// Close modals on overlay click
document.getElementById('nomModal')?.addEventListener('click', function(e) {
  if (e.target === this) closeNomModal();
});
document.getElementById('leadModal')?.addEventListener('click', function(e) {
  if (e.target === this) closeLeadModal();
});

// Initial render
setDirection('right');
renderSegmentsTable();
renderPriceLines();

// Delay canvas init to ensure layout is ready
requestAnimationFrame(() => { resizeCanvas(); });
