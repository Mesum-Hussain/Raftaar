const stage = document.querySelector('.editor-stage');
const preview = document.querySelector('.editor-preview');
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
const pointer = window.matchMedia('(hover: hover) and (pointer: fine)');
const narrow = window.matchMedia('(max-width: 760px)');

if (stage && preview) {
  let frame = 0;
  let previous = 0;
  let x = .5, y = .1, tiltX = 0, tiltY = 0;
  let targetX = .5, targetY = .1, targetTiltX = 0, targetTiltY = 0;

  function paint() {
    preview.style.setProperty('--light-x', `${(x * 100).toFixed(2)}%`);
    preview.style.setProperty('--light-y', `${(y * 100).toFixed(2)}%`);
    preview.style.setProperty('--tilt-x', `${tiltX.toFixed(3)}deg`);
    preview.style.setProperty('--tilt-y', `${tiltY.toFixed(3)}deg`);
  }

  function animate(now) {
    const dt = previous ? Math.min(now - previous, 64) : 16;
    previous = now;
    const easing = 1 - Math.exp(-dt / 160);
    x += (targetX - x) * easing;
    y += (targetY - y) * easing;
    tiltX += (targetTiltX - tiltX) * easing;
    tiltY += (targetTiltY - tiltY) * easing;
    paint();
    const remaining = Math.abs(targetX - x) + Math.abs(targetY - y) + Math.abs(targetTiltX - tiltX) + Math.abs(targetTiltY - tiltY);
    if (remaining > .001) frame = requestAnimationFrame(animate);
    else { frame = previous = 0; }
  }

  function wake() {
    if (!frame && !document.hidden) frame = requestAnimationFrame(animate);
  }

  function reset() {
    targetX = .5;
    targetY = .1;
    targetTiltX = targetTiltY = 0;
    wake();
  }

  function stop() {
    cancelAnimationFrame(frame);
    frame = previous = 0;
    targetX = x = .5;
    targetY = y = .1;
    targetTiltX = targetTiltY = tiltX = tiltY = 0;
    paint();
  }

  stage.addEventListener('pointermove', event => {
    if (reducedMotion.matches || !pointer.matches || narrow.matches || event.pointerType === 'touch') return;
    const rect = stage.getBoundingClientRect();
    targetX = Math.max(0, Math.min(1, (event.clientX - rect.left) / rect.width));
    targetY = Math.max(0, Math.min(1, (event.clientY - rect.top) / rect.height));
    targetTiltX = (.5 - targetY) * 1.4;
    targetTiltY = (targetX - .5) * 1.8;
    wake();
  });
  stage.addEventListener('pointerleave', reset);
  window.addEventListener('blur', stop);
  document.addEventListener('visibilitychange', stop);
  reducedMotion.addEventListener('change', stop);
  pointer.addEventListener('change', stop);
  narrow.addEventListener('change', stop);
  new IntersectionObserver(entries => { if (!entries[0].isIntersecting) stop(); }).observe(stage);
}

// A slow pixel current behind the hero. Stop drawing when it is offscreen.
const canvas = document.querySelector('#pixel-canvas');
const hero = document.querySelector('.hero');
const context = canvas?.getContext('2d');
if (context && hero) {
  let width = 0, height = 0, frame = 0, last = 0, time = 0;
  let visible = true;
  let mouseX = .5, targetX = .5;
  let dark = document.documentElement.dataset.colorScheme === 'dark';

  function draw() {
    context.clearRect(0, 0, width, height);
    const spacing = width < 760 ? 9 : 10;
    const phase = time * .00025;
    for (let x = 0; x < width; x += spacing) {
      const edge = Math.pow(Math.abs(x / width - .5) * 2, .8);
      for (let row = 0; row < 24; row++) {
        const y = height * .67 + row * spacing * .62
          + Math.sin(x * .006 + phase + row * .09) * (32 + edge * 35)
          + Math.sin(x * .002 - phase * .6) * 35;
        const envelope = Math.sin(row / 24 * Math.PI);
        const ripple = .5 + .5 * Math.sin(x * .012 - phase * 1.5 + row * .4);
        const proximity = Math.max(0, 1 - Math.abs(x / width - mouseX) * 3);
        const alpha = envelope * (.06 + edge * .38) * (.35 + ripple * .65) + proximity * envelope * .025;
        context.fillStyle = dark ? `rgba(138,164,255,${alpha})` : `rgba(80,106,199,${alpha})`;
        const size = ripple > .8 ? 2.2 : 1.3;
        context.fillRect(Math.round(x), Math.round(y), size, size);
      }
    }
  }

  function animate(now) {
    frame = 0;
    if (!last || now - last >= 32) {
      time += last ? Math.min(now - last, 64) : 0;
      last = now;
      mouseX += (targetX - mouseX) * .08;
      draw();
    }
    if (visible && !reducedMotion.matches && !document.hidden) frame = requestAnimationFrame(animate);
  }

  function update() {
    cancelAnimationFrame(frame);
    frame = last = 0;
    draw();
    if (visible && !reducedMotion.matches && !document.hidden) frame = requestAnimationFrame(animate);
  }

  new ResizeObserver(() => {
    const bounds = canvas.getBoundingClientRect();
    width = bounds.width;
    height = bounds.height;
    const ratio = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = Math.round(width * ratio);
    canvas.height = Math.round(height * ratio);
    context.setTransform(ratio, 0, 0, ratio, 0, 0);
    update();
  }).observe(canvas);
  new IntersectionObserver(entries => { visible = entries[0].isIntersecting; update(); }).observe(hero);
  hero.addEventListener('pointermove', event => {
    if (reducedMotion.matches || !pointer.matches || event.pointerType === 'touch') return;
    const bounds = hero.getBoundingClientRect();
    targetX = (event.clientX - bounds.left) / bounds.width;
  });
  hero.addEventListener('pointerleave', () => { targetX = .5; });
  document.addEventListener('appearancechange', event => { dark = event.detail.color === 'dark'; draw(); });
  document.addEventListener('visibilitychange', update);
  reducedMotion.addEventListener('change', update);
}
