import React from 'react';
import {
  AbsoluteFill, Audio, Easing, Img, OffthreadVideo, Sequence, interpolate, random, spring, staticFile,
  useCurrentFrame, useVideoConfig,
} from 'remotion';
import {useFonts} from './Ad15';
import {Footage, INK, Phone, SH, SW, Screen, ease} from './Promo';
import {Grain} from './Zoomer';

// A1 «Вихідні в місті» (scripts/A1-weekend.md): 24 с, 120 BPM, B = 15 f.
// v2: хук-подія першою (орган під зорями), далі відлік 03 → 02 → 01, де 01 — та сама подія.
// Higgsfield: hf/a1-shot1.mp4 (мапа з пінами), hf/a1-organ.mp4, hf/a1-jazz.mp4, music/a1-b.m4a, sfx/*.wav.
const B = 15;
const MUSIC_SHIFT = 2; // перший удар a1-b на ~0.06 с
const MUSIC_GAIN = 0.42; // трек нормалізовано в 0 dBFS; так мікс ≈ −14 LUFS
export const A1_FRAMES = 48 * B;

const BG = '#0B0B0F';
const CORAL = '#E0582F';
const GREY = '#A1A1A8';
const SERIF = "'Source Serif 4'";
const soft = (f: number, fps: number) => spring({frame: f, fps, config: {damping: 26, stiffness: 70, mass: 1.2}});
const lively = (f: number, fps: number) => spring({frame: f, fps, config: {damping: 11, stiffness: 260, mass: 0.6}});

const Glow = ({color = '#1B1A36', x = 50, y = 55}: {color?: string; x?: number; y?: number}) => (
  <AbsoluteFill style={{background: `radial-gradient(900px 1100px at ${x}% ${y}%, ${color} 0%, transparent 70%)`}} />
);

// Текст «спливає» з розмиттям; delay — у кадрах від початку сцени
const Rise = ({delay, children, style, fast}: {delay: number; children: React.ReactNode; style?: React.CSSProperties; fast?: boolean}) => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  const s = Math.min(1, (fast ? lively : soft)(f - delay, fps));
  return <div style={{opacity: s, filter: `blur(${(1 - s) * 12}px)`, transform: `translateY(${(1 - s) * 30}px)`, ...style}}>{children}</div>;
};

// ── Сцена 1: хук — орган під зорями (0–75) ────────────────────────────
const HOOK = 75;
const Hook = () => {
  const f = useCurrentFrame();
  const out = ease(f, HOOK - 6, HOOK, [0, 1], Easing.in(Easing.cubic)); // whip вліво
  return (
    <AbsoluteFill style={{transform: `translateX(${-600 * out}px)`, filter: `blur(${40 * out}px)`}}>
      <Stars />
      {/* наїзд на труби органа; назва з постера ховається під нашим текстом */}
      <AbsoluteFill style={{transform: `translateY(170px) scale(${ease(f, 0, HOOK, [1.85, 2.0])})`, transformOrigin: '50% 54%'}}>
        <Footage src="hf/a1-organ.mp4" dim={0} />
      </AbsoluteFill>
      <AbsoluteFill style={{background: `linear-gradient(${BG} 0px, ${BG} 560px, ${BG}00 800px)`}} />
      <div style={{position: 'absolute', top: 250, left: 60, right: 60, textAlign: 'center', color: INK}}>
        <Rise fast delay={0} style={{fontFamily: SERIF, fontWeight: 600, fontSize: 104, lineHeight: 1.04, letterSpacing: '-0.02em'}}>у києві є орган,</Rise>
        <Rise fast delay={6} style={{fontFamily: SERIF, fontWeight: 600, fontSize: 104, lineHeight: 1.04, letterSpacing: '-0.02em'}}>який грає</Rise>
        <Rise fast delay={12} style={{fontFamily: "'Playfair Display'", fontStyle: 'italic', fontWeight: 600, fontSize: 140, lineHeight: 1.04, color: CORAL}}>під зорями</Rise>
      </div>
    </AbsoluteFill>
  );
};

// ── Сцена 2: обіцянка + стрічка (75–135) ────────────────────────────────────────
const Feed = () => {
  const f = useCurrentFrame();
  const t = ease(f, 0, 6, [1, 0], Easing.out(Easing.cubic));
  return (
    <AbsoluteFill style={{transform: `translateX(${600 * t}px)`, filter: `blur(${40 * t}px)`}}>
      <Glow y={70} />
      <Phone width={SW * 1.55} cam={{y: 520}}>
        <OffthreadVideo src={staticFile('clips/home_posters.mp4')} trimBefore={Math.round(24.8 * 30)} playbackRate={1.6} muted
          style={{width: SW, height: SH}} />
      </Phone>
      <div style={{position: 'absolute', top: 280, left: 80, right: 80, textAlign: 'center', color: INK}}>
        <Rise fast delay={4} style={{fontFamily: SERIF, fontWeight: 600, fontSize: 88, lineHeight: 1.08, letterSpacing: '-0.01em'}}>
          але спершу —<br />ще 2 плани
        </Rise>
      </div>
    </AbsoluteFill>
  );
};

// ── Сцени 3–5: постери (по 150 f) ────────────────────────────────────
type Pick = {
  n: string; day: string; title: string; venue: string; note?: string; poster: string; from: number; dur: number;
  clip?: string; rate?: number; ry: [number, number]; glow: [string, string]; stars?: boolean; exit: 'left' | 'right' | 'pin';
};
const PICKS: Pick[] = [
  {n: '03', day: 'СБ 18:00', title: 'Болеро. Дощ', venue: 'Kyiv Modern Ballet · Київська опера', note: 'від 250 грн', poster: '01.jpg', from: 135, dur: 135, ry: [12, -3], glow: ['#1B1A36', '#1B1A36'], exit: 'left'},
  {n: '02', day: 'НД 15:00', title: 'Бах. Джаз. Brass', venue: '«Київська троянда»', poster: '03.jpg', clip: 'hf/a1-jazz.mp4', from: 270, dur: 135, ry: [8, -2], glow: ['#1B1A36', '#3F2419'], exit: 'right'},
  // 01 — розв'язка хука; кліп 4.04 с на 0.75× покриває 161 f
  {n: '01', day: 'СБ 19:30', title: 'Орган під зорями', venue: 'Київський планетарій', note: 'до 21:30', poster: '02.jpg', clip: 'hf/a1-organ.mp4', rate: 0.75, from: 405, dur: 161, ry: [-10, 2], glow: ['#1B1A36', '#1B1A36'], stars: true, exit: 'pin'},
];
const PW = 640;
const PH = Math.round(PW * 1000 / 707);
const PTOP = 590;

const Stars = () => {
  const f = useCurrentFrame();
  return (
    <AbsoluteFill>
      {Array.from({length: 70}, (_, i) => (
        <div key={i} style={{
          position: 'absolute', left: `${random(`sx${i}`) * 100}%`, top: `${random(`sy${i}`) * 100}%`,
          width: 3 + random(`sr${i}`) * 4, height: 3 + random(`sr${i}`) * 4, borderRadius: '50%', background: '#fff',
          opacity: 0.15 + 0.6 * Math.abs(Math.sin(f / (10 + random(`sp${i}`) * 14) + i)),
        }} />
      ))}
    </AbsoluteFill>
  );
};

const PickScene = ({p}: {p: Pick}) => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  const s = soft(f, fps);
  const t = ease(f, p.dur - 30, p.dur, [0, 1], Easing.in(Easing.cubic)); // відліт
  const card = p.exit === 'pin'
    ? `translateY(${t * 380}px) scale(${1 - t * 0.97})`
    : `translate(${(p.exit === 'left' ? -700 : 700) * t}px, ${-900 * t}px) rotate(${(p.exit === 'left' ? -14 : 14) * t}deg)`;
  return (
    <AbsoluteFill>
      <AbsoluteFill style={{background: BG}} />
      <Glow color={p.glow[0]} />
      <AbsoluteFill style={{opacity: ease(f, 0, 30, [0, 1])}}><Glow color={p.glow[1]} /></AbsoluteFill>
      {p.stars && <AbsoluteFill style={{opacity: s * (1 - t)}}><Stars /></AbsoluteFill>}
      <AbsoluteFill style={{perspective: 2000}}>
        <div style={{
          position: 'absolute', left: (1080 - PW) / 2, top: PTOP, width: PW, height: PH, overflow: 'hidden', borderRadius: 6,
          boxShadow: '0 50px 120px rgba(0,0,0,.7), 0 0 0 1px rgba(255,255,255,.06)',
          transform: `${card} translateY(${ease(f, 15, p.dur - 30, [0, p.exit === 'right' ? 30 : -30])}px) rotateY(${p.ry[0] + (p.ry[1] - p.ry[0]) * s}deg) scale(${0.4 + 0.6 * s})`,
          filter: `blur(${t * 24}px)`, opacity: 1 - t * 0.6,
        }}>
          {p.clip ? (
            <OffthreadVideo src={staticFile(p.clip)} muted playbackRate={p.rate ?? 0.8} style={{width: '100%', height: '100%', objectFit: 'cover'}} />
          ) : (
            <>
              <Img src={staticFile(`posters/10-10/${p.poster}`)} style={{width: '100%', height: '100%', transform: `scale(${ease(f, 15, p.dur - 30, [1, 1.06])})`}} />
              {/* світловий відблиск по паперу */}
              <AbsoluteFill style={{
                mixBlendMode: 'screen',
                background: `linear-gradient(120deg, transparent ${ease(f, 20, 110, [-40, 100])}%, rgba(255,214,190,.28) ${ease(f, 20, 110, [-25, 115])}%, transparent ${ease(f, 20, 110, [-10, 130])}%)`,
              }} />
            </>
          )}
        </div>
      </AbsoluteFill>
      <div style={{position: 'absolute', top: 250, left: 80, right: 160, color: INK, opacity: 1 - t * 2}}>
        <div style={{display: 'flex', alignItems: 'baseline', gap: 28}}>
          <Rise delay={4} style={{fontFamily: SERIF, fontWeight: 600, fontSize: 120, lineHeight: 1, color: CORAL, opacity: 0.9}}>{p.n}</Rise>
          <Rise delay={20} style={{fontFamily: 'Inter', fontWeight: 600, fontSize: 52, letterSpacing: '0.01em'}}>
            {p.day}{p.note && <span style={{color: GREY, fontWeight: 400, fontSize: 40}}> · {p.note}</span>}
          </Rise>
        </div>
        <Rise delay={30} style={{fontFamily: SERIF, fontWeight: 600, fontSize: 84, lineHeight: 1.05, letterSpacing: '-0.01em', marginTop: 10}}>{p.title}</Rise>
        <Rise delay={42} style={{fontFamily: 'Inter', fontWeight: 400, fontSize: 40, color: GREY, marginTop: 12}}>{p.venue}</Rise>
      </div>
    </AbsoluteFill>
  );
};

// ── Сцена 6: мапа, «ще 200+» (570–630) ──────────────────────────────
// рожеві піни на map_posters.png (частки ширини/висоти екрана)
const MAP_PINS: [number, number][] = [[0.13, 0.565], [0.58, 0.635], [0.80, 0.72]];
const MapScene = () => {
  const f = useCurrentFrame();
  const n = Math.round(ease(f, 8, 32, [0, 200], Easing.out(Easing.cubic)));
  return (
    <AbsoluteFill style={{opacity: ease(f, 0, 8, [0, 1])}}>
      <AbsoluteFill style={{background: BG}} />
      <Glow color="#2A2560" y={62} />
      <Phone cam={{s: ease(f, 0, 40, [1.6, 1]), fx: 0.58, fy: 0.635, y: 140}}>
        <Screen src="map_posters" />
        {MAP_PINS.map(([x, y], i) => {
          const k = ((f - 10 - i * 8) % 30) / 30;
          return f < 10 + i * 8 ? null : (
            <div key={i} style={{
              position: 'absolute', left: x * SW - 40, top: y * SH - 40, width: 80, height: 80, borderRadius: '50%',
              border: `5px solid ${CORAL}`, opacity: 1 - k, transform: `scale(${0.6 + k * 1.2})`,
            }} />
          );
        })}
      </Phone>
      {/* поки телефон ще великий, білий текст лежить на світлій мапі */}
      <AbsoluteFill style={{background: `linear-gradient(${BG} 0px, ${BG}E6 420px, transparent 640px)`, opacity: ease(f, 20, 40, [1, 0.6])}} />
      <div style={{position: 'absolute', top: 250, left: 80, right: 80, textAlign: 'center', color: INK}}>
        <div style={{fontFamily: SERIF, fontWeight: 600, fontSize: 150, lineHeight: 1, letterSpacing: '-0.02em', textShadow: '0 10px 50px rgba(0,0,0,.6)'}}>ще {n}+</div>
        <Rise delay={12} style={{fontFamily: 'Inter', fontWeight: 600, fontSize: 44, marginTop: 16}}>на ці вихідні — на мапі</Rise>
      </div>
    </AbsoluteFill>
  );
};

// ── Сцена 7: енд-карт (630–720), стандарт бренд-біблії ────────────────
const EndCard = () => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  const s = lively(f, fps);
  return (
    <AbsoluteFill style={{background: BG, alignItems: 'center', justifyContent: 'center', color: INK}}>
      <Glow />
      <Img src={staticFile('icon.png')} style={{
        width: 240, height: 240, borderRadius: 56, transform: `scale(${s}) rotate(${(1 - s) * -20}deg)`,
        boxShadow: '0 40px 100px rgba(224,88,47,.4)',
      }} />
      <Rise delay={8} style={{fontFamily: SERIF, fontWeight: 600, fontSize: 110, marginTop: 50, letterSpacing: '-0.02em'}}>Усе — поряд.</Rise>
      <Rise delay={18} style={{fontFamily: 'Inter', fontWeight: 400, fontSize: 40, color: GREY, marginTop: 14}}>безкоштовно в App Store</Rise>
    </AbsoluteFill>
  );
};

// ── Звук ─────────────────────────────────────────────────────────────
const Sfx = ({at, src, volume}: {at: number; src: string; volume: number}) => (
  <Sequence from={at} layout="none"><Audio src={staticFile(`sfx/${src}.wav`)} volume={volume} /></Sequence>
);
const TICKS = [84, 92, 100, 108, 116, 124];

export const A1 = () => {
  useFonts();
  return (
    <AbsoluteFill style={{background: BG, overflow: 'hidden'}}>
      <Audio src={staticFile('music/a1-b.m4a')} trimBefore={MUSIC_SHIFT}
        // брейк (відбій) сцени 6 робимо гучністю: у треці його нема
        volume={(fr) => interpolate(fr, [0, 2, 566, 576, 618, 624, A1_FRAMES - 20, A1_FRAMES], [0, 1, 1, 0.35, 0.35, 1, 1, 0].map((v) => v * MUSIC_GAIN), {extrapolateRight: 'clamp'})} />
      <Sfx at={0} src="pin_pop_1" volume={0.2} />
      <Sfx at={8} src="pin_pop_2" volume={0.16} />
      <Sfx at={HOOK - 6} src="whoosh" volume={0.25} />
      {TICKS.map((at) => <Sfx key={at} at={at} src="ui_tick" volume={0.12} />)}
      {PICKS.map((p, i) => (
        <React.Fragment key={i}>
          <Sfx at={p.from} src={`pin_pop_${i + 1}`} volume={0.2} />
          {p.exit !== 'pin' && <Sfx at={p.from + p.dur - 30} src="whoosh" volume={0.25} />}
        </React.Fragment>
      ))}
      <Sfx at={578} src="counter_tick" volume={0.2} />

      <Sequence durationInFrames={HOOK}><Hook /></Sequence>
      <Sequence from={HOOK} durationInFrames={60}><Feed /></Sequence>
      {PICKS.map((p) => (
        <Sequence key={p.n} from={p.from} durationInFrames={p.dur}><PickScene p={p} /></Sequence>
      ))}
      <Sequence from={566} durationInFrames={64}><MapScene /></Sequence>
      <Sequence from={630}><EndCard /></Sequence>
      <Grain />
    </AbsoluteFill>
  );
};
