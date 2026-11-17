// Stowmap faux UI for the site's stills and videos.
// A JavaScript port of design/build.py (the app's interface design). Markup and class names match
// design/interface.html, and the styles are design/interface.css copied verbatim (interface.css here).
// appHTML(state) is a pure function: no timers, no randomness. Every frame is a function of the state.
(function () {
  const PAL = ['#8C5CFF', '#40D9FF', '#FF7366', '#FFC74D', '#59EBA6', '#FF8CB3', '#4DBFFF', '#B380FF', '#FFD94D', '#73F2B3'];
  const REST = 'rgba(255,255,255,.22)';
  const KICON = { folder: 'folder', video: 'film-strip', small: 'files', hidden: 'eye-slash' };
  const clamp = (x, a = 0, b = 1) => Math.max(a, Math.min(b, x));
  const lerp = (a, b, k) => a + (b - a) * k;

  function bezier(x1, y1, x2, y2) {
    const cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx, cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by;
    return function (x) {
      x = clamp(x); let t = x;
      for (let i = 0; i < 8; i++) { const f = ((ax * t + bx) * t + cx) * t - x, d = (3 * ax * t + 2 * bx) * t + cx; if (Math.abs(d) < 1e-6) break; t -= f / d; }
      t = clamp(t); return ((ay * t + by) * t + cy) * t;
    };
  }
  const E = { travel: bezier(0.45, 0, 0.1, 1), arrive: bezier(0.25, 0.8, 0.25, 1), io: bezier(0.65, 0, 0.1, 1), out: x => 1 - Math.pow(1 - clamp(x), 3) };

  const icon = (n, cls = '', extra = '') => `<svg class="i ${cls}" viewBox="0 0 256 256" aria-hidden="true" ${extra}>${window.ICONS[n] || ''}</svg>`;
  const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;');
  const gb = v => v >= 1000 ? (v / 1000).toFixed(2) + ' TB' : v >= 1 ? v.toFixed(1) + ' GB' : Math.round(v * 1000) + ' MB';
  const pct = f => f < 0.1 ? (f * 100).toFixed(1) + '%' : Math.round(f * 100) + '%';
  const int = n => Math.round(n).toLocaleString('en-US');
  const f2 = n => n.toFixed(2), f3 = n => n.toFixed(3);

  // slices drawn in the donut: top nine items in palette order, the rest merged
  function slices(items) {
    const top = items.slice(0, 9), rest = items.slice(9);
    const out = top.map((it, i) => ({ v: it.s, col: PAL[i] }));
    if (rest.length) out.push({ v: rest.reduce((a, b) => a + b.s, 0), col: REST });
    return out;
  }
  // same geometry as build.py donut(): clockwise from 12 o'clock, 1.4 degree gaps, hovered slice grows 8px
  function donut(items, o) {
    const size = o.size || 320, thick = o.thick || 54, c = size / 2, reveal = o.reveal == null ? 1 : o.reveal;
    const total = items.reduce((a, b) => a + b.v, 0), hk = o.hk || 0;
    let a = 0, out = `<svg class="donut" data-id="donut" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">`;
    items.forEach((it, idx) => {
      const span = it.v / total * 360 * reveal, g = span > 3 ? 0.7 : 0, a0 = a + g, a1 = a + span - g; a += span;
      if (span < 0.05) return;
      const hot = idx === o.hot, ro = c - 8 + (hot ? 8 * hk : 0), ri = c - 8 - thick;
      const P = (r, ang) => { const t = (ang - 90) * Math.PI / 180; return [c + r * Math.cos(t), c + r * Math.sin(t)]; };
      const [x0, y0] = P(ro, a0), [x1, y1] = P(ro, a1), [x2, y2] = P(ri, a1), [x3, y3] = P(ri, a0), large = (a1 - a0) > 180 ? 1 : 0;
      const op = o.hot == null || hot ? 1 : 1 - 0.45 * hk;
      const glow = hot && hk > 0.01 ? ` style="filter:drop-shadow(0 0 7px rgba(64,217,255,${f3(0.55 * hk)}))"` : '';
      out += `<path d="M${f2(x0)} ${f2(y0)}A${f2(ro)} ${f2(ro)} 0 ${large} 1 ${f2(x1)} ${f2(y1)}L${f2(x2)} ${f2(y2)}A${ri} ${ri} 0 ${large} 0 ${f2(x3)} ${f2(y3)}Z" fill="${it.col}" opacity="${f3(op)}"${glow}/>`;
    });
    return out + '</svg>';
  }
  function sliceMid(items, i, size = 320, thick = 54) {
    const total = items.reduce((a, b) => a + b.v, 0); let a = 0;
    for (let j = 0; j < i; j++) a += items[j].v / total * 360;
    const m = (a + items[i].v / total * 180 - 90) * Math.PI / 180, rm = size / 2 - 8 - thick / 2;
    return [size / 2 + rm * Math.cos(m), size / 2 + rm * Math.sin(m)];
  }

  function sidebar(st, D) {
    let h = `<aside class="side"><div class="lights"><b></b><b></b><b></b></div><div class="brand"><img src="${D.icon}" alt=""><span>Stowmap</span></div><div class="vols">`;
    for (const [title, keys] of D.groups) {
      h += `<div class="grp">${title}</div>`;
      for (const k of keys) {
        const v = D.vols[k], on = st.drive === k ? ' on' : '';
        const scanned = st.scanned && st.scanned[k] != null ? st.scanned[k] : v.scanned;
        const state = st.scanning === k ? `<span class="spin" style="transform:rotate(${f2((st.spin || 0) % 360)}deg)"></span>` : scanned ? icon('check-circle', 'ok') : '';
        const col = (v.frac || 0) > 0.92 ? '#FF6666' : (v.frac || 0) > 0.82 ? '#FFBF40' : '#40D9FF';
        const meter = v.frac ? `<div class="meter"><i style="width:${Math.round(v.frac * 100)}%;background:${col}"></i></div>` : '';
        h += `<div class="vol${on}" data-id="vol-${k}"${st.pressed === 'vol-' + k ? ' style="background:rgba(255,255,255,.14)"' : ''}><div class="vic">${icon(v.icon)}</div><div class="vtx"><div class="vn"><span>${esc(v.name)}</span>${state}</div>${meter}<div class="vs">${esc(v.sub)}</div></div></div>`;
      }
    }
    return h + `</div><div class="sfoot"><button class="quiet">${icon('folder-plus')}Scan a Folder…</button>${icon('gear-six', 'gear')}</div></aside>`;
  }
  function header(st, D) {
    const v = D.vols[st.drive];
    const pills = st.pills || (st.view === 'map' ? ['Scanned 2m ago', v.files] : null);
    const right = pills ? `<span class="pill g"><i></i>${pills[0]}</span><span class="pill c"><i></i>${pills[1]}</span><button class="quiet cy">${icon('eye')}Hidden</button>${icon('dots-three-circle', 'more')}<button class="quiet">${icon('arrow-clockwise')}Rescan</button>` : '';
    const col = v.frac > 0.92 ? '#FF6666' : '#40D9FF';
    return `<div class="head"><div class="ht"><div class="h1">${esc(v.name)}</div><div class="hs">${esc(v.head)}</div></div><div class="hr" style="opacity:${f3(st.pillAlpha == null ? 1 : st.pillAlpha)}">${right}</div></div><div class="meter big"><i style="width:${Math.round(v.frac * 100)}%;background:${col}"></i></div>`;
  }
  function tabs(active) {
    const t = [['Map', 'chart-donut'], ['Tree', 'tree-structure'], ['File Types', 'stack'], ['Largest Files', 'ranking']];
    return '<div class="tabs">' + t.map(([n, ic], i) => `<div class="tab${i === active ? ' on' : ''}">${icon(ic)}${n}</div>`).join('') + '</div>';
  }
  function crumbs(st, parts) {
    let h = `<div class="crumbs"><span class="ib">${icon('caret-up')}</span>`;
    parts.forEach((p, i) => { if (i) h += icon('caret-right', 'sep'); h += `<span data-id="crumb-${i}" class="${i === parts.length - 1 ? 'cur' : ''}"${st.pressed === 'crumb-' + i ? ' style="color:#fff"' : ''}>${esc(p)}</span>`; });
    return h + `<span class="grow"></span><span class="ib">${icon('folder')}</span></div>`;
  }
  const COLL_H = 54;
  function collector(st) {
    const c = st.coll; if (!c || c.show <= 0.001) return '';
    const chips = c.items.map(it => `<span class="chip" style="opacity:${f3(it.k)};transform:translateY(${f2((1 - it.k) * -8)}px)">${esc(it.n)}<em>${gb(it.s)}</em>${icon('x', 'x')}</span>`).join('');
    const pressed = st.pressed === 'btn-trash' ? ';background:rgba(255,102,102,.22)' : '';
    return `<div style="height:${f2(c.show * COLL_H)}px;margin-top:${f2(-14 * (1 - c.show))}px;opacity:${f3(clamp(c.show * 1.4))};flex:none"><div class="card coll" data-id="coll" style="height:${COLL_H}px">${icon('tray', 'tray')}<div class="ct"><small>Collector</small><b class="num">${c.count} ${c.count === 1 ? 'item' : 'items'}  ·  ${c.size.toFixed(1)} GB</b></div>` +
      `<div class="chips">${chips}</div><button class="quiet">Clear</button><button class="quiet red" data-id="btn-trash" style="flex:none${pressed}">${icon('trash')}Move to Trash</button></div></div>`;
  }
  function rows(st, items, total) {
    const first = items[0].s / total;
    return items.map((it, i) => {
      const col = i < 9 ? PAL[i] : REST, f = it.s / total, kind = it.k || 'folder', hid = !!it.h;
      const tint = kind === 'folder' && !hid ? '#4DBFFF' : kind === 'video' ? '#8C5CFF' : 'rgba(255,255,255,.55)';
      const tag = hid ? `<span class="tag">${icon('eye-slash')}</span>` : '';
      const coll = (st.collected || []).includes(it.n);
      const hot = st.hotRow === i ? (st.hotK == null ? 1 : st.hotK) : 0;
      const k = st.rowReveal ? st.rowReveal(i) : 1, gone = st.rowGone ? st.rowGone(it) : 0;
      const prs = st.pressed === 'col-' + i;
      let acts;
      if (kind === 'small' || kind === 'hidden') acts = `<span class="ib none"></span>` + (kind === 'small' ? `<span class="ib">${icon('folder')}</span>` : `<span class="ib none"></span>`);
      else acts = (coll ? `<span class="ib amber" data-id="col-${i}">${icon('tray')}</span>` : `<span class="ib" data-id="col-${i}" style="background:rgba(255,255,255,${f3((prs ? 0.18 : 0.06) * hot)});color:rgba(255,255,255,${f3(0.55 * hot)})">${icon('tray-arrow-down')}</span>`) + `<span class="ib">${icon(kind === 'folder' ? 'folder' : 'magnifying-glass')}</span>`;
      const chev = kind === 'folder' ? icon('caret-right', 'chev') : '<span class="chev"></span>';
      const sty = `opacity:${f3(k * Math.pow(1 - gone, 2.5))};transform:translateY(${f2((1 - k) * 8)}px);` + (gone > 0 ? `height:${f2(40 * (1 - gone))}px;padding-top:${f2(8 * (1 - gone))}px;padding-bottom:${f2(8 * (1 - gone))}px;margin-top:${f2(-2 * gone)}px;overflow:hidden;` : '') + (hot > 0 ? `background:rgba(255,255,255,${f3(0.08 * hot)});` : '');
      return `<div class="row${hid ? ' hid' : ''}" data-id="row-${i}" style="${sty}flex:none"><i class="dot" style="background:${col}"></i><span class="ric" style="color:${tint}">${icon(KICON[kind] || 'folder')}</span><span class="rn"><span>${esc(it.n)}</span>${tag}</span>` +
        `<div class="meter"><i style="width:${Math.max(2, Math.round(f * 100 / first * k))}%;background:${col}"></i></div><span class="rs">${gb(it.s)}</span><span class="rp">${pct(f)}</span>${acts}${chev}</div>`;
    }).join('');
  }
  function mapBody(st, D) {
    const node = D.node(st.drive, st.path || []), items = node.items, total = node.total, sl = slices(items);
    const hot = st.hot, hk = st.hk || 0;
    let center;
    if (hot != null && hk > 0.5) { const it = hot < 9 ? items[hot] : { n: 'Everything else', s: sl[9].v }; center = `<div class="cl" style="color:${sl[hot].col}">${esc(it.n)}</div><div class="cv">${gb(it.s)}</div><div class="cs">${pct(it.s / total)} of this folder</div>`; }
    else center = `<div class="cl dim">${esc(node.name)}</div><div class="cv">${gb(total)}</div><div class="cs">${items.length} ${items.length === 1 ? 'item' : 'items'}</div>`;
    const ca = st.centerAlpha == null ? 1 : st.centerAlpha;
    return `<div class="card dcard">${donut(sl, { size: st.L.donut || 320, hot, hk, reveal: st.reveal })}<div class="center" style="opacity:${f3(ca)}">${center}</div></div><div class="card list">${rows(st, items, total)}</div>`;
  }
  let rid = 0;
  function ring(frac, label, sub, sweep) {
    const r = 83, c = 95, L = 2 * Math.PI * r, gid = 'rg' + (++rid);
    const sp = sweep == null ? '' : `<circle cx="${c}" cy="${c}" r="${r + 13}" fill="none" stroke="#40D9FF" stroke-width="3" stroke-linecap="round" stroke-dasharray="${(2 * Math.PI * (r + 13) * 0.18).toFixed(1)} 999" transform="rotate(${f2(sweep)} ${c} ${c})"/>`;
    return `<div class="ringw"><svg width="216" height="216" viewBox="-13 -13 216 216"><defs><linearGradient id="${gid}" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#8C5CFF"/><stop offset="1" stop-color="#40D9FF"/></linearGradient></defs>` +
      `<circle cx="${c}" cy="${c}" r="${r}" fill="none" stroke="rgba(255,255,255,.08)" stroke-width="13"/>` +
      (frac > 0.004 ? `<circle cx="${c}" cy="${c}" r="${r}" fill="none" stroke="url(#${gid})" stroke-width="13" stroke-linecap="round" stroke-dasharray="${(L * frac).toFixed(1)} ${L.toFixed(1)}" transform="rotate(-90 ${c} ${c})"/>` : '') +
      `${sp}</svg><div class="center"><div class="cv num">${label}</div><div class="cs">${sub}</div></div></div>`;
  }
  const facts = (title, list) => `<div class="ctitle">${title}</div>` + list.map(([k, v]) => `<div class="fact"><span>${k}</span><b>${v}</b></div>`).join('');
  function scanBody(st, D) {
    const v = D.vols[st.drive], s = st.scan, paths = v.paths, n = paths.length, off = Math.floor(s.p * v.ticks);
    const el = Math.floor(s.p * v.elapsed), mm = Math.floor(el / 60), ss = String(el % 60).padStart(2, '0');
    const left = `<div class="card hero">${ring(s.p, gb(v.used * s.p), 'mapped', 205 + s.t * 300)}<div class="it">Mapping ${esc(v.name)}</div><div class="ip">You can keep working. Other drives can scan at the same time.</div><button class="quiet">Cancel</button></div>`;
    let tick = ''; for (let i = 0; i < 6; i++) tick += `<div class="tk" style="opacity:${(1 - i * 0.15).toFixed(2)}">${esc(paths[(off + n * 100 - i) % n])}</div>`;
    const right = `<div class="card list plain">` + facts('This scan', [['Mapped so far', gb(v.used * s.p)], ['Files', int(v.fileCount * s.p)], ['Progress', Math.round(s.p * 100) + '%'], ['Elapsed', mm + ':' + ss], ['Folders without access', '0']]) + `<div class="ctitle gap">Reading now</div>${tick}</div>`;
    return left + right;
  }
  function idleBody(st, D) {
    const v = D.vols[st.drive], pr = st.pressed === 'btn-scan' ? ';filter:brightness(.88)' : '';
    const left = `<div class="card hero">${ring(v.frac, Math.round(v.frac * 100) + '%', 'used')}<div class="it">See what's filling ${esc(v.name)}</div><div class="ip">Stowmap reads every folder, hidden ones included, and draws the result as a map you can click through.</div><button class="glow" data-id="btn-scan" style="flex:none${pr}">${icon('magnifying-glass')}Scan ${esc(v.name)}</button></div>`;
    const gets = [['chart-donut', 'Map', 'The biggest folders as slices. Click one to go inside.'], ['tree-structure', 'Tree', 'Every folder as an outline, with search.'], ['stack', 'File Types', 'Space by kind and by extension.'], ['ranking', 'Largest Files', 'The 250 biggest files on the drive.']];
    const right = `<div class="card list plain">` + facts('This drive', v.facts) + `<div class="ctitle gap">What you get</div>` + gets.map(([ic, t, d]) => `<div class="get"><span class="gi">${icon(ic)}</span><span><b>${t}</b><small>${d}</small></span></div>`).join('') + `</div>`;
    return left + right;
  }

  // state: { L:{W,H,donut}, drive, view:'map'|'scan'|'idle', path, hot, hk, hotRow, hotK, reveal, rowReveal, rowGone,
  //          collected, coll, scan:{p,t}, scanning, scanned, pressed, bodyAlpha, splitAlpha, pills }
  function appHTML(st, D) {
    rid = 0;
    const L = st.L, v = D.vols[st.drive];
    const ba = st.bodyAlpha == null ? 1 : st.bodyAlpha, sa = st.splitAlpha == null ? 1 : st.splitAlpha;
    const fade = a => `opacity:${f3(a)};transform:translateY(${f2((1 - a) * 8)}px)`;
    let inner;
    if (st.view === 'map') inner = tabs(0) + crumbs(st, [v.name].concat(st.path || [])) + `<div class="split" style="${fade(sa)}">${mapBody(st, D)}</div>` + collector(st);
    else inner = `<div class="split">${st.view === 'scan' ? scanBody(st, D) : idleBody(st, D)}</div>`;
    return `<section class="win" style="width:${L.W}px;height:${L.H}px">${sidebar(st, D)}<main class="main">${header(st, D)}<div class="bodyw" style="${fade(ba)}">${inner}</div></main></section>`;
  }
  const CSS_EXTRA = `.win{border-radius:0!important;box-shadow:none!important;position:absolute;left:0;top:0}
.bodyw{flex:1;min-height:0;display:flex;flex-direction:column;gap:14px}`;
  window.Stow = { appHTML, CSS_EXTRA, E, clamp, lerp, gb, pct, int, PAL, icon, sliceMid, slices, bezier };
})();
