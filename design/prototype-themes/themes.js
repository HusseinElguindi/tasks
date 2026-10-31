/* Tasks · themes (design/THEMES.md).
   The sample themes in the theme file's shape (§3), the derivation rules (§2.4) and the contrast check (§2.5).
   The prototype reads it as window.TasksThemes; the app's version is TK.Theme + TK.Palette(theme:dark:) (§6).
   Nothing here runs per frame: a palette is derived once per (theme, appearance) and cached. */
(function () {
  // ---------- Colour math: straight sRGB mixes (the same as Pane's tokens.json) and WCAG contrast ----------
  function rgb(hex) {
    const h = String(hex).replace('#', '');
    return [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16)];
  }
  function hex(c) {
    return '#' + c.map((v) => Math.round(Math.max(0, Math.min(255, v))).toString(16).padStart(2, '0')).join('').toUpperCase();
  }
  function mix(a, b, t) { const x = rgb(a), y = rgb(b); return hex(x.map((v, i) => v + (y[i] - v) * t)); }
  function alpha(c, a) { const [r, g, b] = rgb(c); return 'rgba(' + r + ', ' + g + ', ' + b + ', ' + a + ')'; }
  function lum(c) {
    const f = (v) => { v /= 255; return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); };
    const [r, g, b] = rgb(c);
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
  }
  function contrast(a, b) { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); }

  // ---------- The sample themes, each in the file format: per appearance, 3 required colours and a few optional ----------
  // Required: base (the focused pane), ink (titles), accent. Optional: ground (window and sidebar; derived from base),
  // danger, attention (derived from the list palette's red and yellow), lists (six hues; Rex's ANSI by default),
  // contrast ("standard" or "high"), tokens (pins for any derived token; only the default uses them).
  const REX_LISTS = {
    dark: { blue: '#58A6FF', magenta: '#BC8CFF', green: '#3FB950', cyan: '#39C5CF', yellow: '#D29922', red: '#FF7B72' },
    light: { blue: '#0969DA', magenta: '#8250DF', green: '#116329', cyan: '#1B7C83', yellow: '#9A6700', red: '#CF222E' },
  };
  // The default theme pins today's measured values (tasks-v2.css:46–78), so choosing it changes nothing. The rules
  // below reproduce them within a level or two per channel (the Tokens board shows each pair).
  const REX_PINS = {
    dark: {
      ground: '#181818', base: '#1C1C1C', dim: '#181818', popover: '#262626', lift: '#2C2C2C',
      'line-pane': '#323334', 'line-pane-dim': '#282929', 'line-sep': '#363738', 'line-field': '#696B6E',
      'ink-2': '#A8ADB1', 'ink-3': '#7F8386', 'ink-q': '#6D7072', sel: '#333333', 'sel-dim': '#292929',
      'fill-control': '#2D2E2E', 'fill-track': '#303132', 'fill-thumb': '#4A4C4D', 'fill-strong': '#444444',
      'edge-outer': '#5E5E5E', 'edge-inner': '#535353', hover: 'rgba(255, 255, 255, 0.07)', press: 'rgba(255, 255, 255, 0.12)',
      'accent-text': '#5799F6', 'accent-tint': '#1E2938', 'danger-tint': '#3C2928', 'attn-tint': '#352E1D',
      'tile-fill': '#444444', 'tile-ring': 'rgba(255, 255, 255, 0.10)', 'lift-chip': '#3A3A3A',
      'mark-trail': '#6D7072', 'mark-rings': '#A8ADB1',
    },
    light: {
      ground: '#F5F5F5', base: '#FFFFFF', dim: '#FAFAFA', popover: '#FFFFFF', lift: '#FFFFFF',
      'line-pane': '#D4D5D6', 'line-pane-dim': '#EBEBEC', 'line-sep': '#E7E8E8', 'line-field': '#848689',
      'ink-2': '#626568', 'ink-3': '#6C6F72', 'ink-q': '#888A8D', sel: '#E6E6E8', 'sel-dim': '#EFEFF0',
      'fill-control': '#EDEDEE', 'fill-track': '#E9E9EA', 'fill-thumb': '#FFFFFF', 'fill-strong': '#E0E0E1',
      'edge-outer': '#CFCFD0', 'edge-inner': '#D6D6D7', 'accent-tint': '#E6F0FB', 'danger-tint': '#FBEBEC', 'attn-tint': '#FAF7F2',
      'tile-fill': '#E3E3E4', 'lift-chip': '#E9E9EA', 'mark-trail': '#A9ACAF', 'mark-rings': '#626568',
    },
  };

  const THEMES = [
    { id: 'default', name: 'Default', mood: 'Rex: graphite and white, a blue accent',
      dark: { base: '#1C1C1C', ground: '#181818', ink: '#E6EDF3', accent: '#2F81F7', tokens: REX_PINS.dark },
      light: { base: '#FFFFFF', ground: '#F5F5F5', ink: '#1F2328', accent: '#0969DA', tokens: REX_PINS.light } },
    { id: 'paper', name: 'Paper', mood: 'Warm paper and brown ink, a rust accent',
      dark: { base: '#1F1C18', ground: '#1A1714', ink: '#EAE3D8', accent: '#E0905F',
        lists: { blue: '#8FB3D9', magenta: '#D49AC4', green: '#A8C07A', cyan: '#7FC1B8', yellow: '#DDB25C', red: '#EE8A74' } },
      light: { base: '#FBF8F2', ground: '#F1ECE2', ink: '#2A2621', accent: '#A44E2A',
        lists: { blue: '#2F5F8A', magenta: '#8A4B7A', green: '#4F6B2A', cyan: '#2E6E6A', yellow: '#8A6512', red: '#B0362A' } } },
    { id: 'contrast', name: 'Contrast', mood: 'Black and white, brighter quiet ink, stronger lines',
      dark: { base: '#0A0A0A', ground: '#000000', ink: '#FFFFFF', accent: '#4AA8FF', contrast: 'high' },
      light: { base: '#FFFFFF', ground: '#EDEDED', ink: '#000000', accent: '#0047B3', contrast: 'high' } },
    { id: 'dusk', name: 'Dusk', mood: 'Muted slate, soft ink, a periwinkle accent',
      dark: { base: '#23232A', ground: '#1D1D23', ink: '#D9DAE2', accent: '#9AA7E0',
        lists: { blue: '#8FA8D8', magenta: '#B9A0D6', green: '#9DC0A0', cyan: '#8CC3C8', yellow: '#D2BA84', red: '#DE9A94' } },
      light: { base: '#F6F6F4', ground: '#ECECE8', ink: '#34353C', accent: '#55639D',
        lists: { blue: '#4A6596', magenta: '#76598F', green: '#4C7352', cyan: '#3D7478', yellow: '#7F6629', red: '#9E4D47' } } },
    { id: 'harbor', name: 'Harbor', mood: 'Cool blue-grey surfaces, a clear sky accent',
      dark: { base: '#15202B', ground: '#101922', ink: '#DCE7F2', accent: '#4CB2EC' },
      light: { base: '#F7FAFD', ground: '#E9EFF6', ink: '#18232F', accent: '#0E6FB5' } },
    { id: 'iris', name: 'Iris', mood: 'The default surfaces with one vivid violet accent',
      dark: { base: '#1C1C1C', ground: '#181818', ink: '#E6EDF3', accent: '#9B6BFF' },
      light: { base: '#FFFFFF', ground: '#F5F5F5', ink: '#1F2328', accent: '#7A3FF2' } },
    { id: 'moss', name: 'Moss', mood: 'Green-grey surfaces, a leaf accent',
      dark: { base: '#1B1F1C', ground: '#161A17', ink: '#DEE6DD', accent: '#62C08A' },
      light: { base: '#FAFBF8', ground: '#EDF1EA', ink: '#212822', accent: '#2B7A4B' } },
  ];

  // ---------- Derivation rules ----------
  // Each derived token is a mix: [from, to, t] (t of the way from one input to the other), or an alpha of one. The
  // amounts are Rex's own: each one solves today's measured value from Rex's base, ink and accent.
  // 'high' contrast halves the ink steps and strengthens lines and edges by 1.6.
  const R = {
    dark: {
      ground: ['base', '#000000', 0.14], dim: ['ground'], popover: ['base', 'ink', 0.05], lift: ['base', 'ink', 0.078],
      'line-pane': ['base', 'ink', 0.107, 'line'], 'line-pane-dim': ['base', 'ink', 0.058, 'line'], 'line-sep': ['base', 'ink', 0.127, 'line'], 'line-field': ['base', 'ink', 0.375, 'line'],
      'ink-2': ['ink', 'base', 0.307, 'ink'], 'ink-3': ['ink', 'base', 0.51, 'ink'], 'ink-q': ['ink', 'base', 0.6, 'ink'],
      sel: ['base', 'ink', 0.114], 'sel-dim': ['base', 'ink', 0.064],
      'fill-control': ['base', 'ink', 0.084], 'fill-track': ['base', 'ink', 0.099], 'fill-thumb': ['base', 'ink', 0.225], 'fill-strong': ['base', 'ink', 0.198],
      'edge-outer': ['base', 'ink', 0.327, 'line'], 'edge-inner': ['base', 'ink', 0.272, 'line'],
      hover: ['@', 'ink', 0.07], press: ['@', 'ink', 0.12],
      'accent-text': ['accent', 'ink', 0.22], 'accent-tint': ['base', 'accent', 0.13], 'text-sel': ['@', 'accent', 0.45],
      'danger-tint': ['base', 'danger', 0.141], 'attn-tint': ['base', 'attention', 0.137],
      'tile-fill': ['fill-strong'], 'tile-ring': ['@', 'ink', 0.1], 'lift-chip': ['base', 'ink', 0.147],
      'mark-trail': ['ink-q'], 'mark-rings': ['ink-2'],
    },
    light: {
      ground: ['base', 'ink', 0.045], dim: ['base', 'ground', 0.5], popover: ['base'], lift: ['base'],
      'line-pane': ['base', 'ink', 0.192, 'line'], 'line-pane-dim': ['base', 'ink', 0.089, 'line'], 'line-sep': ['base', 'ink', 0.107, 'line'], 'line-field': ['base', 'ink', 0.549, 'line'],
      'ink-2': ['ink', 'base', 0.3, 'ink'], 'ink-3': ['ink', 'base', 0.344, 'ink'], 'ink-q': ['ink', 'base', 0.47, 'ink'],
      sel: ['base', 'ink', 0.112], 'sel-dim': ['base', 'ink', 0.071],
      'fill-control': ['base', 'ink', 0.08], 'fill-track': ['base', 'ink', 0.098], 'fill-thumb': ['base'], 'fill-strong': ['base', 'ink', 0.138],
      'edge-outer': ['base', 'ink', 0.214, 'line'], 'edge-inner': ['base', 'ink', 0.183, 'line'],
      hover: ['@', 'ink', 0.06], press: ['@', 'ink', 0.11],
      'accent-text': ['accent'], 'accent-tint': ['base', 'accent', 0.1], 'text-sel': ['@', 'accent', 0.25],
      'danger-tint': ['base', 'danger', 0.09], 'attn-tint': ['base', 'attention', 0.05],
      'tile-fill': ['base', 'ink', 0.125], 'tile-ring': ['@', 'ink', 0.1], 'lift-chip': ['fill-track'],
      'mark-trail': ['ink', 'base', 0.616], 'mark-rings': ['ink-2'],
    },
  };
  // The order tokens are derived in (each reads only earlier ones).
  const ORDER = ['ground', 'dim', 'popover', 'lift', 'line-pane', 'line-pane-dim', 'line-sep', 'line-field', 'ink-2', 'ink-3', 'ink-q',
    'sel', 'sel-dim', 'fill-control', 'fill-track', 'fill-thumb', 'fill-strong', 'edge-outer', 'edge-inner', 'hover', 'press',
    'accent-text', 'accent-tint', 'text-sel', 'danger-tint', 'attn-tint', 'tile-fill', 'tile-ring', 'lift-chip', 'mark-trail', 'mark-rings'];

  // ---------- Contrast floors (§2.5) ----------
  // fix: the token is moved toward ink in 2% steps until it passes (derived tokens only; a pinned one is checked as is).
  // reject: a base colour the theme chose; the theme doesn't load, and Settings says which pair failed.
  const FLOORS = [
    { t: 'ink', on: ['base', 'ground', 'sel', 'popover'], min: 7, kind: 'reject', why: 'Titles and task text' },
    { t: 'accent', on: ['base'], min: 3, kind: 'reject', why: 'The checked box, focus rings, the highlighted day' },
    { t: 'ink-2', on: ['base', 'ground', 'sel', 'fill-control'], min: 4.5, kind: 'fix', why: 'Labels, values, chip text, a list’s notes' },
    { t: 'ink-3', on: ['base', 'ground'], min: 4.5, kind: 'fix', why: 'Group labels, counts, placeholders' },
    { t: 'ink-q', on: ['base', 'ground'], min: 3, kind: 'fix', why: 'Icons at rest, strike-throughs, Markdown marks (non-text)' },
    { t: 'line-field', on: ['base'], min: 3, kind: 'fix', why: 'The checkbox ring (a control’s edge)' },
    { t: 'accent-text', on: ['base', 'accent-tint'], min: 4.5, kind: 'fix', why: 'Links, today’s date, tinted chips and buttons' },
    { t: 'danger', on: ['danger-tint', 'base'], min: 4.5, kind: 'fix', why: 'The overdue chip' },
    { t: 'attention', on: ['attn-tint', 'base'], min: 4.5, kind: 'fix', why: 'The due-today chip' },
    { t: 'on-accent', on: ['accent'], min: 3, kind: 'fix', why: 'The checkmark and the highlighted menu item (macOS’s own white-on-accent)' },
    { t: 'list', on: ['tile-fill'], min: 3, kind: 'fix', why: 'A list’s monogram on its tile' },
  ];
  // Rex's measured ink-3 is 4.46:1 on the dark base; pins are checked at 4.45 so the default stays exactly Rex.
  const PIN_TOLERANCE = 0.05;

  const LIST_SLOTS = ['blue', 'magenta', 'green', 'cyan', 'yellow', 'red'];

  function derive(theme, appearance) {
    const dark = appearance !== 'light';
    const side = (dark ? theme.dark : theme.light) || {};
    const rules = R[dark ? 'dark' : 'light'];
    const high = side.contrast === 'high';
    const pins = side.tokens || {};
    const lists = Object.assign({}, REX_LISTS[dark ? 'dark' : 'light'], side.lists || {});
    const v = { base: side.base, ink: side.ink, accent: side.accent };
    v.danger = side.danger || lists.red;
    v.attention = side.attention || lists.yellow;
    if (side.ground) v.ground = side.ground;
    const src = {};   // how each token was made: 'input', 'pinned', or the rule's text
    ['base', 'ink', 'accent'].forEach((k) => (src[k] = 'input'));
    src.danger = side.danger ? 'input' : 'lists.red';
    src.attention = side.attention ? 'input' : 'lists.yellow';
    if (side.ground) src.ground = 'input';
    const ruleText = {};
    ORDER.forEach((k) => {
      if (k === 'ground' && side.ground) return;
      const r = rules[k];
      let t = r[2];
      if (high && r[3] === 'ink') t *= 0.5;
      if (high && r[3] === 'line') t = Math.min(0.9, t * 1.6);
      let val, text;
      if (r[0] === '@') { val = alpha(v[r[1]], t); text = r[1] + ' at ' + Math.round(t * 100) + '%'; }
      else if (r.length === 1) { val = v[r[0]]; text = '= ' + r[0]; }
      else { val = mix(v[r[0]], v[r[1]] || r[1], t); text = r[0] + ' → ' + (v[r[1]] ? r[1] : r[1]) + ' ' + (Math.round(t * 1000) / 10) + '%'; }
      ruleText[k] = text;
      if (pins[k]) { val = pins[k]; src[k] = 'pinned'; } else src[k] = text;
      v[k] = val;
    });
    // On the accent: white when it reads (3:1, macOS's own convention), else the darkest ink there is.
    v['on-accent'] = contrast('#FFFFFF', v.accent) >= 3 ? '#FFFFFF' : (dark ? v.base : v.ink);
    src['on-accent'] = 'white, or ' + (dark ? 'base' : 'ink') + ' under 3:1';
    ruleText['on-accent'] = src['on-accent'];
    v['mark-bar'] = v.ink; v['mark-head'] = v.accent; src['mark-bar'] = '= ink'; src['mark-head'] = '= accent';
    v.focus = v.accent; src.focus = '= accent';

    // Floors.
    const checks = [];
    let ok = true;
    const nudge = (k, on, min) => {
      let c = v[k], steps = 0;
      while (contrast(c, v[on]) < min && steps < 50) { c = mix(c, dark ? '#FFFFFF' : '#000000', 0.02); steps++; }
      return c;
    };
    FLOORS.forEach((f) => {
      const targets = f.t === 'list' ? LIST_SLOTS.map((s) => 'list-' + s) : [f.t];
      if (f.t === 'list') LIST_SLOTS.forEach((s) => { if (!v['list-' + s]) { v['list-' + s] = lists[s]; src['list-' + s] = side.lists && side.lists[s] ? 'input' : 'Rex ANSI ' + s; } });
      targets.forEach((k) => {
        f.on.forEach((on) => {
          const before = contrast(v[k], v[on]);
          const min = src[k] === 'pinned' ? f.min - PIN_TOLERANCE : f.min;
          if (before >= min) { checks.push({ t: k, on, ratio: before, min: f.min, result: 'pass', why: f.why }); return; }
          if (f.kind === 'reject' || src[k] === 'pinned') {
            ok = false; checks.push({ t: k, on, ratio: before, min: f.min, result: 'reject', why: f.why }); return;
          }
          v[k] = nudge(k, on, f.min);
          src[k] = (src[k] || '') + ' · raised for ' + on;
          checks.push({ t: k, on, ratio: contrast(v[k], v[on]), was: before, min: f.min, result: 'fixed', why: f.why });
        });
      });
    });
    v['list-ink'] = v.ink;

    // CSS variables, the prototype's names (tasks-v2.css:46–78) plus the ones themes.css adds.
    const vars = {};
    ['ground', 'base', 'dim', 'popover', 'lift', 'line-pane', 'line-pane-dim', 'line-sep', 'line-field', 'ink', 'ink-2', 'ink-3', 'ink-q',
      'sel', 'sel-dim', 'fill-control', 'fill-track', 'fill-thumb', 'fill-strong', 'edge-outer', 'edge-inner', 'hover', 'press',
      'accent', 'accent-text', 'accent-tint', 'on-accent', 'text-sel', 'tile-fill', 'tile-ring', 'lift-chip', 'focus',
      'mark-trail', 'mark-rings', 'mark-bar', 'mark-head'].forEach((k) => (vars['--' + k] = v[k]));
    vars['--danger'] = v.danger; vars['--danger-tint'] = v['danger-tint'];
    vars['--attn'] = v.attention; vars['--attn-tint'] = v['attn-tint'];
    LIST_SLOTS.forEach((s) => (vars['--ansi-' + s] = v['list-' + s]));
    vars['--ansi-ink'] = v.ink;
    vars['--on-accent-2'] = alpha(v['on-accent'], 0.78);
    // Shadows: fixed per appearance; only their 0.5pt ring takes the theme's ink.
    vars['--shadow-popover'] = dark ? '0 0 0 0.5px ' + alpha(v.ink, 0.14) + ', 0 12px 32px rgba(0, 0, 0, 0.5)' : '0 0 0 0.5px ' + alpha(v.ink, 0.16) + ', 0 12px 32px ' + alpha(v.ink, 0.16);
    vars['--shadow-lift'] = dark ? '0 0 0 0.5px ' + alpha(v.ink, 0.14) + ', 0 8px 24px rgba(0, 0, 0, 0.5)' : '0 0 0 0.5px ' + alpha(v.ink, 0.14) + ', 0 8px 24px ' + alpha(v.ink, 0.18);
    if (theme.id === 'default') { vars['--shadow-popover'] = null; vars['--shadow-lift'] = null; vars['--hover'] = pins.hover || vars['--hover']; }
    return { id: theme.id, name: theme.name, appearance: dark ? 'dark' : 'light', v, vars, src, ruleText, checks, ok };
  }

  // The style attribute that applies a palette (one string, built once per theme and appearance).
  const cache = {};
  function styleFor(id, appearance) {
    const key = id + ':' + appearance;
    if (cache[key]) return cache[key];
    const p = derive(byId(id), appearance);
    cache[key] = Object.keys(p.vars).filter((k) => p.vars[k]).map((k) => k + ': ' + p.vars[k]).join('; ');
    return cache[key];
  }
  function byId(id) { return THEMES.find((t) => t.id === id) || THEMES[0]; }

  window.TasksThemes = { THEMES, derive, styleFor, byId, contrast, mix, RULES: R, ORDER, FLOORS, REX_PINS };
})();
