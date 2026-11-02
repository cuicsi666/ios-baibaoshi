// ===== 我们的日子 · 核心逻辑 =====
'use strict';

// ===== 人物数据 =====
const persons = {
  baby: { label:'宝宝', emoji:'👶', tag:'我家小王子', face:'data/avatar-baby.jpg?v=2',
    lunarMonth:6, lunarDay:28, year:2023, month:8, day:14, hour:15, minute:33,
    lunarLabel:'二〇二三年 六月廿八' },
  wife: { label:'媳妇', emoji:'👩', tag:'我的女王', face:'data/avatar-wife.jpg?v=3',
    lunarMonth:12, lunarDay:7, year:2003, month:1, day:9, hour:13, minute:14,
    lunarLabel:'壬午年 腊月初七' },
  self: { label:'老大', emoji:'💪', tag:'顶梁柱', face:'data/avatar-self.jpg?v=2',
    lunarMonth:1, lunarDay:30, year:2000, month:3, day:18, hour:5, minute:20,
    lunarLabel:'庚辰年 正月三十' }
};
const ORDER = ['baby','wife','self'];

// 各主题漂浮装饰
const FLOAT_EMOJI = {
  baby: ['🧸','⭐','🎈','🍼','🚀','🌈','🦆','🍭','☁️'],
  wife: ['🌸','💕','🌹','💐','🦋','💗','🌷','✨','🍒'],
  self: ['⚡','🔥','💪','🚀','⛰️','🏆','💫','🦅','📈']
};

// 签卡配置
const QUOTE_SRC = { baby: ()=>window.IDIOMS_BABY, self: ()=>window.IDIOMS_SELF, wife: ()=>window.LOVE_WIFE };
const QUOTE_META = {
  baby: { label:'🌱 宝宝成长签', hint:'👆 点我换一签' },
  self: { label:'🔥 老大奋斗签', hint:'👆 点我换一签' },
  wife: { label:'💕 今日爱语',   hint:'👆 点我抽一句' }
};

let curKey = 'baby';
const state = {};

// ===== 工具 =====
const pad2 = n => String(n).padStart(2,'0');

function dateDiff(from, to){
  let y = to.getFullYear()-from.getFullYear();
  let m = to.getMonth()-from.getMonth();
  let d = to.getDate()-from.getDate();
  let h = to.getHours()-from.getHours();
  let mi = to.getMinutes()-from.getMinutes();
  let s = to.getSeconds()-from.getSeconds();
  if(s<0){ s+=60; mi--; }
  if(mi<0){ mi+=60; h--; }
  if(h<0){ h+=24; d--; }
  if(d<0){ m--; d += new Date(to.getFullYear(), to.getMonth(), 0).getDate(); }
  if(m<0){ m+=12; y--; }
  return { years:y, months:m, days:d, hours:h, minutes:mi, seconds:s };
}

function nextBirthday(data){
  const now = new Date();
  let target;
  try{
    if(typeof Solar==='undefined') throw 0;
    const lunarNow = Solar.fromDate(now).getLunar();
    let tl = Lunar.fromYmd(lunarNow.getYear(), data.lunarMonth, data.lunarDay);
    let ts = tl.getSolar();
    target = new Date(ts.getYear(), ts.getMonth()-1, ts.getDay(), data.hour||0, data.minute||0);
    if(target<=now){
      tl = Lunar.fromYmd(lunarNow.getYear()+1, data.lunarMonth, data.lunarDay);
      ts = tl.getSolar();
      target = new Date(ts.getYear(), ts.getMonth()-1, ts.getDay(), data.hour||0, data.minute||0);
    }
  }catch(e){
    target = new Date(now.getFullYear(), data.month-1, data.day, data.hour||0, data.minute||0);
    if(target<=now) target = new Date(now.getFullYear()+1, data.month-1, data.day, data.hour||0, data.minute||0);
  }
  const ms = target-now;
  return { days:Math.floor(ms/864e5), hours:Math.floor(ms%864e5/36e5), minutes:Math.floor(ms%36e5/6e4),
    dateStr: target.getFullYear()+'年'+(target.getMonth()+1)+'月'+target.getDate()+'日' };
}

function dayHash(key, len){
  const d = new Date();
  const s = ''+d.getFullYear()+d.getMonth()+d.getDate()+key;
  let h = 0;
  for(let i=0;i<s.length;i++) h = (h*31 + s.charCodeAt(i))>>>0;
  return h % len;
}

// ===== 数字滚动（setTimeout 引擎，后台/前台都稳定）=====
function countUp(el, target, dur=900, delay=0){
  const t0 = Date.now()+delay;
  let last = -1;
  function tick(){
    const p = Math.min(Math.max((Date.now()-t0)/dur,0),1);
    const v = Math.round(target*(1-Math.pow(1-p,3)));
    if(v!==last){ el.textContent = v.toLocaleString(); last=v; }
    if(p<1) setTimeout(tick,16);
  }
  setTimeout(tick,16);
}

function animateRing(pct){
  const C = 2*Math.PI*46;
  const fg = document.getElementById('ringFg');
  if(!fg) return;
  fg.setAttribute('stroke-dasharray', C.toFixed(1));
  fg.setAttribute('stroke-dashoffset', C.toFixed(1));
  setTimeout(()=>{ fg.style.strokeDashoffset = (C*(1-pct)).toFixed(1); }, 80);
}

function updateRingGrad(){
  const cs = getComputedStyle(document.body);
  const a1 = cs.getPropertyValue('--a1').trim(), a2 = cs.getPropertyValue('--a2').trim();
  document.querySelectorAll('#ringGrad stop').forEach((s,i)=> s.setAttribute('stop-color', i===0?a1:a2));
}

// ===== 结婚纪念日 =====
function annivHTML(delay){
  const now = new Date();
  const start = new Date(2021, 6, 29, 5, 20);
  const tg = dateDiff(start, now);
  let target = new Date(now.getFullYear(), 6, 29, 5, 20);
  if(target<now) target.setFullYear(now.getFullYear()+1);
  const ms = target-now;
  return `<section class="panel card-anim" style="animation-delay:${delay}s">
    <div class="sec-t">💍 结婚纪念日</div>
    <div class="wed-grid">
      <div class="wed-item"><div class="l">领证日子</div><div class="v">2021年7月29日</div></div>
      <div class="wed-item"><div class="l">农历</div><div class="v">六月十六</div></div>
    </div>
    <div class="stats" style="margin-bottom:10px">
      <div class="stat"><div class="n" data-count="${tg.years}" data-live="wed:years">0</div><div class="u">年</div></div>
      <div class="stat"><div class="n" data-count="${tg.months}" data-live="wed:months">0</div><div class="u">月</div></div>
      <div class="stat"><div class="n" data-count="${tg.days}" data-live="wed:days">0</div><div class="u">天</div></div>
      <div class="stat"><div class="n" data-count="${tg.hours}" data-live="wed:hours">0</div><div class="u">时</div></div>
      <div class="stat"><div class="n" data-count="${tg.minutes}" data-live="wed:minutes">0</div><div class="u">分</div></div>
      <div class="stat"><div class="n" data-live="wed:seconds">${pad2(tg.seconds)}</div><div class="u">秒</div></div>
    </div>
    <div class="wed-count">
      <div class="c"><div class="n" data-count="${Math.floor(ms/864e5)}">0</div><div class="u">天</div></div>
      <div class="c"><div class="n" data-count="${Math.floor(ms%864e5/36e5)}">0</div><div class="u">时</div></div>
      <div class="c"><div class="n" data-count="${Math.floor(ms%36e5/6e4)}">0</div><div class="u">分</div></div>
    </div>
    <div class="wed-next">距下次纪念日 · ${target.getFullYear()}年7月29日</div>
  </section>`;
}

// ===== 主渲染 =====
function renderCard(key){
  const data = persons[key];
  const now = new Date();
  const birth = new Date(data.year, data.month-1, data.day, data.hour||0, data.minute||0);
  const diff = dateDiff(birth, now);
  const total = Math.max(0, Math.floor((now-birth)/864e5));
  const next = nextBirthday(data);
  const pct = Math.min(Math.max((365-next.days)/365, 0.02), 1);

  const list = QUOTE_SRC[key]();
  state[key] = { idx: dayHash(key, list.length), manual:false };
  const item = list[state[key].idx];
  const qLabel = item.w || item.t;
  const qMeta = QUOTE_META[key];
  const isLove = key==='wife';

  let tip = '✨ 每一天都在期待';
  if(next.days===0) tip = '🎂 今天就是生日，祝快乐！';
  else if(next.days<=7) tip = '🎁 生日快到啦，礼物准备好了吗';
  else if(next.days<=30) tip = '🌸 生日不远啦，悄悄期待一下';

  let h = '';
  h += `<section class="panel card-anim" style="animation-delay:.05s">
    <div class="hero">
      <div class="avatar" id="avatar"><img src="${data.face}" alt="${data.label}"></div>
      <div class="hero-info">
        <div class="hero-name">${data.label}<span class="hero-tag">${data.tag}</span></div>
        <div class="hero-sub">${data.lunarLabel}<br>${data.year}.${pad2(data.month)}.${pad2(data.day)} ${pad2(data.hour||0)}:${pad2(data.minute||0)} 出生</div>
      </div>
      <div class="hero-days"><div class="num" data-count="${total}">0</div><div class="unit">来到世界的天数</div></div>
    </div>
  </section>`;

  h += `<section class="panel card-anim" style="animation-delay:.12s">
    <div class="sec-t">✦ 已成长 ✦</div>
    <div class="stats">
      <div class="stat"><div class="n" data-count="${diff.years}" data-live="main:years">0</div><div class="u">年</div></div>
      <div class="stat"><div class="n" data-count="${diff.months}" data-live="main:months">0</div><div class="u">月</div></div>
      <div class="stat"><div class="n" data-count="${diff.days}" data-live="main:days">0</div><div class="u">日</div></div>
      <div class="stat"><div class="n" data-count="${diff.hours}" data-live="main:hours">0</div><div class="u">时</div></div>
      <div class="stat"><div class="n" data-count="${diff.minutes}" data-live="main:minutes">0</div><div class="u">分</div></div>
      <div class="stat"><div class="n" data-live="main:seconds">${pad2(diff.seconds)}</div><div class="u">秒</div></div>
    </div>
  </section>`;

  h += `<section class="panel card-anim" style="animation-delay:.19s">
    <div class="sec-t">✦ 距离下次生日 ✦</div>
    <div class="bd">
      <div class="ringwrap">
        <svg width="104" height="104" viewBox="0 0 104 104">
          <defs><linearGradient id="ringGrad" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%"/><stop offset="100%"/>
          </linearGradient></defs>
          <circle class="ring-bg" cx="52" cy="52" r="46"/>
          <circle class="ring-fg" id="ringFg" cx="52" cy="52" r="46"/>
        </svg>
        <div class="ring-mid"><div class="pct">${Math.round(pct*100)}%</div><div class="pl">今年进度</div></div>
      </div>
      <div class="bd-info">
        <div class="bd-nums">
          <div class="bn"><div class="n" data-count="${next.days}">0</div><div class="u">天</div></div>
          <div class="bn"><div class="n" data-count="${next.hours}">0</div><div class="u">时</div></div>
          <div class="bn"><div class="n" data-count="${next.minutes}">0</div><div class="u">分</div></div>
        </div>
        <div class="bd-date">下次生日：${next.dateStr}</div>
        <div class="bd-tip">${tip}</div>
      </div>
    </div>
  </section>`;

  h += `<section class="qcard card-anim" id="qcard" style="animation-delay:.26s">
    <div class="q-top"><span>${qMeta.label}</span><span class="q-no">今日签 ${state[key].idx+1} / ${list.length}</span></div>
    <span class="q-hint">👆</span>
    <div class="q-body${isLove?' love':''}"><div class="q-word">${qLabel}</div><div class="q-sub">${item.s}</div></div>
    <div class="q-foot">${qMeta.hint} · 共 ${list.length} 支</div>
  </section>`;

  if(key!=='baby') h += annivHTML(0.33);
  document.getElementById('main').innerHTML = h;

  document.querySelectorAll('[data-count]').forEach((el,i)=> countUp(el, parseInt(el.dataset.count,10)||0, 900, 120+i*70));
  animateRing(pct);
  updateRingGrad();

  // 实时翻牌引擎
  const births = { main: birth };
  if(key!=='baby') births.wed = new Date(2021,6,29,5,20);
  startTicker(births);
}

// ===== 每秒翻牌 =====
let tickerTimer = null;
function startTicker(births){
  if(tickerTimer){ clearInterval(tickerTimer); tickerTimer = null; }
  const tick = ()=>{
    const els = document.querySelectorAll('[data-live]');
    if(!els.length){
      if(tickerTimer){ clearInterval(tickerTimer); tickerTimer = null; }
      return;
    }
    const diffs = {};
    for(const k in births) diffs[k] = dateDiff(births[k], new Date());
    els.forEach(el=>{
      const parts = el.dataset.live.split(':');
      const dff = diffs[parts[0]];
      if(!dff) return;
      const unit = parts[1];
      const v = dff[unit];
      const txt = (unit==='seconds'||unit==='minutes') ? pad2(v) : String(v);
      if(el.textContent === txt) return;
      if(unit==='seconds'){
        el.classList.add('tick');
        setTimeout(()=>{ el.textContent = txt; el.classList.remove('tick'); }, 110);
      } else {
        el.textContent = txt;
      }
    });
  };
  tick();
  tickerTimer = setInterval(tick, 1000);
}

// ===== 抽签（翻牌动画）=====
function drawQuote(key, forceRandom){
  const list = QUOTE_SRC[key]();
  if(!list || !list.length) return;
  if(forceRandom){
    let ni;
    do { ni = Math.floor(Math.random()*list.length); } while(ni===state[key].idx && list.length>1);
    state[key] = { idx:ni, manual:true };
  }
  const st = state[key];
  const item = list[st.idx];
  const label = item.w || item.t;
  const card = document.getElementById('qcard');
  if(!card) return;
  const body = card.querySelector('.q-body');
  const no = card.querySelector('.q-no');
  card.classList.add('flipping');
  setTimeout(()=>{
    body.innerHTML = `<div class="q-word">${label}</div><div class="q-sub">${item.s}</div>`;
    no.textContent = (st.manual?'手气签':'今日签')+' '+(st.idx+1)+' / '+list.length;
    card.classList.remove('flipping');
    if(key==='wife') spawnHearts(card);
  }, 240);
}

// ===== 爱心粒子 =====
function spawnHearts(anchor){
  const r = anchor.getBoundingClientRect();
  const cx = r.left + r.width/2, cy = r.top + r.height/2;
  const glyphs = ['❤️','💖','💕','💘','💗'];
  for(let i=0;i<12;i++){
    const s = document.createElement('span');
    s.className = 'heart-pop';
    s.textContent = glyphs[i%glyphs.length];
    const ang = Math.random()*Math.PI*2;
    const dist = 55 + Math.random()*85;
    s.style.left = cx+'px';
    s.style.top = cy+'px';
    s.style.setProperty('--dx', (Math.cos(ang)*dist).toFixed(0)+'px');
    s.style.setProperty('--dy', (Math.sin(ang)*dist-45).toFixed(0)+'px');
    s.style.setProperty('--rot', ((Math.random()*60)-30).toFixed(0)+'deg');
    document.body.appendChild(s);
    setTimeout(()=>s.remove(), 950);
  }
}

// ===== 漂浮装饰 =====
function initFloaters(emojis){
  let wrap = document.getElementById('floaters');
  if(!wrap){
    wrap = document.createElement('div');
    wrap.id = 'floaters';
    document.body.appendChild(wrap);
  }
  wrap.innerHTML = '';
  for(let i=0;i<9;i++){
    const s = document.createElement('span');
    s.className = 'floater';
    s.textContent = emojis[i%emojis.length];
    s.style.left = (2+Math.random()*92).toFixed(1)+'%';
    s.style.fontSize = (13+Math.random()*16).toFixed(0)+'px';
    const dur = 13+Math.random()*11;
    s.style.animationDuration = dur.toFixed(1)+'s';
    s.style.animationDelay = (-Math.random()*dur).toFixed(1)+'s';
    wrap.appendChild(s);
  }
}

// ===== 日期栏 =====
function initDatebar(){
  const now = new Date();
  const wk = '日一二三四五六'[now.getDay()];
  let lunarStr = '';
  try{
    const l = Solar.fromDate(now).getLunar();
    lunarStr = `农历${l.getMonthInChinese()}月${l.getDayInChinese()}`;
  }catch(e){ lunarStr=''; }
  document.getElementById('todaySolar').textContent =
    `${now.getFullYear()}年${now.getMonth()+1}月${now.getDate()}日 星期${wk}`;
  document.getElementById('todayLunar').textContent = lunarStr;
}

// ===== 声音 / 震动反馈 =====
let AC = null;
function playSwipe(dir){
  try{
    AC = AC || new (window.AudioContext||window.webkitAudioContext)();
    if(AC.state==='suspended') AC.resume();
    const t = AC.currentTime;
    const seq = dir>0 ? [[600,0,.06],[940,.055,.09]] : [[860,0,.06],[540,.055,.09]];
    for(const [f,dt,d] of seq){
      const o = AC.createOscillator(), g = AC.createGain();
      o.type='sine'; o.frequency.setValueAtTime(f, t+dt);
      g.gain.setValueAtTime(0.0001, t+dt);
      g.gain.exponentialRampToValueAtTime(0.25, t+dt+0.012);
      g.gain.exponentialRampToValueAtTime(0.0001, t+dt+d);
      o.connect(g); g.connect(AC.destination);
      o.start(t+dt); o.stop(t+dt+d+0.02);
    }
  }catch(e){}
}
function buzz(){
  try{ if(navigator.vibrate) navigator.vibrate(18); }catch(e){}
}

// ===== 切换人物 =====
function switchPerson(key, dir=0, silent=false){
  if(!silent && curKey!==key){ playSwipe(dir||1); buzz(); }
  curKey = key;
  document.body.dataset.theme = key;
  document.querySelectorAll('.pcard').forEach(b=> b.classList.toggle('on', b.dataset.key===key));
  const cs = getComputedStyle(document.body);
  document.getElementById('metaTheme').setAttribute('content', cs.getPropertyValue('--bgA').trim());
  document.getElementById('main').dataset.dir = dir>0?'1':dir<0?'-1':'0';
  renderCard(key);
  initFloaters(FLOAT_EMOJI[key]);
}

// ===== 手势：左滑右滑切换 =====
function swipeTo(dir){
  const oi = ORDER.indexOf(curKey);
  const ni = (oi+dir+ORDER.length) % ORDER.length;
  switchPerson(ORDER[ni], dir);
}
(function(){
  let sx=0, sy=0, on=false, dragged=false;
  const mainEl = document.getElementById('main');
  document.addEventListener('touchstart', e=>{
    const t = e.touches[0];
    sx=t.clientX; sy=t.clientY; on=true; dragged=false;
  }, {passive:true});
  document.addEventListener('touchmove', e=>{
    if(!on) return;
    const t = e.touches[0], dx=t.clientX-sx, dy=t.clientY-sy;
    if(Math.abs(dx)>18 && Math.abs(dx)>Math.abs(dy)*1.2){
      dragged = true;
      mainEl.style.transition = 'none';
      mainEl.style.transform = 'translateX('+(dx*0.22).toFixed(1)+'px)';
      mainEl.style.opacity = String(1-Math.min(Math.abs(dx)/700, .3));
    }
  }, {passive:true});
  document.addEventListener('touchend', e=>{
    if(!on) return; on=false;
    mainEl.style.transition = 'transform .3s ease, opacity .3s ease';
    mainEl.style.transform = '';
    mainEl.style.opacity = '';
    if(!dragged) return;
    const dx = e.changedTouches[0].clientX - sx;
    const dy = e.changedTouches[0].clientY - sy;
    if(Math.abs(dx)>65 && Math.abs(dx)>Math.abs(dy)*1.4) swipeTo(dx<0?1:-1);
  }, {passive:true});
})();

// ===== 事件 =====
document.getElementById('pswitch').addEventListener('click', e=>{
  const btn = e.target.closest('.pcard');
  if(!btn || btn.dataset.key===curKey) return;
  const ni = ORDER.indexOf(btn.dataset.key), oi = ORDER.indexOf(curKey);
  switchPerson(btn.dataset.key, ni>oi?1:-1);
});

document.getElementById('main').addEventListener('click', e=>{
  const av = e.target.closest('.avatar');
  if(av){
    av.classList.remove('bounce');
    void av.offsetWidth;
    av.classList.add('bounce');
    if(curKey==='wife') spawnHearts(av);
    return;
  }
  if(e.target.closest('.qcard')) drawQuote(curKey, true);
});

// ===== 启动 =====
initDatebar();
switchPerson('baby');
