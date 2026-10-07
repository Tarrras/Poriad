import React from 'react';
import {AbsoluteFill, Audio, Easing, Img, Sequence, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {useFonts} from './Ad15';
import {Phone, SH, SW, Screen, ease} from './Promo';
import {Grain} from './Zoomer';

// TikTok-трек для 20–30 (scripts/tiktok-genz.md): T1 «тиждень до зарплати», T2 «нема куди піти».
// Голос: малі літери, нативні «носії» (нотатки, переписка), склейка на біт. Музика — music/zoomer.m4a
// (Sonilo, 130 BPM); у TikTok її можна замінити трендовим звуком (рендер з music={false}).
export const B = 1800 / 130; // кадрів на долю
export const at = (beats: number) => Math.round(beats * B);
const MUSIC_SHIFT = 3;

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

// ── T1 · «тиждень до зарплати. на рахунку 500» ───────────────────────
type Spend = {day: string; title: string; sub: string; cost: number; row: number; hit: number};
const SPENDS: Spend[] = [
  {day: 'сб', title: 'котики фест', sub: 'вднг · від 150 грн', cost: 150, row: at(3), hit: at(5)},
  {day: 'нд', title: 'бродячий стендап', sub: 'бочка пивна · від 190 грн', cost: 190, row: at(9), hit: at(11)},
  {day: 'ср', title: 'відкритий мікрофон', sub: 'doskabar · від 150 грн', cost: 150, row: at(15), hit: at(17)},
];
const T1_STRIKE = at(19);
const T1_END = at(22);
export const T1_FRAMES = at(26);

const Notes = () => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  const title = 'тиждень до зарплати.\nна рахунку 500 🫠';
  // баланс: після кожного «удару» лічильником з'їжджає вниз
  let balance = 500;
  let shake = 0;
  for (const s of SPENDS) {
    const k = ease(f, s.hit, s.hit + 8, [0, 1], Easing.out(Easing.cubic));
    balance -= s.cost * k;
    if (f >= s.hit) shake = Math.max(shake, Math.exp(-(f - s.hit) / 4));
  }
  const broke = f >= SPENDS[2].hit;
  return (
    <AbsoluteFill style={{background: '#FFFDF8', color: '#1D1D1F', fontFamily: 'Inter'}}>
      <div style={{position: 'absolute', top: 250, left: 80, right: 80}}>
        <div style={{fontSize: 34, color: '#8E8E93'}}>четвер, 8 жовтня</div>
        <div style={{fontWeight: 600, fontSize: 78, lineHeight: 1.1, letterSpacing: '-0.03em', marginTop: 14, whiteSpace: 'pre-line', minHeight: 172}}>
          {typed(title, f, 0, 4)}
        </div>
        {SPENDS.map((s, i) => {
          if (f < s.row) return null;
          const strike = ease(f, T1_STRIKE + i * 4, T1_STRIKE + i * 4 + 8, [0, 1]);
          const hit = lively(f - s.hit, fps);
          return (
            <div key={i} style={{display: 'flex', alignItems: 'flex-start', marginTop: 46, position: 'relative'}}>
              <div style={{flex: 1}}>
                <div style={{fontWeight: 600, fontSize: 56, letterSpacing: '-0.02em'}}>
                  <span style={{color: '#8E8E93'}}>{typed(`${s.day} · `, f, s.row, 3)}</span>{typed(s.title, f, s.row + 2, 3)}
                </div>
                <div style={{fontSize: 38, color: '#8E8E93', marginTop: 6}}>{typed(s.sub, f, s.row + 8, 4)}</div>
              </div>
              {f >= s.hit && (
                <div style={{fontWeight: 600, fontSize: 56, color: CORAL, transform: `scale(${hit}) translateY(${(1 - hit) * -30}px)`}}>−{s.cost}</div>
              )}
              {strike > 0 && (
                <div style={{position: 'absolute', left: -10, top: 36, height: 7, borderRadius: 4, background: '#1D1D1F', width: `${strike * 100}%`}} />
              )}
            </div>
          );
        })}
      </div>
      {/* баланс унизу безпечної зони */}
      <div style={{position: 'absolute', left: 80, right: 80, top: 1170, textAlign: 'center', transform: `translateX(${Math.sin(f * 2.6) * 14 * shake}px)`}}>
        <div style={{fontSize: 36, color: '#8E8E93'}}>залишок</div>
        <div style={{fontFamily: 'Unbounded', fontWeight: 800, fontSize: 170, lineHeight: 1, letterSpacing: '-0.04em', color: broke ? CORAL : '#1D1D1F'}}>
          {Math.round(balance)}{broke && <span style={{fontSize: 120}}> 💀</span>}
        </div>
      </div>
      <div style={{position: 'absolute', left: 0, right: 0, top: 700, textAlign: 'center'}}>
        <Sticker delay={T1_STRIKE + 12} rotate={-4}>10 грн.<br />зате тиждень не вдома</Sticker>
      </div>
    </AbsoluteFill>
  );
};

// Фінал: запис мапи + «знайшла все тут → поряд»
export const Found = ({line}: {line: React.ReactNode}) => {
  const f = useCurrentFrame();
  const t = ease(f, 0, 6, [1, 0], Easing.out(Easing.cubic));
  return (
    <AbsoluteFill style={{background: '#0B0B0F', transform: `translateY(${t * 700}px)`, filter: `blur(${t * 30}px)`}}>
      <AbsoluteFill style={{background: 'radial-gradient(900px 1000px at 50% 70%, #2A2560 0%, transparent 70%)'}} />
      <Phone width={SW * 1.25} cam={{y: 330, s: ease(f, 0, 60, [1.0, 1.08])}}>
        <Screen src="map_posters" />
      </Phone>
      <div style={{position: 'absolute', top: 290, left: 0, right: 0, textAlign: 'center'}}>
        <Sticker delay={2} rotate={2}>{line}</Sticker>
      </div>
    </AbsoluteFill>
  );
};

export const T1 = ({music = true}: {music?: boolean}) => {
  useFonts();
  return (
    <AbsoluteFill style={{overflow: 'hidden'}}>
      <Music on={music} frames={T1_FRAMES} />
      {SPENDS.map((s, i) => (
        <React.Fragment key={i}>
          {[0, 4, 8, 12, 16].map((d) => <Sfx key={d} at={s.row + d} src="ui_tick" volume={0.14} />)}
          <Sfx at={s.hit} src={`pin_pop_${i + 1}`} volume={0.3} />
        </React.Fragment>
      ))}
      <Sfx at={T1_STRIKE + 12} src="pin_pop_2" volume={0.3} />
      <Sfx at={T1_END} src="whoosh" volume={0.3} />
      <Sequence durationInFrames={T1_END + 6}><Notes /></Sequence>
      <Sequence from={T1_END}><Found line={<>знайшла все тут → <b>поряд</b></>} /></Sequence>
      <Grain />
    </AbsoluteFill>
  );
};

// ── T2 · «пов: ти сказав „в києві нема куди піти“» ───────────────────
const SPAM = [
  'котики фест на вднг 🐈', 'стендап про редфлеги', 'диско в карибському клубі 🪩', 'мафія наживо',
  'стендап і коктейлі 🍸', 'настолки в п\'ятницю 🎲', 'планетарій і сузір\'я 🌌', 'фестиваль їжі й вина 🍷',
];
const SPAM_FROM = 4; // доля першої відповіді
const PREVIEW_AT = at(SPAM_FROM + SPAM.length + 0.5);
const LAST_AT = at(SPAM_FROM + SPAM.length + 2);
const OK_AT = at(SPAM_FROM + SPAM.length + 4);
export const T2_FRAMES = at(SPAM_FROM + SPAM.length + 7);

const Preview = () => (
  <div style={{width: 600, borderRadius: 34, overflow: 'hidden', background: '#C2461F'}}>
    <div style={{height: 400, overflow: 'hidden', position: 'relative'}}>
      <Img src={staticFile('screens/map_posters.png')} style={{width: 600, position: 'absolute', top: -430}} />
    </div>
    <div style={{padding: '18px 28px 22px', textAlign: 'left'}}>
      <div style={{fontWeight: 600, fontSize: 40}}>Поряд — усе на мапі</div>
      <div style={{fontSize: 32, opacity: 0.75, marginTop: 4}}>poriad.app</div>
    </div>
  </div>
);

export type Msg = {at: number; mine: boolean; h: number; node: React.ReactNode; raw?: boolean};
export const BUBBLE = 112;
const MSGS: Msg[] = [
  {at: 4, mine: false, h: BUBBLE, node: 'в києві нема куди піти'},
  ...SPAM.map((t, i) => ({at: at(SPAM_FROM + i), mine: true, h: BUBBLE, node: t})),
  {at: at(SPAM_FROM + SPAM.length), mine: true, h: BUBBLE, node: <b>і ще 250+ на ці вихідні</b>},
  {at: PREVIEW_AT, mine: true, h: 560, node: <Preview />, raw: true},
  {at: LAST_AT, mine: true, h: BUBBLE, node: 'ще питання?'},
  {at: OK_AT, mine: false, h: BUBBLE, node: 'ок 😶'},
];
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

export const T2 = ({music = true}: {music?: boolean}) => {
  useFonts();
  return (
    <AbsoluteFill style={{overflow: 'hidden'}}>
      <Music on={music} frames={T2_FRAMES} />
      {MSGS.map((m, i) => <Sfx key={i} at={m.at} src={`pin_pop_${(i % 3) + 1}`} volume={m.mine ? 0.22 : 0.3} />)}
      {[30, 38, 46].map((d) => <Sfx key={d} at={d} src="ui_tick" volume={0.12} />)}
      <Chat msgs={MSGS} typing={[26, MSGS[1].at]} hookOut={at(SPAM_FROM)} hook={<>пов: ти написав це<br />не тій людині</>} />
      <Grain />
    </AbsoluteFill>
  );
};

// Картка-подія для T3/T5/T7: назва великим, під нею день · ціна
export const Card = ({title, sub, dark = true, style}: {title: React.ReactNode; sub?: string; dark?: boolean; style?: React.CSSProperties}) => (
  <div style={{
    padding: '18px 26px', borderRadius: 26, background: dark ? '#1D1D22' : '#fff', color: dark ? '#F5F5F7' : '#1D1D1F',
    boxShadow: '0 16px 40px rgba(0,0,0,.25)', fontFamily: 'Inter', ...style,
  }}>
    <div style={{fontWeight: 600, fontSize: 44, lineHeight: 1.1, letterSpacing: '-0.02em'}}>{title}</div>
    {sub && <div style={{fontSize: 30, opacity: 0.6, marginTop: 6}}>{sub}</div>}
  </div>
);

// Падіння згори з пружиною й нахилом
const Drop = ({at: from, children, style}: {at: number; children: React.ReactNode; style?: React.CSSProperties}) => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  if (f < from) return null;
  const s = lively(f - from, fps);
  return <div style={{transform: `translateY(${(1 - s) * -700}px) rotate(${(1 - s) * -14}deg)`, ...style}}>{children}</div>;
};

// ── T3 · «тір-лист: як легко витягнути друзів» ───────────────────────
const TIERS: [string, string][] = [['S', '#FF7F7F'], ['A', '#FFBF7F'], ['B', '#FFDF7F'], ['C', '#BFFF7F'], ['D', '#7FBFFF']];
const T3_PICKS = [
  {tier: 0, at: at(3), title: 'котики фест', sub: 'сб 10.10 · від 150', joke: 'погодяться всі. навіть ті, хто «нікуди не ходить»'},
  {tier: 1, at: at(7), title: 'стендап і коктейлі', sub: 'нд 11.10 · від 200', joke: 'якщо пообіцяти не перший ряд'},
  {tier: 2, at: at(11), title: 'мафія наживо', sub: 'нд 11.10 · від 350', joke: 'хтось точно образиться до кінця вечора'},
  {tier: 3, at: at(15), title: 'бій мма за титул', sub: 'сб 17.10 · від 500', joke: 'піде тільки один. ти знаєш хто'},
  {tier: 4, at: at(19), title: 'друг, який «подивиться по самопочуттю»', sub: undefined, joke: 'без коментарів 🫠'},
];
const T3_ASK = at(23);
const T3_END = at(25);
export const T3_FRAMES = at(31);
const ROW = 176;
const GRID_TOP = 430;

const Tier = () => {
  const f = useCurrentFrame();
  const cur = [...T3_PICKS].reverse().find((p) => f >= p.at);
  return (
    <AbsoluteFill style={{background: '#0B0B0F', fontFamily: 'Inter', color: '#F5F5F7'}}>
      <div style={{position: 'absolute', top: 250, left: 60, right: 60, fontWeight: 600, fontSize: 60, lineHeight: 1.1, letterSpacing: '-0.03em'}}>
        {typed('тір-лист: як легко витягнути друзів цього тижня', f, 0, 4)}
      </div>
      {TIERS.map(([t, c], i) => (
        <div key={t} style={{position: 'absolute', top: GRID_TOP + i * ROW, left: 60, right: 60, height: ROW - 12, display: 'flex', background: '#16161B', borderRadius: 20, overflow: 'hidden'}}>
          <div style={{width: 130, background: c, color: '#111', fontFamily: 'Unbounded', fontWeight: 800, fontSize: 72, display: 'flex', alignItems: 'center', justifyContent: 'center'}}>{t}</div>
        </div>
      ))}
      {T3_PICKS.map((p, i) => (
        <div key={i} style={{position: 'absolute', top: GRID_TOP + p.tier * ROW + 10, left: 210, right: 80}}>
          <Drop at={p.at}><Card title={p.title} sub={p.sub} style={{display: 'inline-block', maxWidth: 760, padding: p.sub ? '14px 24px' : '24px 24px'}} /></Drop>
        </div>
      ))}
      {/* жарт до поточної картки — під сіткою */}
      {cur && f < T3_ASK && (
        <Sequence from={cur.at + 6} layout="none">
          <div style={{position: 'absolute', top: GRID_TOP + 5 * ROW + 10, left: 40, right: 40, textAlign: 'center'}}>
            <Sticker rotate={-2} style={{fontSize: 46}}>{cur.joke}</Sticker>
          </div>
        </Sequence>
      )}
      <div style={{position: 'absolute', top: GRID_TOP + 5 * ROW + 10, left: 0, right: 0, textAlign: 'center'}}>
        <Sticker delay={T3_ASK} rotate={3}>а куди тягнути твоїх? 👇</Sticker>
      </div>
    </AbsoluteFill>
  );
};

export const T3 = ({music = true}: {music?: boolean}) => {
  useFonts();
  return (
    <AbsoluteFill style={{overflow: 'hidden'}}>
      <Music on={music} frames={T3_FRAMES} />
      {T3_PICKS.map((p, i) => <Sfx key={i} at={p.at + 8} src={`pin_pop_${(i % 3) + 1}`} volume={0.32} />)}
      <Sfx at={T3_END} src="whoosh" volume={0.3} />
      <Sequence durationInFrames={T3_END + 6}><Tier /></Sequence>
      <Sequence from={T3_END}><Found line={<>все на мапі → <b>поряд</b></>} /></Sequence>
      <Grain />
    </AbsoluteFill>
  );
};

// ── T5 · «інтроверт vs екстраверт: субота в києві» ───────────────────
const PAIRS: [[string, string], [string, string]][] = [
  [['планетарій 🌌', 'сузір\'я · сб 17:00 · від 400'], ['диско в карибському 🪩', 'сб 18:30 · від 290']],
  [['клуб настільних ігор 🎲', 'пт 19:00 · від 300'], ['мафія наживо 🗣️', 'нд 17:00 · від 350']],
  [['котики фест 🐈', 'котики не говорять · від 150'], ['відкритий мікрофон 🎤', 'вийди на сцену · ср · від 150']],
];
const T5_AMBI = at(12);
const T5_END = at(15);
export const T5_FRAMES = at(20);

const Split = () => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  const head = lively(f, fps);
  const cell = (side: 0 | 1, i: number) => {
    const [title, sub] = PAIRS[i][side];
    const from = at(2 + i * 3) + side * at(1);
    if (f < from) return null;
    const s = lively(f - from, fps);
    return (
      <div key={`${side}${i}`} style={{marginTop: 34, transform: `translateX(${(1 - s) * (side ? 400 : -400)}px)`, opacity: s}}>
        <div style={{fontWeight: 600, fontSize: 48, lineHeight: 1.1, letterSpacing: '-0.02em'}}>{title}</div>
        <div style={{fontSize: 30, opacity: 0.7, marginTop: 6}}>{sub}</div>
      </div>
    );
  };
  return (
    <AbsoluteFill style={{fontFamily: 'Inter', color: '#F5F5F7'}}>
      <div style={{position: 'absolute', inset: 0, right: '50%', background: '#14141B'}} />
      <div style={{position: 'absolute', inset: 0, left: '50%', background: CORAL}} />
      {[0, 1].map((side) => (
        <div key={side} style={{position: 'absolute', top: 280, width: 460, [side ? 'right' : 'left']: 50}}>
          <div style={{fontFamily: 'Unbounded', fontWeight: 800, fontSize: 52, letterSpacing: '-0.03em', transform: `scale(${head})`, transformOrigin: 'left'}}>
            {side ? 'екстраверт 🤩' : 'інтроверт 🫣'}
          </div>
          <div style={{fontSize: 30, opacity: 0.7, marginTop: 6}}>субота в києві</div>
          {PAIRS.map((_, i) => cell(side as 0 | 1, i))}
        </div>
      ))}
      <div style={{position: 'absolute', top: 1280, left: 0, right: 0, textAlign: 'center'}}>
        <Sticker delay={T5_AMBI} rotate={-3}>амбіверт: обидві колонки 🫠</Sticker>
      </div>
    </AbsoluteFill>
  );
};

export const T5 = ({music = true}: {music?: boolean}) => {
  useFonts();
  return (
    <AbsoluteFill style={{overflow: 'hidden'}}>
      <Music on={music} frames={T5_FRAMES} />
      {PAIRS.flatMap((_, i) => [0, 1].map((side) => (
        <Sfx key={`${i}${side}`} at={at(2 + i * 3) + side * at(1)} src={`pin_pop_${side + 1}`} volume={0.3} />
      )))}
      <Sfx at={T5_AMBI} src="pin_pop_3" volume={0.32} />
      <Sfx at={T5_END} src="whoosh" volume={0.3} />
      <Sequence durationInFrames={T5_END + 6}><Split /></Sequence>
      <Sequence from={T5_END}><Found line={<>а ти хто? все тут → <b>поряд</b></>} /></Sequence>
      <Grain />
    </AbsoluteFill>
  );
};

// ── T7 · «що робити в києві коли…» — пошуковий рядок ─────────────────
const QUERY = 'що робити в києві коли';
const SUGGEST = ['нема грошей', 'друзі злились', 'дощ', 'все набридло'];
const ANSWERS = [
  {pick: 1, at: at(4), cards: [['бродячий стендап 🎤', 'нд 16:00 · від 190']], joke: 'іди сам. там усі сміються однаково'},
  {pick: 2, at: at(10), cards: [['планетарій 🌌', 'сб 17:00 · від 400'], ['настолки 🎲', 'пт 19:00 · від 300']], joke: 'дах над головою включено'},
  {pick: 0, at: at(16), cards: [['котики фест 🐈', 'сб, вднг · від 150']], joke: '150 грн і 0 причин сумувати'},
];
const T7_LAST = at(22); // «все набридло» → застосунок
export const T7_FRAMES = at(28);

const Search = () => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  const cur = [...ANSWERS].reverse().find((a) => f >= a.at);
  const pick = f >= T7_LAST ? 3 : cur?.pick ?? -1;
  const open = cur && f < T7_LAST ? lively(f - cur.at - 4, fps) : 0;
  return (
    <AbsoluteFill style={{background: '#F5F5F7', fontFamily: 'Inter', color: '#1D1D1F'}}>
      <div style={{position: 'absolute', top: 270, left: 60, right: 60, height: 120, borderRadius: 60, background: '#fff', boxShadow: '0 10px 40px rgba(0,0,0,.08)', display: 'flex', alignItems: 'center', padding: '0 44px', gap: 26}}>
        <div style={{fontSize: 44, opacity: 0.5}}>🔍</div>
        <div style={{fontSize: 48, fontWeight: 600, letterSpacing: '-0.02em'}}>
          {typed(QUERY, f, 0, 3)}
          {pick >= 0 && <span style={{color: CORAL}}> {SUGGEST[pick]}</span>}
          <span style={{opacity: Math.floor(f / 8) % 2 ? 0 : 1, fontWeight: 400}}>|</span>
        </div>
      </div>
      {SUGGEST.map((s, i) => {
        const from = 10 + i * 3;
        if (f < from) return null;
        const k = lively(f - from, fps);
        const on = i === pick;
        return (
          <div key={s} style={{
            position: 'absolute', top: 420 + i * 112, left: 60, right: 60, height: 100, borderRadius: 24,
            display: 'flex', alignItems: 'center', gap: 24, padding: '0 44px', fontSize: 44,
            background: on ? '#1D1D1F' : 'transparent', color: on ? '#fff' : '#1D1D1F', opacity: k, transform: `translateY(${(1 - k) * 20}px)`,
          }}>
            <span style={{opacity: 0.4}}>🔍</span>
            <span><span style={{opacity: 0.45}}>…коли </span><b>{s}</b></span>
          </div>
        );
      })}
      {/* відповідь виїжджає знизу аркушем */}
      {cur && f < T7_LAST && (
        <div style={{position: 'absolute', left: 40, right: 40, top: 900 + (1 - open) * 900, padding: '36px 36px 44px', borderRadius: 44, background: '#0B0B0F', color: '#F5F5F7', boxShadow: '0 -20px 60px rgba(0,0,0,.2)'}}>
          {cur.cards.map(([t, s]) => <Card key={t} title={t} sub={s} style={{marginBottom: 18, background: '#1D1D22'}} />)}
          <div style={{textAlign: 'center', marginTop: 10}}>
            <Sequence from={cur.at + 14} layout="none"><Sticker rotate={-2} style={{fontSize: 44}}>{cur.joke}</Sticker></Sequence>
          </div>
        </div>
      )}
    </AbsoluteFill>
  );
};

export const T7 = ({music = true}: {music?: boolean}) => {
  useFonts();
  return (
    <AbsoluteFill style={{overflow: 'hidden'}}>
      <Music on={music} frames={T7_FRAMES} />
      {[0, 5, 10, 15, 20].map((d) => <Sfx key={d} at={d} src="ui_tick" volume={0.14} />)}
      {ANSWERS.map((a, i) => <Sfx key={i} at={a.at} src={`pin_pop_${(i % 3) + 1}`} volume={0.3} />)}
      <Sfx at={T7_LAST + 8} src="whoosh" volume={0.3} />
      <Sequence durationInFrames={T7_LAST + 14}><Search /></Sequence>
      <Sequence from={T7_LAST + 8}><Found line={<>…коли все набридло → <b>поряд</b></>} /></Sequence>
      <Grain />
    </AbsoluteFill>
  );
};
