import React, {useState} from 'react';
import {
  AbsoluteFill, Audio, Img, OffthreadVideo, Sequence, continueRender, delayRender,
  interpolate, spring, staticFile, useCurrentFrame, useVideoConfig,
} from 'remotion';

const BG = '#0B0B0F';
const INK = '#F5F5F7';
const ACCENT = '#E0582F';
const PURPLE = '#3B2F8F';

// Шрифти ті самі, що на сайті й у застосунку; Inter розбитий на кирилицю й латиницю, як на сайті
const CYR = 'U+0301,U+0400-045F,U+0490-0491,U+04B0-04B1,U+2116';
const LAT = 'U+0000-00FF,U+0131,U+0152-0153,U+02BB-02BC,U+02C6,U+02DA,U+02DC,U+2000-206F,U+20AC,U+2122,U+2191,U+2193,U+2212,U+2215,U+FEFF,U+FFFD';
const FONTS: [string, string, string, string?, string?][] = [
  ['Inter', 'inter-cyrillic-400-normal.woff2', '400', CYR],
  ['Inter', 'inter-cyrillic-600-normal.woff2', '600', CYR],
  ['Inter', 'inter-latin-400-normal.woff2', '400', LAT],
  ['Inter', 'inter-latin-600-normal.woff2', '600', LAT],
  ['Source Serif 4', 'source-serif-4-600.woff2', '600'],
  // для вступу Zoomer (Google Fonts, OFL): Unbounded — змінна вага, Playfair — лише курсив
  ['Unbounded', 'unbounded-cyrillic.woff2', '200 900', CYR],
  ['Unbounded', 'unbounded-latin.woff2', '200 900', LAT],
  ['Playfair Display', 'playfair-italic-cyrillic.woff2', '600', CYR, 'italic'],
  ['Playfair Display', 'playfair-italic-latin.woff2', '600', LAT, 'italic'],
];
export const useFonts = () => {
  const [handle] = useState(() => {
    const h = delayRender('fonts');
    Promise.all(FONTS.map(([family, file, weight, unicodeRange, style]) =>
      new FontFace(family, `url(${staticFile('fonts/' + file)})`, {weight, ...(unicodeRange && {unicodeRange}), ...(style && {style})}).load()
        .then((f) => document.fonts.add(f)),
    )).then(() => continueRender(h));
    return h;
  });
  return handle;
};

// Сцени, у кадрах (30 fps)
const HOOK = [0, 66];
const HOME = [60, 170];
const MAP = [170, 280];
const DETAIL = [280, 375];
const END = [375, 450];

// Телефон: ширина екрана 640, пропорції скріна симулятора 1206×2622
const SW = 640;
const SH = Math.round(SW * 2622 / 1206);
const BEZEL = 14;
const PHONE_TOP = 450;

const Glow = ({color, size, x, y, opacity}: {color: string; size: number; x: number; y: number; opacity: number}) => (
  <div style={{
    position: 'absolute', left: x - size / 2, top: y - size / 2, width: size, height: size, borderRadius: '50%',
    background: `radial-gradient(circle, ${color} 0%, transparent 65%)`, opacity,
  }} />
);

const Background = () => {
  const f = useCurrentFrame();
  return (
    <AbsoluteFill style={{background: BG, overflow: 'hidden'}}>
      <Glow color={PURPLE} size={1500} x={900 + Math.sin(f / 40) * 60} y={250} opacity={0.9} />
      <Glow color={ACCENT} size={1100} x={120} y={1750 + Math.cos(f / 50) * 50} opacity={0.45} />
    </AbsoluteFill>
  );
};

// Титр зі «спливанням» по рядках
const Caption = ({lines, accent, top, size = 92}: {lines: string[]; accent?: number; top: number; size?: number}) => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  return (
    <div style={{position: 'absolute', top, left: 70, right: 70, textAlign: 'center'}}>
      {lines.map((l, i) => {
        const s = spring({frame: f - i * 5, fps, config: {damping: 16, stiffness: 140}});
        return (
          <div key={i} style={{
            fontFamily: "'Source Serif 4'", fontWeight: 600, fontSize: size, lineHeight: 1.06, letterSpacing: '-0.02em',
            color: i === accent ? ACCENT : INK, opacity: s, transform: `translateY(${(1 - s) * 40}px)`,
          }}>{l}</div>
        );
      })}
    </div>
  );
};

// Вміст екрана з плавною появою на початку сцени
const Screen = ({children, fadeIn = true}: {children: React.ReactNode; fadeIn?: boolean}) => {
  const f = useCurrentFrame();
  const o = fadeIn ? interpolate(f, [0, 8], [0, 1], {extrapolateRight: 'clamp'}) : 1;
  return <AbsoluteFill style={{opacity: o}}>{children}</AbsoluteFill>;
};

const Shot = ({src, zoom, origin}: {src: string; zoom: [number, number]; origin: string}) => {
  const f = useCurrentFrame();
  const {durationInFrames} = useVideoConfig();
  const s = interpolate(f, [0, durationInFrames], zoom);
  return <Img src={staticFile(src)} style={{width: SW, height: SH, transform: `scale(${s})`, transformOrigin: origin}} />;
};

// Пульсуюча рамка навколо «Шукаю компанію» (координати з detail.png, перераховані на SW)
const Pulse = () => {
  const f = useCurrentFrame();
  const k = SW / 1206;
  const [cx, cy, w, h] = [603 * k, 2405 * k, 1040 * k, 152 * k];
  const t = (f % 30) / 30;
  const on = interpolate(f, [18, 26], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  return (
    <div style={{
      position: 'absolute', left: cx - w / 2, top: cy - h / 2, width: w, height: h, borderRadius: h / 2,
      border: `4px solid ${ACCENT}`, opacity: on * (1 - t * 0.7), transform: `scale(${1 + t * 0.08})`,
    }} />
  );
};

const Phone = () => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  const enter = spring({frame: f - HOME[0], fps, config: {damping: 18, stiffness: 90}});
  const exit = interpolate(f, [END[0] - 4, END[0] + 10], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  const y = (1 - enter) * 1400 + exit * 200;
  if (f < HOME[0]) return null;
  return (
    <div style={{
      position: 'absolute', left: (1080 - SW) / 2 - BEZEL, top: PHONE_TOP - BEZEL, padding: BEZEL,
      borderRadius: 96, background: 'linear-gradient(160deg,#3a3a3e,#111113 40%,#1c1c1f)',
      boxShadow: '0 0 0 2px #4a4a50, 0 60px 120px rgba(0,0,0,.6)',
      transform: `translateY(${y}px) scale(${1 - exit * 0.08})`, opacity: 1 - exit,
    }}>
      <div style={{width: SW, height: SH, borderRadius: 82, overflow: 'hidden', position: 'relative', background: '#fff'}}>
        <Sequence from={HOME[0]} durationInFrames={HOME[1] - HOME[0] + 8}>
          <Screen fadeIn={false}>
            {/* Скрол афіші; до 9.3 с у кадрі картка демо для App Review, тому її відрізаємо */}
            <OffthreadVideo src={staticFile('clips/home.mp4')} trimBefore={Math.round(9.3 * 30)} playbackRate={0.6} muted
              style={{width: SW, height: SH}} />
          </Screen>
        </Sequence>
        <Sequence from={MAP[0]} durationInFrames={MAP[1] - MAP[0] + 8}>
          <Screen><Shot src="clips/map.png" zoom={[1.0, 1.14]} origin="50% 42%" /></Screen>
        </Sequence>
        <Sequence from={DETAIL[0]} durationInFrames={DETAIL[1] - DETAIL[0] + 15}>
          <Screen>
            <Shot src="clips/detail.png" zoom={[1.06, 1.0]} origin="50% 90%" />
            <Pulse />
          </Screen>
        </Sequence>
      </div>
    </div>
  );
};

const EndCard = () => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  const s = spring({frame: f, fps, config: {damping: 14, stiffness: 120}});
  const s2 = spring({frame: f - 8, fps, config: {damping: 18}});
  return (
    <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center', color: INK, fontFamily: 'Inter'}}>
      <Img src={staticFile('icon.png')} style={{
        width: 260, height: 260, borderRadius: 58, transform: `scale(${s})`,
        boxShadow: '0 30px 80px rgba(0,0,0,.5)',
      }} />
      <div style={{fontFamily: "'Source Serif 4'", fontWeight: 600, fontSize: 150, marginTop: 50, opacity: s2, letterSpacing: '-0.02em'}}>Поряд</div>
      <div style={{fontSize: 52, marginTop: 10, opacity: s2 * 0.75}}>Афіша твого міста</div>
      <div style={{
        marginTop: 80, padding: '30px 64px', borderRadius: 100, background: INK, color: BG,
        fontSize: 50, fontWeight: 600, opacity: s2, transform: `translateY(${(1 - s2) * 30}px)`,
      }}>Безкоштовно в App Store</div>
    </AbsoluteFill>
  );
};

// Музика — Higgsfield (Sonilo), 15 с, без вокалу
export const Ad15 = ({music = 'a'}: {music?: string}) => {
  useFonts();
  const f = useCurrentFrame();
  const hookOut = interpolate(f, [HOOK[1] - 10, HOOK[1]], [1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  const seq = (r: number[], node: React.ReactNode) => (
    <Sequence from={r[0]} durationInFrames={r[1] - r[0]}>{node}</Sequence>
  );
  return (
    <AbsoluteFill>
      <Background />
      <Audio src={staticFile(`music/${music}.m4a`)}
        volume={(fr) => interpolate(fr, [0, 6, 425, 450], [0, 1, 1, 0], {extrapolateRight: 'clamp'})} />
      <Sequence from={0} durationInFrames={HOOK[1]}>
        <AbsoluteFill style={{opacity: hookOut}}>
          <Caption top={640} size={128} accent={2} lines={['Не знаєш,', 'куди піти', 'на вихідних?']} />
        </AbsoluteFill>
      </Sequence>
      {seq([HOME[0] + 6, HOME[1]], <Caption top={180} lines={['Уся афіша Києва', 'в одному застосунку']} accent={1} />)}
      {seq(MAP, <Caption top={180} lines={['Усе, що поруч, —', 'на мапі']} accent={1} />)}
      {seq(DETAIL, <Caption top={180} lines={['Нема з ким піти?', 'Знайди компанію']} accent={1} />)}
      <Phone />
      {seq(END, <EndCard />)}
    </AbsoluteFill>
  );
};
