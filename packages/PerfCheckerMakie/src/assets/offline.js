// Viewport controls for the actual exported WGLMakie figure.
(() => {
  const model = __PERFCHECKER_OFFLINE_MODEL__;
  const width = __PERFCHECKER_OFFLINE_WIDTH__, height = __PERFCHECKER_OFFLINE_HEIGHT__;
  function install() {
    const viewport = document.getElementById('offline-viewport');
    const figure = document.getElementById('offline-figure');
    if (!viewport || !figure) throw new Error('The exported Makie figure is missing');
    const style = document.createElement('style');
    style.textContent = `
      body{margin:0;background:#f6f8fb;color:#17243b;font:14px system-ui,sans-serif}
      .plot-toolbar{display:flex;align-items:center;flex-wrap:wrap;gap:8px;padding:10px 14px}
      .plot-brand{font-size:11px;letter-spacing:.05em;color:#64748b;margin-right:auto}
      .plot-toolbar button,#point-controls input{font:inherit;color:inherit;background:white;border:1px solid #c8d2e1;border-radius:6px;padding:7px 10px}
      .plot-toolbar button{cursor:pointer}.plot-toolbar button:focus-visible,#point-controls input:focus-visible,#offline-viewport:focus-visible{outline:2px solid #2563eb;outline-offset:2px}
      #point-controls{align-items:center;font-size:13px}#point-controls label{white-space:nowrap}
      #point-readout{flex:1;min-width:220px;padding:10px;border-left:3px solid #2563eb;background:#edf3ff;overflow-wrap:anywhere}
      #offline-viewport{box-sizing:border-box;border:1px solid #d5ddeb;background:white!important;overflow:auto!important;touch-action:pan-x pan-y}
      #offline-surface{position:relative;margin-inline:auto}#offline-figure{position:absolute;left:0;top:0}
      .popup:not(.show){display:none}.popup{box-sizing:border-box;max-width:calc(100vw - 16px);max-height:calc(100vh - 16px);overflow:auto;overflow-wrap:anywhere}
      .plot-help{font-size:12px;color:#526078;padding:0 14px 10px;margin:0}
      @media(max-width:600px){.plot-brand{flex-basis:100%}}
    `;
    document.head.append(style);
    const toolbar = document.createElement('div');
    toolbar.className = 'plot-toolbar';toolbar.setAttribute('aria-label','Plot controls');
    const brand = document.createElement('span');brand.className='plot-brand';brand.textContent='PerfChecker.jl · SAVED MEASUREMENTS';toolbar.append(brand);
    const button = (text,label,action) => {const node=document.createElement('button');node.textContent=text;node.setAttribute('aria-label',label);node.addEventListener('click',action);toolbar.append(node);return node};
    let zoom=1,fitScale=1;
    const surface=document.createElement('div');surface.id='offline-surface';
    viewport.insertBefore(surface,figure);surface.append(figure);
    const zoomLevel=document.createElement('output');zoomLevel.setAttribute('aria-live','polite');
    const hidePopups=()=>document.querySelectorAll('.popup.show').forEach(popup=>popup.classList.remove('show'));
    viewport.addEventListener('scroll',hidePopups,{passive:true});
    const renderSize=()=>{
      hidePopups();
      const scale=fitScale*zoom;
      figure.style.transform='scale('+scale+')';
      surface.style.width=(width*scale)+'px';surface.style.height=(height*scale)+'px';
      zoomLevel.textContent=Math.round(zoom*100)+'%';
    };
    const resize=()=>{
      const availableHeight=Math.max(540,Math.min(720,window.innerHeight-viewport.offsetTop-50));
      viewport.style.height=availableHeight+'px';
      fitScale=Math.max(Math.min(1,900/width),Math.min(1,(viewport.clientWidth-2)/width,(availableHeight-2)/height));
      renderSize();
    };
    const zoomTo=value=>{
      const previous=zoom;zoom=Math.max(1,Math.min(6,value));renderSize();
      viewport.scrollLeft=(viewport.scrollLeft+viewport.clientWidth/2)*zoom/previous-viewport.clientWidth/2;
      viewport.scrollTop=(viewport.scrollTop+viewport.clientHeight/2)*zoom/previous-viewport.clientHeight/2;
    };
    const fit=()=>{zoom=1;resize();viewport.scrollTo(0,0)};
    button('Fit','Fit plot',fit);button('−','Zoom out',()=>zoomTo(zoom/1.5));toolbar.append(zoomLevel);button('+','Zoom in',()=>zoomTo(zoom*1.5));
    button('Model JSON','Download plot model JSON',()=>{
      const url=URL.createObjectURL(new Blob([JSON.stringify(model,null,2)],{type:'application/json'}));
      const link=document.createElement('a');link.href=url;link.download='perfchecker-'+String(model.kind)+'.json';link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
    });
    viewport.before(toolbar);
    const help=document.createElement('p');help.className='plot-help';help.textContent=(document.getElementById('point-controls')?'Click a point marker to inspect it. Select an exact point with the index above. ':'')+'Shift-drag or scroll to pan; + / − zoom, 0 fits the plot.';viewport.after(help);
    viewport.setAttribute('role','group');viewport.tabIndex=0;
    // WGL's picker consumes untransformed canvas coordinates; CSS viewport
    // zoom changes its bounding rectangle. Keep popup page coordinates real.
    viewport.addEventListener('mousedown',event=>{
      const canvas=event.target.closest('canvas');if(!canvas)return;
      const box=canvas.getBoundingClientRect();
      if(!box.width||!box.height)return;
      Object.defineProperties(event,{
        clientX:{value:box.left+(event.clientX-box.left)*canvas.clientWidth/box.width},
        clientY:{value:box.top+(event.clientY-box.top)*canvas.clientHeight/box.height},
      });
    },true);
    viewport.addEventListener('mousedown',()=>{
      document.querySelectorAll('.popup.show').forEach(popup=>{
        const box=popup.getBoundingClientRect();
        popup.style.left=(window.scrollX+Math.max(8,Math.min(box.left,innerWidth-box.width-8)))+'px';
        popup.style.top=(window.scrollY+Math.max(8,Math.min(box.top,innerHeight-box.height-8)))+'px';
      });
    });
    viewport.addEventListener('keydown',event=>{
      if(event.target!==viewport)return;
      if(['+','=','-','0','ArrowLeft','ArrowRight','ArrowUp','ArrowDown'].includes(event.key))event.preventDefault();
      if(event.key==='+'||event.key==='=')zoomTo(zoom*1.5);
      else if(event.key==='-')zoomTo(zoom/1.5);
      else if(event.key==='0')fit();
      else if(event.key.startsWith('Arrow'))viewport.scrollBy(event.key==='ArrowLeft'?-50:event.key==='ArrowRight'?50:0,event.key==='ArrowUp'?-50:event.key==='ArrowDown'?50:0);
    });
    let drag;
    viewport.addEventListener('pointerdown',event=>{
      if(event.pointerType!=='mouse'||event.button!==0||!event.shiftKey)return;
      event.preventDefault();event.stopPropagation();viewport.setPointerCapture(event.pointerId);
      drag={x:event.clientX,y:event.clientY,left:viewport.scrollLeft,top:viewport.scrollTop};
    },true);
    viewport.addEventListener('pointermove',event=>{if(drag){viewport.scrollLeft=drag.left+drag.x-event.clientX;viewport.scrollTop=drag.top+drag.y-event.clientY}});
    viewport.addEventListener('pointerup',()=>drag=null);viewport.addEventListener('pointercancel',()=>drag=null);
    new ResizeObserver(resize).observe(viewport);window.addEventListener('resize',resize);resize();
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',install);else install();
})();
