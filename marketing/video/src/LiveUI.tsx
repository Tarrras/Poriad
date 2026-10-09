import React from 'react';
import {AbsoluteFill, Easing, Img, OffthreadVideo, Sequence, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {ease} from './kit';

// Живий інтерфейс у кадрі: великий телефон майже фронтально, справжні записи з симулятора,
// макронаїзди й шматки екрана, що відриваються до глядача. Використовує Hybrid.
// Координати на екрані — у точках iOS (402×874).

export const BG = '#07070A';
const springy = (f: number, fps: number, damping = 18, stiffness = 120) => spring({frame: f, fps, config: {damping, stiffness, mass: 0.9}});

// Сяйво за телефоном
export const Aura = ({color, x = 50, y = 58, size = 1000, opacity = 1}: {color: string; x?: number; y?: number; size?: number; opacity?: number}) => (
  <AbsoluteFill style={{opacity, background: `radial-gradient(${size}px ${size * 1.1}px at ${x}% ${y}%, ${color} 0%, transparent 68%)`}} />
);

// Великий телефон майже фронтально, щоб UI читався. Координати на екрані — у точках iOS (402×874).
const PT = 402;
const SCR_W = 600;
const K = SCR_W / PT; // пікселів кадру на точку
const SCR_H = Math.round(874 * K);
const SCR_L = (1080 - SCR_W) / 2;
const SCR_T = 600;
const BEZ = 16;
export const px = (x: number) => SCR_L + x * K;
export const py = (y: number) => SCR_T + y * K;

export type Rect = [number, number, number, number]; // x, y, w, h у точках
// Шматок екрана, що відривається від телефона й піднімається до глядача
export const Pop = ({src, rect, at, until, tx = 540, ty, s = 1.18, rz = 0, glow}: {
  src: string; rect: Rect; at: number; until: number; tx?: number; ty: number; s?: number; rz?: number; glow?: string;
}) => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  if (f < at || f >= until) return null;
  const p = Math.min(1, springy(f - at, fps, 16, 130)) * ease(f, until - 8, until, [1, 0], Easing.in(Easing.cubic));
  const [x, y, w, h] = rect;
  const cx = px(x + w / 2);
  const cy = py(y + h / 2);
  return (
    <>
    {/* «гніздо» на місці піднятого елемента */}
    <div style={{position: 'absolute', left: px(x), top: py(y), width: w * K, height: h * K, borderRadius: 18 * K,
      background: `rgba(7,7,10,${0.55 * p})`, boxShadow: `inset 0 6px 18px rgba(0,0,0,${0.5 * p})`}} />
    <div style={{
      position: 'absolute', left: px(x), top: py(y), width: w * K, height: h * K, borderRadius: 18 * K,
      backgroundImage: `url(${staticFile(src)})`, backgroundSize: `${SCR_W}px ${SCR_H}px`, backgroundPosition: `${-x * K}px ${-y * K}px`,
      transform: `translate(${(tx - cx) * p}px, ${(ty - cy) * p}px) scale(${1 + (s - 1) * p}) rotate(${rz * p}deg)`,
      boxShadow: `0 ${50 * p}px ${110 * p}px rgba(0,0,0,${0.6 * p})${glow ? `, 0 0 ${60 * p}px ${glow}` : ''}`,
      outline: `${2 * p}px solid rgba(255,255,255,${0.35 * p})`,
    }} />
    </>
  );
};

// Дотик пальця на екрані
export const Touch = ({at, x, y}: {at: number; x: number; y: number}) => {
  const f = useCurrentFrame() - at;
  if (f < -4 || f > 16) return null;
  const k = Math.max(0, f) / 16;
  const press = f < 0 ? ease(f, -4, 0, [0, 1]) : 1 - k;
  return (
    <div style={{
      position: 'absolute', left: px(x) - 44, top: py(y) - 44, width: 88, height: 88, borderRadius: 44,
      background: `rgba(255,255,255,${0.35 * press})`, border: `3px solid rgba(255,255,255,${0.9 * (1 - k)})`,
      transform: `scale(${f < 0 ? 0.8 : 0.8 + k * 0.9})`, boxShadow: '0 0 30px rgba(0,0,0,.25)',
    }} />
  );
};

// Відрізок екрана: живий запис з симулятора, далі — його останній кадр
export type Seg = {at: number; clip?: string; from?: number; dur?: number; rate?: number; still: string};
// Розмиті зони екрана (постери з обличчями артистів), у точках iOS
export type Blur = {rect: Rect; until: number; from?: number};
export const LiveScreen = ({segs, blur}: {segs: Seg[]; blur?: Blur | Blur[]}) => {
  const f = useCurrentFrame();
  const blurs = Array.isArray(blur) ? blur : blur ? [blur] : [];
  return (
    <div style={{position: 'absolute', left: SCR_L, top: SCR_T, width: SCR_W, height: SCR_H, borderRadius: 64, overflow: 'hidden', background: '#fff'}}>
      {segs.map((g, i) => {
        const end = segs[i + 1]?.at ?? 10000;
        if (f < g.at || f >= end + 4) return null;
        const fade = i ? ease(f, g.at, g.at + 4, [0, 1]) : 1;
        return (
          <AbsoluteFill key={i} style={{opacity: fade}}>
            <Sequence from={g.at} layout="none">
              {g.clip && f < g.at + (g.dur ?? 0) ? (
                <OffthreadVideo src={staticFile(g.clip)} trimBefore={Math.round((g.from ?? 0) * 30)} playbackRate={g.rate ?? 1} muted
                  style={{width: SCR_W, height: SCR_H, display: 'block'}} />
              ) : (
                <Img src={staticFile(g.still)} style={{width: SCR_W, height: SCR_H, display: 'block'}} />
              )}
            </Sequence>
          </AbsoluteFill>
        );
      })}
      {blurs.filter((b) => f >= (b.from ?? 0) && f < b.until).map(({rect}, i) => (
        <div key={i} style={{position: 'absolute', left: rect[0] * K, top: rect[1] * K, width: rect[2] * K, height: rect[3] * K,
          borderRadius: 14 * K, backdropFilter: 'blur(14px)', background: 'rgba(230,230,235,.35)'}} />
      ))}
    </div>
  );
};

// Рамка телефона навколо екрана
export const Bezel = () => (
  <div style={{position: 'absolute', left: SCR_L - BEZ, top: SCR_T - BEZ, width: SCR_W + BEZ * 2, height: SCR_H + BEZ * 2, borderRadius: 80,
    background: 'linear-gradient(160deg,#4a4a50,#111113 40%,#2a2a2e)', boxShadow: '0 0 0 2px #55555c, 0 80px 160px rgba(0,0,0,.7)'}} />
);

// Затемнення екрана, поки елемент «піднято»
export const Dim = ({spans}: {spans: [number, number][]}) => {
  const f = useCurrentFrame();
  const o = Math.max(0, ...spans.map(([a, b]) => Math.min(ease(f, a, a + 8, [0, 1]), ease(f, b - 8, b, [1, 0]))));
  return <div style={{position: 'absolute', left: SCR_L, top: SCR_T, width: SCR_W, height: SCR_H, borderRadius: 64, background: `rgba(7,7,10,${0.55 * o})`}} />;
};

export type Zoom = [number, number, number, number]; // кадр, масштаб, фокус x (точки), фокус y (точки)
export const zoomAt = (f: number, keys: Zoom[]) => {
  const fr = keys.map((k) => k[0]);
  const opt = {extrapolateLeft: 'clamp' as const, extrapolateRight: 'clamp' as const, easing: Easing.inOut(Easing.cubic)};
  return {
    z: interpolate(f, fr, keys.map((k) => k[1]), opt),
    fx: interpolate(f, fr, keys.map((k) => k[2]), opt),
    fy: interpolate(f, fr, keys.map((k) => k[3]), opt),
  };
};

export type Demo = {
  glow: string; len: number;
  segs: Seg[]; zoom: Zoom[]; pops: React.ComponentProps<typeof Pop>[]; touches: {at: number; x: number; y: number}[];
  blur?: Blur | Blur[];
  sample?: number; // до якого кадру на екрані тестові дані з dev — позначка «приклад»
};

export const C = 'clips/brand/'; // dev-збірка з тестовими даними (компанія, від людей)
export const P = 'clips/prod/'; // prod-збірка 09.10: мапа, Котики Фест, вибір міста
// картки внизу мапи з постерами-фото: ліва повністю й край правої
export const CARD_BLURS: Rect[] = [[28, 650, 84, 85], [368, 650, 34, 85]];
export const CYCLE = [['київ', 'kyiv'], ['львів', 'lviv'], ['одеса', 'odesa'], ['дніпро', 'dnipro'], ['харків', 'kharkiv']];
