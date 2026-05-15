(() => {
  function tintThumbs() {
    document.querySelectorAll(".paper-thumb[data-hash]").forEach((el) => {
      const h = el.dataset.hash || "";
      let n = 0;
      for (let i = 0; i < h.length; i++) n = (n * 31 + h.charCodeAt(i)) & 0xffffffff;
      const hue1 = Math.abs(n) % 360;
      const hue2 = (hue1 + 50) % 360;
      el.style.background = `linear-gradient(135deg, hsl(${hue1} 35% 75%) 0%, hsl(${hue2} 30% 65%) 100%)`;
    });
  }
  function attachToggles() {
    document.querySelectorAll(".paper-entry-head").forEach((head) => {
      head.addEventListener("click", (e) => {
        if (e.target.closest("a")) return;
        head.closest(".paper-entry").classList.toggle("expanded");
      });
    });
  }
  document.addEventListener("DOMContentLoaded", () => { tintThumbs(); attachToggles(); });
})();
