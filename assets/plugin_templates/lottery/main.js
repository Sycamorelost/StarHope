// StarHope 抽奖插件 (shp.sycamorelost.lottery)
// 全量功能：奖品管理(增删/权重) · 多策略(均匀/按权重/不重复) · 抽奖 · 历史 · 统计
// 本地持久化 via starhope.storage；UI 由 render() 返回 JSON 树，宿主渲染。

starhope.title = '🎰 抽奖';

var draftName = '';
var draftWeight = '1';
var lastResult = '';
var msg = '';

function getPrizes(){ return starhope.storage.get('prizes') || []; }
function getHistory(){ return starhope.storage.get('history') || []; }
function getStrategy(){ return starhope.storage.get('strategy') || 'uniform'; }
function getUnique(){ return starhope.storage.get('unique') === true; }
function getDrawn(){ return starhope.storage.get('drawn') || []; }
function nowStr(){ var d = new Date(); function p(n){ return n<10?'0'+n:n; } return p(d.getMonth()+1)+'-'+p(d.getDate())+' '+p(d.getHours())+':'+p(d.getMinutes()); }
function uid(){ return Math.random().toString(36).slice(2,9); }
function savePrizes(p){ starhope.storage.set('prizes', p); }

function render(){
  var prizes = getPrizes();
  var history = getHistory();
  var drawn = getDrawn();
  var kids = [
    {type: 'text', text: '🎰 抽奖', size: 24, weight: 'bold'},
    {type: 'sizedbox', height: 8},
    card('添加奖品', [
      {type: 'row', children: [
        {type: 'expanded', child: {type: 'textfield', key: 'name', label: '奖品名', value: draftName, onChanged: 'setName'}},
        {type: 'sizedbox', width: 8},
        {type: 'sizedbox', width: 70, child: {type: 'textfield', key: 'weight', label: '权重', value: draftWeight, keyboard: 'number', onChanged: 'setWeight'}},
        {type: 'button', icon: 'add', label: '加', onTap: 'add'},
      ]},
    ]),
    {type: 'sizedbox', height: 10},
    card('奖品列表 (' + prizes.length + ')', prizes.length ? [wrap(prizes.map(function(p){
      return {type: 'card', onTap: '', padding: 8, child: {type: 'row', children: [
        {type: 'text', text: p.name, weight: 'bold'},
        {type: 'sizedbox', width: 6},
        {type: 'text', text: '×'+(p.weight||1), size: 11, color: 'muted'},
        {type: 'sizedbox', width: 6},
        {type: 'button', icon: 'delete', variant: 'outlined', onTap: 'remove:' + p.id},
      ]}};
    }))].concat([
      {type: 'sizedbox', height: 6},
      {type: 'button', icon: 'delete', variant: 'outlined', label: '清空全部奖品', onTap: 'clearPrizes'},
    ]) : [{type: 'text', text: '还没有奖品，添加几个吧～', color: 'muted', size: 12}]),
    {type: 'sizedbox', height: 10},
    card('抽奖策略', [
      {type: 'segmented', value: getStrategy(), options: [
        {value: 'uniform', label: '均匀随机'},
        {value: 'weighted', label: '按权重'},
      ], onChanged: 'setStrategy'},
      {type: 'sizedbox', height: 6},
      {type: 'checkbox', value: getUnique(), label: '不重复抽取（抽中即移出奖池）', onChanged: 'setUnique'},
      getUnique() ? {type: 'text', text: '已抽 ' + drawn.length + ' / ' + prizes.length, size: 11, color: 'muted'} : {type: 'sizedbox', height: 0},
      getUnique() ? {type: 'button', variant: 'outlined', icon: 'refresh', label: '重置奖池', onTap: 'resetDrawn'} : {type: 'sizedbox', height: 0},
    ]),
    {type: 'sizedbox', height: 10},
    card('', [
      {type: 'button', icon: 'casino', label: prizes.length ? '🎉 开始抽奖' : '请先添加奖品', onTap: 'draw', expanded: true},
      {type: 'sizedbox', height: 10},
      lastResult ? {type: 'center', child: {type: 'text', text: '🎊 ' + lastResult + ' 🎊', size: 26, weight: 'bold', color: 'primary'}} : {type: 'sizedbox', height: 0},
      msg ? {type: 'text', text: msg, color: 'error', size: 12} : {type: 'sizedbox', height: 0},
    ]),
    {type: 'sizedbox', height: 10},
    card('历史 (' + history.length + ')', [
      {type: 'button', icon: 'delete', variant: 'outlined', label: '清空历史', onTap: 'clearHistory'},
      {type: 'sizedbox', height: 6},
    ].concat(history.slice(0, 10).map(function(h){
      return {type: 'row', children: [
        {type: 'text', text: h.time, size: 11, color: 'muted'},
        {type: 'sizedbox', width: 8},
        {type: 'text', text: h.name, weight: 'bold'},
        {type: 'spacer'},
        h.count ? {type: 'text', text: '第 '+h.count+' 次', size: 11, color: 'muted'} : {type: 'sizedbox'},
      ]};
    }))).concat([{type: 'divider'}, {type: 'text', text: '统计：共抽 ' + history.length + ' 次 · ' + prizes.length + ' 个奖品', size: 11, color: 'muted'}]),
    ]),
  ];
  return {type: 'column', crossAxisAlignment: 'stretch', children: kids};
}

function card(title, children){
  var c = [];
  if (title) { c.push({type: 'text', text: title, weight: 'bold'}); c.push({type: 'sizedbox', height: 6}); }
  c = c.concat(children);
  return {type: 'card', child: {type: 'column', crossAxisAlignment: 'stretch', children: c}};
}
function wrap(items){ return {type: 'wrap', children: items}; }

function onAction(name, args){
  msg = '';
  if (name.indexOf('remove:') === 0) { removePrize(name.substring(7)); return; }
  switch (name) {
    case 'setName': draftName = args.value; break;
    case 'setWeight': draftWeight = args.value; break;
    case 'add': addPrize(); break;
    case 'clearPrizes': savePrizes([]); starhope.storage.set('drawn', []); break;
    case 'setStrategy': starhope.storage.set('strategy', args.value); break;
    case 'setUnique': starhope.storage.set('unique', args.value); break;
    case 'resetDrawn': starhope.storage.set('drawn', []); break;
    case 'draw': draw(); break;
    case 'clearHistory': starhope.storage.set('history', []); break;
  }
}

function addPrize(){
  var n = (draftName || '').trim();
  if (!n) { msg = '奖品名不能为空'; return; }
  var w = parseInt(draftWeight) || 1; if (w < 1) w = 1;
  var p = getPrizes(); p.push({id: uid(), name: n, weight: w}); savePrizes(p);
  draftName = ''; draftWeight = '1';
}
function removePrize(id){ savePrizes(getPrizes().filter(function(p){ return p.id !== id; })); }

function draw(){
  var prizes = getPrizes();
  if (!prizes.length) { msg = '请先添加奖品'; lastResult = ''; return; }
  var pool = prizes.slice();
  if (getUnique()) {
    var drawn = getDrawn();
    pool = prizes.filter(function(p){ return drawn.indexOf(p.id) < 0; });
    if (!pool.length) { msg = '奖品已抽完，点「重置奖池」'; lastResult = ''; return; }
  }
  var winner;
  if (getStrategy() === 'weighted') {
    var total = pool.reduce(function(a, p){ return a + (parseInt(p.weight) || 1); }, 0);
    var r = Math.random() * total, acc = 0;
    for (var i = 0; i < pool.length; i++) { acc += (parseInt(pool[i].weight) || 1); if (r < acc) { winner = pool[i]; break; } }
    if (!winner) winner = pool[pool.length - 1];
  } else {
    winner = pool[Math.floor(Math.random() * pool.length)];
  }
  lastResult = winner.name;
  var history = getHistory();
  // 统计该奖品抽中次数
  var sameCount = history.filter(function(h){ return h.name === winner.name; }).length + 1;
  history.unshift({time: nowStr(), name: winner.name, count: sameCount});
  if (history.length > 100) history = history.slice(0, 100);
  starhope.storage.set('history', history);
  if (getUnique()) { var d2 = getDrawn(); d2.push(winner.id); starhope.storage.set('drawn', d2); }
}
