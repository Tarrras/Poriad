# A1 · Промпти для Higgsfield MCP

Вставити повідомлення нижче в чат, де підключено Higgsfield MCP. Воно генерує тільки те, що A1 бере з Higgsfield: музику, звуки й одну опційну атмосферну підкладку. Мапу, постери, UI і текст збираємо в Remotion за [A1-weekend.md](A1-weekend.md): AI малює вигадані екрани й ламає кирилицю.

Орієнтовна ціна: музика + SFX ≈ 5 кредитів, підкладка (опційно) ≈ 10.

---

```text
You are producing audio and one optional background plate for a 24-second vertical (9:16) Instagram Reels / TikTok ad for "Poriad", an app that shows every city event on one map. The final edit is assembled elsewhere (Remotion), so generate ONLY the assets listed below — no full video, no app screens, no on-screen text.

Hard rules
- Before each generation, check the credit cost and show it to me. Stop and ask if the total goes above 20 credits.
- Never render text, letters, logos, UI, phone screens, or recognizable landmarks.
- No people, no faces, no vocals.
- After each asset, give me the download URL and its exact duration.

ASSET 1 — Music bed (required)
Model: sonilo_music, duration 25 s.
Prompt: "Warm nu-disco / French house instrumental, exactly 120 BPM, 4/4. Starts directly on a strong downbeat hit (kick + bright synth stab) at 0.00 s, no fade-in. Plucky bass enters at 2.0 s. Soft claps and bright synth stabs, uplifting evening mood, polished and modern. At 19.0 s the percussion drops out for a 2-second breakdown, then one final big stab at 21.0 s and a clean 3-second tail. No vocals."
Generate 2 variations. I will pick the one whose first hit is closest to 0.00 s and whose tempo holds steady.

ASSET 2 — Sound-effects pack (required)
Model: seed_audio. One short file per sound, dry (no reverb tail unless stated), normalized:
a) "pin_pop": a soft, bouncy, satisfying bubble pop, like a map pin springing up, 0.15 s. Make 3 variations at slightly different pitches.
b) "whoosh": a fast clean air whoosh for a whip-pan transition, 0.4 s.
c) "ui_tick": a tiny crisp interface click, high and light, 0.05 s.
d) "counter_tick": a quiet mechanical rolling-counter ticking, 1.0 s, evenly spaced ticks.
e) "city_bed": distant night city ambience — soft traffic hum, faint far-away voices unintelligible, calm, 4 s, loopable.

ASSET 3 — Optional intro plate (only after Assets 1–2 are done and I confirm)
Step A, keyframe image: model nano_banana_pro, aspect 9:16.
Prompt: "Abstract aerial view of a large city at night from very high above, dark navy and near-black tones, streets as faint thin lines of light, scattered warm coral and amber light points, river as a dark curving band, soft haze, minimal, no landmarks, no text, cinematic, tack sharp."
Generate 2 variations and wait for my pick.
Step B, animation: model kling3_0_turbo, start image = my pick, aspect 9:16, resolution 1080p, duration 5 s.
Prompt: "Lights across the city switch on in a wave spreading outward from the center, warm coral points appearing one after another, very slow push-in, camera otherwise static, calm and magical."

Deliver at the end: a list of all files with URLs, durations, model used, and credits spent.
```

---

## Що робити з результатом

| Ассет | Куди | Як використати |
|---|---|---|
| Музика | `marketing/video/public/music/a1.m4a` | Перевірити темп: перший удар має бути на 0 с, 120 BPM (B = 15 f). Якщо зсув, виставити `MUSIC_SHIFT`, як у Promo |
| SFX | `marketing/video/public/sfx/*.wav` | pin_pop на піни в сцені 1, whoosh на whip-переходи, ui_tick на постери в стрічці, counter_tick на лічильник у сцені 6, city_bed під сцену 1 (−30 dB) |
| Підкладка | `marketing/video/public/hf/a1-city.mp4` | Хук D: розмита й притемнена (dim 0.5) під мапою в сцені 1 або окремий варіант першої секунди |

Події ролика (10–11.10, перевірено на prod 07.10):
- 01 — Болеро. Дощ, Kyiv Modern Ballet, Київська опера, сб 18:00 (постер: силует танцівниці, облич нема)
- 02 — Орган під зорями «КінОрганум», Київський планетарій, сб 19:30 (ілюстрація)
- 03 — Бах. Джаз. Brass, «Київська троянда», нд 15:00

Стендап і «Ой не ходи, Грицю…» прибрано з добірки 07.10, бо на їхніх постерах обличчя артистів.

---

# Частина 2 · Промпт для самого відео

Як це зроблено: ролик генерується по шотах, і кожен шот анімує **справжній кадр** (постер чи скриншот мапи) як стартовий. Перший кадр тоді точний, а рух малий (світло, наїзд, паралакс), тож постери майже не спотворюються. Повний ролик одним проходом (Seedance 2.5, 24 с) вигадав би постери й інтерфейс і коштував би 150+ кредитів.

Текст, дати й фінальний кадр з логотипом AI не малює. Їх накладаємо в Remotion або CapCut за таблицею нижче.

Ціна: 5 кліпів Kling 3.0 Turbo 1080p, 21 с ≈ 42 кредити. Лишилося ≈ 44, тож або без Assets 3 з частини 1, або поповнити баланс.

Перед вставкою прикріпити до повідомлення файл `marketing/video/public/screens/map_posters.png`.

```text
Produce the shots for a 24-second vertical (9:16) Reels/TikTok ad for "Poriad", an app that shows every city event on one map. Theme: "Where to go in Kyiv this weekend, Oct 10–11" — three picks shown as real posters, then the map. I will add all text, music and the end card myself, so the clips must contain NO generated text.

Hard rules
- Model for every shot: kling3_0_turbo, aspect 9:16, resolution 1080p.
- Before each generation, show me the credit cost; stop and ask if the running total exceeds 45 credits.
- For shots 2–5 the start image is a REAL poster or screenshot. Its artwork, lettering and layout must stay unchanged: motion comes only from the camera, light and a subtle physical feel of the paper. No morphing, no new elements on the poster, no hands, no people.
- Never add text, logos, UI elements, phone frames or landmarks.
- Generate one take per shot. Show it to me before moving to the next shot.
- At the end, list every clip with URL, duration and credits spent.

Visual language for all shots: night mood, near-black background (#0B0B0F) with a faint violet glow, warm coral accent light (#E0582F), soft film grain, premium and calm, like an Apple product film.

SHOT 1 — "The city lights up" (5 s, text-to-video, no start image)
"Top-down view of an abstract dark city map at night, thin faint grey street lines and a dark curving river on a near-black background. Small glowing coral map pins pop up one after another in a wave spreading from the center outward, each with a tiny bounce and soft glow, about forty pins in total. Very slow push-in. Minimal, elegant, no text, no labels."

SHOT 2 — Pick 01, theatre (4 s)
Start image: https://images.karabas.com/external/018e50bb-71e5-7428-9b44-4f503fcfd169/events/019f6a39-fb90-7716-93ec-e6e0406eac43/2824516440_ImageBig639149638151071392.jpeg
"The poster rests on a dark matte surface as a physical printed object. Slow push-in with a gentle 3-degree tilt, a soft warm light sweep glides diagonally across the paper, subtle shadow under the poster edges. The poster artwork stays exactly the same."

SHOT 3 — Pick 02, stand-up (4 s)
Start image: https://storage.concert.ua/JIK/23/HE/6ab3cbc06f229/f22c.png:31-catalog-event_item-desktop
(If this poster shows a photo of a performer's face, skip this shot and tell me.)
"The poster rests on a dark surface. Slightly energetic camera: a quick small push-in that settles, then a gentle drift down, a cool-to-warm light flicker crosses the paper like stage lights. The poster artwork stays exactly the same."

SHOT 4 — Pick 03, jazz on Sunday afternoon (4 s)
Start image: https://images.karabas.com/external/018e50bb-71e5-7428-9b44-4f503fcfd169/events/01a0b58f-5ccc-77fb-8207-58f3b2b07d23/2898686756_ImageBig639253600188077063.jpeg
"The poster rests on a dark surface. Warm amber afternoon light slowly fills the frame from the left like sunlight through a window, slow push-in, soft dust particles float in the light. The poster artwork stays exactly the same."

SHOT 5 — The map (4 s)
Start image: the attached file map_posters.png (a real app screenshot).
"Very slow pull-back, the screenshot floats in dark space with a soft violet glow behind it and a gentle shadow, the coral map pins pulse softly once. Keep every element of the screenshot exactly as it is, no new UI, no text changes."

## Монтаж (Remotion / CapCut)

> Це таймлайн v1. Актуальний (v2, хук з органом і відлік 03 → 01, 07.10) — у [A1-weekend.md](A1-weekend.md). Shot 1 (мапа з пінами) у v2 не використовується.

| Час | Кліп | Текст поверх (бренд-біблія) | Звук |
|---|---|---|---|
| 0:00–0:02 | Shot 1, лише 0–2.4 с на 1.2× (далі піни розповзаються, центр порожніє) | **Київ** · **10–11 жовтня** · *куди піти* | удар музики, pin_pop × багато |
| 0:02–0:04 | whip → стрічка постерів (Remotion, `home_posters.mp4`) | **3 плани, які я б не пропустив** | whoosh |
| 0:04–0:09 | Remotion: статичний постер, Ken Burns + світловий відблиск | **01** · **СБ 18:00** · **Болеро. Дощ** · Київська опера | ui_tick |
| 0:09–0:14 | Shot «Орган» (Kling, 4 с → 0.8×) | **02** · **СБ 19:30** · **Орган під зорями** · Київський планетарій | whoosh |
| 0:14–0:19 | Shot 4 | **03** · **НД 15:00** · **Бах. Джаз. Brass** · «Київська троянда» | whoosh |
| 0:19–0:21 | Remotion: скриншот мапи на сяйві | **ще 200+** · на ці вихідні — на мапі | counter_tick, брейк |
| 0:21–0:24 | Енд-кард (не AI) | **Усе — поряд.** · безкоштовно в App Store | фінальний акорд |

Перевірити кожен кліп покадрово: якщо літери на постері «попливли», беремо замість кліпу статичний постер із наїздом у Remotion. Позначку AI-generated у TikTok і Instagram краще увімкнути: охоплення вона не ріже, а ризик блокування за неї знімає.
