/* Native scrolling, progressively enhanced. Every guide and anchor works without JS. */
(() => {
  const links = [...document.querySelectorAll('[data-track]')];
  const sections = links.map(link => document.getElementById(link.dataset.track));
  const rail = document.querySelector('.category-rail');
  const motion = matchMedia('(prefers-reduced-motion: reduce)');
  const narrow = matchMedia('(max-width: 760px)');
  let pending = false;
  let active = -1;

  function update() {
    pending = false;
    if (!sections.length) return;
    // The reading line sits below the sticky header and mobile category menu.
    const readingLine = narrow.matches && rail ? 240 : innerHeight * .32;
    const tops = sections.map(section => section.getBoundingClientRect().top);
    let index = 0;
    tops.forEach((top, i) => { if (top <= readingLine) index = i; });
    if (scrollY + innerHeight >= document.documentElement.scrollHeight - 4) index = links.length - 1;
    if (index !== active) {
      active = index;
      links.forEach((link, i) => {
        if (i === index) link.setAttribute('aria-current', 'location');
        else link.removeAttribute('aria-current');
      });
    }
    if (rail) {
      links.forEach((link, i) => {
        const distance = Math.max(-3, Math.min(3, i - index));
        link.style.transform = motion.matches || narrow.matches ? '' :
          `translateX(${i === index ? 10 : Math.abs(distance) * -3}px) rotateY(${Math.abs(distance) * -7}deg) scale(${i === index ? 1.06 : 1 - Math.abs(distance) * .025})`;
      });
      const first = tops[0];
      const last = sections.at(-1).getBoundingClientRect().bottom;
      const progress = Math.max(0, Math.min(1, (readingLine - first) / (last - first)));
      rail.style.setProperty('--read-progress', progress);
    }
  }
  function schedule() {
    if (!pending) { pending = true; requestAnimationFrame(update); }
  }
  addEventListener('scroll', schedule, {passive: true});
  addEventListener('resize', schedule, {passive: true});
  addEventListener('load', schedule);
  motion.addEventListener('change', schedule);
  narrow.addEventListener('change', schedule);
  update();

  document.querySelectorAll('.guide-content pre').forEach(pre => {
    const code = pre.querySelector('code');
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'copy-code';
    button.textContent = 'Copy';
    button.setAttribute('aria-label', 'Copy code');
    const status = document.createElement('span');
    status.className = 'sr-only';
    status.setAttribute('role', 'status');
    pre.append(button, status);
    button.addEventListener('click', async () => {
      try {
        await navigator.clipboard.writeText(code.textContent);
        button.textContent = 'Copied';
        status.textContent = 'Copied to clipboard.';
        setTimeout(() => { button.textContent = 'Copy'; status.textContent = ''; }, 2000);
      } catch {
        status.textContent = 'Could not copy. Select and copy the code above.';
        button.textContent = 'Select to copy';
      }
    });
  });
})();
