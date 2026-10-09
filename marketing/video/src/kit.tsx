import React from 'react';
import {AbsoluteFill, Audio, Easing, Sequence, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';

// Спільні дрібниці роликів: згладжування, зерно, звук, наліпка, чат.

const SMOOTH = Easing.bezier(0.45, 0, 0.2, 1);
export const ease = (f: number, from: number, to: number, [a, b]: [number, number], e = SMOOTH) =>
  interpolate(f, [from, to], [a, b], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: e});

// Плівкове зерно поверх кадру
export const Grain = () => {
  const f = useCurrentFrame();
  return (
    <AbsoluteFill style={{opacity: 0.09, mixBlendMode: 'overlay', pointerEvents: 'none'}}>
      <svg width="100%" height="100%">
        <filter id="g"><feTurbulence type="fractalNoise" baseFrequency="0.85" numOctaves={2} seed={f % 60} stitchTiles="stitch" /></filter>
        <rect width="100%" height="100%" filter="url(#g)" />
      </svg>
    </AbsoluteFill>
  );
};

// Музика P2/P3 — music/zoomer.m4a (Sonilo, 130 BPM)
const MUSIC_SHIFT = 3; // перший удар zoomer.m4a на 0.10 с

export const CORAL = '#E0582F';
export const GRAD = 'linear-gradient(100deg,#FF7A45,#E0582F 45%,#8B6CFF)';

export const lively = (f: number, fps: number) => spring({frame: f, fps, config: {damping: 13, stiffness: 220, mass: 0.6}});

export const Music = ({on, frames}: {on: boolean; frames: number}) => on ? (
  <Audio src={staticFile('music/zoomer.m4a')} trimBefore={MUSIC_SHIFT}
    volume={(fr) => interpolate(fr, [0, 3, frames - 12, frames], [0, 0.85, 0.85, 0], {extrapolateRight: 'clamp'})} />
) : null;

export const Sfx = ({at: from, src, volume}: {at: number; src: string; volume: number}) => (
  <Sequence from={from} layout="none"><Audio src={staticFile(`sfx/${src}.wav`)} volume={volume} /></Sequence>
);

// Текст «друкується»: cps символів на кадр від start
export const typed = (text: string, f: number, start: number, cps = 3) => text.slice(0, Math.max(0, Math.floor((f - start) * cps)));

// Наліпка-плашка TikTok
export const Sticker = ({children, delay = 0, rotate = -3, style}: {children: React.ReactNode; delay?: number; rotate?: number; style?: React.CSSProperties}) => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  const s = lively(f - delay, fps);
  if (f < delay) return null;
  return (
    <div style={{
      display: 'inline-block', padding: '18px 34px', borderRadius: 26, background: GRAD, color: '#fff',
      fontFamily: 'Inter', fontWeight: 600, fontSize: 58, lineHeight: 1.12, letterSpacing: '-0.02em',
      boxShadow: '0 24px 60px rgba(224,88,47,.35)', transform: `scale(${s}) rotate(${rotate + (1 - s) * 12}deg)`, ...style,
    }}>{children}</div>
  );
};

export type Msg = {at: number; mine: boolean; h: number; node: React.ReactNode; raw?: boolean};
export const BUBBLE = 112;
const GAP = 16;
const BOTTOM = 1430;

export const Chat = ({msgs, typing: [t0, t1], hook, hookOut, who = 'друг', face = '🙄'}: {
  msgs: Msg[]; typing: [number, number]; hook: React.ReactNode; hookOut: number; who?: string; face?: string;
}) => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  // плавний «скрол»: кожне нове повідомлення штовхає старі вгору на свою висоту
  const lift = (i: number) => msgs.slice(i + 1).reduce((y, m) => y + (m.h + GAP) * Math.min(1, lively(f - m.at, fps)), 0);
  const typing = f >= t0 && f < t1;
  return (
    <AbsoluteFill style={{background: '#0B0B0F', fontFamily: 'Inter', color: '#F5F5F7'}}>
      {/* старі повідомлення гаснуть під шапкою */}
      <AbsoluteFill style={{maskImage: 'linear-gradient(transparent 360px, #000 470px)', WebkitMaskImage: 'linear-gradient(transparent 360px, #000 470px)'}}>
      {msgs.map((m, i) => {
        if (f < m.at) return null;
        const s = lively(f - m.at, fps);
        const y = BOTTOM - m.h - lift(i);
        if (y + m.h < 360) return null;
        return (
          <div key={i} style={{
            position: 'absolute', top: y, [m.mine ? 'right' : 'left']: 60, maxWidth: 800,
            transform: `scale(${s})`, transformOrigin: m.mine ? 'right bottom' : 'left bottom',
          }}>
            {m.raw ? m.node : (
              <div style={{
                height: BUBBLE, display: 'flex', alignItems: 'center', padding: '0 38px', borderRadius: 40, whiteSpace: 'nowrap',
                background: m.mine ? CORAL : '#26262E', fontSize: 48, letterSpacing: '-0.01em',
              }}>{m.node}</div>
            )}
          </div>
        );
      })}
      </AbsoluteFill>
      {typing && (
        <div style={{position: 'absolute', top: BOTTOM - 70, right: 60, display: 'flex', gap: 12, padding: '26px 34px', borderRadius: 40, background: '#26262E'}}>
          {[0, 1, 2].map((d) => <div key={d} style={{width: 18, height: 18, borderRadius: 9, background: '#A1A1A8', opacity: 0.35 + 0.65 * Math.max(0, Math.sin((f - d * 4) / 3))}} />)}
        </div>
      )}
      <div style={{position: 'absolute', top: 210, left: 0, right: 0, display: 'flex', flexDirection: 'column', alignItems: 'center'}}>
        <div style={{width: 84, height: 84, borderRadius: 42, background: '#26262E', fontSize: 48, display: 'flex', alignItems: 'center', justifyContent: 'center'}}>{face}</div>
        <div style={{fontWeight: 600, fontSize: 36, marginTop: 8}}>{who}</div>
      </div>
      <div style={{position: 'absolute', top: 470, left: 0, right: 0, textAlign: 'center', opacity: ease(f, hookOut - 4, hookOut, [1, 0])}}>
        <Sticker delay={0} rotate={-3}>{hook}</Sticker>
      </div>
    </AbsoluteFill>
  );
};

