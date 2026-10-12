/* Split-flap engine for A2, shared by the board, the signs and the turn line.
   Lifted from the registry block split-flap-board (compositions/split-flap-board.html):
   the same forward-only drum walk and the same falling leaf (theta = 180·p², shade by sin).
   Added: a Cyrillic drum, rows that retarget over time (`script`), a capped walk so a row
   lands on a beat (`maxSteps`), and a cell that spins without landing (`spin`).
   paint(t) is a pure function of the scene's local time: no state carried between frames. */
(function () {
  var DRUM = " АБВГҐДЕЄЖЗИІЇЙКЛМНОПРСТУФХЦЧШЩЬЮЯ0123456789.,?!«»—✓·";
  var N = DRUM.length;
  var DEG = Math.PI / 180;

  function at(i) {
    return DRUM.charAt(((i % N) + N) % N);
  }
  function idx(ch) {
    var i = DRUM.indexOf(ch);
    return i < 0 ? 0 : i;
  }
  // deterministic 0..1 hash (no Math.random in a render)
  function hash(a, b) {
    var h = Math.sin(a * 127.1 + b * 311.7) * 43758.5453;
    return h - Math.floor(h);
  }

  function face(cls, h, font, top) {
    var f = document.createElement("div");
    f.className = "flap-face " + cls;
    var g = document.createElement("span");
    g.className = "flap-glyph";
    g.style.height = h + "px";
    g.style.lineHeight = h + "px";
    g.style.fontSize = font + "px";
    g.style.top = top + "px";
    // the mechanism IS stacked, half-clipped glyphs: declared so the layout audit reports real regressions
    g.setAttribute("data-layout-allow-overlap", "");
    g.setAttribute("data-layout-allow-occlusion", "");
    f.appendChild(g);
    return f;
  }

  /* o: { el, cells, w, h, gap, font, color, accent, accentChars, flip, stagger, maxSteps,
          script: [[t, "TEXT", maxSteps?], ...], spin: { cell, from, flip } , seed } */
  function row(o) {
    var cells = o.cells, w = o.w, h = o.h;
    var flip = o.flip || 0.04, stagger = o.stagger || 0.03, maxSteps = o.maxSteps || 9;
    var color = o.color || "#F4EFE2", accent = o.accent || "#F2B544";
    var accentChars = o.accentChars || "✓—";
    var seed = o.seed || 1;
    o.el.style.display = "flex";
    o.el.style.gap = (o.gap || 6) + "px";

    var list = [];
    for (var i = 0; i < cells; i++) {
      var cell = document.createElement("div");
      cell.className = "flap-cell";
      cell.style.width = w + "px";
      cell.style.height = h + "px";
      cell.setAttribute("data-layout-allow-overflow", "");
      var half = Math.round(h / 2);
      var top = face("flap-top", h, o.font, 0);
      var bot = face("flap-bot", h, o.font, -half);
      var la = face("flap-leaf-a", h, o.font, 0);
      var lb = face("flap-leaf-b", h, o.font, -half);
      var seam = document.createElement("div");
      seam.className = "flap-seam";
      cell.appendChild(top);
      cell.appendChild(bot);
      cell.appendChild(la);
      cell.appendChild(lb);
      cell.appendChild(seam);
      o.el.appendChild(cell);

      // events for this cell, in time order
      var entries = [];
      for (var k = 0; k < o.script.length; k++) {
        var s = o.script[k];
        entries.push({ t: s[0] + i * stagger, ch: s[1].charAt(i) || " ", k: k, m: s[2] });
      }
      if (o.spin && o.spin.cell === i) entries.push({ t: o.spin.from, spin: o.spin.flip });
      entries.sort(function (a, b) {
        return a.t - b.t;
      });

      var events = [], cur = 0, spinEv = null;
      for (var e = 0; e < entries.length; e++) {
        var en = entries[e];
        if (spinEv) {
          // the spinning cell is caught wherever its drum happens to be
          cur = (spinEv.from + Math.floor((en.t - spinEv.at) / spinEv.flip)) % N;
          spinEv = null;
        }
        if (en.spin) {
          spinEv = { at: en.t, from: cur, flip: en.spin, spin: true };
          events.push(spinEv);
          continue;
        }
        var to = idx(en.ch);
        if (to === cur) continue;
        var d = (to - cur + N) % N;
        var cap = (en.m || maxSteps) + Math.floor(hash(i + 1, en.k + seed) * 4);
        events.push({ at: en.t, from: cur, to: to, steps: Math.min(d, cap), flip: flip });
        cur = to;
      }

      list.push({
        events: events,
        top: top.firstChild,
        bot: bot.firstChild,
        la: la,
        lb: lb,
        ga: la.firstChild,
        gb: lb.firstChild,
      });
    }

    // char index shown at drum step j of event ev (j = 0 is where it started)
    function seq(ev, j) {
      if (ev.spin || ev.steps === (ev.to - ev.from + N) % N) return ev.from + j;
      return j === 0 ? ev.from : ev.to - ev.steps + j;
    }
    function tint(g, ch) {
      g.textContent = ch;
      g.style.color = accentChars.indexOf(ch) >= 0 ? accent : color;
    }
    function clear(leaf, g) {
      leaf.style.opacity = "0";
      leaf.style.transform = "";
      leaf.style.filter = "";
      g.textContent = "";
    }
    function show(leaf, g, ch, angle, shade) {
      tint(g, ch);
      leaf.style.opacity = "1";
      leaf.style.transform = "rotateX(" + angle.toFixed(2) + "deg)";
      leaf.style.filter = "brightness(" + shade + ")";
    }

    function paint(t) {
      for (var i = 0; i < list.length; i++) {
        var c = list[i], ev = null;
        for (var k = 0; k < c.events.length; k++) if (c.events[k].at <= t) ev = c.events[k];
        if (!ev) {
          tint(c.top, " ");
          tint(c.bot, " ");
          clear(c.la, c.ga);
          clear(c.lb, c.gb);
          continue;
        }
        var raw = (t - ev.at) / ev.flip;
        var j = Math.floor(raw), p = raw - j;
        if (!ev.spin && j >= ev.steps) {
          tint(c.top, at(ev.to));
          tint(c.bot, at(ev.to));
          clear(c.la, c.ga);
          clear(c.lb, c.gb);
          continue;
        }
        var out = at(seq(ev, j)), inc = at(seq(ev, j + 1));
        if (p <= 0) {
          tint(c.top, out);
          tint(c.bot, out);
          clear(c.la, c.ga);
          clear(c.lb, c.gb);
          continue;
        }
        tint(c.top, inc);
        tint(c.bot, out);
        var theta = 180 * p * p;
        var shade = (1 - 0.5 * Math.sin(theta * DEG)).toFixed(3);
        if (theta < 90) {
          show(c.la, c.ga, out, -theta, shade);
          clear(c.lb, c.gb);
        } else {
          clear(c.la, c.ga);
          show(c.lb, c.gb, inc, 180 - theta, shade);
        }
      }
    }
    paint(-1);
    return { paint: paint };
  }

  /* One driver per scene: GSAP writes `t` on every seek, the setter paints every row. */
  function drive(tl, duration, rows) {
    var now = 0, d = {};
    Object.defineProperty(d, "t", {
      get: function () {
        return now;
      },
      set: function (v) {
        now = v;
        for (var i = 0; i < rows.length; i++) rows[i].paint(v);
      },
    });
    tl.fromTo(d, { t: 0 }, { t: duration, duration: duration, ease: "none" }, 0);
  }

  window.SplitFlap = { row: row, drive: drive };
})();
