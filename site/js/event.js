// Сторінка афішної події (worker eventPage): «Шукаю компанію» відкриває ту саму шторку, що й на /afisha, — з квитком
// події, QR на комп'ютері й «Уже є застосунок? Відкрити подію» на iPhone. Збій картки — шторка без квитка.
import { ensureCards, cards, openInstall } from "./ui.js?v=23";

const id = location.pathname.split("/")[2].toLowerCase();
document.querySelectorAll("[data-lock]").forEach((button) => button.addEventListener("click", async () => {
  await ensureCards([id]).catch(() => []);
  openInstall(button.dataset.lock, cards.get(id) ?? null);
}));
