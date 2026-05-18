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
  function attachTopicFilter() {
    const chips = document.querySelectorAll(".topic-chip[data-topic]");
    if (!chips.length) return;
    const entries = document.querySelectorAll(".paper-entry[data-tags]");
    const blocks = document.querySelectorAll(".year-block");
    const apply = (topic) => {
      entries.forEach((entry) => {
        const tags = (entry.dataset.tags || "").split(/\s+/);
        entry.classList.toggle("filtered-out", topic !== null && !tags.includes(topic));
      });
      blocks.forEach((b) => {
        const anyVisible = b.querySelector(".paper-entry:not(.filtered-out)");
        b.classList.toggle("filtered-out", !anyVisible);
      });
      chips.forEach((c) => c.classList.toggle("active", c.dataset.topic === topic));
    };
    chips.forEach((chip) => {
      chip.addEventListener("click", (e) => {
        e.preventDefault();
        const topic = chip.dataset.topic;
        const wasActive = chip.classList.contains("active");
        apply(wasActive ? null : topic);
        if (!wasActive) {
          const firstMatch = document.querySelector(".year-block:not(.filtered-out)");
          if (firstMatch) firstMatch.scrollIntoView({ behavior: "smooth", block: "start" });
        }
      });
    });
  }
  document.addEventListener("DOMContentLoaded", () => { tintThumbs(); attachToggles(); attachTopicFilter(); });
})();
