import React from 'react';
import {AbsoluteFill, Audio, Easing, Img, Sequence, interpolate, random, spring, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {useFonts} from './fonts';
import {Grain, Sfx, ease} from './kit';

// Motion design «Поряд» (24 с, 9:16): продукт, зібраний з векторних форм у кольорах бренду.
// Пін падає → розмножується в мапу міста → стає карткою події → «шукаю компанію» заповнюється →
// події від людей → 5 міст з'єднуються → усе стягується в іконку.
// Музика music/brand.m4a: з 16.0 с треку (дроп = кадр 0), далі ще раз з 18.0 с. Доля 15 кадрів, такт 60.
export const MOTION_FRAMES = 720;

export const INK = '#0B0B0F';
export const PAPER = '#F5F5F7';
export const CORAL = '#E0582F';
export const VIOLET = '#6D4AC9';
export const BLUE = '#2F63C4';
export const AMBER = '#E8A33D';
const GREEN = '#3DAA6B';
const UNB = 'Unbounded';
export const SMOOTH = Easing.bezier(0.65, 0, 0.35, 1);

export const pop = (f: number, fps: number, damping = 12, stiffness = 170) => spring({frame: f, fps, config: {damping, stiffness, mass: 0.7}});

// ── Примітиви ────────────────────────────────────────────────────────

export const Pin = ({size, color = CORAL, dot = '#fff', style}: {size: number; color?: string; dot?: string; style?: React.CSSProperties}) => (
  <svg width={size} height={size * 1.3} viewBox="0 0 100 130" style={{overflow: 'visible', ...style}}>
    <path d="M50 2 C24 2 4 22 4 48 C4 80 50 128 50 128 C50 128 96 80 96 48 C96 22 76 2 50 2 Z" fill={color} />
    <circle cx="50" cy="48" r="17" fill={dot} />
  </svg>
);

// Слова, що піднімаються по літерах
export const Kinetic = ({text, at, size, weight = 900, color = '#fff', stagger = 1.2, style}: {
  text: string; at: number; size: number; weight?: number; color?: string; stagger?: number; style?: React.CSSProperties;
}) => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  return (
    <div style={{fontFamily: UNB, fontWeight: weight, fontSize: size, color, letterSpacing: '-0.045em', lineHeight: 1, whiteSpace: 'pre', ...style}}>
      {[...text].map((ch, i) => {
        if (ch === '\n') return <br key={i} />;
        const p = pop(f - at - i * stagger, fps, 14, 200);
        return (
          <span key={i} style={{display: 'inline-block', transform: `translateY(${(1 - p) * 0.9}em) rotate(${(1 - p) * 8}deg)`, opacity: Math.min(1, p * 1.5)}}>
            {ch}
          </span>
        );
      })}
    </div>
  );
};

// Сцена, що відкривається колом з точки дії
export const Wipe = ({at, x, y, color, children}: {at: number; x: number; y: number; color: string; children: React.ReactNode}) => {
  const f = useCurrentFrame();
  const r = ease(f, at, at + 16, [0, 2300], SMOOTH);
  if (f < at) return null;
  return (
    <AbsoluteFill style={{clipPath: `circle(${r}px at ${x}px ${y}px)`, background: color}}>
      {children}
    </AbsoluteFill>
  );
};

export const Head = ({light, heavy, at, color = '#fff', heavySize = 104, top = 260}: {light: string; heavy: string; at: number; color?: string; heavySize?: number; top?: number}) => (
  <div style={{position: 'absolute', top, left: 70, right: 70}}>
    <Kinetic text={light} at={at} size={68} weight={300} color={color} stagger={0.8} />
    <Kinetic text={heavy} at={at + 6} size={heavySize} color={color} style={{marginTop: 10}} />
  </div>
);

// ── Бренд-елементи для всіх роликів ──────────────────────────────────
// Назва в кадрі з першої секунди: іконка + «Поряд» з великої (у реченні «поряд» читається як «неподалік»).
export const Lockup = ({until = 9999, top = 258, left = 66}: {until?: number; top?: number; left?: number}) => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  const k = pop(f, fps, 12, 200);
  return (
    <div style={{position: 'absolute', top, left, display: 'flex', alignItems: 'center', gap: 14, opacity: ease(f, until - 6, until, [1, 0]), transform: `scale(${k})`, transformOrigin: 'left center'}}>
      <Img src={staticFile('icon.png')} style={{width: 58, height: 58, borderRadius: 14, boxShadow: '0 8px 24px rgba(224,88,47,.45)'}} />
      <div style={{fontFamily: UNB, fontWeight: 900, fontSize: 40, letterSpacing: '-0.04em', color: CORAL}}>Поряд</div>
    </div>
  );
};

// Офіційний бейдж Apple (uk-ua, toolbox.marketingtools.apple.com): без змін і без анімації, один на ролик,
// з чистим полем ≥ ¼ висоти; наприкінці — рядок про торговельні марки.
export const StoreBadge = ({at, top}: {at: number; top: number}) => {
  const f = useCurrentFrame();
  if (f < at) return null;
  return (
    <>
      <div style={{position: 'absolute', top, left: 0, right: 0, display: 'flex', justifyContent: 'center'}}>
        <Img src={staticFile('appstore-badge-uk.svg')} style={{height: 104}} />
      </div>
      <div style={{position: 'absolute', top: top + 104 + 40, left: 80, right: 80, textAlign: 'center', fontFamily: 'Inter', fontSize: 22, lineHeight: 1.3, color: '#6E6E78'}}>
        Apple, логотип Apple і App Store є торговельними марками Apple Inc.
      </div>
    </>
  );
};

// Позначка на кадрах з тестовими даними (dev): лічильники й зустрічі там не справжня активність
export const Sample = ({from = 0, until = 9999, top = 548}: {from?: number; until?: number; top?: number}) => {
  const f = useCurrentFrame();
  if (f < from || f >= until) return null;
  return (
    <div style={{position: 'absolute', top, right: 228, padding: '8px 20px', borderRadius: 22, background: 'rgba(255,255,255,.14)', border: '1px solid rgba(255,255,255,.22)',
      fontFamily: 'Inter', fontWeight: 600, fontSize: 28, color: '#E5E5EA', opacity: ease(f, from, from + 6, [0, 1])}}>приклад</div>
  );
};

// ── A · пін (0–75) ───────────────────────────────────────────────────
export const PinDrop = () => {
  const f = useCurrentFrame();
  const fall = ease(f, 0, 10, [-900, 0], Easing.in(Easing.quad));
  const impact = f >= 10 ? Math.exp(-(f - 10) / 5) * Math.cos((f - 10) / 2.2) : 0;
  const sx = 1 + 0.28 * impact;
  const sy = 1 - 0.28 * impact;
  const out = ease(f, 62, 75, [1, 0.32], SMOOTH);
  return (
    <AbsoluteFill style={{background: INK}}>
      <div style={{position: 'absolute', top: 360, left: 0, right: 0, textAlign: 'center'}}>
        <Kinetic text={'куди піти\nв києві?'} at={14} size={104} />
      </div>
      {[0, 1, 2].map((i) => {
        const k = ease(f, 10 + i * 6, 40 + i * 6, [0, 1], Easing.out(Easing.cubic));
        return k > 0 && k < 1 ? (
          <div key={i} style={{position: 'absolute', left: 540 - 300 * k, top: 1080 - 90 * k, width: 600 * k, height: 180 * k, borderRadius: '50%',
            border: `${6 * (1 - k)}px solid ${CORAL}`, opacity: 1 - k}} />
        ) : null;
      })}
      <div style={{position: 'absolute', left: 540 - 110, top: 1080 - 286 + fall, transformOrigin: '50% 100%', transform: `scale(${sx * out}, ${sy * out})`}}>
        <Pin size={220} />
      </div>
    </AbsoluteFill>
  );
};

// ── B · мапа міста (60–195) ──────────────────────────────────────────
const PALETTE = [CORAL, VIOLET, BLUE, AMBER, GREEN, CORAL, CORAL];
const PINS = Array.from({length: 150}, (_, i) => {
  const x = 70 + random(`px${i}`) * 940;
  const y = 600 + random(`py${i}`) * 950;
  return {x, y, c: PALETTE[Math.floor(random(`pc${i}`) * PALETTE.length)], s: 22 + random(`ps${i}`) * 22, d: Math.hypot(x - 540, y - 1080)};
}).filter((p) => Math.hypot(p.x - 540, p.y - 1080) > 70);
const STREETS = Array.from({length: 22}, (_, i) => {
  const horiz = i % 2 === 0;
  const a = random(`sa${i}`) * 1080;
  const b = a + (random(`sb${i}`) - 0.5) * 500;
  return horiz ? `M -40 ${560 + random(`sy${i}`) * 1000} L 1120 ${560 + random(`sz${i}`) * 1000}` : `M ${a} 540 L ${b} 1620`;
});

export const CityMap = ({dive: diveOn = true}: {dive?: boolean}) => {
  const f = useCurrentFrame(); // локальний, 0 = кадр 60
  const {fps} = useVideoConfig();
  const n = Math.round(ease(f, 30, 85, [0, 2000], Easing.out(Easing.cubic)));
  const dive = diveOn ? ease(f, 108, 135, [1, 9], Easing.in(Easing.cubic)) : 1;
  return (
    <AbsoluteFill style={{background: INK}}>
      <AbsoluteFill style={{transformOrigin: '540px 1080px', transform: `scale(${dive})`}}>
        <svg width={1080} height={1920} style={{position: 'absolute'}}>
          {STREETS.map((d, i) => (
            <path key={i} d={d} pathLength={1} stroke="#2A2A33" strokeWidth={i % 3 ? 3 : 7} fill="none"
              strokeDasharray={1} strokeDashoffset={1 - ease(f, i * 1.5, 30 + i * 1.5, [0, 1], SMOOTH)} />
          ))}
          <path d="M 760 520 C 640 760, 900 900, 700 1150 S 560 1500, 760 1680" pathLength={1} stroke="#1E2A44" strokeWidth={70} fill="none"
            strokeLinecap="round" strokeDasharray={1} strokeDashoffset={1 - ease(f, 4, 44, [0, 1], SMOOTH)} />
        </svg>
        {PINS.map((p, i) => {
          const k = pop(f - 14 - p.d / 22, fps, 11, 220);
          return k > 0.01 ? (
            <div key={i} style={{position: 'absolute', left: p.x - p.s / 2, top: p.y - p.s * 1.3, transformOrigin: '50% 100%', transform: `scale(${k})`}}>
              <Pin size={p.s} color={p.c} />
            </div>
          ) : null;
        })}
        <div style={{position: 'absolute', left: 540 - 28, top: 1080 - 73, transformOrigin: '50% 100%', transform: `scale(${pop(f - 2, fps)})`}}>
          <Pin size={56} />
        </div>
      </AbsoluteFill>
      <AbsoluteFill style={{background: `linear-gradient(${INK} 0px, ${INK}E6 560px, ${INK}00 820px)`, opacity: ease(f, 24, 34, [0, 1]) * ease(f, 100, 112, [1, 0])}} />
      <div style={{position: 'absolute', top: 250, left: 70, right: 70, opacity: ease(f, 100, 112, [1, 0])}}>
        <div style={{fontFamily: UNB, fontWeight: 900, fontSize: 170, color: '#fff', letterSpacing: '-0.06em', lineHeight: 1, fontVariantNumeric: 'tabular-nums',
          opacity: ease(f, 28, 34, [0, 1])}}>{n.toLocaleString('uk-UA')}+</div>
        <Kinetic text="подій щомісяця" at={44} size={56} weight={300} style={{marginTop: 18}} />
        <Kinetic text="на одній мапі" at={56} size={56} weight={300} color={CORAL} style={{marginTop: 8}} />
      </div>
    </AbsoluteFill>
  );
};

// ── C · картка події (195–315) ───────────────────────────────────────
const CARD_W = 780;
const CARD_H = 940;
const CARD_TOP = 600;

const EventCard = () => {
  const f = useCurrentFrame(); // 0 = кадр 195
  const {fps} = useVideoConfig();
  const m = ease(f, 0, 20, [0, 1], SMOOTH);
  const w = interpolate(m, [0, 1], [70, CARD_W]);
  const h = interpolate(m, [0, 1], [70, CARD_H]);
  const r = interpolate(m, [0, 1], [35, 56]);
  const top = interpolate(m, [0, 1], [1080 - 35, CARD_TOP]);
  const title = 'котики фест';
  const shown = Math.max(0, Math.floor((f - 24) / 1.6));
  const chip = (at: number) => pop(f - at, fps);
  const sun = pop(f - 14, fps, 10, 120);
  return (
    <AbsoluteFill style={{background: PAPER}}>
      <Head light="відкриваєш —" heavy="і все ясно" at={6} color={INK} />
      <div style={{position: 'absolute', left: 540 - w / 2, top, width: w, height: h, borderRadius: r, background: '#fff', overflow: 'hidden',
        boxShadow: `0 ${40 * m}px ${100 * m}px rgba(11,11,15,.18)`}}>
        {/* «постер» з форм */}
        <div style={{position: 'absolute', left: 0, right: 0, top: 0, height: 460 * m, background: `linear-gradient(150deg, ${AMBER}, ${CORAL} 60%, #C2461F)`, overflow: 'hidden'}}>
          <div style={{position: 'absolute', left: 470, top: 70, width: 220, height: 220, borderRadius: 110, background: '#FFD9C8', transform: `scale(${sun})`}} />
          <svg width={CARD_W} height={460} style={{position: 'absolute', left: 0, top: 0}}>
            <path d="M -20 360 C 120 260, 240 440, 400 330 S 680 260, 820 360" stroke="#fff" strokeWidth={22} fill="none" strokeLinecap="round"
              pathLength={1} strokeDasharray={1} strokeDashoffset={1 - ease(f, 16, 40, [0, 1], SMOOTH)} />
          </svg>
          <div style={{position: 'absolute', left: 40, bottom: 34, display: 'flex', gap: 14}}>
            {['сб · 11:00', 'вднг'].map((t, i) => (
              <div key={t} style={{padding: '12px 24px', borderRadius: 30, background: 'rgba(255,255,255,.92)', fontFamily: 'Inter', fontWeight: 600, fontSize: 32, color: INK,
                transform: `scale(${chip(40 + i * 5)})`, transformOrigin: 'left center'}}>{t}</div>
            ))}
          </div>
        </div>
        <div style={{position: 'absolute', left: 44, right: 44, top: 500, opacity: m}}>
          <div style={{fontFamily: UNB, fontWeight: 900, fontSize: 76, color: INK, letterSpacing: '-0.045em', height: 90}}>
            {title.slice(0, shown)}<span style={{opacity: f % 16 < 8 && shown < title.length ? 1 : 0, color: CORAL}}>|</span>
          </div>
          {/* скелет тексту, що «наливається» */}
          {[0.92, 0.7].map((wd, i) => (
            <div key={i} style={{height: 22, borderRadius: 11, background: '#EBEBF0', marginTop: 22, width: `${wd * 100 * ease(f, 30 + i * 4, 46 + i * 4, [0, 1], SMOOTH)}%`}} />
          ))}
          <div style={{display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginTop: 48}}>
            <div style={{fontFamily: 'Inter', fontWeight: 600, fontSize: 40, color: INK, transform: `scale(${chip(52)})`, transformOrigin: 'left center'}}>від 150 ₴</div>
            <div style={{padding: '24px 40px', borderRadius: 40, background: INK, color: '#fff', fontFamily: 'Inter', fontWeight: 600, fontSize: 36, transform: `scale(${chip(58)})`}}>
              купити квиток
            </div>
          </div>
          <div style={{marginTop: 22, padding: '24px 0', borderRadius: 40, background: '#EBEBF0', textAlign: 'center', fontFamily: 'Inter', fontWeight: 600, fontSize: 36, color: INK,
            transform: `scale(${chip(66)})`, boxShadow: f > 96 ? `0 0 0 ${6 * Math.abs(Math.sin((f - 96) / 4))}px ${VIOLET}66` : 'none'}}>
            шукаю компанію
          </div>
        </div>
      </div>
    </AbsoluteFill>
  );
};

// ── D · шукаю компанію (300–435) ─────────────────────────────────────
export const FRIENDS = [{l: 'м', c: CORAL}, {l: 'о', c: AMBER}, {l: 'с', c: GREEN}, {l: 'д', c: BLUE}];
const SLOT_Y = 1060;
const slotX = (i: number) => 540 + (i - 1.5) * 200;

export const Company = () => {
  const f = useCurrentFrame(); // 0 = кадр 300
  const {fps} = useVideoConfig();
  const joined = FRIENDS.filter((_, i) => f >= 22 + i * 15).length;
  const full = f >= 22 + 3 * 15 + 6;
  return (
    <AbsoluteFill style={{background: VIOLET}}>
      <Head light="друзі злились?" heavy="шукаю компанію" at={4} heavySize={84} />
      {FRIENDS.map((p, i) => {
        const at = 22 + i * 15;
        const k = ease(f, at - 10, at, [0, 1], Easing.out(Easing.back(1.6)));
        const fromX = [-200, 1280, -200, 1280][i];
        const fromY = [700, 760, 1500, 1460][i];
        const land = f >= at ? pop(f - at, fps, 9, 260) : 0;
        return (
          <React.Fragment key={i}>
            <div style={{position: 'absolute', left: slotX(i) - 80, top: SLOT_Y - 80, width: 160, height: 160, borderRadius: 80, border: '6px dashed rgba(255,255,255,.4)'}} />
            {f >= at - 10 && (
              <div style={{position: 'absolute', left: interpolate(k, [0, 1], [fromX, slotX(i)]) - 80, top: interpolate(k, [0, 1], [fromY, SLOT_Y]) - 80,
                width: 160, height: 160, borderRadius: 80, background: p.c, border: '8px solid #fff', display: 'flex', alignItems: 'center', justifyContent: 'center',
                fontFamily: UNB, fontWeight: 900, fontSize: 72, color: '#fff', transform: `scale(${0.85 + 0.15 * land})`, boxShadow: '0 30px 60px rgba(0,0,0,.25)'}}>
                {p.l}
              </div>
            )}
          </React.Fragment>
        );
      })}
      <div style={{position: 'absolute', top: SLOT_Y + 140, left: 0, right: 0, textAlign: 'center', fontFamily: UNB, fontWeight: 900, fontSize: 120, color: '#fff', letterSpacing: '-0.05em'}}>
        {Math.max(1, joined)} з 4
      </div>
      {/* смужка заповнення */}
      <div style={{position: 'absolute', left: 190, right: 190, top: SLOT_Y + 300, height: 22, borderRadius: 11, background: 'rgba(255,255,255,.25)'}}>
        <div style={{width: `${ease(f, 10, 74, [25, 100], SMOOTH)}%`, height: '100%', borderRadius: 11, background: '#fff'}} />
      </div>
      {full && (
        <>
          {Array.from({length: 26}, (_, i) => {
            const a = (i / 26) * Math.PI * 2;
            const k = ease(f, 73, 100, [0, 1], Easing.out(Easing.cubic));
            return <div key={i} style={{position: 'absolute', left: 540 + Math.cos(a) * 520 * k - 10, top: SLOT_Y + Math.sin(a) * 420 * k - 10, width: 20, height: 20,
              borderRadius: i % 2 ? 10 : 4, background: [CORAL, AMBER, '#fff', GREEN][i % 4], opacity: 1 - k, transform: `rotate(${k * 360}deg)`}} />;
          })}
          <div style={{position: 'absolute', top: SLOT_Y + 380, left: 0, right: 0, textAlign: 'center'}}>
            <Kinetic text="і йдете разом" at={76} size={64} weight={300} />
          </div>
        </>
      )}
    </AbsoluteFill>
  );
};

// ── E · події від людей (420–555) ────────────────────────────────────
const Icon = ({kind}: {kind: 'dice' | 'run' | 'film'}) => (
  <svg width={150} height={150} viewBox="0 0 100 100">
    {kind === 'dice' && (<>
      <rect x="18" y="18" width="64" height="64" rx="14" fill="none" stroke={INK} strokeWidth="7" />
      {[[36, 36], [64, 64], [50, 50], [64, 36], [36, 64]].map(([x, y], i) => <circle key={i} cx={x} cy={y} r="6" fill={INK} />)}
    </>)}
    {kind === 'run' && (<>
      <path d="M22 78 L22 22 L72 34 L22 48" fill="none" stroke={INK} strokeWidth="7" strokeLinejoin="round" strokeLinecap="round" />
    </>)}
    {kind === 'film' && (<>
      <rect x="14" y="26" width="72" height="50" rx="10" fill="none" stroke={INK} strokeWidth="7" />
      <path d="M44 40 L60 51 L44 62 Z" fill={INK} />
    </>)}
  </svg>
);
const TILES: {k: 'dice' | 'run' | 'film'; t: string}[] = [{k: 'dice', t: 'настолки'}, {k: 'run', t: 'пробіжки'}, {k: 'film', t: 'кіно'}];

export const People = ({form = true}: {form?: boolean}) => {
  const f = useCurrentFrame(); // 0 = кадр 420
  const {fps} = useVideoConfig();
  const second = form && f >= 62;
  const plus = pop(f - 58, fps, 12, 160);
  const grow = ease(f, 66, 84, [0, 1], SMOOTH);
  const name = 'вечір настолок';
  return (
    <AbsoluteFill style={{background: CORAL}}>
      {!second ? <Head light="немає потрібної?" heavy="збери своїх" at={4} /> : <Head light="кілька тапів —" heavy="і подія є" at={62} />}
      {TILES.map((t, i) => {
        const k = pop(f - 14 - i * 6, fps, 11, 180);
        const away = form ? ease(f, 56, 66, [0, 1], Easing.in(Easing.cubic)) : 0;
        return (
          <div key={t.k} style={{position: 'absolute', left: 90 + i * 310, top: 760 - away * 300, width: 280, height: 360, borderRadius: 44, background: '#fff',
            display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 20,
            transform: `perspective(1200px) rotateY(${(1 - k) * 90}deg) scale(${1 - away * 0.4})`, opacity: 1 - away, boxShadow: '0 30px 60px rgba(0,0,0,.18)'}}>
            <Icon kind={t.k} />
            <div style={{fontFamily: 'Inter', fontWeight: 600, fontSize: 38, color: INK}}>{t.t}</div>
          </div>
        );
      })}
      {form && f >= 56 && (
        <div style={{position: 'absolute', left: 540 - interpolate(grow, [0, 1], [70, 400]), top: interpolate(grow, [0, 1], [1010, 700]),
          width: interpolate(grow, [0, 1], [140, 800]), height: interpolate(grow, [0, 1], [140, 560]), borderRadius: interpolate(grow, [0, 1], [70, 48]),
          background: grow < 0.5 ? INK : '#fff', transform: `scale(${grow > 0 ? 1 : plus})`, overflow: 'hidden', boxShadow: '0 40px 90px rgba(0,0,0,.25)'}}>
          {grow < 0.4 && <div style={{position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#fff', fontFamily: 'Inter', fontWeight: 300, fontSize: 110, transform: `rotate(${grow * 200}deg)`}}>+</div>}
          {grow >= 1 && (
            <div style={{padding: 48, fontFamily: 'Inter', color: INK}}>
              <div style={{fontSize: 28, fontWeight: 600, letterSpacing: '0.12em', color: '#8E8E96'}}>НОВА ПОДІЯ</div>
              <div style={{fontFamily: UNB, fontWeight: 900, fontSize: 60, letterSpacing: '-0.045em', marginTop: 18, height: 72}}>{name.slice(0, Math.max(0, Math.floor((f - 86) / 1.4)))}</div>
              <div style={{display: 'flex', gap: 14, marginTop: 30}}>
                {['пт · 19:00', 'поділ'].map((t, i) => (
                  <div key={t} style={{padding: '12px 24px', borderRadius: 30, background: '#EBEBF0', fontWeight: 600, fontSize: 32, transform: `scale(${pop(f - 104 - i * 4, fps)})`, transformOrigin: 'left center'}}>{t}</div>
                ))}
              </div>
              <div style={{marginTop: 34, padding: '24px 0', borderRadius: 40, background: INK, color: '#fff', textAlign: 'center', fontWeight: 600, fontSize: 36,
                transform: `scale(${pop(f - 112, fps)})`}}>опублікувати</div>
            </div>
          )}
        </div>
      )}
    </AbsoluteFill>
  );
};

// ── F · 5 міст (540–645) ─────────────────────────────────────────────
export const CITY: {n: string; lat: number; lon: number}[] = [
  {n: 'київ', lat: 50.45, lon: 30.52}, {n: 'львів', lat: 49.84, lon: 24.03}, {n: 'одеса', lat: 46.48, lon: 30.73},
  {n: 'дніпро', lat: 48.46, lon: 35.05}, {n: 'харків', lat: 49.99, lon: 36.23},
];
export const proj = ({lat, lon}: {lat: number; lon: number}) => ({x: 110 + (lon - 23.6) * 0.64 * 108, y: 760 + (50.9 - lat) * 108 * 1.25});

export const Cities = ({merge: mergeOn = true, light = 'одна мапа', heavy = '5 міст'}: {merge?: boolean; light?: string; heavy?: string}) => {
  const f = useCurrentFrame(); // 0 = кадр 540
  const {fps} = useVideoConfig();
  const k0 = proj(CITY[0]);
  const merge = mergeOn ? ease(f, 92, 105, [0, 1], Easing.in(Easing.cubic)) : 0;
  return (
    <AbsoluteFill style={{background: INK}}>
      <Head light={light} heavy={heavy} at={0} heavySize={150} />
      <svg width={1080} height={1920} style={{position: 'absolute', opacity: 1 - merge}}>
        {CITY.slice(1).map((c, i) => {
          const p = proj(c);
          const mx = (k0.x + p.x) / 2;
          const my = Math.min(k0.y, p.y) - 160;
          return <path key={c.n} d={`M ${k0.x} ${k0.y} Q ${mx} ${my} ${p.x} ${p.y}`} stroke={CORAL} strokeWidth={5} fill="none" strokeLinecap="round"
            pathLength={1} strokeDasharray={1} strokeDashoffset={1 - ease(f, 10 + i * 12, 26 + i * 12, [0, 1], SMOOTH)} opacity={0.7} />;
        })}
      </svg>
      {CITY.map((c, i) => {
        const p = proj(c);
        const at = i === 0 ? 2 : 22 + (i - 1) * 12;
        const k = pop(f - at, fps, 10, 200);
        const x = interpolate(merge, [0, 1], [p.x, 540]);
        const y = interpolate(merge, [0, 1], [p.y, 1080]);
        return (
          <React.Fragment key={c.n}>
            <div style={{position: 'absolute', left: x - 28, top: y - 28, width: 56, height: 56, borderRadius: 28, background: i === 0 ? CORAL : '#fff',
              transform: `scale(${k})`, boxShadow: `0 0 0 ${14 * Math.abs(Math.sin((f - at) / 6)) * (1 - merge)}px ${CORAL}33`}} />
            <div style={{position: 'absolute', left: p.x - 200, width: 400, top: p.y + (c.n === 'одеса' ? 46 : -96), textAlign: 'center', opacity: (1 - merge) * Math.min(1, k)}}>
              <Kinetic text={c.n} at={at + 2} size={46} weight={600} stagger={0.8} />
            </div>
          </React.Fragment>
        );
      })}
    </AbsoluteFill>
  );
};

// ── G · знак (645–720) ───────────────────────────────────────────────
export const Logo = () => {
  const f = useCurrentFrame(); // 0 = кадр 645
  const {fps} = useVideoConfig();
  const sq = pop(f - 2, fps, 13, 150);
  const pin = pop(f, fps, 9, 220);
  return (
    <AbsoluteFill style={{background: INK, alignItems: 'center'}}>
      <AbsoluteFill style={{background: `radial-gradient(900px 900px at 50% 46%, #3A2560, transparent 70%)`, opacity: sq}} />
      <div style={{position: 'absolute', top: 600, left: 540 - 140, width: 280, height: 280, borderRadius: 66, background: '#16161B',
        transform: `scale(${sq})`, boxShadow: `0 50px 140px rgba(224,88,47,${0.45 * sq})`, border: '2px solid #2A2A33'}} />
      <div style={{position: 'absolute', top: 600 + 140 - 78, left: 540 - 60, transform: `scale(${pin})`}}>
        <Pin size={120} color="#fff" dot={CORAL} />
      </div>
      <div style={{position: 'absolute', top: 945, left: 0, right: 0, textAlign: 'center'}}>
        <Kinetic text="поряд" at={10} size={160} />
      </div>
      <div style={{position: 'absolute', top: 1130, left: 0, right: 0, textAlign: 'center'}}>
        <Kinetic text="твоє місто. нарешті видно." at={20} size={44} weight={300} stagger={0.4} />
      </div>
      <div style={{position: 'absolute', top: 1212, left: 0, right: 0, textAlign: 'center', fontFamily: 'Inter', fontWeight: 600, fontSize: 36, color: '#A1A1A8',
        opacity: ease(f, 28, 34, [0, 1])}}>безкоштовно</div>
      <StoreBadge at={30} top={1286} />
    </AbsoluteFill>
  );
};

export const Motion = ({music = true}: {music?: boolean}) => {
  useFonts();
  const LOOP = 14 * 30; // трек 16–30 с під фільм 0–14 с, далі ще раз з 18 с
  const wipes = [195, 300, 420, 540, 645];
  return (
    <AbsoluteFill style={{background: INK, overflow: 'hidden'}}>
      {music && (
        <>
          <Sequence durationInFrames={LOOP + 2} layout="none">
            <Audio src={staticFile('music/brand.m4a')} trimBefore={16 * 30}
              volume={(fr) => interpolate(fr, [0, 3, LOOP - 2, LOOP + 2], [0, 0.9, 0.9, 0], {extrapolateRight: 'clamp'})} />
          </Sequence>
          <Sequence from={LOOP - 2} layout="none">
            <Audio src={staticFile('music/brand.m4a')} trimBefore={18 * 30 - 2}
              volume={(fr) => interpolate(fr, [0, 4, MOTION_FRAMES - LOOP - 30, MOTION_FRAMES - LOOP], [0, 0.9, 0.9, 0], {extrapolateRight: 'clamp'})} />
          </Sequence>
        </>
      )}
      <Sfx at={10} src="pin_pop_1" volume={0.4} />
      {[0, 1, 2, 3, 4, 5].map((i) => <Sfx key={`m${i}`} at={76 + i * 6} src={`pin_pop_${(i % 3) + 1}`} volume={0.2} />)}
      <Sfx at={90} src="counter_tick" volume={0.25} />
      {wipes.map((t) => <Sfx key={t} at={t - 3} src="whoosh" volume={0.25} />)}
      {Array.from({length: 7}, (_, i) => <Sfx key={`ty${i}`} at={219 + i * 3} src="ui_tick" volume={0.18} />)}
      {FRIENDS.map((_, i) => <Sfx key={`f${i}`} at={322 + i * 15} src={`pin_pop_${(i % 3) + 1}`} volume={0.32} />)}
      {[0, 1, 2].map((i) => <Sfx key={`t${i}`} at={434 + i * 6} src="ui_tick" volume={0.25} />)}
      {CITY.map((_, i) => <Sfx key={`c${i}`} at={540 + (i === 0 ? 2 : 22 + (i - 1) * 12)} src={`pin_pop_${(i % 3) + 1}`} volume={0.3} />)}
      <Sfx at={647} src="pin_pop_3" volume={0.4} />

      <Sequence durationInFrames={76}><PinDrop /><Lockup until={72} /></Sequence>
      <Sequence from={60} durationInFrames={140}><CityMap /></Sequence>
      <Sequence from={195} durationInFrames={110}>
        <Wipe at={0} x={540} y={1080} color={PAPER}><EventCard /></Wipe>
      </Sequence>
      <Sequence from={300} durationInFrames={125}>
        <Wipe at={0} x={540} y={1430} color={VIOLET}><Company /></Wipe>
      </Sequence>
      <Sequence from={420} durationInFrames={125}>
        <Wipe at={0} x={540} y={1060} color={CORAL}><People /></Wipe>
      </Sequence>
      <Sequence from={540} durationInFrames={110}>
        <Wipe at={0} x={540} y={980} color={INK}><Cities /></Wipe>
      </Sequence>
      <Sequence from={645}>
        <Wipe at={0} x={540} y={1080} color={INK}><Logo /></Wipe>
      </Sequence>
      <Grain />
    </AbsoluteFill>
  );
};
