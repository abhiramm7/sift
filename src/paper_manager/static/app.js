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

  function attachDropzone() {
    const zone = document.getElementById("pdf-dropzone");
    if (!zone || zone.dataset.attached) return;
    zone.dataset.attached = "1";
    const input = zone.querySelector("#pdf-input");
    const picker = zone.querySelector("#pdf-pick");
    const filesEl = zone.querySelector("#pdf-files");
    const submit = zone.querySelector(".dropzone-submit");

    function renderFiles() {
      const files = Array.from(input.files || []);
      if (!files.length) {
        filesEl.textContent = "";
        submit.disabled = true;
        return;
      }
      filesEl.innerHTML = files
        .map((f) => `<span class="dropzone-file">${f.name}</span>`)
        .join("");
      submit.disabled = false;
    }

    picker.addEventListener("click", (e) => {
      e.preventDefault();
      input.click();
    });
    input.addEventListener("change", renderFiles);

    ["dragenter", "dragover"].forEach((ev) => {
      zone.addEventListener(ev, (e) => {
        e.preventDefault();
        e.stopPropagation();
        zone.classList.add("is-dragging");
      });
    });
    ["dragleave", "dragend", "drop"].forEach((ev) => {
      zone.addEventListener(ev, (e) => {
        e.preventDefault();
        e.stopPropagation();
        if (ev !== "drop") zone.classList.remove("is-dragging");
      });
    });
    zone.addEventListener("drop", (e) => {
      zone.classList.remove("is-dragging");
      const dropped = Array.from(e.dataTransfer?.files || [])
        .filter((f) => f.type === "application/pdf" || f.name.toLowerCase().endsWith(".pdf"));
      if (!dropped.length) return;
      const dt = new DataTransfer();
      dropped.forEach((f) => dt.items.add(f));
      input.files = dt.files;
      renderFiles();
    });

    zone.addEventListener("htmx:afterRequest", () => {
      input.value = "";
      renderFiles();
    });
  }

  function init() {
    tintArt();
    attachPaperToggle();
    attachDropzone();
  }

  document.addEventListener("DOMContentLoaded", init);
  document.addEventListener("htmx:afterSwap", init);
})();
