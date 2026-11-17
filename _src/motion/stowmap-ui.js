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

  const DRV = { mac: '#40D9FF', ssd: '#B380FF', arc: '#FFC74D', nas: '#59EBA6', fold: '#FF8CB3' };
  const badge = (D, k) => `<span class="badge"><i style="color:${DRV[k]}">${icon(D.vols[k].icon)}</i>${esc(D.vols[k].name)}</span>`;
  const tile = (D, k) => `<div class="vic" style="color:${DRV[k]}">${icon(D.vols[k].icon)}</div>`;
  const loc = (D, k, path) => `<span class="loc">${badge(D, k)}<small>${esc(path)}</small></span>`;
  // st.sel: 'dups' | 'copy' | null (then st.drive is selected). st.tools: { dups|copy: { frac, status, tone } }
  function sidebar(st, D) {
    let h = `<aside class="side"><div class="lights"><b></b><b></b><b></b></div><div class="brand"><img src="${D.icon}" alt=""><span>Stowmap</span></div>` +
      `<div class="sbox">${icon('magnifying-glass')}<span class="q">Search all drives</span><kbd>⌘F</kbd></div><div class="tools">`;
    for (const [k, name, ic, idle] of [['dups', 'Duplicates', 'copy', 'Find matching folders'], ['copy', 'Copy &amp; Verify', 'shield-check', 'Copy with checksums']]) {
      const t = (st.tools || {})[k] || { status: idle, tone: '' }, on = st.sel === k ? ' on' : '';
      const meter = t.frac != null ? `<div class="meter work"><i style="width:${f2(t.frac * 100)}%"></i></div>` : '';
      h += `<div class="vol${on}" data-id="tool-${k}"${st.pressed === 'tool-' + k ? ' style="background:rgba(255,255,255,.14)"' : ''}><div class="vic">${icon(ic)}</div><div class="vtx"><div class="vn"><span>${name}</span></div>${meter}<div class="vs ${t.tone || ''}">${t.status}</div></div></div>`;
    }
    h += `</div><div class="vols">`;
    for (const [title, keys] of D.groups) {
      h += `<div class="grp">${title}</div>`;
      for (const k of keys) {
        const v = D.vols[k], on = !st.sel && st.drive === k ? ' on' : '';
        const scanned = st.scanned && st.scanned[k] != null ? st.scanned[k] : v.scanned;
        const scanning = st.scanning === k;
        const state = scanning ? `<span class="spin" style="transform:rotate(${f2((st.spin || 0) % 360)}deg)"></span>` : scanned ? icon('check-circle', 'ok') : '';
        const col = (v.frac || 0) > 0.92 ? '#FF6666' : (v.frac || 0) > 0.82 ? '#FFBF40' : '#40D9FF';
        let meter = v.frac ? `<div class="meter"><i style="width:${Math.round(v.frac * 100)}%;background:${col}"></i></div>` : '', sub = `<div class="vs">${esc(v.sub)}</div>`;
        if (scanning) {
          const n = v.fileCount * st.scan.p, files = n >= 1e6 ? (n / 1e6).toFixed(1) + 'M' : Math.round(n / 1000) + 'K';
          meter = `<div class="meter scan"><i style="width:${f2(st.scan.p * 100)}%"></i></div>`;
          sub = `<div class="vs cy">Scanning ${Math.round(st.scan.p * 100)}% · ${files} files</div>`;
        }
        h += `<div class="vol${on}" data-id="vol-${k}"${st.pressed === 'vol-' + k ? ' style="background:rgba(255,255,255,.14)"' : ''}><div class="vic">${icon(v.icon)}</div><div class="vtx"><div class="vn"><span>${esc(v.name)}</span>${state}</div>${meter}${sub}</div></div>`;
      }
    }
    return h + `</div><div class="sfoot"><button class="quiet scanall">${icon('hard-drives')}Scan All Drives</button><div class="sfr"><button class="quiet">${icon('folder-plus')}Scan a Folder…</button>${icon('gear-six', 'gear')}</div></div></aside>`;
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
    const chips = c.items.map(it => `<span class="chip" style="opacity:${f3(it.k)};transform:translateY(${f2((1 - it.k) * -8)}px)">${esc(it.n)}<em>${it.e || gb(it.s)}</em>${icon('x', 'x')}</span>`).join('');
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

  // ---------- Copy & Verify, Duplicates (ports of the same functions in design/build.py) ----------
  const seg = (items, active, cls = '') => `<div class="seg ${cls}">` + items.map((n, i) => `<span class="${i === active ? 'on' : ''}">${n}</span>`).join('') + '</div>';
  const toolHead = (title, sub, right) => `<div class="head"><div class="ht"><div class="h1">${title}</div><div class="hs">${sub}</div></div><div class="hr">${right || ''}</div></div>`;
  const MODE = i => seg([icon('copy') + 'Copy', icon('list-checks') + 'Check a Copy'], i, 'mode');
  const pr = (st, id, css) => st.pressed === id ? css : '';
  const hash32 = i => { let x = (i + 1) * 2654435761 >>> 0; x ^= x >>> 15; x = Math.imul(x, 2246822519) >>> 0; x ^= x >>> 13; x = Math.imul(x, 3266489917) >>> 0; return (x ^ (x >>> 16)) >>> 0; };
  const fileAt = j => ({ n: `A00${3 + Math.floor(j / 14)}_C${String(j % 14 + 1).padStart(3, '0')}_1107KT.braw`, p: `11 Lakeshore Wedding/A-Cam/Card 0${3 + Math.floor(j / 14)}`, s: 3 + (hash32(j) % 92) / 10, h: hash32(j * 7 + 3).toString(16).padStart(8, '0') });

  function copySetup(st, D) {
    const C = D.copy;
    const src = C.sources.map(x => `<div class="crow"><span class="sic" style="color:#4DBFFF">${icon('folder')}</span><span class="fn"><b>${esc(x.n)}</b>${loc(D, C.from, x.p)}</span><span class="csz"><b>${gb(x.s)}</b><small>${x.c} files</small></span><span class="ib ghostx">${icon('x')}</span></div>`).join('');
    const left = `<div class="card pane"><div class="phead"><b>From</b><span>${C.sources.length} items  ·  ${C.total} GB</span><span class="grow"></span><button class="quiet sm">${icon('plus')}Add…</button></div>${src}<div class="drop">${icon('tray-arrow-down')}<span>Drop files or folders here</span></div></div>`;
    const dst = C.dests.map(d => `<div class="dest">${tile(D, d.k)}<div class="dtx"><div class="dl1"><b>${esc(D.vols[d.k].name)}</b><small>${esc(d.p)}</small></div><div class="meter two"><i style="width:${(d.used * 100).toFixed(1)}%"></i><i class="add" style="width:${Math.max(d.add * 100, 1.2).toFixed(1)}%"></i></div><div class="dl2"><span>${d.free}</span><span>${d.after}</span></div></div><span class="ib ghostx">${icon('x')}</span></div>`).join('');
    const right = `<div class="card pane"><div class="phead"><b>To</b><span>${C.dests.length} of 3 destinations</span></div><div class="dests">${dst}</div><div class="drop">${icon('plus-circle')}<span>Add Destination…</span><small>Up to three. Drop a drive or folder here.</small></div></div>`;
    const menu = (l, v) => `<div class="opt"><small>${l}</small><button class="quiet">${v}${icon('caret-up-down', 'cd')}</button></div>`;
    const sw = (l, on) => `<div class="opt"><small>${l}</small><span class="sw${on ? ' on' : ''}"><i></i></span></div>`;
    const opts = `<div class="card opts">` + menu('Checksum', 'xxHash64') + menu('Verify', 'Destination') + menu('If a file exists', 'Skip') + sw('Include hidden files', false) + sw('Write checksum list (MHL)', true) + `</div>`;
    const foot = `<div class="go"><div class="sum"><b>${C.files} files  ·  ${C.total} GB to ${C.dests.length} destinations</b><span>Needs ${C.total * C.dests.length} GB. Both destinations have room.</span></div><button class="glow xl" data-id="btn-start" style="flex:none${pr(st, 'btn-start', ';filter:brightness(.88)')}">${icon('shield-check')}Start Copy</button></div>`;
    return { head: toolHead('Copy &amp; Verify', 'Copy to as many as three places and check every file.', MODE(0)), body: `<div class="split">${left}${right}</div>` + opts + foot };
  }
  // sample speed curve (MB/s) over the whole job, x in 0..1: quick ramp, steady run, two small-file dips
  const speedAt = x => Math.max(0, 405 * (1 - Math.exp(-x * 30)) + 16 * Math.sin(x * 38) + 9 * Math.sin(x * 97 + 1) - 150 * Math.exp(-Math.pow((x - 0.3) / 0.03, 2)) - 95 * Math.exp(-Math.pow((x - 0.62) / 0.026, 2)));
  function smooth(pts) {
    let d = `M${pts[0][0].toFixed(1)} ${pts[0][1].toFixed(1)}`;
    for (let i = 0; i < pts.length - 1; i++) {
      const p0 = pts[Math.max(i - 1, 0)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[Math.min(i + 2, pts.length - 1)];
      d += `C${(p1[0] + (p2[0] - p0[0]) / 6).toFixed(1)} ${(p1[1] + (p2[1] - p0[1]) / 6).toFixed(1)} ${(p2[0] - (p3[0] - p1[0]) / 6).toFixed(1)} ${(p2[1] - (p3[1] - p1[1]) / 6).toFixed(1)} ${p2[0].toFixed(1)} ${p2[1].toFixed(1)}`;
    }
    return d;
  }
  function spark(tf, w) {
    const h = 124, pad = 7, vmax = 470, N = 64, Y = v => h - 6 - v / vmax * (h - 16), X = x => pad + x * (w - 2 * pad);
    const pts = []; const last = Math.max(tf, 0.004);
    for (let i = 0; i <= N; i++) { const x = i / N; if (x >= last) break; pts.push([X(x), Y(speedAt(x))]); }
    pts.push([X(last), Y(speedAt(last))]);
    const line = smooth(pts), [ex, ey] = pts[pts.length - 1], u = ++rid;
    const grid = [200, 400].map(v => `<line x1="0" x2="${w}" y1="${Y(v).toFixed(1)}" y2="${Y(v).toFixed(1)}" stroke="rgba(255,255,255,.06)"/>`).join('');
    return `<svg class="spark" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}"><defs><linearGradient id="spl${u}" gradientUnits="userSpaceOnUse" x1="0" x2="${w}" y1="0" y2="0"><stop stop-color="#8C5CFF"/><stop offset="1" stop-color="#40D9FF"/></linearGradient>` +
      `<linearGradient id="spf${u}" gradientUnits="userSpaceOnUse" x1="0" x2="0" y1="0" y2="${h}"><stop stop-color="#40D9FF" stop-opacity=".30"/><stop offset="1" stop-color="#8C5CFF" stop-opacity="0"/></linearGradient></defs>` +
      `${grid}<line x1="0" x2="${w}" y1="${h - 0.5}" y2="${h - 0.5}" stroke="rgba(255,255,255,.10)"/>` +
      `<path d="${line}L${ex.toFixed(1)} ${h}L${pts[0][0].toFixed(1)} ${h}Z" fill="url(#spf${u})"/><path d="${line}" fill="none" stroke="url(#spl${u})" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>` +
      `<circle cx="${ex.toFixed(1)}" cy="${ey.toFixed(1)}" r="8" fill="rgba(64,217,255,.22)"/><circle cx="${ex.toFixed(1)}" cy="${ey.toFixed(1)}" r="4" fill="#40D9FF" stroke="#12121a" stroke-width="1.5"/></svg>`;
  }
  function bigring(copied, verified, center, done) {
    const S = 260, c = 130, ro = 116, ri = 97, Lo = 2 * Math.PI * ro, Li = 2 * Math.PI * ri, u = ++rid;
    const arc = (r, w, L, f, col) => f > 0.004 ? `<circle cx="${c}" cy="${c}" r="${r}" fill="none" stroke="${col}" stroke-width="${w}" stroke-linecap="round" stroke-dasharray="${(L * Math.min(f, 1)).toFixed(1)} ${L.toFixed(1)}" transform="rotate(-90 ${c} ${c})"/>` : '';
    return `<div class="bigring"><svg width="${S}" height="${S}" viewBox="0 0 ${S} ${S}"><defs><linearGradient id="brg${u}" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#8C5CFF"/><stop offset="1" stop-color="#40D9FF"/></linearGradient></defs>` +
      `<circle cx="${c}" cy="${c}" r="${ro}" fill="none" stroke="rgba(255,255,255,.07)" stroke-width="16"/><circle cx="${c}" cy="${c}" r="${ri}" fill="none" stroke="rgba(255,255,255,.07)" stroke-width="8"/>` +
      `${arc(ro, 16, Lo, copied, done ? '#59E699' : `url(#brg${u})`)}${arc(ri, 8, Li, verified, '#59E699')}</svg><div class="center">${center}</div></div>`;
  }
  const stat = (l, v, sub) => `<div class="st"><small>${l}</small><b>${v}</b><span>${sub}</span></div>`;
  const mmss = s => Math.floor(s / 60) + ':' + String(Math.floor(s % 60)).padStart(2, '0');
  // st.copy = { phase: 'run', tf } with tf the fraction of the whole job (copy until SPLIT, then the rest of verifying)
  const SPLIT = 0.74;
  function copyRun(st, D) {
    const C = D.copy, tf = clamp(st.copy.tf), copying = tf < SPLIT;
    const cp = clamp(tf / SPLIT), vp = copying ? cp * 0.7 : lerp(0.7, 1, (tf - SPLIT) / (1 - SPLIT));
    const speed = Math.round(speedAt(tf)), files = Math.floor(C.filesN * cp), sparkW = st.L.W - 628;
    const center = `<div class="pv">${Math.round((copying ? cp : vp) * 100)}<em>%</em></div><div class="ph"${copying ? '' : ' style="color:#59E699"'}>${copying ? 'Copying' : 'Verifying'}</div>`;
    const left = C.seconds * (1 - tf);
    const stats = stat('Copied', gb(C.total * cp), `of ${C.total} GB`) + stat('Files', int(files), `of ${int(C.filesN)}`) + stat('Time left', left >= 60 ? Math.ceil(left / 60) + ' min' : Math.ceil(left) + ' s', 'with verifying') + stat('Elapsed', mmss(C.seconds * tf), 'started 2:16 PM');
    const hero = `<div class="card run">${bigring(cp, vp, center)}<div class="rside"><div class="spd"><b>${speed}</b><span>MB/s</span><span class="grow"></span><div class="key"><span><i class="kc"></i>Copied ${Math.round(cp * 100)}%</span><span><i class="kv"></i>Verified ${Math.round(vp * 100)}%</span></div></div>${spark(tf, sparkW)}<div class="stats4">${stats}</div></div></div>`;
    const lanes = C.dests.map((d, i) => { const lv = Math.min(cp, i ? Math.pow(vp, 1.3) : 1 - Math.pow(1 - vp, 1.2)); // the second lane trails, both end at 100%
      return `<div class="lane">${tile(D, d.k)}<div class="ln2"><b>${esc(D.vols[d.k].name)}</b><small>${esc(d.p)}</small></div><div class="lbars"><div class="meter copy"><i style="width:${f2(cp * 100)}%"></i></div><div class="meter ver"><i style="width:${f2(lv * 100)}%"></i></div></div><div class="lst"><b>${copying ? 'Writing ' + Math.round(speed * (i ? 0.97 : 1)) + ' MB/s' : 'Reading back'}</b><small>Verified ${int(C.filesN * lv)} of ${int(files)}</small></div></div>`; }).join('');
    // the visible list ticks a few rows a second; the counters above carry the real totals
    const tick = tf * C.ticks, j = Math.floor(tick), fr = tick - j, slide = copying ? 1 - E.out(clamp(fr / 0.3)) : 0;
    let rows = '';
    if (copying) { const f = fileAt(j); rows += `<div class="cfile now"><span class="ric" style="color:#8C5CFF">${icon('film-strip')}</span><span class="cn">${f.n}</span><div class="meter work"><i style="width:${f2(fr * 100)}%"></i></div><span class="rs">${gb(f.s)}</span><span class="hash num">${Math.round(fr * 100)}%</span><span class="spin" style="transform:rotate(${f2(tf * 9000 % 360)}deg)"></span></div>`; }
    const jj = copying ? j : Math.floor(SPLIT * C.ticks) + 1;
    for (let k = 1; k <= 9 && jj - k >= 0; k++) { const f = fileAt(jj - k);
      rows += `<div class="cfile" style="${k === 1 && slide > 0 ? `opacity:${f3(1 - slide)};` : ''}transform:translateY(${f2(-slide * 28)}px)"><span class="ric" style="color:#8C5CFF">${icon('film-strip')}</span><span class="cn">${f.n}</span><small class="fp">${f.p}</small><span class="rs">${gb(f.s)}</span><span class="hash">${f.h}</span>${icon('check-circle', 'okc')}</div>`; }
    const filesCard = `<div class="card list files"><div class="ctitle"><span>Files</span><em>${int(files)} of ${int(C.filesN)}</em></div>${rows}</div>`;
    const ctl = `<button class="quiet">${icon('pause')}Pause</button><button class="quiet red">${icon('stop')}Stop</button>`;
    return { head: toolHead('Copy &amp; Verify', `${C.sources.length} items from ${esc(D.vols[C.from].name)} to ${C.dests.map(d => esc(D.vols[d.k].name)).join(' and ')}  ·  xxHash64  ·  verifying each destination`, ctl), body: hero + `<div class="card lanes">${lanes}</div>` + filesCard };
  }
  function copyDone(st, D) {
    const C = D.copy, k = st.copy.k == null ? 1 : st.copy.k; // k: 0..1 arrival of the check
    const center = `<div style="transform:scale(${f3(0.6 + 0.4 * k)});opacity:${f3(k)}">${icon('check-fat', 'bigcheck')}</div>`;
    const btns = `<div class="btns"><button class="quiet">${icon('folder')}Show in Finder</button><button class="quiet">${icon('file-text')}Open Checksum List</button><button class="glow sm" data-id="btn-new" style="flex:none${pr(st, 'btn-new', ';filter:brightness(.88)')}">${icon('plus')}New Copy</button></div>`;
    const hero = `<div class="card run done">${bigring(1, 1, center, true)}<div class="rside"><div class="dt1">All ${int(C.filesN)} files verified</div><div class="dp">Every file was read back from ${C.dests.map(d => esc(D.vols[d.k].name)).join(' and ')}, and its checksum matches the source.</div>` +
      `<div class="stats4 three">${stat('Copied', C.total + ' GB', 'to each destination')}${stat('Time', C.time, 'copy and verify')}${stat('Average', C.avg, 'over the whole copy')}</div>${btns}</div></div>`;
    const dres = d => `<div class="lane res">${tile(D, d.k)}<div class="ln2"><b>${esc(D.vols[d.k].name)}</b><small>${esc(d.p)}  ·  ${int(C.filesN)} files, ${C.total} GB</small></div><span class="pill g">${icon('seal-check')}Verified</span></div>`;
    const cl = (n, sub) => `<div class="lane res"><div class="vic" style="color:rgba(255,255,255,.7)">${icon('file-text')}</div><div class="ln2"><b>${n}</b><small>${sub}</small></div><span class="ib">${icon('magnifying-glass')}</span></div>`;
    const left = `<div class="card pane res"><div class="ctitle">Destinations</div>${C.dests.map(dres).join('')}<div class="ctitle gap">Checksum lists</div>${cl('Footage SSD 2026-11-17 1416.mhl', 'MHL  ·  xxHash64  ·  ' + int(C.filesN) + ' entries')}${cl('Footage SSD 2026-11-17 1416.txt', 'Plain text  ·  one line per file')}</div>`;
    let rows = ''; const jj = Math.floor(SPLIT * C.ticks) + 1;
    for (let i = 1; i <= 12; i++) { const f = fileAt(jj - i); rows += `<div class="cfile narrow"><span class="ric" style="color:#8C5CFF">${icon('film-strip')}</span><span class="cn">${f.n}</span><span class="rs">${gb(f.s)}</span><span class="hash">${f.h}</span>${icon('check-circle', 'okc')}</div>`; }
    const right = `<div class="card list files"><div class="ctitle"><span>Files</span><em>${int(C.filesN)} verified</em></div>${rows}</div>`;
    return { head: toolHead('Copy &amp; Verify', `Finished at 2:30 PM  ·  ${C.sources.length} items from ${esc(D.vols[C.from].name)} to ${C.dests.length} destinations`, MODE(0)), body: hero + `<div class="split">${left}${right}</div>` };
  }
  // st.dups = { finding: 0..1 | null, found: bool, tau: seconds since the rows arrived, ver: { setIndex: 0..1 | 'done' }, side: [setIndex, locIndex] | null }
  function dupsView(st, D) {
    const U = D.dups, d = st.dups || {};
    const right = `<button class="quiet">${icon('hard-drives')}All drives${icon('caret-down', 'cd')}</button><button class="quiet">${icon('sliders-horizontal')}Filters${icon('caret-down', 'cd')}</button><button class="glow sm" data-id="btn-find" style="flex:none${pr(st, 'btn-find', ';filter:brightness(.88)')}">${icon('copy')}Find Duplicates</button>`;
    let sub = U.idle, body;
    if (d.finding != null) sub = `Comparing the saved scans of 4 drives  ·  ${Math.round(d.finding * 100)}%`;
    if (d.found) sub = U.summary;
    if (!d.found) {
      const bar = d.finding != null ? `<div class="meter scan" style="width:220px"><i style="width:${f2(d.finding * 100)}%"></i></div>` : '';
      body = `<div class="card list tree dups" style="align-items:center;justify-content:center;gap:12px;-webkit-mask-image:none;mask-image:none"><span class="gi" style="width:44px;height:44px;border-radius:13px">${icon('copy')}</span><div class="it">${d.finding != null ? 'Looking for matching folders' : 'Find folders that hold the same files'}</div><div class="ip" style="margin-top:-4px">${U.prompt}</div>${bar}</div>`.replace('<div class="card list tree dups" style="', `<div class="card list tree dups" style="opacity:${f3(d.pa == null ? 1 : d.pa)};`);
    } else {
      const sets = U.sets.map((s, i) => {
        const k = E.out(clamp(((d.tau == null ? 9 : d.tau) - i * 0.07) / 0.45));
        const ls = s.locs.map(([dk, p], li) => { const c = d.side && d.side[0] === i && d.side[1] === li, id = `side-${i}-${li}`;
          return `<div class="dloc">${badge(D, dk)}<small>${esc(p)}</small><span class="ib sm${c ? ' amber' : ''}" data-id="${id}"${pr(st, id, ' style="background:rgba(255,255,255,.18)"')}>${icon(c ? 'tray' : 'tray-arrow-down')}</span></div>`; }).join('');
        const v = (d.ver || {})[i]; let slot;
        if (v === 'done') slot = `<span class="pill g">${icon('seal-check')}Verified identical</span>`;
        else if (v != null) slot = `<div class="vprog"><div class="meter work"><i style="width:${f2(v * 100)}%"></i></div><span class="num">${Math.round(v * 100)}%</span><button class="quiet sm">Stop</button></div>`;
        else slot = `<button class="quiet" data-id="ver-${i}" style="flex:none${pr(st, 'ver-' + i, ';background:rgba(255,255,255,.2)')}">${icon('shield-check')}Verify</button>`;
        const free = s.per * (s.locs.length - 1);
        return `<div class="dset" style="opacity:${f3(k)};transform:translateY(${f2((1 - k) * 10)}px)"><div class="drow"><span class="car">${icon('caret-right')}</span><span class="sic" style="color:#4DBFFF">${icon('folder')}</span><div class="dbody"><b class="dt">${esc(s.n)}</b>${ls}</div>` +
          `<div class="dstat"><b>${gb(free)} to free</b><small>${s.files} files  ·  ${gb(s.per)} per copy</small></div><div class="dver">${slot}</div><span class="ib">${icon('prohibit')}</span></div></div>`;
      }).join('');
      body = `<div class="card list tree dups">${sets}</div>`;
    }
    return { head: toolHead('Duplicates', sub, right), body: body + collector(st) };
  }

  // state: { L:{W,H,donut}, drive, view:'map'|'scan'|'idle'|'copy'|'dups', path, hot, hk, hotRow, hotK, reveal, rowReveal, rowGone,
  //          collected, coll, scan:{p,t}, scanning, scanned, pressed, bodyAlpha, splitAlpha, pills, sel, tools, copy, dups }
  function appHTML(st, D) {
    rid = 0;
    const L = st.L, v = D.vols[st.drive];
    const ba = st.bodyAlpha == null ? 1 : st.bodyAlpha, sa = st.splitAlpha == null ? 1 : st.splitAlpha;
    const fade = a => `opacity:${f3(a)};transform:translateY(${f2((1 - a) * 8)}px)`;
    let inner, head = null;
    if (st.view === 'copy' || st.view === 'dups') {
      const o = st.view === 'dups' ? dupsView(st, D) : st.copy.phase === 'setup' ? copySetup(st, D) : st.copy.phase === 'done' ? copyDone(st, D) : copyRun(st, D);
      return `<section class="win" style="width:${L.W}px;height:${L.H}px">${sidebar(st, D)}<main class="main"><div class="bodyw" style="${fade(ba)}">${o.head}${o.body}</div></main></section>`;
    }
    if (st.view === 'map') inner = tabs(0) + crumbs(st, [v.name].concat(st.path || [])) + `<div class="split" style="${fade(sa)}">${mapBody(st, D)}</div>` + collector(st);
    else inner = `<div class="split">${st.view === 'scan' ? scanBody(st, D) : idleBody(st, D)}</div>`;
    return `<section class="win" style="width:${L.W}px;height:${L.H}px">${sidebar(st, D)}<main class="main">${header(st, D)}<div class="bodyw" style="${fade(ba)}">${inner}</div></main></section>`;
  }
  const CSS_EXTRA = `.win{border-radius:0!important;box-shadow:none!important;position:absolute;left:0;top:0}
.bodyw{flex:1;min-height:0;display:flex;flex-direction:column;gap:14px}`;
  window.Stow = { appHTML, CSS_EXTRA, E, clamp, lerp, gb, pct, int, PAL, icon, sliceMid, slices, bezier };
})();
