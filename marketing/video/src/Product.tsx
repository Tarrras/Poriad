import React from 'react';
import {AbsoluteFill, Easing, Img, Sequence, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {useFonts} from './Ad15';
import {ease} from './Promo';
import {BUBBLE, CORAL, Chat, Msg, Music, Sfx, Sticker, lively, typed} from './Tiktok';
import {Grain} from './Zoomer';

// Продуктові ролики (scripts/tiktok-genz.md, P2–P4): герой — застосунок, події лише приклад усередині UI.
// Екрани — справжні знімки prod-збірки (screens/p1, p3/web.png — сторінка poriad.app/e/{id}).

const BG = '#0B0B0F';
const SCR_W = 1206;
const SCR_H = 2622;
const PT_W = 402; // ширина екрана в точках iOS
const PT_H = 874;

// Телефон без 3D: рамка + екран; tap — точка дотику в точках iOS
const MiniPhone = ({x, y, w, children, style}: {x: number; y: number; w: number; children: React.ReactNode; style?: React.CSSProperties}) => {
  const h = Math.round(w * SCR_H / SCR_W);
  return (
    <div style={{position: 'absolute', left: x, top: y, width: w, height: h, borderRadius: w * 0.14, padding: 10, background: '#1C1C1F',
      boxShadow: '0 0 0 2px #3A3A3F, 0 60px 140px rgba(0,0,0,.6)', ...style}}>
      <div style={{width: '100%', height: '100%', borderRadius: w * 0.12, overflow: 'hidden', position: 'relative', background: '#fff'}}>
        {children}
      </div>
    </div>
  );
};

const Shot = ({src}: {src: string}) => <Img src={staticFile(`screens/${src}`)} style={{width: '100%', height: '100%', display: 'block'}} />;

// Коло дотику: з'являється й розходиться за 14 кадрів
const Tap = ({at: from, x, y}: {at: number; x: number; y: number}) => {
  const f = useCurrentFrame() - from;
  if (f < 0 || f > 14) return null;
  const k = f / 14;
  return (
    <div style={{
      position: 'absolute', left: `${x / PT_W * 100}%`, top: `${y / PT_H * 100}%`, width: 90, height: 90, marginLeft: -45, marginTop: -45,
      borderRadius: 45, background: 'rgba(29,29,31,.28)', border: '4px solid rgba(255,255,255,.9)',
      transform: `scale(${0.6 + k * 0.8})`, opacity: 1 - k,
    }} />
  );
};

const Glow = () => (
  <AbsoluteFill style={{background: `radial-gradient(900px 1000px at 50% 60%, #2A2560 0%, transparent 70%), ${BG}`}} />
);

// Міста з подіями й кількість подій на найближчі 30 днів (prod, 07.10; округлено вниз)
const CITIES: [string, string][] = [['Київ', '1 200+'], ['Львів', '280+'], ['Одеса', '270+'], ['Дніпро', '300+'], ['Харків', '200+']];

// Фінал продуктових роликів: іконка, назва, що це, де взяти
const EndCTA = ({line}: {line: string}) => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  const s = lively(f, fps);
  return (
    <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center', fontFamily: 'Inter', color: '#F5F5F7', opacity: ease(f, 0, 6, [0, 1])}}>
      <Glow />
      <Img src={staticFile('icon.png')} style={{width: 220, height: 220, borderRadius: 52, transform: `scale(${s}) rotate(${(1 - s) * -18}deg)`, boxShadow: '0 40px 100px rgba(224,88,47,.45)'}} />
      {/* position: relative — інакше абсолютний Glow малюється поверх тексту */}
      <div style={{position: 'relative', fontFamily: 'Unbounded', fontWeight: 800, fontSize: 110, letterSpacing: '-0.04em', marginTop: 40, opacity: lively(f - 6, fps)}}>поряд</div>
      <div style={{position: 'relative', fontWeight: 600, fontSize: 44, color: '#A1A1A8', marginTop: 10, textAlign: 'center', opacity: lively(f - 12, fps)}}>{line}</div>
      <div style={{position: 'relative', marginTop: 44, padding: '22px 44px', borderRadius: 40, background: '#F5F5F7', color: '#0B0B0F', fontWeight: 600, fontSize: 44, transform: `scale(${lively(f - 18, fps)})`}}>
        безкоштовно в App Store
      </div>
      <div style={{position: 'relative', display: 'flex', gap: 14, marginTop: 36, opacity: lively(f - 24, fps)}}>
        {CITIES.map(([c]) => <div key={c} style={{padding: '10px 22px', borderRadius: 24, background: '#26262E', fontWeight: 600, fontSize: 32}}>{c}</div>)}
      </div>
    </AbsoluteFill>
  );
};

// ── P2 · «відписалась від 5 каналів з афішею» ────────────────────────
const CHANNELS = [47, 23, 31, 12, 64];
const UNSUB = 80; // з цього кадру сповіщення по черзі змахуються
const SOURCES = ['Concert.ua', 'Karabas', 'Kontramarka', 'TicketsBox', 'та інші'];
const SRC_AT = 145;
const PHONE_AT = 175;
const P2_ONE = 250;
const P2_CTA = 300;
export const P2_FRAMES = 370;

const Unsub = () => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  const phoneIn = lively(f - PHONE_AT, fps);
  const count = Math.round(ease(f, PHONE_AT + 10, PHONE_AT + 40, [0, 2000], Easing.out(Easing.cubic)));
  return (
    <AbsoluteFill style={{fontFamily: 'Inter', color: '#F5F5F7'}}>
      <Glow />
      <div style={{position: 'absolute', top: 250, left: 60, right: 60, fontWeight: 600, fontSize: 66, lineHeight: 1.1, letterSpacing: '-0.03em', opacity: ease(f, SRC_AT - 6, SRC_AT, [1, 0])}}>
        {typed('відписалась від 5 каналів з афішею.', f, 0, 4)}
      </div>
      <div style={{position: 'absolute', top: 430, left: 60, opacity: ease(f, SRC_AT - 6, SRC_AT, [1, 0])}}>
        <Sticker delay={22} rotate={-3}>не шкодую 🙂</Sticker>
      </div>
      {/* хаос сповіщень (канали умовні, без назв) */}
      {CHANNELS.map((n, i) => {
        const from = 4 + i * 7;
        if (f < from) return null;
        const s = lively(f - from, fps);
        const out = ease(f, UNSUB + i * 10, UNSUB + i * 10 + 10, [0, 1], Easing.in(Easing.cubic));
        const shake = f < UNSUB ? Math.sin(f * 1.7 + i) * 4 : 0;
        return (
          <div key={i} style={{
            position: 'absolute', left: 50, right: 50, top: 640 + i * 150, height: 128, borderRadius: 30, background: 'rgba(38,38,46,.92)',
            display: 'flex', alignItems: 'center', gap: 24, padding: '0 30px', boxShadow: '0 20px 50px rgba(0,0,0,.4)',
            transform: `translateY(${(1 - s) * -80}px) translateX(${out * -1200 + shake}px) rotate(${out * -8}deg)`, opacity: s,
          }}>
            <div style={{width: 76, height: 76, borderRadius: 20, background: '#3A3A44', fontSize: 40, display: 'flex', alignItems: 'center', justifyContent: 'center'}}>📢</div>
            <div style={{flex: 1}}>
              <div style={{fontWeight: 600, fontSize: 38}}>канал з афішею {i + 1}</div>
              <div style={{fontSize: 30, color: '#A1A1A8'}}>{n} нових повідомлень</div>
            </div>
            {f >= UNSUB + i * 10 - 6 && <div style={{fontSize: 30, fontWeight: 600, color: CORAL}}>відписатись ✓</div>}
          </div>
        );
      })}
      {/* джерела летять у телефон */}
      {f >= SRC_AT && f < PHONE_AT + 40 && (
        <>
          <div style={{position: 'absolute', top: 250, left: 60, right: 60, fontWeight: 600, fontSize: 60, lineHeight: 1.1, letterSpacing: '-0.03em', opacity: ease(f, PHONE_AT + 30, PHONE_AT + 40, [1, 0])}}>
            замість 5 каналів і 4 сайтів квитків —
          </div>
          {SOURCES.map((s, i) => {
            const k = lively(f - SRC_AT - i * 4, fps);
            const suck = ease(f, PHONE_AT + 6 + i * 3, PHONE_AT + 22 + i * 3, [0, 1], Easing.in(Easing.cubic));
            const x0 = [120, 600, 160, 560, 380][i];
            const y0 = [520, 560, 760, 800, 980][i];
            return (
              <div key={s} style={{
                position: 'absolute', left: x0 + (390 - x0) * suck, top: y0 + (1100 - y0) * suck, padding: '18px 32px', borderRadius: 40,
                background: '#F5F5F7', color: '#0B0B0F', fontWeight: 600, fontSize: 44, transform: `scale(${k * (1 - suck)})`,
              }}>{s}</div>
            );
          })}
        </>
      )}
      {f >= PHONE_AT && (
        <>
          <MiniPhone x={250} y={640 + (1 - phoneIn) * 900} w={580} style={{transform: `scale(${ease(f, PHONE_AT, P2_CTA, [1, 1.05])})`}}>
            <Shot src="map_posters.png" />
          </MiniPhone>
          <div style={{position: 'absolute', top: 250, left: 0, right: 0, textAlign: 'center', opacity: ease(f, PHONE_AT + 10, PHONE_AT + 18, [0, 1])}}>
            <div style={{fontFamily: 'Unbounded', fontWeight: 800, fontSize: 120, letterSpacing: '-0.04em', lineHeight: 1}}>{count.toLocaleString('uk-UA')}+</div>
            <div style={{fontWeight: 600, fontSize: 44, color: '#A1A1A8', marginTop: 10}}>подій щомісяця · 5 міст</div>
            <div style={{display: 'flex', flexWrap: 'wrap', justifyContent: 'center', gap: 12, margin: '22px 60px 0'}}>
              {CITIES.map(([c, n], i) => {
                const k = lively(f - PHONE_AT - 24 - i * 4, fps);
                return <div key={c} style={{padding: '10px 22px', borderRadius: 24, background: '#F5F5F7', color: '#0B0B0F', fontSize: 34, transform: `scale(${k})`}}><b>{c}</b> {n}</div>;
              })}
            </div>
          </div>
          <div style={{position: 'absolute', top: 1220, left: 0, right: 0, textAlign: 'center'}}>
            <Sticker delay={P2_ONE} rotate={-3} style={{fontSize: 62}}>одна мапа. 5 міст.</Sticker>
          </div>
        </>
      )}
    </AbsoluteFill>
  );
};

export const P2 = ({music = true}: {music?: boolean}) => {
  useFonts();
  return (
    <AbsoluteFill style={{overflow: 'hidden', background: BG}}>
      <Music on={music} frames={P2_FRAMES} />
      {CHANNELS.map((_, i) => <Sfx key={i} at={4 + i * 7} src={`pin_pop_${(i % 3) + 1}`} volume={0.3} />)}
      {CHANNELS.map((_, i) => <Sfx key={`u${i}`} at={UNSUB + i * 10} src="whoosh" volume={0.18} />)}
      {SOURCES.map((_, i) => <Sfx key={`s${i}`} at={SRC_AT + i * 4} src="ui_tick" volume={0.2} />)}
      <Sfx at={PHONE_AT} src="whoosh" volume={0.3} />
      <Sfx at={P2_ONE} src="pin_pop_2" volume={0.32} />
      <Sequence durationInFrames={P2_CTA + 6}><Unsub /></Sequence>
      <Sequence from={P2_CTA}><EndCTA line="уся афіша — на одній мапі" /></Sequence>
      <Grain />
    </AbsoluteFill>
  );
};

// ── P3 · «друг без застосунку» ───────────────────────────────────────
const LinkCard = () => (
  <div style={{width: 600, borderRadius: 34, overflow: 'hidden', background: '#C2461F', fontFamily: 'Inter', color: '#fff'}}>
    <Img src={staticFile('posters/kotyky.jpg')} style={{width: 600, height: 420, objectFit: 'cover', display: 'block'}} />
    <div style={{padding: '18px 28px 22px'}}>
      <div style={{fontWeight: 600, fontSize: 38, lineHeight: 1.15}}>КОТИКИ ФЕСТ — Поряд</div>
      <div style={{fontSize: 30, opacity: 0.8, marginTop: 4}}>субота, 10 жовтня о 11:00 · ВДНГ</div>
      <div style={{fontSize: 30, opacity: 0.65, marginTop: 2}}>poriad.app</div>
    </div>
  </div>
);
const CHAT1: Msg[] = [
  {at: 4, mine: true, h: 590, node: <LinkCard />, raw: true},
  {at: 40, mine: false, h: BUBBLE, node: 'ще один застосунок качати? 🙄'},
  {at: 72, mine: true, h: BUBBLE, node: 'не треба. просто відкрий 🙂'},
];
const WEB_AT = 110;
const BACK_AT = 255;
const CHAT2: Msg[] = [
  ...CHAT1.map((m) => ({...m, at: m.at - 200})),
  {at: 8, mine: false, h: BUBBLE, node: 'о, го 🐈'},
  {at: 24, mine: false, h: BUBBLE, node: 'в суботу об 11 біля входу?'},
  {at: 44, mine: true, h: BUBBLE, node: '✅'},
];
const P3_CTA = 330;
export const P3_FRAMES = 400;

const Browser = () => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  const s = lively(f, fps);
  const w = 600;
  const h = Math.round(w * SCR_H / SCR_W);
  return (
    <AbsoluteFill style={{fontFamily: 'Inter'}}>
      <Glow />
      <div style={{position: 'absolute', top: 250, left: 0, right: 0, textAlign: 'center'}}>
        <Sticker delay={4} rotate={-2} style={{fontSize: 52}}>у друга — просто в браузері</Sticker>
      </div>
      <MiniPhone x={240} y={470 + (1 - s) * 800} w={w}>
        <div style={{position: 'absolute', inset: 0, background: '#F5F5F7'}} />
        <Img src={staticFile('screens/p3/web.png')} style={{position: 'absolute', top: 60 + ease(f, 30, 120, [0, -h * 0.55]), width: '100%'}} />
        {/* статус-бар і адресний рядок у стилі Safari */}
        <div style={{position: 'absolute', top: 0, left: 0, right: 0, height: 60, background: '#F5F5F7', display: 'flex', alignItems: 'center', paddingLeft: 52, fontWeight: 600, fontSize: 24, color: '#111'}}>9:41</div>
        <div style={{position: 'absolute', bottom: 22, left: 26, right: 26, height: 70, borderRadius: 35, background: 'rgba(255,255,255,.92)', boxShadow: '0 6px 24px rgba(0,0,0,.15)', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 28, color: '#111'}}>
          🔒 poriad.app
        </div>
      </MiniPhone>
      <div style={{position: 'absolute', top: 1300, left: 0, right: 0, textAlign: 'center'}}>
        <Sticker delay={70} rotate={3} style={{fontSize: 46}}>дата, місце, ціна, квитки 👌</Sticker>
      </div>
    </AbsoluteFill>
  );
};

export const P3 = ({music = true}: {music?: boolean}) => {
  useFonts();
  return (
    <AbsoluteFill style={{overflow: 'hidden', background: BG}}>
      <Music on={music} frames={P3_FRAMES} />
      {CHAT1.map((m, i) => <Sfx key={i} at={m.at} src={`pin_pop_${(i % 3) + 1}`} volume={0.28} />)}
      <Sfx at={WEB_AT} src="whoosh" volume={0.3} />
      {CHAT2.slice(CHAT1.length).map((m, i) => <Sfx key={`b${i}`} at={BACK_AT + m.at} src={`pin_pop_${(i % 3) + 1}`} volume={0.28} />)}
      <Sequence durationInFrames={WEB_AT + 4}>
        <Chat msgs={CHAT1} typing={[0, 0]} hookOut={72} hook={<>пов: друг не хоче качати<br />ще один застосунок</>} />
      </Sequence>
      <Sequence from={WEB_AT} durationInFrames={BACK_AT - WEB_AT + 4}><Browser /></Sequence>
      <Sequence from={BACK_AT} durationInFrames={P3_CTA - BACK_AT + 6}>
        <Chat msgs={CHAT2} typing={[0, 0]} hookOut={0} hook={null} />
      </Sequence>
      <Sequence from={P3_CTA}><EndCTA line="кидай друзям події одним посиланням" /></Sequence>
      <Grain />
    </AbsoluteFill>
  );
};

// ── P4 · «друзі злились → Шукаю компанію + події від людей у 5 містах» ──
// Дані — dev (тестові люди й пошуки компанії, див. memory marketing-footage-dev), екрани — Debug-Dev збірка.
type Step = {at: number; src: string};
type TapAt = {at: number; x: number; y: number};

// Екрани в телефоні: новий в'їжджає справа поверх попереднього
const PhoneSeq = ({steps, taps = [], x, y, w}: {steps: Step[]; taps?: TapAt[]; x: number; y: number; w: number}) => {
  const f = useCurrentFrame();
  return (
    <MiniPhone x={x} y={y} w={w}>
      {steps.map((s, i) => f >= s.at && (
        <div key={i} style={{position: 'absolute', inset: 0, transform: `translateX(${i ? ease(f, s.at, s.at + 8, [100, 0], Easing.out(Easing.cubic)) : 0}%)`}}>
          <Shot src={s.src} />
        </div>
      ))}
      {taps.map((t, i) => <Tap key={i} at={t.at} x={t.x} y={t.y} />)}
    </MiniPhone>
  );
};

// Наліпка у верхній смузі кадру на відрізку [from, to)
const Top = ({from, to, children, rotate = -2, size = 52}: {from: number; to: number; children: React.ReactNode; rotate?: number; size?: number}) => {
  const f = useCurrentFrame();
  if (f < from || f >= to) return null;
  return (
    <div style={{position: 'absolute', top: 250, left: 40, right: 40, textAlign: 'center', opacity: ease(f, to - 5, to, [1, 0])}}>
      <Sticker delay={from} rotate={rotate} style={{fontSize: size}}>{children}</Sticker>
    </div>
  );
};

const BAIL: Msg[] = [
  {at: 4, mine: true, h: BUBBLE, node: 'хто на котики фест у суботу? 🐈'},
  {at: 30, mine: false, h: BUBBLE, node: 'я пас 😬'},
  {at: 46, mine: false, h: BUBBLE, node: 'не можу, сорі'},
  {at: 62, mine: false, h: BUBBLE, node: 'може наступного разу 🙏'},
];
const P4_B = 100; // афіша → пошуки компанії → запит
const P4_C = 265; // події від людей і міста
const P4_D = 385; // своя подія
const P4_CTA = 435;
export const P4_FRAMES = 505;
const PX = 270;
const PY = 470;
const PW = 540;

const Companion = () => {
  return (
    <AbsoluteFill style={{fontFamily: 'Inter'}}>
      <Glow />
      <PhoneSeq x={PX} y={PY} w={PW} steps={[
        {at: 0, src: 'p4/kotyky-detail.png'},
        {at: 40, src: 'p4/companions-list.png'},
        {at: 100, src: 'p4/companion-detail.png'},
      ]} taps={[{at: 92, x: 297, y: 521}, {at: 135, x: 295, y: 800}]} />
      <Top from={2} to={92}>а на афіші вже є ті,<br />хто теж іде сам 👀</Top>
      <Top from={100} to={170} rotate={2}>надсилаєш запит —<br />і йдете разом 🙌</Top>
    </AbsoluteFill>
  );
};

const People = () => (
  <AbsoluteFill style={{fontFamily: 'Inter'}}>
    <Glow />
    <PhoneSeq x={PX} y={PY} w={PW} steps={[
      {at: 0, src: 'p4/map-people.png'},
      {at: 42, src: 'p4/city-lviv.png'},
      {at: 64, src: 'p4/city-odesa.png'},
      {at: 86, src: 'p4/cities.png'},
    ]} />
    <Top from={2} to={42}>а ще — події від людей:<br />настолки, пробіжки, кіно 🎲</Top>
    <Top from={42} to={64} rotate={3} size={72}>львів 📍</Top>
    <Top from={64} to={86} rotate={-3} size={72}>одеса 📍</Top>
    <Top from={86} to={125} size={50}>5 міст: київ, львів, одеса,<br />дніпро, харків</Top>
  </AbsoluteFill>
);

const Organize = () => (
  <AbsoluteFill style={{fontFamily: 'Inter'}}>
    <Glow />
    <PhoneSeq x={PX} y={PY} w={PW} steps={[{at: 0, src: 'ios_create.png'}]} />
    <Top from={2} to={60}>або збери своїх:<br />«організувати подію» ✨</Top>
  </AbsoluteFill>
);

export const P4 = ({music = true}: {music?: boolean}) => {
  useFonts();
  return (
    <AbsoluteFill style={{overflow: 'hidden', background: BG}}>
      <Music on={music} frames={P4_FRAMES} />
      {BAIL.map((m, i) => <Sfx key={i} at={m.at} src={`pin_pop_${(i % 3) + 1}`} volume={0.28} />)}
      {[P4_B, P4_B + 40, P4_B + 100, P4_C, P4_C + 42, P4_C + 64, P4_C + 86, P4_D].map((t, i) => <Sfx key={`w${i}`} at={t} src="whoosh" volume={0.2} />)}
      {[P4_B + 92, P4_B + 135].map((t) => <Sfx key={`t${t}`} at={t} src="ui_tick" volume={0.3} />)}
      <Sequence durationInFrames={P4_B + 4}>
        <Chat msgs={BAIL} typing={[0, 0]} hookOut={P4_B} hook={<>пов: друзі злились.<br />знову.</>} who="друзі · субота" face="👥" />
      </Sequence>
      <Sequence from={P4_B} durationInFrames={P4_C - P4_B + 4}><Companion /></Sequence>
      <Sequence from={P4_C} durationInFrames={P4_D - P4_C + 4}><People /></Sequence>
      <Sequence from={P4_D} durationInFrames={P4_CTA - P4_D + 4}><Organize /></Sequence>
      <Sequence from={P4_CTA}><EndCTA line="на події — не самому" /></Sequence>
      <Grain />
    </AbsoluteFill>
  );
};
