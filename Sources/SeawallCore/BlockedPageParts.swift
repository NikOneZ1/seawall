import Foundation

/// The pieces the blocked-site pages are put together from: one shell (header, the reopening time
/// and its rows, the block-is-over state, the clock) and three small concepts. Generated from flat HTML/CSS/JS;
/// no external files, no fixed positioning, no WebGL.
enum BlockedPageParts {
    static let icon = ##"""
<svg class="mark" viewBox="100 100 824 824" aria-hidden="true"><defs><clipPath id="blk"><rect x="262" y="262" width="500" height="500" rx="130"/></clipPath></defs><rect x="100" y="100" width="824" height="824" rx="185" fill="#E2382F"/><rect x="262" y="262" width="500" height="500" rx="130" fill="#fff"/><path d="M250 557 L258 563 L266 568 L274 572 L282 576 L290 580 L298 582 L306 583 L314 583 L322 582 L330 580 L338 576 L346 572 L354 568 L362 563 L370 557 L378 552 L386 546 L394 541 L402 536 L410 533 L418 530 L426 528 L434 527 L442 527 L450 529 L458 531 L466 534 L474 539 L482 543 L490 549 L498 554 L506 560 L514 565 L522 570 L530 575 L538 578 L546 581 L554 582 L562 583 L570 582 L578 581 L586 578 L594 575 L602 570 L610 565 L618 560 L626 554 L634 549 L642 543 L650 539 L658 534 L666 531 L674 529 L682 527 L690 527 L698 528 L706 530 L714 533 L722 536 L730 541 L738 546 L746 552 L754 557 L762 563 L770 568 L772 780 L250 780Z" fill="#C9CCCE" clip-path="url(#blk)"/><path d="M250 653 L258 649 L266 645 L274 640 L282 635 L290 629 L298 624 L306 619 L314 615 L322 611 L330 608 L338 606 L346 604 L354 604 L362 605 L370 607 L378 609 L386 613 L394 617 L402 622 L410 627 L418 632 L426 637 L434 642 L442 647 L450 651 L458 655 L466 657 L474 659 L482 660 L490 660 L498 658 L506 656 L514 653 L522 649 L530 645 L538 640 L546 635 L554 629 L562 624 L570 619 L578 615 L586 611 L594 608 L602 606 L610 604 L618 604 L626 605 L634 607 L642 609 L650 613 L658 617 L666 622 L674 627 L682 632 L690 637 L698 642 L706 647 L714 651 L722 655 L730 657 L738 659 L746 660 L754 660 L762 658 L770 656 L772 780 L250 780Z" fill="#161616" clip-path="url(#blk)"/></svg>
"""##
    static let shellCSS = ##"""
:root{color-scheme:light dark;--bg:#FFFFFF;--ink:#161616;--muted:#686C70;--rule:#161616;--soft:#E4E4E2;--chip:#EFEFEC;--time:#D93026;--on-ink:#FFFFFF;
--font:"Barlow",-apple-system,BlinkMacSystemFont,"Helvetica Neue",sans-serif;--cond:"Barlow Semi Condensed","Barlow",-apple-system,BlinkMacSystemFont,"Helvetica Neue",sans-serif}
@media (prefers-color-scheme:dark){:root{--bg:#141414;--ink:#F2F2F0;--muted:#A3A7AB;--rule:#F2F2F0;--soft:#2E2E2E;--chip:#262626;--time:#FF5A4F;--on-ink:#141414}}
*{box-sizing:border-box}
html{background:var(--bg);margin:0}
body{margin:0;min-height:100vh;background:var(--bg);color:var(--ink);font:17px/1.45 var(--font);-webkit-font-smoothing:antialiased;font-variant-numeric:tabular-nums;display:flex;flex-direction:column}
::selection{background:var(--ink);color:var(--bg)}
[hidden]{display:none!important}
.top{display:grid;grid-template-columns:1fr auto 1fr;align-items:end;gap:16px;margin:0 48px;padding-top:24px;border-bottom:2px solid var(--rule)}
.brand{display:flex;align-items:center;gap:10px;font:700 20px/1 var(--cond);padding-bottom:12px}
.mark{width:28px;height:28px;display:block}
.seg{display:flex;gap:28px}
.seg button{border:0;background:none;padding:0 0 12px;font:600 16px/1 var(--font);color:var(--muted)}
.seg button:hover{color:var(--ink)}
.seg button[aria-selected=true]{color:var(--ink);box-shadow:inset 0 -3px 0 var(--ink)}
main{flex:1;display:grid;grid-template-columns:minmax(0,1.05fr) minmax(0,1fr);gap:72px;align-items:center;width:100%;max-width:1320px;margin:0 auto;padding:40px 48px 56px}
.when{min-width:0}
.when .host{margin:0;font-size:22px;overflow-wrap:anywhere}
.when .time{margin:10px 0 0;font:700 clamp(112px,16vw,240px)/.84 var(--cond);letter-spacing:-.03em;color:var(--time);white-space:nowrap}
.when .time.word{font-size:clamp(80px,10vw,150px)}
.rows{margin:36px 0 0;max-width:520px}
.rows div{display:grid;grid-template-columns:130px 1fr;gap:12px;padding:12px 0;border-top:1px solid var(--rule)}
.rows div:last-child{border-bottom:1px solid var(--rule)}
.rows dt{color:var(--muted)}
.rows dd{margin:0;font-weight:600}
.act{display:flex;flex-direction:column;align-items:center;min-width:0}
body.is-over main{grid-template-columns:1fr}
body.is-over .when{display:none}
.c{display:flex;flex-direction:column;align-items:center;text-align:center;width:100%}
button{font:inherit;color:inherit;cursor:pointer}
button:focus-visible,a:focus-visible,canvas:focus-visible{outline:2px solid var(--ink);outline-offset:3px}
.btn{background:var(--ink);color:var(--on-ink);border:0;border-radius:10px;padding:15px 22px;font:600 17px/1 var(--font)}
.btn:hover{opacity:.86}
.btn.ghost{background:var(--chip);color:var(--ink)}
.btn.ghost:hover{background:var(--soft);opacity:1}
.btn[disabled]{background:var(--chip);color:var(--muted);box-shadow:none;cursor:default;opacity:1}
h1{margin:0;font:700 clamp(30px,3.4vw,44px)/1.05 var(--cond);letter-spacing:-.01em}
p.sub{margin:12px 0 0;color:var(--muted);font-size:18px;max-width:30em}
a.open{display:inline-block;margin-top:24px;text-decoration:none}
@media (max-width:900px){.top{margin:0 20px;grid-template-columns:1fr;justify-items:start}.top>span:empty{display:none}.seg{gap:20px;max-width:100%;overflow-x:auto}main{grid-template-columns:1fr;gap:44px;padding:28px 20px 44px}.rows div{grid-template-columns:110px 1fr}}
@media (prefers-reduced-motion:reduce){*{transition:none!important;animation:none!important}}
"""##
    static let shellJS = ##"""
const SW=(()=>{
  const q=new URLSearchParams(location.search);
  const raw=q.get('url')||'';
  const host=raw.replace(/^https?:\/\/(www\.)?/,'').split(/[/?#]/)[0]||'this site';
  const until=(Number(q.get('until'))||0)*1000;
  // Tries in this block; 0 when `n` is missing or not a positive whole number, and then nothing is shown.
  const tries=(s=>/^[0-9]+$/.test(s)&&Number.isSafeInteger(+s)&&+s>0?+s:0)((q.get('n')||'').trim());
  const pad=n=>String(n).padStart(2,'0');
  const ord=n=>{const t=n%100,o=n%10;return n+(t>10&&t<14?'th':o===1?'st':o===2?'nd':o===3?'rd':'th')};
  const left=()=>until?Math.max(0,Math.ceil((until-Date.now())/1000)):0;
  const hms=s=>{const h=Math.floor(s/3600),m=Math.floor(s/60)%60,x=s%60;return h?`${h}:${pad(m)}:${pad(x)}`:`${m}:${pad(x)}`};
  const short=s=>{if(s<60)return'under a minute';const h=Math.floor(s/3600),m=Math.floor(s/60)%60;return h?`${h}h ${pad(m)}m`:`${m}m`};
  // When the block ends: today is just the time, tomorrow and later days say so before "at".
  function endParts(){
    const e=new Date(until),time=pad(e.getHours())+':'+pad(e.getMinutes()),tom=new Date();tom.setDate(tom.getDate()+1);
    if(e.toDateString()===new Date().toDateString())return {day:'',time};
    if(e.toDateString()===tom.toDateString())return {day:'tomorrow',time};
    return {day:'on '+e.toLocaleDateString('en-US',{month:'short',day:'numeric'}),time};
  }
  const esc=v=>String(v).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'})[c]);
  const store=ns=>({get(k,d){try{const v=localStorage.getItem('sw.'+ns+'.'+k);return v==null?d:JSON.parse(v)}catch(e){return d}},set(k,v){try{localStorage.setItem('sw.'+ns+'.'+k,JSON.stringify(v))}catch(e){}}});
  const $=id=>document.getElementById(id);
  const concepts={},stats={};let current=null;
  const render=()=>{
    const over=until&&left()===0;
    document.title=over?'Block is over':'Blocked';
    if(document.body)document.body.classList.toggle('is-over',!!over);
    const end=until?endParts():null,time=$('time');
    $('host').textContent=end?`${host} opens again ${end.day?end.day+' ':''}at`:`${host} is closed`;
    time.textContent=end?end.time:'Closed';time.className=end?'time':'time word';
    const rows=[];
    if(!over){if(until)rows.push(['Left',short(left())]);if(tries)rows.push(['This block',`${ord(tries)} try`]);if(current&&stats[current])rows.push(stats[current])}
    $('rows').innerHTML=rows.map(([k,v])=>`<div><dt>${esc(k)}</dt><dd>${esc(v)}</dd></div>`).join('');
    $('over').hidden=!over;
    document.querySelectorAll('.c').forEach(c=>{if(c.id==='over')return;if(over)c.hidden=true;else c.hidden=c.dataset.name!==current});
    const sw=$('seg');if(sw)sw.hidden=!!over;
    if(over&&/^https?:\/\//.test(raw)){const a=$('openLink');a.href=raw;a.textContent='Open '+host;a.hidden=false}
  };
  function show(name){
    if(current&&current!==name&&concepts[current])concepts[current].stop();
    current=name;
    document.querySelectorAll('#seg button').forEach(b=>b.setAttribute('aria-selected',b.dataset.name===name));
    render();
  }
  return {$,host,tries,left,hms,short,ord,store,render,show,
    reduce:matchMedia('(prefers-reduced-motion: reduce)').matches,
    today:new Date().toDateString(),
    register(name,api){concepts[name]=api},
    // A concept's own counter, as [label, value], shown as a row; null hides it.
    setStat(name,row){stats[name]=row;if(current===name)render()},
    boot(){
      const names=[...document.querySelectorAll('.c:not(#over)')].map(c=>c.dataset.name);
      const seg=$('seg');
      if(seg){
        const mem=store('page'),last=mem.get('tab',names[0]);
        seg.addEventListener('click',e=>{const b=e.target.closest('button');if(b){mem.set('tab',b.dataset.name);show(b.dataset.name)}});
        seg.addEventListener('keydown',e=>{
          const i=names.indexOf(current);let n=-1;
          if(e.key==='ArrowRight')n=(i+1)%names.length;else if(e.key==='ArrowLeft')n=(i+names.length-1)%names.length;
          if(n>=0){e.preventDefault();mem.set('tab',names[n]);show(names[n]);seg.querySelector(`[data-name="${names[n]}"]`).focus()}
        });
        show(names.includes(last)?last:names[0]);
      }else show(names[0]);
      setInterval(render,1000);
    }};
})();
"""##
    static let breatheCSS = ##"""
.c-breathe .stage{position:relative;width:300px;height:300px;margin:30px 0 28px;display:grid;place-items:center}
.c-breathe svg{position:absolute;inset:0;width:100%;height:100%;transform:rotate(-90deg)}
.c-breathe .track{fill:none;stroke:var(--soft);stroke-width:8}
.c-breathe .arc{fill:none;stroke:var(--time);stroke-width:8}
.c-breathe .cue{position:relative;display:flex;flex-direction:column;align-items:center;gap:6px}
.c-breathe .cue b{font:700 32px/1 var(--cond)}
.c-breathe .cue span{font:600 24px/1 var(--cond);color:var(--time);min-height:24px}
.c-breathe .actions{display:flex;gap:12px;min-height:48px}
.c-breathe .sub{min-height:1.4em}
"""##
    static let breatheBody = ##"""
<section class="c c-breathe" id="c-breathe" data-name="breathe">
  <h1 id="b-title">Let’s take one breath first.</h1>
  <div class="stage" aria-live="polite"><svg viewBox="0 0 300 300" aria-hidden="true"><circle class="track" cx="150" cy="150" r="144"/><circle class="arc" id="b-arc" cx="150" cy="150" r="144" pathLength="100" stroke-dasharray="0 100"/></svg><div class="cue"><b id="b-cue">Ready when you are</b><span id="b-secs"></span></div></div>
  <div class="actions" id="b-actions"></div>
  <p class="sub" id="b-after" hidden></p>
</section>
"""##
    static let breatheJS = ##"""
(()=>{
  const $=SW.$,st=SW.store('breathe'),KEY='breaths:'+SW.today;
  let breaths=st.get(KEY,0),raf=0;
  const IN=4000,HOLD=1000,OUT=6000,MIN=.52,ease=t=>(1-Math.cos(Math.PI*t))/2;
  const scaleAt=ms=>ms<IN?MIN+(1-MIN)*ease(ms/IN):ms<IN+HOLD?1:1-(1-MIN)*ease(Math.min(1,(ms-IN-HOLD)/OUT));
  const phase=ms=>ms<IN?'Breathe in':ms<IN+HOLD?'Hold':'Breathe out';
  const paint=s=>$('b-arc').setAttribute('stroke-dasharray',`${((s-MIN)/(1-MIN)*100).toFixed(2)} 100`);
  const secs=ms=>ms<IN?Math.ceil((IN-ms)/1000):ms<IN+HOLD?0:Math.ceil((IN+HOLD+OUT-ms)/1000);
  const stat=()=>SW.setStat('breathe',breaths?['Breaths today',breaths]:null);
  function actions(html,wire){$('b-actions').innerHTML=html;wire&&wire()}
  function idle(){
    cancelAnimationFrame(raf);paint(MIN);$('b-cue').textContent='Ready when you are';$('b-secs').textContent='';
    $('b-title').textContent='Let’s take one breath first.';$('b-after').hidden=true;
    actions('<button class="btn" id="b-go">Start one breath</button>',()=>$('b-go').onclick=start);
  }
  function start(){
    $('b-after').hidden=true;$('b-title').textContent='Follow the ring.';
    actions('<button class="btn" disabled>Breathing…</button>');
    const t0=performance.now();let last='';
    (function tick(now){
      const ms=now-t0;
      if(ms>=IN+HOLD+OUT)return done();
      const p=phase(ms);
      paint(SW.reduce?(p==='Breathe out'?MIN:1):scaleAt(ms));
      if(p!==last){$('b-cue').textContent=p;last=p}
      const n=secs(ms);$('b-secs').textContent=n?'0:0'+n:'';
      raf=requestAnimationFrame(tick);
    })(t0);
  }
  function done(){
    breaths++;st.set(KEY,breaths);stat();paint(MIN);$('b-cue').textContent='Done';$('b-secs').textContent='';
    $('b-title').textContent='That was one breath.';
    const a=$('b-after');a.hidden=false;a.textContent='Urges tend to ease within a minute or so. Another breath, or back to what you were doing?';
    actions('<button class="btn" id="b-again">Another breath</button><button class="btn ghost" id="b-fine">I’m good</button>',()=>{
      $('b-again').onclick=start;
      $('b-fine').onclick=()=>{a.textContent='Good. You can close this tab whenever you like.';actions('<button class="btn ghost" id="b-more">One more breath</button>',()=>$('b-more').onclick=start)};
    });
  }
  SW.register('breathe',{stop:idle});idle();stat();
})();
"""##
    static let whyCSS = ##"""
.c-why .chips{display:flex;flex-wrap:wrap;gap:10px;justify-content:center;max-width:560px;margin-top:28px}
.c-why .chip{border:0;background:var(--chip);color:var(--ink);padding:13px 18px;border-radius:10px;font:600 17px/1 var(--font)}
.c-why .chip:hover{background:var(--soft)}
.c-why .chip[aria-pressed=true]{background:var(--ink);color:var(--on-ink)}
.c-why .card{display:grid;grid-template-columns:auto 1fr;gap:18px 20px;align-items:start;text-align:left;margin-top:28px;max-width:560px;width:100%;border-top:2px solid var(--rule);border-bottom:1px solid var(--rule);padding:22px 0}
.c-why .ico{width:48px;height:48px;border-radius:12px;background:var(--chip);display:grid;place-items:center}
.c-why .ico svg{width:26px;height:26px;stroke:var(--ink);fill:none;stroke-width:1.8;stroke-linecap:round;stroke-linejoin:round}
.c-why .card h2{margin:0;font:700 24px/1.1 var(--cond)}.c-why .card p{margin:6px 0 0;color:var(--muted)}
.c-why .cta{grid-column:1/-1;display:flex;gap:12px}
.c-why .thanks{margin:26px 0 0;font:700 28px/1.15 var(--cond)}
.c-why .thanks small{display:block;font:400 17px/1.45 var(--font);color:var(--muted);margin-top:8px}
"""##
    static let whyBody = ##"""
<section class="c c-why" id="c-why" data-name="why">
  <h1 id="w-title">What brought you here?</h1>
  <p class="sub" id="w-lede">No wrong answer. Pick the closest one.</p>
  <div class="chips" id="w-chips"></div>
  <div class="card" id="w-card" hidden>
    <div class="ico" id="w-ico"></div>
    <div><h2 id="w-ctitle"></h2><p id="w-cbody"></p></div>
    <div class="cta"><button class="btn" id="w-did">I’ll do that</button><button class="btn ghost" id="w-skip">Pick another</button></div>
  </div>
  <p class="thanks" id="w-thanks" hidden></p>
</section>
"""##
    static let whyJS = ##"""
(()=>{
  const $=SW.$,st=SW.store('why'),KEY='wins:'+SW.today;
  const I={
    water:'<path d="M12 3c3 4 6 7 6 11a6 6 0 0 1-12 0c0-4 3-7 6-11Z"/>',
    breath:'<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3.5"/>',
    walk:'<circle cx="13" cy="4.5" r="1.8"/><path d="M9 21l2.5-6 3 1.5V21M11.5 15l-1-5 4 1 2.5 3M9 11l2-3"/>',
    note:'<path d="M5 4h14v16H5z"/><path d="M8.5 9h7M8.5 13h7M8.5 17h4"/>',
    stretch:'<circle cx="12" cy="4.5" r="1.8"/><path d="M12 7v7m0 0-3 6m3-6 3 6M5 9l7-2 7 2"/>',
    mail:'<rect x="3.5" y="6" width="17" height="12" rx="2"/><path d="m4 8 8 5 8-5"/>'};
  const WHY=[
    ['Bored','water','Get a glass of water','Stand up, fill a glass, drink it. It takes two minutes and the itch often moves on.'],
    ['Stressed','breath','Take three slow breaths','In for four, out for six. Nothing else to do for a moment.'],
    ['Need a break','walk','Walk to the window','Look at something far away for a minute. Eyes rest, head follows.'],
    ['Avoiding something','note','Write the first small step','One line: what is the very next thing? Just the first step, not all of it.'],
    ['Just habit','stretch','Stretch your shoulders','Roll them back ten times. Habits like a new motion to replace the old one.'],
    ['I need it for work','mail','Check the plan first','If it is really needed, the Seawall menu can end a block early after a short wait.']];
  const WORK=5;
  let wins=st.get(KEY,0),pick=-1;
  const chips=$('w-chips'),stat=()=>SW.setStat('why',wins?['Wins today',wins]:null);
  WHY.forEach((w,i)=>{const b=document.createElement('button');b.className='chip';b.textContent=w[0];b.setAttribute('aria-pressed','false');b.onclick=()=>choose(i);chips.appendChild(b)});
  function choose(i){
    pick=i;[...chips.children].forEach((c,j)=>c.setAttribute('aria-pressed',j===i));
    const w=WHY[i];$('w-ico').innerHTML='<svg viewBox="0 0 24 24" aria-hidden="true">'+I[w[1]]+'</svg>';
    $('w-ctitle').textContent=w[2];$('w-cbody').textContent=w[3];
    $('w-card').hidden=false;$('w-thanks').hidden=true;$('w-did').textContent=i===WORK?'Got it':'I’ll do that';
  }
  function reset(){
    pick=-1;[...chips.children].forEach(c=>c.setAttribute('aria-pressed','false'));
    $('w-card').hidden=true;$('w-thanks').hidden=true;chips.hidden=false;$('w-lede').hidden=false;$('w-title').textContent='What brought you here?';
  }
  $('w-did').onclick=()=>{
    if(pick!==WORK){wins++;st.set(KEY,wins);stat()}
    $('w-card').hidden=true;chips.hidden=true;$('w-lede').hidden=true;
    $('w-title').textContent=pick===WORK?'Fair enough.':'Nice. That’s a win.';
    const t=$('w-thanks');t.hidden=false;
    t.innerHTML=pick===WORK?'The block is still on, and that’s on purpose.<small>Open the Seawall menu in the menu bar to start the wait for leaving early.</small>'
      :'That’s '+wins+(wins===1?' win':' wins')+' today.<small>The tab can close now. You’re doing fine.</small>';
  };
  $('w-skip').onclick=()=>{$('w-card').hidden=true;[...chips.children].forEach(c=>c.setAttribute('aria-pressed','false'))};
  SW.register('why',{stop:reset});stat();
})();
"""##
    static let stackCSS = ##"""
.c-stack .wrap{width:min(520px,100%);margin:22px 0 14px}
.c-stack canvas{width:100%;height:auto;display:block;background:var(--bg);border:1px solid var(--soft);border-radius:12px;touch-action:manipulation;cursor:pointer}
.c-stack .hud{display:flex;align-items:center;gap:14px;margin-top:12px;font-size:15px;color:var(--muted)}
.c-stack .hud b{color:var(--ink);font:700 20px/1 var(--cond)}
.c-stack .bar{flex:1;height:4px;background:var(--soft);border-radius:2px;overflow:hidden}
.c-stack .bar i{display:block;height:100%;width:100%;background:var(--time);transform-origin:left}
.c-stack .actions{min-height:48px}.c-stack .sub{font-size:16px;margin-top:10px}
"""##
    static let stackBody = ##"""
<section class="c c-stack" id="c-stack" data-name="stack">
  <h1 id="s-title">Stack a few blocks instead.</h1>
  <div class="wrap"><canvas id="s-cv" width="560" height="360" role="img" aria-label="Block stacking game. Press Space or tap to drop the block."></canvas>
    <div class="hud"><span>Height <b id="s-score">0</b></span><span class="bar"><i id="s-bar"></i></span><span>Best <b id="s-best">0</b></span></div></div>
  <div class="actions"><button class="btn" id="s-play">Start</button></div>
  <p class="sub" id="s-hint">Tap, click or press Space to drop the block. Line it up.</p>
</section>
"""##
    static let stackJS = ##"""
(()=>{
  const $=SW.$,st=SW.store('stack'),cv=$('s-cv'),ctx=cv.getContext('2d'),W=cv.width,H=cv.height,BH=30,BASE=180;
  const css=n=>getComputedStyle(document.documentElement).getPropertyValue(n).trim();
  const dark=()=>matchMedia('(prefers-color-scheme: dark)').matches;
  const tones=()=>dark()?['#F2F2F0','#C8CACC','#9EA1A4','#76797C']:['#161616','#45484B','#6E7175','#97999C'];
  let best=st.get('best',0),stack,cur,dir,speed,running=false,tEnd=0,score=0,raf=0;
  const stat=()=>SW.setStat('stack',best?['Best stack',best]:null);
  $('s-best').textContent=best;
  const rr=(x,y,w,h)=>{ctx.beginPath();if(ctx.roundRect)ctx.roundRect(x,y,w,h,2);else ctx.rect(x,y,w,h);ctx.fill()};
  function spawn(){const top=stack[stack.length-1];cur={x:0,w:top.w};dir=1;speed=2.2+Math.min(3.2,stack.length*.12)}
  function reset(){stack=[{x:(W-BASE)/2,w:BASE}];score=0;$('s-score').textContent=0;spawn()}
  function draw(){
    ctx.clearRect(0,0,W,H);const T=tones(),baseY=H-24,view=Math.max(0,(stack.length+1)*BH-(H-60));
    ctx.fillStyle=css('--rule');ctx.fillRect(0,baseY,W,2);
    stack.forEach((b,i)=>{ctx.fillStyle=T[i%4];rr(b.x,baseY-(i+1)*BH+view,b.w,BH-3)});
    if(running){ctx.fillStyle=T[stack.length%4];rr(cur.x,baseY-(stack.length+1)*BH+view,cur.w,BH-3)}
  }
  function frame(now){
    if(!running)return;
    const left=Math.max(0,tEnd-now);$('s-bar').style.transform=`scaleX(${left/30000})`;
    if(left<=0)return finish('Time.');
    cur.x+=dir*speed*(SW.reduce?.6:1);
    if(cur.x<0){cur.x=0;dir=1}if(cur.x+cur.w>W){cur.x=W-cur.w;dir=-1}
    draw();raf=requestAnimationFrame(frame);
  }
  function drop(){
    if(!running)return;
    const top=stack[stack.length-1],l=Math.max(cur.x,top.x),r=Math.min(cur.x+cur.w,top.x+top.w),w=r-l;
    if(w<=4)return finish('Missed. That happens.');
    stack.push(Math.abs(cur.x-top.x)<5?{x:top.x,w:top.w}:{x:l,w});score++;$('s-score').textContent=score;spawn();draw();
  }
  function finish(msg){
    running=false;cancelAnimationFrame(raf);draw();
    const record=score>best;
    if(record){best=score;st.set('best',best);$('s-best').textContent=best;stat()}
    $('s-title').textContent=record?'A new best: '+score+'.':'You stacked '+score+'.';
    $('s-hint').textContent=msg+' How’s the urge now?';
    $('s-play').disabled=false;$('s-play').textContent='Play again';
  }
  function start(){
    reset();running=true;tEnd=performance.now()+30000;$('s-play').disabled=true;$('s-play').textContent='Go';
    $('s-title').textContent='Stack a few blocks instead.';$('s-hint').textContent='Tap, click or press Space to drop.';
    raf=requestAnimationFrame(frame);
  }
  function stop(){running=false;cancelAnimationFrame(raf);reset();draw();$('s-bar').style.transform='scaleX(1)';
    $('s-title').textContent='Stack a few blocks instead.';$('s-hint').textContent='Tap, click or press Space to drop the block. Line it up.';
    $('s-play').disabled=false;$('s-play').textContent='Start'}
  $('s-play').onclick=start;
  cv.addEventListener('pointerdown',e=>{e.preventDefault();drop()});
  addEventListener('keydown',e=>{if(e.code==='Space'&&running&&!$('c-stack').hidden){e.preventDefault();drop()}});
  matchMedia('(prefers-color-scheme: dark)').addEventListener('change',draw);
  SW.register('stack',{stop});reset();draw();stat();
})();
"""##
}
