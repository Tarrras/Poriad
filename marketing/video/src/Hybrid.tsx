import React from 'react';
import {AbsoluteFill, Audio, Easing, Img, Sequence, interpolate, random, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {Aura, BG, Bezel, C, CARD_BLURS, CYCLE, Demo, Dim, LiveScreen, P, Pop, Touch, py, zoomAt} from './LiveUI';
import {useFonts} from './fonts';
import {AMBER, CITY, CORAL, Cities, INK, Kinetic, Lockup, Logo, Pin, SMOOTH, Sample, VIOLET, Wipe, pop, proj} from './Motion';
import {Grain, Sfx, ease} from './kit';

// Гібрид v3 (32.7 с, 9:16). Правило: один кадр — одне твердження — один доказ; підпис змінюється разом з інтерфейсом.
// Хук: пошукова фраза «куди піти в києві на вихідних?» + одна цифра з prod: фільтр «Вихідні» на мапі Києва = 151 (09.10).
// Цифру перераховувати в день рендеру (clips/prod/weekend.mov) і міняти в хуку й підписі разом.
// Біль показує motion design, рішення — справжній інтерфейс: prod (clips/prod) скрізь, де можна;
// «шукаю компанію» і фільтр «від людей» — dev з тестовими даними, на них позначка «приклад».
// Музика calm.m4a (спокійна; brand.m4a виявився «занадто активним»).
export const HYBRID_FRAMES = 980;
const WEEKEND = 151; // prod, Київ, фільтр «Вихідні», 09.10
const events = (n: number) => `${n} ${n % 10 === 1 && n % 100 !== 11 ? 'подія' : [2, 3, 4].includes(n % 10) && ![12, 13, 14].includes(n % 100) ? 'події' : 'подій'}`;

// ── Підписи: кожен бит має свій текст і живе лише поки на екрані те, про що він ──
// hold — світлий рядок не анімується заново (той самий, що в попередньому биті), важкий з'являється швидко
// brand — перед світлим рядком іконка й «Поряд» коралом, щоб назву застосунку не сплутати зі словом
// still — бит продовжує попередній з тим самим текстом: показати вже готовим, без повторної анімації
type Cap = {at: number; light?: string; heavy: string; size?: number; sub?: string; color?: string; hold?: boolean; brand?: boolean; still?: boolean};

const CapView = ({c, len, top = 258}: {c: Cap; len: number; top?: number}) => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  const at0 = c.still ? -60 : 0;
  const icon = pop(f - at0, fps, 11, 200);
  return (
    <div style={{position: 'absolute', top, left: 66, right: 66, opacity: c.hold ? 1 : ease(f, len - 4, len, [1, 0])}}>
      {c.brand ? (
        <div style={{display: 'flex', alignItems: 'center', gap: 18}}>
          <Img src={staticFile('icon.png')} style={{width: 76, height: 76, borderRadius: 18, transform: `scale(${icon}) rotate(${(1 - icon) * -20}deg)`,
            boxShadow: '0 12px 34px rgba(224,88,47,.5)'}} />
          <Kinetic text="Поряд" at={at0 + 3} size={70} weight={900} color={CORAL} stagger={0.8} />
          {c.light && <Kinetic text={c.light} at={at0 + 7} size={62} weight={300} stagger={0.5} />}
        </div>
      ) : c.light && <Kinetic text={c.light} at={c.hold || c.still ? -60 : 0} size={62} weight={300} stagger={0.6} />}
      <Kinetic text={c.heavy} at={c.still ? -60 : c.hold ? 0 : c.light ? (c.brand ? 9 : 4) : 0} size={c.size ?? 100} color={c.color ?? '#fff'} stagger={c.hold ? 0.25 : 0.9} style={{marginTop: c.light ? 12 : 0}} />
      {c.sub && <Kinetic text={c.sub} at={10} size={38} weight={500} color="#C7C7CC" stagger={0.4} style={{marginTop: 18}} />}
    </div>
  );
};

const Captions = ({caps, end, top}: {caps: Cap[]; end: number; top?: (c: Cap) => number}) => (
  <>
    {caps.map((c, i) => {
      const to = caps[i + 1]?.at ?? end;
      // перед битом з hold не згасаємо — інакше світлий рядок блимне
      const keep = i === caps.length - 1 || caps[i + 1]?.hold;
      return <Sequence key={i} from={c.at} durationInFrames={to - c.at} layout="none"><CapView c={c} len={keep ? 9999 : to - c.at} top={top?.(c)} /></Sequence>;
    })}
  </>
);

// ── Живий екран ──────────────────────────────────────────────────────
// blurs — додаткові розмиті зони екрана (постери з обличчями артистів), у точках iOS
const UIScene = ({d, caps, intro = false}: {d: Demo; caps: Cap[]; intro?: boolean}) => {
  const f = useCurrentFrame();
  const {z, fx, fy} = zoomAt(f, d.zoom);
  // вхід із піна: телефон від'їжджає з наїзду 2.2× до звичайного розміру
  const zin = intro ? interpolate(f, [0, 22], [2.2, 1], {extrapolateRight: 'clamp', easing: SMOOTH}) : 1;
  const bg = intro ? ease(f, 0, 10, [0, 1]) : 1;
  const ry = Math.sin(f / 45) * 3;
  return (
    <AbsoluteFill>
      <AbsoluteFill style={{background: BG, opacity: bg}}>
        <Aura color={d.glow + '77'} y={70} size={1200} />
      </AbsoluteFill>
      <AbsoluteFill style={{perspective: 2400, transformOrigin: `540px ${py(437)}px`, transform: `scale(${zin})`}}>
        <AbsoluteFill style={{transformOrigin: `${(fx / 402) * 600 + 240}px ${py(fy)}px`, transform: `scale(${z}) rotateY(${ry}deg) rotateX(2deg)`}}>
          <Bezel />
          <div style={{opacity: intro ? ease(f, 0, 6, [0, 1]) : 1}}><LiveScreen segs={d.segs} blur={d.blur} /></div>
          <Dim spans={d.pops.map((p) => [p.at, p.until] as [number, number])} />
          {d.touches.map((t, i) => <Touch key={i} {...t} />)}
          {d.pops.map((p, i) => <Pop key={i} {...p} />)}
        </AbsoluteFill>
      </AbsoluteFill>
      <div style={{position: 'absolute', top: 0, left: 0, right: 0, height: 640, background: `linear-gradient(${INK} 70%, ${INK}00)`, opacity: bg}} />
      {d.sample !== undefined && <Sample until={d.sample} />}
      <Captions caps={caps} end={d.len} />
    </AbsoluteFill>
  );
};

// ── Хук + біль (0–170): мапа вихідних → «а ти знаєш про три» → розкидані канали → усе в один пін ──
const HOOK_PINS = Array.from({length: 230}, (_, i) => {
  const x = 60 + random(`hx${i}`) * 960;
  const y = 700 + random(`hy${i}`) * 1020;
  const colors = [CORAL, VIOLET, '#2F63C4', AMBER, '#3DAA6B'];
  return {x, y, s: 20 + random(`hs${i}`) * 18, c: colors[Math.floor(random(`hc${i}`) * colors.length)], d: Math.hypot(x - 540, y - 1200)};
});
const KNOWN = [{x: 300, y: 930}, {x: 770, y: 1180}, {x: 430, y: 1520}];
const STREETS = Array.from({length: 18}, (_, i) =>
  i % 2 ? `M ${random(`sa${i}`) * 1080} 640 L ${random(`sb${i}`) * 1080} 1800` : `M -40 ${700 + random(`sy${i}`) * 1000} L 1120 ${700 + random(`sz${i}`) * 1000}`);
const CHIPS = [
  ...Array.from({length: 5}, (_, i) => ({t: 'канал з афішею', n: `${[47, 23, 64, 12, 31][i]} нових`, dark: true})),
  ...Array.from({length: 4}, () => ({t: 'сайт квитків', n: 'ще одна вкладка', dark: false})),
];
const SUCK = 138;
const CENTER = {x: 540, y: 1200};

const Hook = () => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  const dim = ease(f, 45, 56, [0, 1], SMOOTH);
  const gone = ease(f, 88, 100, [0, 1], SMOOTH);
  const bigPin = pop(f - SUCK - 12, fps, 10, 160);
  const dive = ease(f, 156, 170, [1, 5], Easing.in(Easing.cubic));
  return (
    <AbsoluteFill style={{background: INK}}>
      <AbsoluteFill style={{transformOrigin: `${CENTER.x}px ${CENTER.y}px`, transform: `scale(${dive})`}}>
        <svg width={1080} height={1920} style={{position: 'absolute', opacity: 1 - 0.6 * gone}}>
          {STREETS.map((d, i) => (
            <path key={i} d={d} pathLength={1} stroke="#24242C" strokeWidth={i % 3 ? 3 : 7} fill="none"
              strokeDasharray={1} strokeDashoffset={1 - ease(f, i, 18 + i, [0, 1], SMOOTH)} />
          ))}
        </svg>
        {/* 200+ подій вихідних */}
        {HOOK_PINS.map((p, i) => {
          const k = pop(f - 2 - p.d / 45, fps, 11, 230);
          const o = (1 - 0.88 * dim) * (1 - gone);
          return k > 0.01 && o > 0.01 ? (
            <div key={i} style={{position: 'absolute', left: p.x - p.s / 2, top: p.y - p.s * 1.3, transformOrigin: '50% 100%', transform: `scale(${k * (1 - 0.2 * dim)})`, opacity: o}}>
              <Pin size={p.s} color={p.c} />
            </div>
          ) : null;
        })}
        {/* три, про які знаєш */}
        {KNOWN.map((p, i) => {
          const k = Math.max(pop(f - 4 - i * 2, fps, 11, 230), 0);
          const grow = pop(f - 48 - i * 4, fps, 10, 180);
          const suck = ease(f, SUCK, SUCK + 12, [0, 1], Easing.in(Easing.cubic));
          const x = interpolate(suck, [0, 1], [p.x, CENTER.x]);
          const y = interpolate(suck, [0, 1], [p.y, CENTER.y]);
          const s = 30 * (1 + 1.4 * grow) * (1 - suck);
          const ring = f > 50 && f < 92 ? Math.abs(Math.sin((f - 50 - i * 4) / 6)) : 0;
          return s > 1 ? (
            <div key={i} style={{position: 'absolute', left: x - s / 2, top: y - s * 1.3, transform: `scale(${k})`, transformOrigin: '50% 100%',
              filter: `drop-shadow(0 0 ${18 * ring}px ${CORAL})`}}>
              <Pin size={s} />
            </div>
          ) : null;
        })}
        {/* розкидані канали й сайти квитків */}
        {CHIPS.map((c, i) => {
          const at = 92 + i * 3;
          if (f < at) return null;
          const k = pop(f - at, fps, 12, 200);
          const sx = 120 + random(`cx${i}`) * 840;
          const sy = 720 + random(`cy${i}`) * 900;
          const fromX = random(`fx${i}`) > 0.5 ? 1300 : -300;
          const suck = ease(f, SUCK + i, SUCK + 12 + i, [0, 1], Easing.in(Easing.cubic));
          const x = interpolate(k, [0, 1], [fromX, sx]) + Math.sin(f / 7 + i) * 10;
          const y = sy + Math.cos(f / 9 + i) * 10;
          const fx = interpolate(suck, [0, 1], [x, CENTER.x]);
          const fy = interpolate(suck, [0, 1], [y, CENTER.y]);
          return (
            <div key={i} style={{position: 'absolute', left: fx - 170, top: fy - 50, width: 340, padding: '18px 22px', borderRadius: 26,
              background: c.dark ? '#24242C' : '#F5F5F7', color: c.dark ? '#F5F5F7' : INK, fontFamily: 'Inter', boxShadow: '0 20px 50px rgba(0,0,0,.45)',
              transform: `rotate(${(random(`cr${i}`) - 0.5) * 16 * (1 - suck)}deg) scale(${1 - 0.9 * suck})`, opacity: 1 - suck}}>
              <div style={{fontWeight: 600, fontSize: 32}}>{c.t}</div>
              <div style={{fontSize: 26, opacity: 0.65}}>{c.n}</div>
            </div>
          );
        })}
        {f >= SUCK + 10 && (
          <div style={{position: 'absolute', left: CENTER.x - 70, top: CENTER.y - 182, transformOrigin: '50% 100%', transform: `scale(${bigPin})`,
            filter: `drop-shadow(0 0 40px ${CORAL})`}}>
            <Pin size={140} />
          </div>
        )}
      </AbsoluteFill>
      <div style={{position: 'absolute', top: 0, left: 0, right: 0, height: 760, background: `linear-gradient(${INK} 66%, ${INK}00)`}} />
      <Lockup until={SUCK + 8} />
      <Captions end={176} top={(c) => (c.brand ? 258 : 340)} caps={[
        {at: 0, light: 'куди піти в києві\nна вихідних?', heavy: `${Math.floor(WEEKEND / 50) * 50}+ подій`, size: 132, color: CORAL},
        {at: 45, heavy: 'а ти знаєш\nпро три.', size: 110},
        {at: 90, light: 'бо вони розкидані:', heavy: '5 каналів\nі 4 сайти', size: 100},
        {at: SUCK + 8, brand: true, light: 'збирає їх', heavy: 'на одну мапу', size: 100},
      ]} />
    </AbsoluteFill>
  );
};

// ── Друзі злились (motion, фіолет) ──────────────────────────────────
const BAIL = ['я пас 😬', 'не можу, сорі', 'може наступного разу 🙏'];
const Friends = () => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  return (
    <AbsoluteFill style={{background: VIOLET}}>
      <Captions end={80} caps={[{at: 0, heavy: 'а друзі\nзлились?', size: 120}]} />
      <div style={{position: 'absolute', top: 760, left: 90, fontFamily: 'Inter', fontWeight: 600, fontSize: 30, color: 'rgba(255,255,255,.7)', letterSpacing: '0.12em',
        opacity: ease(f, 6, 12, [0, 1])}}>ДРУЗІ · СУБОТА</div>
      {BAIL.map((t, i) => {
        const k = pop(f - 12 - i * 13, fps, 12, 210);
        const fall = ease(f, 60 + i * 2, 74 + i * 2, [0, 1], Easing.in(Easing.cubic));
        return (
          <div key={t} style={{position: 'absolute', left: 80, top: 830 + i * 150, padding: '28px 40px', borderRadius: 44, borderBottomLeftRadius: 12,
            background: 'rgba(255,255,255,.16)', color: '#fff', fontFamily: 'Inter', fontWeight: 500, fontSize: 52,
            transformOrigin: 'left bottom', transform: `scale(${k}) translateY(${fall * 900}px) rotate(${fall * (i % 2 ? 14 : -10)}deg)`, opacity: 1 - fall}}>
            {t}
          </div>
        );
      })}
    </AbsoluteFill>
  );
};

// ── Живі сцени ───────────────────────────────────────────────────────
// prod: уся мапа Києва (1032) → тап «Вихідні» → 151 — та сама цифра, що в хуку
const UI_MAP: Demo = {
  glow: CORAL, len: 105,
  segs: [{at: 0, clip: P + 'weekend.mov', from: 0.6, dur: 60, still: P + 'weekend-end.png'}],
  zoom: [[0, 1, 201, 437], [18, 1, 201, 437], [30, 1.18, 300, 220], [44, 1.18, 300, 220], [56, 1, 201, 437]],
  touches: [{at: 25, x: 342, y: 154}],
  pops: [{src: P + 'weekend-end.png', rect: [186, 580, 202, 44], at: 58, until: 105, ty: 1180, s: 1.8, rz: -3, glow: 'rgba(224,88,47,.5)'}],
  blur: CARD_BLURS.map((rect) => ({rect, until: 999})),
};
// prod: пошук «котики» → картка → Котики Фест
const UI_OPEN: Demo = {
  glow: CORAL, len: 90,
  segs: [{at: 0, clip: P + 'open.mov', from: 0, dur: 48, rate: 1.6, still: P + 'open-end.png'}],
  zoom: [[0, 1, 201, 437], [46, 1, 201, 437], [90, 1.08, 201, 640]],
  touches: [{at: 4, x: 190, y: 688}],
  pops: [
    {src: P + 'open-end.png', rect: [22, 652, 178, 56], at: 50, until: 90, ty: 1120, tx: 400, s: 1.8, rz: -3, glow: 'rgba(224,88,47,.5)'},
    {src: P + 'open-end.png', rect: [22, 712, 170, 50], at: 58, until: 90, ty: 1300, tx: 700, s: 1.8, rz: 3, glow: 'rgba(224,88,47,.5)'},
  ],
};
// dev (тестові пошуки компанії) — «приклад»
const UI_COMPANY: Demo = {
  glow: VIOLET, len: 120, sample: 999,
  segs: [{at: 0, clip: C + 's3-scroll.mov', from: 17.35, dur: 58, still: C + 's3-scroll-end.png'}],
  zoom: [[0, 1, 201, 437], [56, 1, 201, 437], [70, 1.15, 201, 600], [120, 1.15, 201, 600]],
  touches: [],
  pops: [
    {src: C + 's3-scroll-end.png', rect: [16, 518, 370, 102], at: 62, until: 120, ty: 1000, s: 1.12, rz: -2},
    {src: C + 's3-scroll-end.png', rect: [28, 776, 346, 52], at: 76, until: 120, ty: 1250, s: 1.2, rz: 2, glow: 'rgba(139,108,255,.6)'},
  ],
};
// dev-фільтр «від людей» — «приклад», далі справжня форма «Нова подія» (prod)
const UI_PEOPLE: Demo = {
  glow: '#2F63C4', len: 110, sample: 52,
  segs: [{at: 0, clip: C + 's5-people.mov', from: 1.3, dur: 26, still: C + 's5-people-end.png'}, {at: 52, still: 'screens/ios_create.png'}],
  zoom: [[0, 1.12, 201, 300], [30, 1.12, 201, 300], [44, 1, 201, 437], [110, 1.04, 201, 437]],
  touches: [{at: 3, x: 197, y: 154}],
  pops: [{src: C + 's5-people-end.png', rect: [130, 136, 133, 38], at: 22, until: 48, ty: 980, s: 1.9, rz: -4, glow: 'rgba(47,99,196,.7)'}],
};
// prod: справжній список «Знайти місто» → тап → п'ять міст на біт; жодних карток і лічильників
const CYCLE_AT = 20;
const BEAT_C = 12;
const UI_CITIES: Demo = {
  glow: AMBER, len: 110,
  segs: [{at: 0, still: P + 'picker.png'}, ...CYCLE.map(([, k], i) => ({at: CYCLE_AT + i * BEAT_C, still: P + `city-${k}.png`}))],
  zoom: [[0, 1.15, 201, 720], [16, 1.15, 201, 720], [24, 1, 201, 437], [110, 1.05, 201, 437]],
  touches: [{at: 14, x: 75, y: 640}],
  pops: [],
  blur: CARD_BLURS.map((rect) => ({rect, from: CYCLE_AT, until: 999})),
};

const T = {hook: 0, map: 170, open: 275, friends: 365, company: 440, people: 560, cities: 670, pick: 775, logo: 885};
const KYIV = proj(CITY[0]);

// Спокійний трек (Sonilo, 32 с): тихіший вступ до 8 с, рівна основна частина, затихає на 30 с — якраз під логотип
const Music = () => (
  <Audio src={staticFile('music/calm.m4a')}
    volume={(fr) => interpolate(fr, [0, 3, HYBRID_FRAMES - 20, HYBRID_FRAMES], [0, 1, 1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})} />
);

export const Hybrid = ({music = true}: {music?: boolean}) => {
  useFonts();
  const ui: [number, Demo][] = [[T.map, UI_MAP], [T.open, UI_OPEN], [T.company, UI_COMPANY], [T.people, UI_PEOPLE], [T.pick, UI_CITIES]];
  const wipes = [T.friends, T.company, T.people, T.cities, T.pick, T.logo];
  return (
    <AbsoluteFill style={{background: INK, overflow: 'hidden'}}>
      {music && <Music />}
      {[2, 5, 8, 11, 14, 17].map((t, i) => <Sfx key={`h${i}`} at={t} src={`pin_pop_${(i % 3) + 1}`} volume={0.22} />)}
      {[48, 52, 56].map((t, i) => <Sfx key={`k${i}`} at={t} src={`pin_pop_${i + 1}`} volume={0.35} />)}
      {CHIPS.map((_, i) => <Sfx key={`c${i}`} at={92 + i * 3} src="ui_tick" volume={0.2} />)}
      <Sfx at={SUCK} src="whoosh" volume={0.3} />
      <Sfx at={SUCK + 12} src="pin_pop_3" volume={0.4} />
      {wipes.map((t) => <Sfx key={t} at={t - 3} src="whoosh" volume={0.25} />)}
      {ui.flatMap(([at, d]) => d.touches.map((t, i) => <Sfx key={`t${at}${i}`} at={at + t.at} src="ui_tick" volume={0.3} />))}
      {ui.flatMap(([at, d]) => d.pops.map((p, i) => <Sfx key={`p${at}${i}`} at={at + p.at} src={`pin_pop_${(i % 3) + 1}`} volume={0.26} />))}
      {BAIL.map((_, i) => <Sfx key={`b${i}`} at={T.friends + 12 + i * 13} src={`pin_pop_${i + 1}`} volume={0.3} />)}
      {CYCLE.map((_, i) => <Sfx key={`cy${i}`} at={T.pick + CYCLE_AT + i * BEAT_C} src="ui_tick" volume={0.28} />)}
      {CITY.map((_, i) => <Sfx key={`ci${i}`} at={T.cities + (i === 0 ? 2 : 22 + (i - 1) * 12)} src={`pin_pop_${(i % 3) + 1}`} volume={0.3} />)}

      <Sequence durationInFrames={T.map + 4}><Hook /></Sequence>
      <Sequence from={T.map} durationInFrames={T.open - T.map + 4}>
        <UIScene d={UI_MAP} intro caps={[
          {at: 0, brand: true, still: true, light: 'збирає їх', heavy: 'на одну мапу'},
          {at: 46, light: 'тапаєш «Вихідні» —', heavy: events(WEEKEND), color: CORAL, size: 112},
        ]} />
      </Sequence>
      <Sequence from={T.open} durationInFrames={T.friends - T.open + 20}>
        <UIScene d={UI_OPEN} caps={[
          {at: 0, light: 'знаходиш —', heavy: 'відкриваєш'},
          {at: 46, light: 'коли й за скільки —', heavy: 'одразу'},
        ]} />
      </Sequence>
      <Sequence from={T.friends} durationInFrames={T.company - T.friends + 20}>
        <Wipe at={0} x={540} y={1150} color={VIOLET}><Friends /></Wipe>
      </Sequence>
      <Sequence from={T.company} durationInFrames={T.people - T.company + 20}>
        <Wipe at={0} x={260} y={1010} color={BG}>
          <UIScene d={UI_COMPANY} caps={[
            {at: 0, light: 'на афіші —', heavy: 'шукаю компанію', size: 88},
            {at: 62, light: 'ті, хто теж без компанії.', heavy: 'тисни «Долучитися»', size: 74},
          ]} />
        </Wipe>
      </Sequence>
      <Sequence from={T.people} durationInFrames={T.cities - T.people + 20}>
        <Wipe at={0} x={540} y={300} color={BG}>
          <UIScene d={UI_PEOPLE} caps={[
            {at: 0, light: 'один тап —', heavy: 'події від людей', size: 92},
            {at: 52, light: 'немає потрібної? —', heavy: 'збери своїх', size: 104},
          ]} />
        </Wipe>
      </Sequence>
      <Sequence from={T.cities} durationInFrames={T.pick - T.cities + 20}>
        <Wipe at={0} x={540} y={980} color={INK}><Cities merge={false} light="не лише київ —" heavy="5 міст" /></Wipe>
      </Sequence>
      <Sequence from={T.pick} durationInFrames={T.logo - T.pick + 20}>
        <Wipe at={0} x={KYIV.x} y={KYIV.y} color={BG}>
          <UIScene d={UI_CITIES} caps={[
            {at: 0, light: 'один тап —', heavy: 'інше місто'},
            ...CYCLE.map(([n], i) => ({at: CYCLE_AT + i * BEAT_C, light: '5 міст:', heavy: n, color: AMBER, size: 130, hold: i > 0})),
            {at: CYCLE_AT + CYCLE.length * BEAT_C, light: '5 міст —', heavy: 'один\nзастосунок', size: 110},
          ]} />
        </Wipe>
      </Sequence>
      <Sequence from={T.logo}>
        <Wipe at={0} x={540} y={1080} color={INK}><Logo /></Wipe>
      </Sequence>
      <Grain />
    </AbsoluteFill>
  );
};
