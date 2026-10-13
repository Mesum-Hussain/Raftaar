(() => {
  "use strict";
  const root = document.documentElement;
  const system = window.matchMedia("(prefers-color-scheme: dark)");
  const choices = ["auto", "light", "dark"];
  let preference = "auto";
  try {
    const saved = localStorage.getItem("raftaar-appearance");
    if (choices.includes(saved)) preference = saved;
  } catch {}

  function apply() {
    const color = preference === "auto" ? (system.matches ? "dark" : "light") : preference;
    root.dataset.appearance = preference;
    root.dataset.colorScheme = color;
    document.querySelector('meta[name="theme-color"]').content = color === "dark" ? "#111216" : "#f3f4f7";
    document.querySelectorAll("[data-appearance]").forEach(button => {
      if (button.tagName === "BUTTON") button.setAttribute("aria-pressed", String(button.dataset.appearance === preference));
    });
    document.dispatchEvent(new CustomEvent("appearancechange", { detail: { color } }));
  }
  apply();
  system.addEventListener("change", apply);
  window.addEventListener("storage", event => {
    if (event.key !== "raftaar-appearance" && event.key !== null) return;
    preference = choices.includes(event.newValue) ? event.newValue : "auto";
    apply();
  });
  document.addEventListener("DOMContentLoaded", () => {
    document.querySelectorAll("button[data-appearance]").forEach(button => {
      button.addEventListener("click", () => {
        preference = button.dataset.appearance;
        try { localStorage.setItem("raftaar-appearance", preference); } catch {}
        apply();
      });
    });
    apply();
  });
})();
