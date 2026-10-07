import React from 'react';
import {
  AbsoluteFill, Audio, Easing, Img, OffthreadVideo, Sequence, interpolate, spring, staticFile,
  useCurrentFrame, useVideoConfig,
} from 'remotion';
import {useFonts} from './Ad15';

// Спокійніша версія в дусі презентацій Apple: наплави на біт, 3D-телефон, плавні наїзди на UI.
// Фон і музика — Higgsfield: hf/city2.mp4 (інтро), hf/lights.mp4 (світло сцени), music/slow.m4a (100 BPM).
const B = 18; // 100 BPM при 30 fps
const MUSIC_SHIFT = 3; // перший удар треку на 0.11 с
const XF = 12; // тривалість наплаву між сценами

const BG = '#000';
export const INK = '#F5F5F7';
export const GRAD = 'linear-gradient(90deg,#FF7A45 0%,#E0582F 35%,#8B6CFF 100%)';

// Екран телефону: пропорції знімків симулятора 1206×2622
export const SW = 600;
export const SH = Math.round(SW * 2622 / 1206);
const BEZEL = 14;
const PHONE_X = (1080 - SW) / 2 - BEZEL;
const PHONE_Y = 500;

const SMOOTH = Easing.bezier(0.45, 0, 0.2, 1);
export const ease = (f: number, from: number, to: number, [a, b]: [number, number], e = SMOOTH) =>
  interpolate(f, [from, to], [a, b], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: e});
const soft = (f: number, fps: number) => spring({frame: f, fps, config: {damping: 26, stiffness: 70, mass: 1.2}});

const Glow = () => {
  const f = useCurrentFrame();
  return (
    <AbsoluteFill style={{background: BG}}>
      <div style={{
        position: 'absolute', inset: -400, opacity: 0.55,
        background: `radial-gradient(800px 700px at ${70 + Math.sin(f / 70) * 8}% 30%, #3B2F8F 0%, transparent 70%),
                     radial-gradient(700px 600px at 20% ${85 + Math.cos(f / 80) * 5}%, #E0582F66 0%, transparent 70%)`,
      }} />
    </AbsoluteFill>
  );
};

// Повноекранне відео з Higgsfield, приглушене, щоб текст і телефон читались
export const Footage = ({src, dim, blur = 0, rate = 1}: {src: string; dim: number; blur?: number; rate?: number}) => (
  <AbsoluteFill>
    <OffthreadVideo src={staticFile(src)} muted playbackRate={rate}
      style={{width: '100%', height: '100%', objectFit: 'cover', filter: blur ? `blur(${blur}px)` : undefined, transform: blur ? 'scale(1.08)' : undefined}} />
    <AbsoluteFill style={{background: `rgba(0,0,0,${dim})`}} />
  </AbsoluteFill>
);

// Слова з'являються по черзі: розмиття → різкість, знизу вгору
const Words = ({text, grad = [], size = 96, top, stagger = 5, font = 'Inter'}: {
  text: string; grad?: number[]; size?: number; top?: number; stagger?: number; font?: string;
}) => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  const words = text.split(' ');
  return (
    <div style={{
      position: 'absolute', left: 60, right: 60, textAlign: 'center',
      ...(top === undefined ? {top: 0, bottom: 0, display: 'flex', alignItems: 'center', justifyContent: 'center'} : {top}),
    }}>
      <div style={{fontFamily: font, fontWeight: 600, fontSize: size, lineHeight: 1.05, letterSpacing: '-0.035em', color: INK}}>
        {words.map((w, i) => {
          const s = soft(f - i * stagger, fps);
          return (
            <span key={i} style={{
              display: 'inline-block', marginRight: '0.24em', opacity: s,
              filter: `blur(${(1 - s) * 16}px)`, transform: `translateY(${(1 - s) * 36}px)`,
              ...(grad.includes(i) ? {backgroundImage: GRAD, WebkitBackgroundClip: 'text', color: 'transparent'} : {}),
            }}>{w}</span>
          );
        })}
      </div>
    </div>
  );
};

type Cam = {rx?: number; ry?: number; rz?: number; x?: number; y?: number; s?: number; fx?: number; fy?: number};

// Телефон у 3D. fx/fy — точка екрана (0..1), навколо якої «камера» наїжджає масштабом s
export const Phone = ({cam, children, width = SW}: {cam: Cam; children: React.ReactNode; width?: number}) => {
  const {rx = 0, ry = 0, rz = 0, x = 0, y = 0, s = 1, fx = 0.5, fy = 0.5} = cam;
  const k = width / SW;
  return (
    <AbsoluteFill style={{perspective: 2600}}>
      <div style={{
        position: 'absolute', left: PHONE_X, top: PHONE_Y, padding: BEZEL * k, borderRadius: 92 * k,
        background: 'linear-gradient(160deg,#4a4a50,#111113 40%,#2a2a2e)',
        boxShadow: '0 0 0 2px #55555c, 0 80px 160px rgba(0,0,0,.7)',
        transformOrigin: `${BEZEL + fx * SW}px ${BEZEL + fy * SH}px`,
        transform: `translate(${x}px,${y}px) rotateX(${rx}deg) rotateY(${ry}deg) rotateZ(${rz}deg) scale(${s * k})`,
      }}>
        <div style={{width: SW, height: SH, borderRadius: 78, overflow: 'hidden', position: 'relative', background: '#fff'}}>
          {children}
        </div>
      </div>
    </AbsoluteFill>
  );
};

export const Screen = ({src}: {src: string}) => <Img src={staticFile(`screens/${src}.png`)} style={{width: SW, height: SH}} />;

// ── Шоти (кожен знає лише свій локальний час) ────────────────────────

const IntroShot = () => {
  const f = useCurrentFrame();
  const {durationInFrames} = useVideoConfig();
  const lines = ['Концерти.', 'Театр.', 'Стендап.', 'Виставки.'];
  const out = ease(f, 4 * B - 8, 4 * B + 4, [1, 0]);
  return (
    <>
      <Footage src="hf/city2.mp4" dim={ease(f, 0, durationInFrames, [0.35, 0.6])} />
      <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center', opacity: out}}>
        {lines.map((l, i) => (
          <Sequence key={l} from={i * B} layout="none">
            <Line text={l} />
          </Sequence>
        ))}
      </AbsoluteFill>
      <Sequence from={4 * B} layout="none">
        <Words text="Усе — поряд." grad={[2]} size={150} stagger={6} />
      </Sequence>
    </>
  );
};

const Line = ({text}: {text: string}) => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  const s = soft(f, fps);
  return (
    <div style={{
      fontFamily: 'Inter', fontWeight: 600, fontSize: 150, letterSpacing: '-0.045em', lineHeight: 1.08, color: INK,
      opacity: s, filter: `blur(${(1 - s) * 18}px)`, transform: `translateY(${(1 - s) * 40}px) scale(${1.06 - s * 0.06})`,
    }}>{text}</div>
  );
};

const HomeShot = () => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  const p = spring({frame: f, fps, config: {damping: 24, stiffness: 40, mass: 1.3}});
  return (
    <>
      <Words top={200} text="Уся афіша міста." grad={[1, 2]} />
      <Phone cam={{rx: (1 - p) * 40, ry: (1 - p) * -28 + Math.sin(f / 40) * 3, y: (1 - p) * 900, s: 0.84 + p * 0.16}}>
        {/* лише стрічка з постерами; плавний скрол у записі з 24.8 до 27.7 с (палець кроком 16 мс) */}
        <OffthreadVideo src={staticFile('clips/home_posters.mp4')} trimBefore={Math.round(24.8 * 30)} playbackRate={1.03} muted
          style={{width: SW, height: SH}} />
      </Phone>
    </>
  );
};

const Counter = ({to, delay}: {to: number; delay: number}) => {
  const f = useCurrentFrame();
  const n = Math.round(ease(f, delay, delay + 40, [0, to], Easing.out(Easing.cubic)));
  return <>{n}</>;
};

const MapShot = () => {
  const f = useCurrentFrame();
  const z = ease(f, 2 * B, 3 * B + XF, [1, 1.6]);
  return (
    <>
      <div style={{position: 'absolute', top: 150, left: 0, right: 0, textAlign: 'center', fontFamily: 'Inter', color: INK}}>
        <div style={{
          fontSize: 210, fontWeight: 600, letterSpacing: '-0.05em', lineHeight: 1,
          backgroundImage: GRAD, WebkitBackgroundClip: 'text', color: 'transparent',
        }}><Counter to={850} delay={4} />+</div>
        <div style={{fontSize: 56, fontWeight: 600, letterSpacing: '-0.02em', opacity: ease(f, 8, 22, [0, 1])}}>подій на мапі Києва</div>
      </div>
      <Phone cam={{s: z, fx: 0.42, fy: 0.42, ry: ease(f, 0, 3 * B, [8, -6]), y: 60}}>
        <Screen src="map_posters" />
      </Phone>
    </>
  );
};

const DetailShot = () => {
  const f = useCurrentFrame();
  const z = ease(f, B, 3 * B, [1, 1.9]);
  const ring = (f % 24) / 24;
  return (
    <>
      <Words top={200} text="Нема з ким піти?" grad={[1]} />
      <Phone cam={{s: z, fx: 0.5, fy: 0.915, ry: ease(f, 0, 3 * B, [-10, 4]), rz: ease(f, 0, 3 * B, [-2, 0])}}>
        <Screen src="ios_detail" />
        <div style={{
          position: 'absolute', left: SW * 0.07, width: SW * 0.86, top: SH * 0.915 - 34, height: 68, borderRadius: 34,
          border: '3px solid #E0582F', opacity: ease(f, B, B + 10, [0, 1]) * (1 - ring * 0.7), transform: `scale(${1 + ring * 0.05})`,
        }} />
      </Phone>
    </>
  );
};

const CompanionsShot = () => {
  const f = useCurrentFrame();
  const up = ease(f, 4, 24, [SH, 0]);
  return (
    <>
      <Words top={200} text="Знайди компанію." grad={[1]} />
      <Phone cam={{s: ease(f, 0, 3 * B, [1, 1.08]), fy: 0.4, ry: ease(f, 0, 3 * B, [6, -4])}}>
        <Screen src="ios_detail" />
        <div style={{position: 'absolute', inset: 0, transform: `translateY(${up}px)`}}><Screen src="ios_companions" /></div>
      </Phone>
    </>
  );
};

const SafetyShot = () => {
  const f = useCurrentFrame();
  return (
    <>
      <Words top={200} text="Укриття — поруч." grad={[2]} />
      <Phone cam={{s: ease(f, B, 3 * B + XF, [1, 1.5]), fx: 0.5, fy: 0.5, ry: ease(f, 0, 3 * B, [-8, 4])}}>
        <Screen src="ios_safety" />
      </Phone>
    </>
  );
};

const CreateShot = () => {
  const f = useCurrentFrame();
  return (
    <>
      <Words top={200} text="Збери своїх." grad={[1]} />
      <Phone cam={{s: ease(f, B, 3 * B + XF, [1, 1.4]), fx: 0.5, fy: 0.72, ry: ease(f, 0, 3 * B, [8, -4])}}>
        <Screen src="ios_create" />
      </Phone>
    </>
  );
};

// Ряд телефонів, що пропливає — як «лінійка» у презентаціях
const LineupShot = () => {
  const f = useCurrentFrame();
  const {fps, durationInFrames} = useVideoConfig();
  const shots = ['home_posters', 'map_posters', 'ios_detail', 'ios_safety', 'ios_create'];
  const pan = ease(f, 0, durationInFrames, [260, -260], Easing.inOut(Easing.sin));
  return (
    <>
      {shots.map((s, i) => {
        const r = soft(f - i * 3, fps);
        return (
          <Phone key={s} width={SW * 0.46} cam={{x: (i - 2) * 300 + pan, y: (1 - r) * 700 - 120 + Math.abs(i - 2) * 30, ry: (i - 2) * -9}}>
            <Screen src={s} />
          </Phone>
        );
      })}
      <Words top={260} text="Усе місто — в одному застосунку." grad={[1]} size={78} stagger={3} />
    </>
  );
};

const EndCard = () => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  const s = spring({frame: f, fps, config: {damping: 18, stiffness: 80}});
  const s2 = soft(f - 8, fps);
  const s3 = soft(f - 18, fps);
  return (
    <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center', color: INK, fontFamily: 'Inter', background: BG}}>
      <Img src={staticFile('icon.png')} style={{
        width: 280, height: 280, borderRadius: 64, transform: `scale(${s})`,
        boxShadow: '0 40px 100px rgba(224,88,47,.35)',
      }} />
      <div style={{
        fontFamily: "'Source Serif 4'", fontWeight: 600, fontSize: 170, marginTop: 50, letterSpacing: '-0.02em',
        opacity: s2, filter: `blur(${(1 - s2) * 12}px)`,
      }}>Поряд</div>
      <div style={{fontSize: 54, marginTop: 6, opacity: s2 * 0.7}}>Афіша твого міста</div>
      <div style={{
        marginTop: 90, padding: '30px 66px', borderRadius: 100, background: INK, color: '#000',
        fontSize: 50, fontWeight: 600, opacity: s3, transform: `translateY(${(1 - s3) * 40}px)`,
      }}>Безкоштовно в App Store</div>
    </AbsoluteFill>
  );
};

// Наплав: сцена з'являється за XF кадрів і лежить поверх попередньої, яка ще грає
const Fade = ({children}: {children: React.ReactNode}) => {
  const f = useCurrentFrame();
  return <AbsoluteFill style={{opacity: ease(f, 0, XF, [0, 1])}}>{children}</AbsoluteFill>;
};

// ── Монтаж (у бітах) ─────────────────────────────────────────────────
const CUTS: [number, number, React.FC][] = [
  [7, 11, HomeShot],
  [11, 14, MapShot],
  [14, 17, DetailShot],
  [17, 20, CompanionsShot],
  [20, 23, SafetyShot],
  [23, 26, CreateShot],
  [26, 29, LineupShot],
  [29, 34, EndCard],
];
export const PROMO_FRAMES = 34 * B;

export const Promo = () => {
  useFonts();
  return (
    <AbsoluteFill style={{overflow: 'hidden'}}>
      <Glow />
      {/* світло сцени під телефоном — від першого телефона до лінійки */}
      <Sequence from={7 * B - XF} durationInFrames={22 * B + XF}>
        <Fade><Footage src="hf/lights.mp4" dim={0.45} blur={6} rate={0.75} /></Fade>
      </Sequence>
      <Audio src={staticFile('music/slow.m4a')} trimBefore={MUSIC_SHIFT}
        volume={(fr) => interpolate(fr, [0, 4, PROMO_FRAMES - 45, PROMO_FRAMES - 15], [0, 1, 1, 0], {extrapolateRight: 'clamp'})} />
      <Sequence durationInFrames={7 * B + XF}><IntroShot /></Sequence>
      {CUTS.map(([a, b, Shot]) => (
        <Sequence key={a} from={a * B - XF} durationInFrames={(b - a) * B + XF}><Fade><Shot /></Fade></Sequence>
      ))}
    </AbsoluteFill>
  );
};
