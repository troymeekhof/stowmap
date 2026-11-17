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
    for (const a of adds) if (t >= a.at) { count++; size += a.s * E.out(clamp((t - a.at) / 0.32)); items.push({ n: a.n, s: a.s, k: E.arrive(clamp((t - a.at - 0.05) / 0.4)) }); }
    const show = Math.min(E.arrive(clamp((t - adds[0].at) / 0.5)), exitAt == null ? 1 : 1 - E.io(clamp((t - exitAt) / 0.45)));
    return { count, size, items, show };
  }
  function scanState(base, t, s0, s1) {
    const p = clamp((t - s0) / (s1 - s0)), pe = p * p * (3 - 2 * p) * 0.3 + p * 0.7;
    return Object.assign({}, base, { view: 'scan', scan: { p: pe, t: t - s0 }, scanning: base.drive, spin: (t - s0) * 420, scanned: { [base.drive]: false } });
  }

  const S = {};

  // ---------------------------------------------------------------- scan
  // Camera: left 667 px of a 1200x556 window (sidebar + the left card).
  S.scan = function () {
    const sc = { w: 1200, h: 1000, dur: 9.5, win: { x: 0, y: 0, s: 1.8 }, L: { W: 1200, H: 556, donut: 292 } };
    const M = { drive: 'mac', view: 'map', path: ['Users', 'alex'] };
    const I = { drive: 'arc', view: 'idle' };
    const A = { drive: 'arc', view: 'map', path: [], pills: ['Scanned just now', '412K files'], scanned: { arc: true } };
    sc.frame = function (t) {
      const P0 = local(sc, 318, 506);
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

  // ---------------------------------------------------------------- hero
  S.hero = function () {
    const sc = { w: 1920, h: 1080, dur: 18, win: { x: 0, y: 0, s: 1920 / 1386 }, L: { W: 1386, H: 780 } };
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
      if (t >= 15.6) {
        const ex = 1 - seg(t, 17.6, 0.36), k = i => E.arrive(seg(t, 15.7 + i * 0.11, 0.8));
        const row = (i, html) => `<div style="opacity:${(Math.min(1, k(i) * 1.5) * ex).toFixed(3)};transform:translateY(${((1 - k(i)) * 30).toFixed(2)}px)">${html}</div>`;
        out.over += `<div class="end">` + row(0, `<img src="${C.brand.icon}" width="200" height="200" alt="">`) + row(1, `<div class="e-n">${C.copy.end.name}</div>`) + row(2, `<div class="e-l">${C.copy.end.line}</div>`) + `</div>`;
      }
      if (t >= 2.2 && t < 15.95) {
        const kin = E.arrive(seg(t, 2.25, 1.0)), kout = E.io(seg(t, 15.25, 0.65));
        out.win = { x: 0, y: (1 - kin) * sc.h + kout * sc.h, s: sc.win.s };
        const s0 = 3.0, s1 = 5.0;
        const st = view(t, [{ at: 0, st: scanState({ drive: 'mac' }, t, s0, s1) }, { at: 5.12, st: R, sweep: 1.0 }, { at: 7.32, st: U, kind: 'split', sweep: 0.6 }, { at: 8.37, st: A, kind: 'split', sweep: 0.85 }]);
        Object.assign(st, st.i === 1 ? hover(t, [{ i: 0, a: 6.45, b: 7.6 }]) : st.i === 2 ? hover(t, [{ i: 0, a: 7.9, b: 8.6 }]) : st.i === 3 ? hover(t, [{ i: 1, a: 9.5, b: 10.35 }, { i: 6, a: 10.85, b: 11.5, row: 1 }, { i: 8, a: 11.65, b: 12.2, row: 1 }, { i: 9, a: 12.35, b: 13.3, row: 1 }]) : {});
        const start = [1560, 1200];
        const kfs = [
          { t: 6.5, d: 0.95, p: slicePt(sc, 'R', R, 0), e: Stow.bezier(0.1, 0.8, 0.3, 0.95) },
          { t: 9.5, d: 0.7, p: slicePt(sc, 'A', A, 1) },
          { t: 11.0, d: 0.7, p: pt(sc, 'A', A, 'col-6', 0.62, 0.66) },
          { t: 11.8, d: 0.45, p: pt(sc, 'A', A, 'col-8', 0.62, 0.66) },
          { t: 12.5, d: 0.45, p: pt(sc, 'A', A, 'col-9', 0.62, 0.66) },
          { t: 13.75, d: 0.8, p: pt(sc, 'Ac', Ac, 'btn-trash', 0.84, 0.72) }
        ];
        const presses = [{ id: 'slice', at: 7.2 }, { id: 'slice', at: 8.25 }, { id: 'col-6', at: 11.05 }, { id: 'col-8', at: 11.85 }, { id: 'col-9', at: 12.55 }, { id: 'btn-trash', at: 13.9 }];
        if (st.i === 3) {
          st.collected = PICKS.filter((p, i) => t >= presses[2 + i].at + 0.1).map(p => p[1]);
          st.coll = coll(t, PICKS.map((p, i) => ({ at: presses[2 + i].at + 0.1, n: p[1], s: p[2] })), 14.25);
          st.rowGone = it => { const j = PICKS.findIndex(p => p[1] === it.n); return j < 0 ? 0 : E.io(seg(t, 14.02 + j * 0.06, 0.42)); };
        }
        st.pressed = press(t, presses);
        out.st = st;
        if (t >= 5.5 && t < 15.1) { const c = cursor(t, start, kfs); out.cursor = { x: c[0], y: c[1], k: pressK(t, presses), a: 1 - seg(t, 14.7, 0.3) }; }
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
      D = { vols: C.data.vols, groups: C.data.groups, icon: '../../assets/img/icon-128.png',
        node(drive, path) { const n = C.data.nodes[drive + ':' + path.join('/')]; const items = n.items.map(x => Object.assign({}, x)); return { name: n.name, items, total: items.reduce((a, b) => a + b.s, 0) }; } };
      return D;
    },
    make(name) { return S[name](); }
  };
})();
