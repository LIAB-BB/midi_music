(() => {
  'use strict';
  const score = document.getElementById('score');
  const layer = document.getElementById('measure-layer');
  let osmd = null;
  let generation = 0;
  let down = null;
  let maxTravel = 0;
  let maxPointerCount = 0;
  let primaryPointerId = null;
  let activeOrdinal = null;
  let resizeTimer = null;
  let zoomTimer = null;
  let currentZoom = 0.7;
  let zoomRequestGeneration = 0;
  const activePointers = new Set();

  const post = (type, payload = {}) => {
    if (window.ScoreBridge && window.ScoreBridge.postMessage) {
      window.ScoreBridge.postMessage(JSON.stringify({ type, ...payload }));
    }
  };

  const decodeUtf8 = (encoded) => {
    const bytes = Uint8Array.from(atob(encoded), (char) => char.charCodeAt(0));
    return new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  };

  const parseMusicXml = (xml) => {
    const document = new DOMParser().parseFromString(xml, 'application/xml');
    if (document.querySelector('parsererror')) {
      throw new Error('无法解析 MusicXML 文档');
    }
    return document;
  };

  const resetRenderSurface = () => {
    clearTimeout(resizeTimer);
    clearTimeout(zoomTimer);
    osmd = null;
    activeOrdinal = null;
    score.replaceChildren();
    layer.replaceChildren();
  };

  const clientToLayer = (clientX, clientY) => {
    const layerRect = layer.getBoundingClientRect();
    return { x: clientX - layerRect.left, y: clientY - layerRect.top };
  };

  const createDocumentMapper = (renderer) => {
    const svg = score.querySelector('svg');
    const pageBox = renderer.GraphicSheet.MusicPages[0]?.PositionAndShape;
    if (!svg || !pageBox || !pageBox.Size || pageBox.Size.width <= 0) {
      throw new Error('无法定位 OSMD SVG 页面');
    }
    const viewBox = svg.viewBox.baseVal;
    const svgRect = svg.getBoundingClientRect();
    if (viewBox.width <= 0 || viewBox.height <= 0 || svgRect.width <= 0 || svgRect.height <= 0) {
      throw new Error('OSMD SVG 页面尺寸无效');
    }
    const pageScale = viewBox.width / pageBox.Size.width;
    const scaleX = svgRect.width / viewBox.width;
    const scaleY = svgRect.height / viewBox.height;
    const pageX = pageBox.AbsolutePosition?.x || 0;
    const pageY = pageBox.AbsolutePosition?.y || 0;
    return (x, y) => clientToLayer(
      svgRect.left + (x - pageX) * pageScale * scaleX,
      svgRect.top + (y - pageY) * pageScale * scaleY,
    );
  };

  const measureRects = (renderer) => {
    const toDocument = createDocumentMapper(renderer);
    return renderer.GraphicSheet.MeasureList.map((staffMeasures, index) => {
      const boxes = staffMeasures
        .filter(Boolean)
        .map((measure) => measure.PositionAndShape)
        .filter(Boolean);
      if (boxes.length === 0) return null;
      const corners = boxes.flatMap((box) => [
        toDocument(box.AbsolutePosition.x + box.BorderLeft, box.AbsolutePosition.y + box.BorderTop),
        toDocument(box.AbsolutePosition.x + box.BorderRight, box.AbsolutePosition.y + box.BorderBottom),
      ]);
      const left = Math.min(...corners.map((point) => point.x));
      const top = Math.min(...corners.map((point) => point.y));
      const right = Math.max(...corners.map((point) => point.x));
      const bottom = Math.max(...corners.map((point) => point.y));
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

  const rebuildLayer = (renderer, complete, renderGeneration) => {
    if (renderGeneration !== generation) return;
    layer.replaceChildren();
    const rects = measureRects(renderer);
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

  const render = async (xml, renderGeneration) => {
    const isCurrent = () => renderGeneration === generation;
    if (!isCurrent()) return;
    const document = parseMusicXml(xml);
    const renderer = new opensheetmusicdisplay.OpenSheetMusicDisplay(score, {
      backend: 'svg',
      autoResize: false,
      drawTitle: false,
      pageFormat: 'Endless',
      pageBackgroundColor: '#f8f0dc',
      drawUpToMeasureNumber: 12,
    });
    renderer.setLogLevel('warn');
    await renderer.load(document);
    if (!isCurrent()) return;
    osmd = renderer;
    renderer.Zoom = currentZoom;
    renderer.render();
    rebuildLayer(renderer, false, renderGeneration);
    if (!isCurrent()) return;
    post('ready');
    await new Promise((resolve) => requestAnimationFrame(resolve));
    if (!isCurrent()) return;
    renderer.setOptions({ drawUpToMeasureNumber: 1000000 });
    renderer.renderAndScrollBack();
    rebuildLayer(renderer, true, renderGeneration);
  };

  document.addEventListener('pointerdown', (event) => {
    activePointers.add(event.pointerId);
    maxPointerCount = Math.max(maxPointerCount, activePointers.size);
    if (!event.isPrimary || down) return;
    primaryPointerId = event.pointerId;
    down = {
      x: event.clientX,
      y: event.clientY,
      at: performance.now(),
    };
    maxTravel = 0;
    maxPointerCount = activePointers.size;
  }, { passive: true });

  document.addEventListener('pointermove', (event) => {
    if (!down || event.pointerId !== primaryPointerId) return;
    maxTravel = Math.max(
      maxTravel,
      Math.hypot(event.clientX - down.x, event.clientY - down.y),
    );
  }, { passive: true });

  const finishGesture = (event) => {
    activePointers.delete(event.pointerId);
    if (!down || event.pointerId !== primaryPointerId) return;
    const point = clientToLayer(event.clientX, event.clientY);
    const gesture = {
      x: point.x,
      y: point.y,
      travel: maxTravel,
      durationMs: Math.round(performance.now() - down.at),
      pointerCount: Math.min(10, Math.max(1, maxPointerCount)),
    };
    down = null;
    primaryPointerId = null;
    maxTravel = 0;
    maxPointerCount = activePointers.size;
    post('gestureEnd', gesture);
  };

  document.addEventListener('pointerup', (event) => {
    finishGesture(event);
  }, { passive: true });

  const cancelGesture = (event) => {
    if (!down) {
      activePointers.delete(event.pointerId);
      return;
    }
    const point = clientToLayer(event.clientX, event.clientY);
    const gesture = {
      x: point.x,
      y: point.y,
      travel: Math.max(maxTravel, 11),
      durationMs: Math.round(performance.now() - down.at),
      pointerCount: Math.min(10, Math.max(1, maxPointerCount)),
    };
    down = null;
    primaryPointerId = null;
    maxTravel = 0;
    maxPointerCount = 0;
    activePointers.clear();
    post('gestureEnd', gesture);
  };

  document.addEventListener('pointercancel', (event) => {
    cancelGesture(event);
  }, { passive: true });

  window.scoreBridge = Object.freeze({
    async loadMusicXmlBase64(encoded) {
      const renderGeneration = ++generation;
      resetRenderSurface();
      try { await render(decodeUtf8(encoded), renderGeneration); }
      catch (error) {
        if (renderGeneration !== generation) return;
        post('error', { message: String(error).slice(0, 500) });
      }
    },
    highlightMeasure(ordinal, scrollIntoView) {
      activeOrdinal = Number(ordinal);
      applyHighlight(activeOrdinal, scrollIntoView);
    },
    clearHighlight() {
      activeOrdinal = null;
      layer.querySelectorAll('.active').forEach((element) => element.classList.remove('active'));
    },
    setZoom(value, requestGeneration = zoomRequestGeneration + 1) {
      const zoom = Number(value);
      if (!Number.isFinite(zoom)) throw new Error('乐谱缩放比例无效');
      const request = Number(requestGeneration);
      if (!Number.isSafeInteger(request) || request < 0) {
        throw new Error('乐谱缩放请求无效');
      }
      if (request < zoomRequestGeneration) return;
      zoomRequestGeneration = request;
      currentZoom = Math.min(1.4, Math.max(0.5, zoom));
      const renderer = osmd;
      if (!renderer) return;
      clearTimeout(zoomTimer);
      const zoomGeneration = generation;
      zoomTimer = setTimeout(() => {
        zoomTimer = null;
        if (
          request !== zoomRequestGeneration ||
          renderer !== osmd ||
          zoomGeneration !== generation
        ) return;
        renderer.Zoom = currentZoom;
        renderer.renderAndScrollBack();
        rebuildLayer(renderer, true, zoomGeneration);
        if (activeOrdinal !== null) applyHighlight(activeOrdinal, true);
      }, 80);
    },
  });

  window.addEventListener('resize', () => {
    clearTimeout(resizeTimer);
    const resizeGeneration = generation;
    const renderer = osmd;
    resizeTimer = setTimeout(() => {
      if (!renderer || renderer !== osmd || resizeGeneration !== generation) return;
      renderer.renderAndScrollBack();
      rebuildLayer(renderer, true, resizeGeneration);
    }, 150);
  });

  window.addEventListener('error', (event) => {
    post('error', { message: String(event.message || '谱面脚本错误').slice(0, 500) });
  });
})();
