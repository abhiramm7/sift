(() => {
  // Per-paper tile/art tint based on a hash of the paper id or tag.
  function tintArt() {
    document.querySelectorAll("[data-hash]").forEach((el) => {
      if (el.dataset.tinted) return;
      el.dataset.tinted = "1";
      const h = el.dataset.hash;
      let n = 0;
      for (let i = 0; i < h.length; i++) n = (n * 31 + h.charCodeAt(i)) & 0xffffffff;
      const hue1 = Math.abs(n) % 360;
      const hue2 = (hue1 + 60) % 360;
      const hue3 = (hue1 + 120) % 360;
      const art = el.classList.contains("hero-card") ? el.querySelector(".hero-art")
                : el.classList.contains("card") ? el.querySelector(".card-art")
                : null;
      if (art) {
        art.style.background = `linear-gradient(135deg, hsl(${hue1} 70% 55%) 0%, hsl(${hue2} 65% 50%) 50%, hsl(${hue3} 75% 55%) 100%)`;
      } else if (el.classList.contains("topic-chip")) {
        el.style.borderLeft = `3px solid hsl(${hue1} 70% 55%)`;
      }
    });
  }

  // Expand/collapse a paper row's summary on the academic /papers page.
  function attachPaperToggle() {
    document.querySelectorAll(".paper-entry").forEach((entry) => {
      if (entry.dataset.attached) return;
      entry.dataset.attached = "1";
      const head = entry.querySelector(".paper-entry-head");
      const body = entry.querySelector(".paper-entry-body");
      if (!head || !body) return;
      head.addEventListener("click", (e) => {
        if (e.target.closest("a")) return;
        entry.classList.toggle("expanded");
      });
    });
  }

  function init() {
    tintArt();
    attachPaperToggle();
  }

  document.addEventListener("DOMContentLoaded", init);
  document.addEventListener("htmx:afterSwap", init);
})();
