(() => {
  'use strict';
  const score = document.getElementById('score');
  const layer = document.getElementById('measure-layer');
  let osmd = null;
  let down = null;
  let maxTravel = 0;
  let activeOrdinal = null;
  let resizeTimer = null;

  const post = (type, payload = {}) => {
    if (window.ScoreBridge && window.ScoreBridge.postMessage) {
      window.ScoreBridge.postMessage(JSON.stringify({ type, ...payload }));
    }
  };

  const decodeUtf8 = (encoded) => {
    const bytes = Uint8Array.from(atob(encoded), (char) => char.charCodeAt(0));
    return new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  };

  const measureRects = () => {
    const unit = opensheetmusicdisplay.EngravingRules.unit;
    return osmd.GraphicSheet.MeasureList.map((staffMeasures, index) => {
      const boxes = staffMeasures
        .filter(Boolean)
        .map((measure) => measure.PositionAndShape)
        .filter(Boolean);
      if (boxes.length === 0) return null;
      const left = Math.min(...boxes.map((box) => (box.AbsolutePosition.x + box.BorderLeft) * unit));
      const top = Math.min(...boxes.map((box) => (box.AbsolutePosition.y + box.BorderTop) * unit));
      const right = Math.max(...boxes.map((box) => (box.AbsolutePosition.x + box.BorderRight) * unit));
      const bottom = Math.max(...boxes.map((box) => (box.AbsolutePosition.y + box.BorderBottom) * unit));
      return { ordinal: index + 1, left, top, width: right - left, height: bottom - top };
    }).filter(Boolean);
  };

  const applyHighlight = (ordinal, scrollIntoView) => {
    layer.querySelectorAll('.active').forEach((element) => element.classList.remove('active'));
    const target = layer.querySelector(`[data-ordinal="${Number(ordinal)}"]`);
    if (!target) return;
    target.classList.add('active');
    if (scrollIntoView) {
      const rect = target.getBoundingClientRect();
      const visible = rect.top >= 48 && rect.bottom <= window.innerHeight - 96;
      if (!visible) target.scrollIntoView({ block: 'center', behavior: 'smooth' });
    }
  };

  const rebuildLayer = (complete) => {
    layer.replaceChildren();
    const rects = measureRects();
    for (const rect of rects) {
      const hit = document.createElement('div');
      hit.className = 'measure-hit';
      hit.dataset.ordinal = String(rect.ordinal);
      hit.style.left = `${rect.left}px`;
      hit.style.top = `${rect.top}px`;
      hit.style.width = `${Math.max(1, rect.width)}px`;
      hit.style.height = `${Math.max(1, rect.height)}px`;
      layer.appendChild(hit);
    }
    layer.style.width = `${score.scrollWidth}px`;
    layer.style.height = `${score.scrollHeight}px`;
    if (activeOrdinal !== null) applyHighlight(activeOrdinal, false);
    post('layout', { complete, measures: rects });
  };

  const render = async (xml) => {
    osmd = new opensheetmusicdisplay.OpenSheetMusicDisplay(score, {
      backend: 'svg',
      autoResize: false,
      drawTitle: true,
      pageFormat: 'Endless',
      pageBackgroundColor: '#f8f0dc',
      drawUpToMeasureNumber: 12,
    });
    osmd.setLogLevel('warn');
    await osmd.load(xml);
    osmd.render();
    rebuildLayer(false);
    post('ready');
    await new Promise((resolve) => requestAnimationFrame(resolve));
    osmd.setOptions({ drawUpToMeasureNumber: 1000000 });
    osmd.renderAndScrollBack();
    rebuildLayer(true);
  };

  document.addEventListener('pointerdown', (event) => {
    down = {
      x: event.clientX,
      y: event.clientY,
      at: performance.now(),
      pointerCount: event.isPrimary ? 1 : 2,
    };
    maxTravel = 0;
  }, { passive: true });

  document.addEventListener('pointermove', (event) => {
    if (!down) return;
    maxTravel = Math.max(
      maxTravel,
      Math.hypot(event.clientX - down.x, event.clientY - down.y),
    );
  }, { passive: true });

  document.addEventListener('pointerup', (event) => {
    if (!down) return;
    const gesture = {
      x: event.clientX + window.scrollX,
      y: event.clientY + window.scrollY,
      travel: maxTravel,
      durationMs: Math.round(performance.now() - down.at),
      pointerCount: down.pointerCount,
    };
    down = null;
    post('gestureEnd', gesture);
  }, { passive: true });

  window.scoreBridge = Object.freeze({
    async loadMusicXmlBase64(encoded) {
      try { await render(decodeUtf8(encoded)); }
      catch (error) { post('error', { message: String(error).slice(0, 500) }); }
    },
    highlightMeasure(ordinal, scrollIntoView) {
      activeOrdinal = Number(ordinal);
      applyHighlight(activeOrdinal, scrollIntoView);
    },
    clearHighlight() {
      activeOrdinal = null;
      layer.querySelectorAll('.active').forEach((element) => element.classList.remove('active'));
    },
  });

  window.addEventListener('resize', () => {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(() => {
      if (!osmd) return;
      osmd.renderAndScrollBack();
      rebuildLayer(true);
    }, 150);
  });

  window.addEventListener('error', (event) => {
    post('error', { message: String(event.message || '谱面脚本错误').slice(0, 500) });
  });
})();
