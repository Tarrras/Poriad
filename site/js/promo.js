// Промокод на сторінці події (worker eventPage, docs/promo-pins-2026-11.md): «Скопіювати» кладе код у буфер і каже, куди
// його вставити. Копіювання рахуємо (`promo_copy`, docs/analytics.md) — для звіту партнеру, тож із самим кодом.
import { track } from "./poriad.js?v=22";

const button = document.querySelector("[data-promo]");
button?.addEventListener("click", async () => {
  const code = button.dataset.promo;
  try { await navigator.clipboard.writeText(code); } catch { prompt("Промокод", code); return; }
  button.closest(".promo").querySelector(".done").textContent = "Скопійовано, вставте на сайті квитків";
  track("promo_copy", { event_id: button.dataset.event, code });
});
