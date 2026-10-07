import React from 'react';
import {
  AbsoluteFill, Audio, Easing, Img, OffthreadVideo, Sequence, interpolate, spring, staticFile,
  useCurrentFrame, useVideoConfig,
} from 'remotion';
import {useFonts} from './Ad15';
import {Footage, GRAD, INK, Phone, SH, SW, Screen, ease} from './Promo';

// «Зумерська» версія: малі літери, «пов:», наліпки, м'які наплави з наїздом, зерно.
// v2: вступ B (журнальний), назва «поряд» — головний акцент, без трусіння/спалахів, плавні пружини.
// Музика — Higgsfield (Sonilo), music/zoomer.m4a.
const BPM = 130;
const B = 1800 / BPM; // кадрів на біт при 30 fps (дробове — округлюємо в at())
const MUSIC_SHIFT = 3; // перший удар треку на 0.10 с
const at = (beats: number) => Math.round(beats * B);
export const ZOOMER_FRAMES = at(32);

const PLAY = "'Playfair Display'";
const ACCENT: React.CSSProperties = {fontFamily: PLAY, fontStyle: 'italic', letterSpacing: '-0.02em'};
const STICKER_BG = 'linear-gradient(100deg,#FF7A45,#E0582F 45%,#8B6CFF)';

// 1 на кожному біті, далі швидко згасає — для «удару» масштабу й трусіння
const useKick = (offset = 0) => {
  const f = useCurrentFrame() + offset;
  const ph = f / B - Math.floor(f / B);
  return {k: Math.exp(-ph * B / 3.5), beat: Math.floor(f / B)};
};

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

// Вхід сцени: наплав поверх попередньої з легким наїздом і розмиттям
const XF = 10;
const Soft = ({children, from = 1.06}: {children: React.ReactNode; from?: number}) => {
  const f = useCurrentFrame();
  const t = ease(f, 0, XF + 4, [0, 1], Easing.out(Easing.cubic));
  return (
    <AbsoluteFill style={{transform: `scale(${from + (1 - from) * t})`, filter: `blur(${(1 - t) * 10}px)`, opacity: ease(f, 0, XF, [0, 1])}}>
      {children}
    </AbsoluteFill>
  );
};

// Слово, що «вискакує» з пружинним перебором
const Pop = ({children, delay = 0, style}: {children: React.ReactNode; delay?: number; style?: React.CSSProperties}) => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  const s = spring({frame: f - delay, fps, config: {damping: 20, stiffness: 150, mass: 0.8}});
  if (f < delay) return null;
  return <span style={{display: 'inline-block', transform: `translateY(${(1 - s) * 30}px) scale(${0.9 + s * 0.1})`, filter: `blur(${(1 - s) * 10}px)`, opacity: s, ...style}}>{children}</span>;
};

// Явний проміжок між словами-Pop: звичайний пробіл між inline-block губиться
const Gap = () => <span style={{display: 'inline-block', width: '0.3em'}} />;

const Line = ({children, top, size = 104, align = 'center'}: {children: React.ReactNode; top: number; size?: number; align?: 'center' | 'left'}) => (
  <div style={{
    position: 'absolute', top, left: 70, right: 70, textAlign: align, color: INK,
    fontFamily: 'Inter', fontWeight: 600, fontSize: size, lineHeight: 1.04, letterSpacing: '-0.045em',
  }}>{children}</div>
);

// Наліпка: градієнтна плашка з нахилом
const Sticker = ({children, delay = 0, rot = -4, size = 64, x = 0, y = 0}: {
  children: React.ReactNode; delay?: number; rot?: number; size?: number; x?: number; y?: number;
}) => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  const s = spring({frame: f - delay, fps, config: {damping: 17, stiffness: 150, mass: 0.8}});
  if (f < delay) return null;
  return (
    <div style={{
      position: 'absolute', left: '50%', top: y, transform: `translateX(-50%) translateX(${x}px) rotate(${rot}deg) scale(${s})`,
      background: STICKER_BG, color: '#fff', fontFamily: 'Inter', fontWeight: 600, fontSize: size, letterSpacing: '-0.03em',
      padding: `${size * 0.22}px ${size * 0.5}px`, borderRadius: size * 0.42, whiteSpace: 'nowrap',
      boxShadow: '0 18px 50px rgba(224,88,47,.35)',
    }}>{children}</div>
  );
};

const Grad = ({children}: {children: React.ReactNode}) => (
  <span style={{backgroundImage: GRAD, WebkitBackgroundClip: 'text', color: 'transparent'}}>{children}</span>
);

// ── Сцени ────────────────────────────────────────────────────────────

const Hook = () => {
  const {k} = useKick();
  return (
    <>
      <AbsoluteFill style={{transform: `scale(${1.08 + k * 0.05})`}}><Footage src="hf/city2.mp4" dim={0.55} /></AbsoluteFill>
      <Line top={640} size={128}>
        <Pop><span style={{
          fontSize: 70, padding: '10px 34px', borderRadius: 40, background: 'rgba(255,255,255,.14)',
          border: '2px solid rgba(255,255,255,.35)', letterSpacing: '-0.02em', verticalAlign: 'middle',
        }}>пов:</span></Pop>
        <br />
        <Pop delay={at(0.5)}>пʼятниця,</Pop>
        <br />
        <Pop delay={at(1.5)}>а планів —</Pop><Gap />
        <Pop delay={at(2.5)} style={ACCENT}><Grad>нуль.</Grad></Pop>
      </Line>
    </>
  );
};


// ── Варіанти вступу ──────────────────────────────────────────────────
const UNB = 'Unbounded';

const PovPill = ({top, delay = 0}: {top: number; delay?: number}) => (
  <div style={{position: 'absolute', top, left: 0, right: 0, textAlign: 'center'}}>
    <Pop delay={delay}><span style={{
      display: 'inline-block', fontFamily: 'Inter', fontWeight: 600, fontSize: 60, color: INK, padding: '8px 30px', borderRadius: 40,
      background: 'rgba(255,255,255,.14)', border: '2px solid rgba(255,255,255,.35)', letterSpacing: '-0.02em',
    }}>пов:</span></Pop>
  </div>
);

// A: Unbounded, одне величезне слово на біт, «нуль.» з луною контурних копій
const HookA = () => {
  const f = useCurrentFrame();
  const {k} = useKick();
  const big = (txt: string, size: number, extra?: React.CSSProperties) => (
    <div style={{fontFamily: UNB, fontWeight: 900, fontSize: size, lineHeight: 0.92, letterSpacing: '-0.04em', color: INK, ...extra}}>{txt}</div>
  );
  const word = f < at(1.5) ? 0 : f < at(2.5) ? 1 : 2;
  return (
    <>
      <AbsoluteFill style={{transform: `scale(${1.1 + k * 0.06})`}}><Footage src="hf/city2.mp4" dim={0.6} /></AbsoluteFill>
      <PovPill top={420} />
      <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center', textAlign: 'center', transform: `scale(${1 + k * 0.035})`}}>
        {word === 0 && <Sequence from={at(0.5)} layout="none"><Pop>{big('пʼят', 250)}{big('ниця,', 250)}</Pop></Sequence>}
        {word === 1 && <Pop delay={at(1.5)}>{big('а', 150, {fontWeight: 700, opacity: 0.8})}{big('планів', 205)}</Pop>}
        {word === 2 && (
          <div style={{position: 'relative'}}>
            {[-2, -1, 1, 2].map((o) => (
              <div key={o} style={{position: 'absolute', left: 0, right: 0, top: o * 265 * ease(f, at(3), at(3) + 6, [0, 1]),
                opacity: ease(f, at(3), at(3) + 4, [0, 0.5 - Math.abs(o) * 0.15])}}>
                {big('нуль.', 290, {color: 'transparent', WebkitTextStroke: '3px #F5F5F7'})}
              </div>
            ))}
            <Pop delay={at(2.5)}>{big('нуль.', 290, {backgroundImage: GRAD, WebkitBackgroundClip: 'text', color: 'transparent'})}</Pop>
          </div>
        )}
      </AbsoluteFill>
    </>
  );
};

// B: журнальний — курсив Playfair + дрібний гротеск, рядки «виїжджають» з-під маски
const Reveal = ({children, delay}: {children: React.ReactNode; delay: number}) => {
  const f = useCurrentFrame();
  const t = ease(f, delay, delay + 9, [0, 1], Easing.out(Easing.cubic));
  return <div style={{overflow: 'hidden', paddingBottom: '0.08em'}}><div style={{transform: `translateY(${(1 - t) * 110}%)`}}>{children}</div></div>;
};
const HookB = () => {
  const f = useCurrentFrame();
  return (
    <>
      <AbsoluteFill style={{transform: `scale(${ease(f, 0, at(4), [1.05, 1.2])})`}}><Footage src="hf/city2.mp4" dim={0.62} /></AbsoluteFill>
      <div style={{position: 'absolute', top: 170, left: 80, right: 80, display: 'flex', justifyContent: 'space-between',
        fontFamily: 'Inter', fontWeight: 600, fontSize: 34, letterSpacing: '0.18em', color: INK, opacity: ease(f, 0, 6, [0, 0.75])}}>
        <span>ПОВ:</span><span>ПТ · 19:47</span>
      </div>
      <div style={{position: 'absolute', left: 80, right: 60, top: 560, color: INK}}>
        <Reveal delay={at(0.5)}><div style={{fontFamily: PLAY, fontStyle: 'italic', fontWeight: 600, fontSize: 178, lineHeight: 1, letterSpacing: '-0.02em'}}>пʼятниця,</div></Reveal>
        <Reveal delay={at(1.5)}><div style={{fontFamily: 'Inter', fontWeight: 600, fontSize: 120, lineHeight: 1.1, letterSpacing: '-0.05em', marginTop: 20}}>а планів —</div></Reveal>
        <Reveal delay={at(2.5)}><div style={{fontFamily: PLAY, fontStyle: 'italic', fontWeight: 600, fontSize: 300, lineHeight: 1, letterSpacing: '-0.03em',
          backgroundImage: GRAD, WebkitBackgroundClip: 'text', color: 'transparent'}}>нуль.</div></Reveal>
      </div>
    </>
  );
};

// C: місто всередині літер, у кінці камера пролітає крізь слово
const HookC = () => {
  const f = useCurrentFrame();
  const fly = ease(f, at(3.25), at(4), [1, 30], Easing.in(Easing.cubic));
  const o = ease(f, 0, 6, [0, 1]);
  return (
    <>
      <AbsoluteFill style={{isolation: 'isolate', transform: `scale(${fly})`, transformOrigin: '55.5% 60%', filter: `blur(${(fly - 1) * 0.8}px)`}}>
        <AbsoluteFill style={{filter: 'brightness(1.5) saturate(1.2)'}}><Footage src="hf/city2.mp4" dim={0} /></AbsoluteFill>
        <AbsoluteFill style={{background: '#000', mixBlendMode: 'multiply', alignItems: 'center', justifyContent: 'center', opacity: 1}}>
          <div style={{fontFamily: UNB, fontWeight: 900, fontSize: 330, lineHeight: 0.88, letterSpacing: '-0.05em', color: '#fff', textAlign: 'center', opacity: o,
            transform: `scale(${ease(f, 0, at(3.25), [1.12, 1])})`}}>
            <div>пʼят</div><div>ниця</div>
          </div>
        </AbsoluteFill>
      </AbsoluteFill>
      <AbsoluteFill style={{opacity: ease(f, at(3.25), at(3.25) + 3, [1, 0])}}>
        <PovPill top={420} delay={2} />
        <div style={{position: 'absolute', top: 1330, left: 0, right: 0, textAlign: 'center', color: INK,
          fontFamily: 'Inter', fontWeight: 600, fontSize: 92, letterSpacing: '-0.045em'}}>
          <Pop delay={at(1.5)}>а планів —</Pop><Gap /><Pop delay={at(2.5)} style={{fontFamily: PLAY, fontStyle: 'italic', fontSize: 120}}><Grad>нуль.</Grad></Pop>
        </div>
      </AbsoluteFill>
    </>
  );
};

const HOOKS: Record<string, React.FC> = {orig: Hook, a: HookA, b: HookB, c: HookC};

// Назва застосунку — головний акцент: великий курсив, як «нуль.» у вступі
const Open = () => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  const s = spring({frame: f, fps, config: {damping: 20, stiffness: 110, mass: 0.9}});
  return (
    <>
      <Footage src="hf/lights.mp4" dim={0.5} blur={8} />
      <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center', transform: `scale(${ease(f, 0, at(3), [1, 1.05], Easing.linear)})`}}>
        <Img src={staticFile('icon.png')} style={{
          width: 190, height: 190, borderRadius: 44, opacity: s, transform: `translateY(${(1 - s) * 40}px)`,
          boxShadow: '0 30px 90px rgba(224,88,47,.45)',
        }} />
        <div style={{marginTop: 70, color: INK, fontFamily: 'Inter', fontWeight: 600, fontSize: 64, letterSpacing: '-0.03em', opacity: 0.85}}>
          <Pop delay={at(0.25)}>відкриваєш</Pop>
        </div>
        <Reveal delay={at(0.75)}>
          <div style={{...ACCENT, fontWeight: 600, fontSize: 330, lineHeight: 1.05, padding: '0 30px',
            backgroundImage: GRAD, WebkitBackgroundClip: 'text', color: 'transparent'}}>поряд</div>
        </Reveal>
      </AbsoluteFill>
    </>
  );
};

const Feed = () => {
  const f = useCurrentFrame();
  return (
    <>
      <Footage src="hf/lights.mp4" dim={0.55} blur={10} rate={0.8} />
      <Phone cam={{s: 1.06, y: 40, rz: ease(f, 0, at(4), [-3, 1]), ry: ease(f, 0, at(4), [-10, 6])}}>
        {/* плавний скрол стрічки з постерами (див. Promo) */}
        <OffthreadVideo src={staticFile('clips/home_posters.mp4')} trimBefore={Math.round(24.8 * 30)} playbackRate={1.4} muted
          style={{width: SW, height: SH}} />
      </Phone>
      <Sticker y={210} rot={-4} size={92} delay={at(0.5)}>850+ подій</Sticker>
      <Sticker y={360} x={120} rot={3} size={56} delay={at(1.25)}>у києві</Sticker>
    </>
  );
};

const MapScene = () => {
  const f = useCurrentFrame();
  const z = ease(f, at(0.5), at(3), [1, 1.4]);
  return (
    <>
      <Footage src="hf/lights.mp4" dim={0.55} blur={10} rate={0.8} />
      <Phone cam={{s: z, fx: 0.42, fy: 0.42, y: 80, ry: ease(f, 0, at(3), [8, -4])}}><Screen src="map_posters" /></Phone>
      <Line top={190}><Pop>усе —</Pop><Gap /><Pop delay={at(0.5)} style={ACCENT}><Grad>поряд</Grad></Pop></Line>
    </>
  );
};

const Company = () => {
  const f = useCurrentFrame();
  const up = ease(f, at(1.25), at(1.25) + 16, [SH, 0]);
  return (
    <>
      <Footage src="hf/lights.mp4" dim={0.55} blur={10} rate={0.8} />
      <Phone cam={{s: 1, y: 60, ry: ease(f, 0, at(3), [-6, 5])}}>
        <Screen src="ios_detail" />
        <div style={{position: 'absolute', inset: 0, transform: `translateY(${up}px)`}}><Screen src="ios_companions" /></div>
      </Phone>
      <Line top={190}><Pop>нема з ким?</Pop></Line>
      <Sticker y={330} rot={-3} size={76} delay={at(1.5)}>знайди компанію</Sticker>
    </>
  );
};

const Safety = () => {
  const f = useCurrentFrame();
  return (
    <>
      <Footage src="hf/lights.mp4" dim={0.6} blur={10} rate={0.8} />
      <Phone cam={{s: ease(f, 0, at(2), [1.15, 1.4]), y: 80, ry: ease(f, 0, at(2), [6, -4])}}><Screen src="ios_safety" /></Phone>
      <Line top={190} size={96}><Pop>укриття —</Pop><Gap /><Pop delay={at(0.5)}><Grad>теж поряд</Grad></Pop></Line>
    </>
  );
};

const Create = () => {
  const f = useCurrentFrame();
  return (
    <>
      <Footage src="hf/lights.mp4" dim={0.6} blur={10} rate={0.8} />
      <Phone cam={{s: ease(f, 0, at(2), [1.05, 1.3]), fy: 0.7, y: 80, ry: ease(f, 0, at(2), [-6, 4])}}><Screen src="ios_create" /></Phone>
      <Line top={190}><Pop>або</Pop><Gap /><Pop delay={at(0.5)} style={ACCENT}><Grad>збери своїх</Grad></Pop></Line>
    </>
  );
};

// Швидка нарізка на пів-біта: слово + екран
const RAPID: [string, string, number, number][] = [
  ['концерти', 'home_posters', 0.5, 0.2],
  ['виставки', 'home_posters', 0.5, 0.75],
  ['вечірки', 'map_posters', 0.4, 0.45],
  ['усе.', 'map_posters', 0.42, 0.5],
];
const Rapid = () => {
  const step = B;
  return (
    <>
      {RAPID.map(([word, src, fx, fy], i) => (
        <Sequence key={i} from={Math.round(i * step)} durationInFrames={Math.round(step) + (i === RAPID.length - 1 ? 1 : XF)}>
          <RapidCut word={word} src={src} fx={fx} fy={fy} i={i} last={i === RAPID.length - 1} />
        </Sequence>
      ))}
    </>
  );
};
const RapidCut = ({word, src, fx, fy, i, last}: {word: string; src: string; fx: number; fy: number; i: number; last: boolean}) => {
  const f = useCurrentFrame();
  const s = interpolate(f, [0, B + XF], [1.85, 1.7]);
  const o = ease(f, 0, 6, [0, 1]);
  return (
    <AbsoluteFill style={{opacity: i === 0 ? 1 : o}}>
      <AbsoluteFill style={{background: '#000'}} />
      <AbsoluteFill style={{opacity: last ? 0.3 : 0.5}}>
        <Phone cam={{s, fx, fy, rz: i % 2 ? 4 : -4, y: 60}}><Screen src={src} /></Phone>
      </AbsoluteFill>
      <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center'}}>
        <div style={{
          ...(last ? ACCENT : {fontFamily: 'Inter', letterSpacing: '-0.05em'}), fontWeight: 600, fontSize: last ? 240 : 170, color: INK,
          transform: `scale(${ease(f, 0, 10, [1.08, 1])})`, filter: `blur(${(1 - o) * 8}px)`,
          textShadow: '0 10px 60px rgba(0,0,0,.6)',
        }}>{last ? <Grad>{word}</Grad> : word}</div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

const End = () => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  const s = spring({frame: f, fps, config: {damping: 20, stiffness: 110}});
  const s2 = spring({frame: f - at(0.5), fps, config: {damping: 20, stiffness: 110}});
  const s3 = spring({frame: f - at(1.5), fps, config: {damping: 18, stiffness: 120}});
  return (
    <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center', color: INK, fontFamily: 'Inter', background: '#000'}}>
      <Img src={staticFile('icon.png')} style={{width: 240, height: 240, borderRadius: 56, opacity: s, transform: `scale(${0.85 + s * 0.15})`, boxShadow: '0 40px 100px rgba(224,88,47,.4)'}} />
      <div style={{...ACCENT, fontWeight: 600, fontSize: 240, lineHeight: 1.1, marginTop: 30, padding: '0 30px', opacity: s2, filter: `blur(${(1 - s2) * 10}px)`,
        transform: `translateY(${(1 - s2) * 30}px)`, backgroundImage: GRAD, WebkitBackgroundClip: 'text', color: 'transparent'}}>поряд</div>
      <div style={{fontSize: 54, marginTop: 24, opacity: s2 * 0.7, letterSpacing: '-0.02em'}}>афіша твого міста</div>
      <div style={{
        marginTop: 80, padding: '28px 62px', borderRadius: 100, background: STICKER_BG, color: '#fff',
        fontSize: 50, fontWeight: 600, letterSpacing: '-0.02em', opacity: s3, transform: `translateY(${(1 - s3) * 30}px) rotate(-2deg)`,
      }}>безкоштовно в App Store</div>
    </AbsoluteFill>
  );
};

// ── Монтаж (у бітах): [початок, кінець, сцена, спалах на вході] ─────────
const CUTS: [number, number, React.FC][] = [
  [0, 4, Hook],
  [4, 7, Open],
  [7, 10, Feed],
  [10, 13, MapScene],
  [13, 16, Company],
  [16, 18, Safety],
  [18, 20, Create],
  [20, 24, Rapid],
  [24, 32, End],
];

export const Zoomer = ({intro = 'b'}: {intro?: string}) => {
  useFonts();
  return (
    <AbsoluteFill style={{background: '#000', overflow: 'hidden'}}>
      <Audio src={staticFile('music/zoomer.m4a')} trimBefore={MUSIC_SHIFT}
        volume={(fr) => interpolate(fr, [0, 2, ZOOMER_FRAMES - 20, ZOOMER_FRAMES], [0, 1, 1, 0], {extrapolateRight: 'clamp'})} />
      {CUTS.map(([a, b, Scene]) => (
        <Sequence key={a} from={a === 0 ? 0 : at(a) - XF} durationInFrames={at(b) - at(a) + (a === 0 ? 0 : XF)}>
          {a === 0 ? React.createElement(HOOKS[intro] ?? Hook) : <Soft><Scene /></Soft>}
        </Sequence>
      ))}
      <Grain />
    </AbsoluteFill>
  );
};
