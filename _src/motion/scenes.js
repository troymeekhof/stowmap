// Scenes for the Stowmap launch set. Each scene returns frame(t): a pure function of time.
// The window is the app's interface design (stowmap-ui.js). Scenes only choose state, camera and cursor.
(function () {
  const { E, clamp, lerp } = Stow;
  let C, D, els;
  const cache = {};
  const seg = (t, a, d) => clamp((t - a) / d);

  const tf = w => `translate(${w.x}px,${w.y}px) scale(${w.s})`;
  function measure(sc, key, st) {
    if (cache.cur !== key) { els.meas.innerHTML = Stow.appHTML(Object.assign({ L: sc.L }, st), D); els.meas.style.transform = tf(sc.win); cache.cur = key; }
    return els.meas;
  }
  function pt(sc, key, st, id, ax = 0.5, ay = 0.5) {
    const ck = key + '|' + id + '|' + ax + '|' + ay; if (cache[ck]) return cache[ck];
    const el = measure(sc, key, st).querySelector(`[data-id="${id}"]`);
    if (!el) throw new Error('no target ' + id + ' in ' + key);
    const r = el.getBoundingClientRect(), s = els.stage.getBoundingClientRect();
    return cache[ck] = [r.left - s.left + r.width * ax, r.top - s.top + r.height * ay];
  }
  function slicePt(sc, key, st, i) {
    const ck = key + '|slice' + i; if (cache[ck]) return cache[ck];
    const o = pt(sc, key, st, 'donut', 0, 0), size = sc.L.donut || 320;
    const [lx, ly] = Stow.sliceMid(Stow.slices(D.node(st.drive, st.path || []).items), i, size);
    return cache[ck] = [o[0] + lx * sc.win.s, o[1] + ly * sc.win.s];
  }
  const local = (sc, x, y) => [sc.win.x + x * sc.win.s, sc.win.y + y * sc.win.s];
  function cursor(t, start, kfs) {
    let prev = start;
    for (const k of kfs) {
      if (t < k.t - k.d) return prev;
      if (t < k.t) { const e = (k.e || E.travel)((t - (k.t - k.d)) / k.d); return [lerp(prev[0], k.p[0], e), lerp(prev[1], k.p[1], e)]; }
      prev = k.p;
    }
    return prev;
  }
  // view track: [{at, st, kind: 'body' | 'split', sweep}] — the first entry is the opening frame
  function view(t, views) {
    let i = 0; for (let j = 0; j < views.length; j++) if (t >= views[j].at) i = j;
    const cur = views[i], next = views[i + 1], tau = t - cur.at, first = i === 0;
    let a = first ? 1 : E.out(clamp(tau / 0.26));
    if (next) a = Math.min(a, clamp((next.at - t) / 0.1));
    const sweep = cur.sweep == null ? 0.9 : cur.sweep;
    const st = Object.assign({}, cur.st, { i, tau });
    const outKind = next && t > next.at - 0.1 ? (next.kind || 'body') : (cur.kind || 'body');
    if (outKind === 'split') st.splitAlpha = a; else st.bodyAlpha = a;
    if (!first && cur.st.view === 'map') {
      st.reveal = sweep === 0 ? 1 : E.arrive(clamp(tau / sweep));
      st.centerAlpha = E.out(clamp((tau - 0.05) / 0.3));
      st.rowReveal = idx => E.out(clamp((tau - 0.06 - idx * 0.045) / 0.4));
    }
    return st;
  }
  function hover(t, hs) {
    for (const h of hs) if (t >= h.a - 0.02 && t <= h.b + 0.18) { const k = Math.min(E.out(clamp((t - h.a) / 0.16)), 1 - E.out(clamp((t - h.b) / 0.16))); return h.row ? { hotRow: h.i, hotK: k } : { hot: h.i, hk: k, hotRow: h.i, hotK: k }; }
    return {};
  }
  const press = (t, ps) => { for (const p of ps) if (t >= p.at && t < p.at + 0.17) return p.id; return null; };
  const pressK = (t, ps) => { for (const p of ps) if (t >= p.at - 0.05 && t < p.at + 0.22) return 1 - 0.14 * Math.sin(Math.PI * clamp((t - p.at + 0.05) / 0.27)); return 1; };
  // collector: adds = [{at, n, s}], leaves at exitAt
  function coll(t, adds, exitAt) {
    if (t < adds[0].at) return null;
    let count = 0, size = 0; const items = [];
    for (const a of adds) if (t >= a.at) { count++; size += a.s * E.out(clamp((t - a.at) / 0.32)); items.push({ n: a.n, s: a.s, e: a.e, k: E.arrive(clamp((t - a.at - 0.05) / 0.4)) }); }
    const show = Math.min(E.arrive(clamp((t - adds[0].at) / 0.5)), exitAt == null ? 1 : 1 - E.io(clamp((t - exitAt) / 0.45)));
    return { count, size, items, show };
  }
  function scanState(base, t, s0, s1) {
    const p = clamp((t - s0) / (s1 - s0)), pe = p * p * (3 - 2 * p) * 0.3 + p * 0.7;
    return Object.assign({}, base, { view: 'scan', scan: { p: pe, t: t - s0 }, scanning: base.drive, spin: (t - s0) * 420, scanned: { [base.drive]: false } });
  }

  const S = {};

  // ---------------------------------------------------------------- scan
  // Camera: left 651 px of the 1200x780 window (the whole sidebar + the left card).
  S.scan = function () {
    const sc = { w: 1000, h: 1198, dur: 9.5, win: { x: 0, y: 0, s: 1000 / 651 }, L: { W: 1200, H: 780 } };
    const M = { drive: 'mac', view: 'map', path: ['Users', 'alex'] };
    const I = { drive: 'arc', view: 'idle' };
    const A = { drive: 'arc', view: 'map', path: [], pills: ['Scanned just now', '412K files'], scanned: { arc: true } };
    sc.frame = function (t) {
      const P0 = local(sc, 318, 706);
      const kfs = [
        { t: 0.95, d: 0.7, p: pt(sc, 'M', M, 'vol-arc', 0.84, 0.62) },
        { t: 2.3, d: 0.8, p: pt(sc, 'I', I, 'btn-scan', 0.84, 0.72) },
        { t: 3.5, d: 0.75, p: P0 },
        { t: 7.9, d: 0.85, p: pt(sc, 'M', M, 'vol-mac', 0.84, 0.62) },
        { t: 8.95, d: 0.75, p: P0 }
      ];
      const presses = [{ id: 'vol-arc', at: 1.0 }, { id: 'btn-scan', at: 2.4 }, { id: 'vol-mac', at: 8.0 }];
      const s0 = 2.62, s1 = 5.2;
      const st = view(t, [{ at: 0, st: M }, { at: 1.12, st: I }, { at: 2.52, st: scanState(I, t, s0, s1) }, { at: 5.32, st: A, sweep: 1.0 }, { at: 8.12, st: Object.assign({}, M, { scanned: { arc: true } }), sweep: 0.6 }]);
      st.pressed = press(t, presses);
      const c = cursor(t, P0, kfs);
      return { st, cursor: { x: c[0], y: c[1], k: pressK(t, presses), a: 1 } };
    };
    return sc;
  };

  // --------------------------------------------------------------- drill
  // Camera: the main pane of a 1200x780 window (sidebar off the left edge).
  const PANE = () => ({ w: 1200, h: 994, win: { x: -258 * 1.2739, y: 0, s: 1.2739 }, L: { W: 1200, H: 780 } });
  S.drill = function () {
    const sc = Object.assign(PANE(), { dur: 9 });
    const R = { drive: 'mac', view: 'map', path: [] }, U = { drive: 'mac', view: 'map', path: ['Users'] }, A = { drive: 'mac', view: 'map', path: ['Users', 'alex'] };
    sc.frame = function (t) {
      const P0 = local(sc, 1010, 213);
      const kfs = [
        { t: 0.9, d: 0.75, p: slicePt(sc, 'R', R, 0) },
        { t: 4.3, d: 0.7, p: slicePt(sc, 'A', A, 1) },
        { t: 5.9, d: 0.6, p: slicePt(sc, 'A', A, 2) },
        { t: 7.2, d: 0.85, p: pt(sc, 'A', A, 'crumb-0', 0.94, 0.85) },
        { t: 8.4, d: 0.8, p: P0 }
      ];
      const presses = [{ id: 'slice', at: 1.85 }, { id: 'slice', at: 2.9 }, { id: 'crumb-0', at: 7.3 }];
      const st = view(t, [{ at: 0, st: R }, { at: 1.97, st: U, kind: 'split', sweep: 0.6 }, { at: 3.02, st: A, kind: 'split', sweep: 0.9 }, { at: 7.42, st: R, kind: 'split', sweep: 0.7 }]);
      Object.assign(st, st.i === 0 ? hover(t, [{ i: 0, a: 0.85, b: 2.2 }]) : st.i === 1 ? hover(t, [{ i: 0, a: 2.15, b: 3.2 }]) : st.i === 2 ? hover(t, [{ i: 1, a: 4.25, b: 5.45 }, { i: 2, a: 5.75, b: 6.6 }]) : {});
      st.pressed = press(t, presses);
      const c = cursor(t, P0, kfs);
      return { st, cursor: { x: c[0], y: c[1], k: pressK(t, presses), a: 1 } };
    };
    return sc;
  };

  // ------------------------------------------------------------- collect
  const PICKS = [[6, '.Trash', 12.7], [8, '.cache', 4.1], [9, '.docker', 2.4]];
  S.collect = function () {
    const sc = Object.assign(PANE(), { dur: 8.5 });
    const A = { drive: 'mac', view: 'map', path: ['Users', 'alex'] };
    const Ac = Object.assign({}, A, { coll: { count: 3, size: 19.2, items: [], show: 1 } });
    sc.frame = function (t) {
      const P0 = local(sc, 1010, 213);
      const kfs = [
        { t: 0.95, d: 0.75, p: pt(sc, 'A', A, 'col-6', 0.62, 0.66) },
        { t: 1.75, d: 0.45, p: pt(sc, 'A', A, 'col-8', 0.62, 0.66) },
        { t: 2.45, d: 0.45, p: pt(sc, 'A', A, 'col-9', 0.62, 0.66) },
        { t: 4.0, d: 0.8, p: pt(sc, 'Ac', Ac, 'btn-trash', 0.84, 0.72) },
        { t: 5.9, d: 0.85, p: P0 }
      ];
      const presses = [{ id: 'col-6', at: 1.0 }, { id: 'col-8', at: 1.8 }, { id: 'col-9', at: 2.5 }, { id: 'btn-trash', at: 4.15 }];
      const st = Object.assign({}, A);
      st.collected = PICKS.filter((p, i) => t >= presses[i].at + 0.1).map(p => p[1]);
      st.coll = coll(t, PICKS.map((p, i) => ({ at: presses[i].at + 0.1, n: p[1], s: p[2] })), 4.5);
      st.rowGone = it => { const j = PICKS.findIndex(p => p[1] === it.n); return j < 0 ? 0 : E.io(seg(t, 4.27 + j * 0.06, 0.42)); };
      Object.assign(st, hover(t, [{ i: 6, a: 0.75, b: 1.45, row: 1 }, { i: 8, a: 1.6, b: 2.15, row: 1 }, { i: 9, a: 2.3, b: 3.3, row: 1 }]));
      if (t > 7.55) { st.splitAlpha = t < 7.85 ? 1 - seg(t, 7.55, 0.25) : E.out(seg(t, 7.9, 0.4)); if (t >= 7.85) { st.rowGone = null; st.collected = []; } } // seam: cut under cover
      st.pressed = press(t, presses);
      const c = cursor(t, P0, kfs);
      return { st, cursor: { x: c[0], y: c[1], k: pressK(t, presses), a: 1 } };
    };
    return sc;
  };

  // ---------------------------------------------------------------- copy
  // Copy & Verify: setup -> Start Copy -> ring fills while the speed graph draws -> Verifying -> all verified -> New Copy.
  const CBASE = { drive: 'mac', sel: 'copy', view: 'copy' };
  const CSET = Object.assign({}, CBASE, { copy: { phase: 'setup' } });
  const crun = tf => Object.assign({}, CBASE, { copy: { phase: 'run', tf } });
  const cdone = k => Object.assign({}, CBASE, { copy: { phase: 'done', k } });
  S.copy = function () {
    const sc = Object.assign(PANE(), { dur: 12.6 });
    sc.frame = function (t) {
      const P0 = local(sc, 900, 742), D1 = cdone(1);
      const kfs = [
        { t: 1.5, d: 0.8, p: pt(sc, 'CSET', CSET, 'btn-start', 0.85, 0.62) },
        { t: 10.5, d: 0.01, p: local(sc, 1010, 470) },
        { t: 11.55, d: 0.75, p: pt(sc, 'CDONE', D1, 'btn-new', 0.85, 0.62) },
        { t: 12.5, d: 0.6, p: P0 }
      ];
      const presses = [{ id: 'btn-start', at: 1.6 }, { id: 'btn-new', at: 11.7 }];
      const st = view(t, [{ at: 0, st: CSET }, { at: 1.72, st: crun(seg(t, 1.9, 7.5)) }, { at: 9.55, st: cdone(E.arrive(seg(t, 9.65, 0.6))) }, { at: 11.82, st: CSET }]);
      st.pressed = press(t, presses);
      const c = cursor(t, P0, kfs);
      const a = t < 10.4 ? 1 - seg(t, 2.3, 0.3) : seg(t, 10.55, 0.3);
      return { st, cursor: { x: c[0], y: c[1], k: pressK(t, presses), a } };
    };
    return sc;
  };

  // ---------------------------------------------------------------- dups
  // Duplicates: Find Duplicates -> matching folders arrive -> one set verifies -> one side goes to the collector.
  S.dups = function () {
    const sc = Object.assign(PANE(), { dur: 9 });
    const B = { drive: 'mac', sel: 'dups', view: 'dups' };
    const I = Object.assign({}, B, { dups: {} }), F = Object.assign({}, B, { dups: { found: true } });
    sc.frame = function (t) {
      const P0 = local(sc, 1000, 128);
      const kfs = [
        { t: 0.85, d: 0.6, p: pt(sc, 'DI', I, 'btn-find', 0.85, 0.62) },
        { t: 3.5, d: 0.85, p: pt(sc, 'DF', F, 'ver-0', 0.85, 0.62) },
        { t: 6.9, d: 0.8, p: pt(sc, 'DF', F, 'side-0-0', 0.62, 0.66) },
        { t: 8.5, d: 0.75, p: P0 }
      ];
      const presses = [{ id: 'btn-find', at: 0.9 }, { id: 'ver-0', at: 3.6 }, { id: 'side-0-0', at: 7.0 }];
      const tt = t >= 8.72 ? -1 : t; // after the cut under cover the pane is back at its opening state
      const d = {};
      if (tt >= 1.02 && tt < 2.1) { d.finding = E.io(seg(tt, 1.02, 0.95)); d.pa = 1 - seg(tt, 1.95, 0.15); }
      if (tt >= 2.1) { d.found = true; d.tau = tt - 2.1; d.ver = {}; if (tt >= 3.72) d.ver[0] = tt < 5.9 ? seg(tt, 3.72, 2.1) : 'done'; if (tt >= 7.1) d.side = [0, 0]; }
      const st = Object.assign({}, B, { dups: d });
      if (tt >= 7.1) st.coll = coll(tt, [{ at: 7.1, n: '11 Lakeshore Wedding', s: 212.4, e: 'on Footage SSD  ·  212.4 GB' }], null);
      if (t > 8.45) st.bodyAlpha = t < 8.72 ? 1 - seg(t, 8.45, 0.25) : E.out(seg(t, 8.74, 0.26));
      st.pressed = press(t, presses);
      const c = cursor(t, P0, kfs);
      return { st, cursor: { x: c[0], y: c[1], k: pressK(t, presses), a: 1 } };
    };
    return sc;
  };

  // ---------------------------------------------------------------- hero
  S.hero = function () {
    const sc = { w: 1920, h: 1080, dur: 22, win: { x: 0, y: 0, s: 1920 / 1386 }, L: { W: 1386, H: 780 } };
    const base = { drive: 'mac', view: 'map', pills: ['Scanned just now', '1.4M files'] };
    const R = Object.assign({}, base, { path: [] }), U = Object.assign({}, base, { path: ['Users'] }), A = Object.assign({}, base, { path: ['Users', 'alex'] });
    const Ac = Object.assign({}, A, { coll: { count: 3, size: 19.2, items: [], show: 1 } });
    sc.frame = function (t) {
      const out = { over: '' };
      if (t < 2.3) {
        const ex = 1 - E.out(seg(t, 1.8, 0.4));
        const lines = C.copy.hook.map((l, i) => { const k = E.arrive(seg(t, 0.25 + i * 0.13, 0.8)); return `<div class="tl"><span style="transform:translateY(${((1 - k) * 105).toFixed(2)}%)">${l}</span></div>`; }).join('');
        out.over += `<div class="title" style="font-size:124px;opacity:${ex.toFixed(3)};transform:translateY(${((1 - ex) * -24).toFixed(2)}px)">${lines}</div>`;
      }
      // end card: the window (Copy & Verify, all verified) steps back to the right, the name arrives on the left
      const END = 19.7, kend = E.io(seg(t, END, 0.9));
      if (t >= END + 0.25) {
        const ex = 1 - seg(t, 21.55, 0.36), k = i => E.arrive(seg(t, END + 0.35 + i * 0.11, 0.8));
        const row = (i, html) => `<div style="opacity:${(Math.min(1, k(i) * 1.5) * ex).toFixed(3)};transform:translateY(${((1 - k(i)) * 30).toFixed(2)}px)">${html}</div>`;
        out.over += `<div class="endc">` + row(0, `<img src="${C.brand.icon}" width="150" height="150" alt="">`) + row(1, `<div class="e-n">${C.copy.end.name}</div>`) + row(2, `<div class="e-l">${C.copy.end.line}</div>`) + `</div>`;
      }
      if (t >= 2.2) {
        const kin = E.arrive(seg(t, 2.25, 1.0)), kout = E.io(seg(t, 21.4, 0.6));
        out.win = { x: 800 * kend, y: (1 - kin) * sc.h + 236 * kend + kout * sc.h, s: lerp(sc.win.s, 1.15, kend) };
        out.framed = t >= END;
        const s0 = 3.0, s1 = 5.0;
        const tf = seg(t, 16.55, 2.35), run = crun(tf);
        const st = view(t, [{ at: 0, st: scanState({ drive: 'mac' }, t, s0, s1) }, { at: 5.12, st: R, sweep: 1.0 }, { at: 7.32, st: U, kind: 'split', sweep: 0.6 }, { at: 8.37, st: A, kind: 'split', sweep: 0.85 },
          { at: 15.32, st: CSET }, { at: 16.42, st: run }, { at: 19.0, st: cdone(E.arrive(seg(t, 19.08, 0.5))) }]);
        if (st.i === 5) st.tools = { copy: tf < 0.74 ? { frac: tf / 0.74, status: `Copying ${Math.round(tf / 0.74 * 100)}%`, tone: 'cy' } : { frac: (tf - 0.74) / 0.26, status: `Verifying ${Math.round((tf - 0.74) / 0.26 * 100)}%`, tone: 'cy' } };
        if (st.i === 6) st.tools = { copy: { status: '1,204 files verified', tone: 'g' } };
        Object.assign(st, st.i === 1 ? hover(t, [{ i: 0, a: 6.45, b: 7.6 }]) : st.i === 2 ? hover(t, [{ i: 0, a: 7.9, b: 8.6 }]) : st.i === 3 ? hover(t, [{ i: 1, a: 9.5, b: 10.35 }, { i: 6, a: 10.85, b: 11.5, row: 1 }, { i: 8, a: 11.65, b: 12.2, row: 1 }, { i: 9, a: 12.35, b: 13.3, row: 1 }]) : {});
        const start = [1560, 1200];
        const kfs = [
          { t: 6.5, d: 0.95, p: slicePt(sc, 'R', R, 0), e: Stow.bezier(0.1, 0.8, 0.3, 0.95) },
          { t: 9.5, d: 0.7, p: slicePt(sc, 'A', A, 1) },
          { t: 11.0, d: 0.7, p: pt(sc, 'A', A, 'col-6', 0.62, 0.66) },
          { t: 11.8, d: 0.45, p: pt(sc, 'A', A, 'col-8', 0.62, 0.66) },
          { t: 12.5, d: 0.45, p: pt(sc, 'A', A, 'col-9', 0.62, 0.66) },
          { t: 13.75, d: 0.8, p: pt(sc, 'Ac', Ac, 'btn-trash', 0.84, 0.72) },
          { t: 15.15, d: 0.85, p: pt(sc, 'A', A, 'tool-copy', 0.84, 0.62) },
          { t: 16.25, d: 0.8, p: pt(sc, 'CSET', CSET, 'btn-start', 0.85, 0.62) }
        ];
        const presses = [{ id: 'slice', at: 7.2 }, { id: 'slice', at: 8.25 }, { id: 'col-6', at: 11.05 }, { id: 'col-8', at: 11.85 }, { id: 'col-9', at: 12.55 }, { id: 'btn-trash', at: 13.9 }, { id: 'tool-copy', at: 15.2 }, { id: 'btn-start', at: 16.3 }];
        if (st.i === 3) {
          st.collected = PICKS.filter((p, i) => t >= presses[2 + i].at + 0.1).map(p => p[1]);
          st.coll = coll(t, PICKS.map((p, i) => ({ at: presses[2 + i].at + 0.1, n: p[1], s: p[2] })), 14.25);
          st.rowGone = it => { const j = PICKS.findIndex(p => p[1] === it.n); return j < 0 ? 0 : E.io(seg(t, 14.02 + j * 0.06, 0.42)); };
        }
        st.pressed = press(t, presses);
        out.st = st;
        if (t >= 5.5 && t < 17.4) { const c = cursor(t, start, kfs); out.cursor = { x: c[0], y: c[1], k: pressK(t, presses), a: 1 - seg(t, 16.9, 0.3) }; }
      }
      return out;
    };
    return sc;
  };

  // --------------------------------------------------------------- stills
  S['still-hidden'] = function () { // root map, the "Hidden space" slice under the pointer
    const sc = Object.assign(PANE(), { dur: 1 });
    sc.frame = () => ({ st: { drive: 'mac', view: 'map', path: [], hot: 1, hk: 1, hotRow: 1, hotK: 1 } }); return sc;
  };
  S.og = function () {
    const sc = { w: 1200, h: 630, dur: 1, win: { x: 566, y: 60, s: 0.95 }, L: { W: 1200, H: 780 }, og: true };
    const st = { drive: 'mac', view: 'map', path: ['Users', 'alex'], hot: 1, hk: 1, hotRow: 1, hotK: 1 };
    sc.frame = () => ({ st, over: `<div class="ogc"><img src="${C.brand.icon}" width="92" height="92" alt=""><div class="og-n">Stowmap</div><div class="og-t">${C.copy.og.title.join('<br>')}</div><div class="og-s">${C.copy.og.sub}</div></div>` });
    return sc;
  };

  window.Scenes = {
    init(campaign, elements) {
      C = campaign; els = elements;
      D = { vols: C.data.vols, groups: C.data.groups, copy: C.data.copy, dups: C.data.dups, icon: '../../assets/img/icon-128.png',
        node(drive, path) { const n = C.data.nodes[drive + ':' + path.join('/')]; const items = n.items.map(x => Object.assign({}, x)); return { name: n.name, items, total: items.reduce((a, b) => a + b.s, 0) }; } };
      return D;
    },
    make(name) { return S[name](); }
  };
})();
