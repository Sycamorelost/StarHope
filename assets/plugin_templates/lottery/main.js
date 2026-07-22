// StarHope 抽奖 & 点名 (shp.sycamorelost.lottery) v7
// 新增：点名加权(姓名权重+策略) + 随机分组(名单随机分N组)。
// 既有：多档抽奖/权重/限中/排除/必中/多策略/批量/概率进度条/中签统计/方案/导入导出。
starhope.title = '抽奖 & 点名';

var draft = { name: '', weight: '1', maxCount: '0', tier: '1' };
var rollDraft = '';
var lastResults = [];
var tierResults = {};
var rollResults = [];
var rollGroups = [];
var msg = '';
var tab = 'draw';

function S(k, d){ var v = starhope.storage.get(k); return (v === undefined || v === null) ? d : v; }
function getPrizes(){ return S('prizes', []); }
function savePrizes(p){ starhope.storage.set('prizes', p); }
function getHistory(){ return S('history', []); }
function getStrategy(){ return S('strategy', 'uniform'); }
function getUnique(){ return S('unique', false) === true; }
function getBatch(){ return S('batch', 1); }
function getSchemes(){ return S('schemes', []); }
function getCounts(){ return S('counts', {}); }
function getDrawn(){ return S('drawn', []); }
function getNames(){ return S('names', []); }
function saveNames(n){ starhope.storage.set('names', n); }
function getRollHistory(){ return S('rollHistory', []); }
function getRollDrawn(){ return S('rollDrawn', []); }
function getRollUnique(){ return S('rollUnique', true) !== false; }
function getRollBatch(){ return S('rollBatch', 1); }
function getRollStrategy(){ return S('rollStrategy', 'uniform'); }
function tierName(t){ return t === 3 ? '三等奖' : (t === 2 ? '二等奖' : '一等奖'); }
function nowStr(){ var d = new Date(); function p(n){ return n<10?'0'+n:n; } return p(d.getMonth()+1)+'-'+p(d.getDate())+' '+p(d.getHours())+':'+p(d.getMinutes()); }
function uid(){ return Math.random().toString(36).slice(2,9); }
function assign(a, b){ var o = {}; for (var k in a) o[k] = a[k]; for (var k2 in b) o[k2] = b[k2]; return o; }

function h1(t){ return {type:'text', text:t, size:18, weight:'bold'}; }
function h2(t){ return {type:'text', text:t, size:14, weight:'bold'}; }
function body(t, color){ return {type:'text', text:t, size:13, color: color || null}; }
function muted(t){ return {type:'text', text:t, size:11, color:'muted'}; }
function gap(h){ return {type:'sizedbox', height: h||8}; }
function resultText(t){ return {type:'text', text:t, size:22, weight:'bold', color:'primary'}; }

function render(){
  return col([ header(), gap(8), tabBar(), gap(10),
    tab === 'prizes' ? prizesTab() :
    tab === 'roll' ? rollTab() :
    tab === 'rollList' ? rollListTab() :
    tab === 'history' ? historyTab() :
    tab === 'scheme' ? schemeTab() : drawTab(),
  ]);
}
function header(){ return {type:'row', children:[ h1('抽奖 & 点名'), {type:'spacer'}, {type:'button', icon:'casino', variant:'tonal', label:'抽奖', onTap:'goto:draw'}, {type:'sizedbox', width:6}, {type:'button', icon:'refresh', variant:'outlined', label:'退出', onTap:'__exit__'} ]}; }
function tabBar(){ return {type:'wrap', children:[ tabBtn('draw','抽奖'), tabBtn('prizes','奖品'), tabBtn('roll','点名'), tabBtn('rollList','名单'), tabBtn('history','历史'), tabBtn('scheme','方案') ]}; }
function tabBtn(t, label){ return {type:'sizedbox', height:36, child:{type:'segmented', value: tab===t ? t : '~~', options:[{value:t, label:label}], onChanged:'setTab'}}; }

function prizesTab(){
  var prizes = getPrizes(); var counts = getCounts();
  var list = prizes.length ? prizes.map(function(p){
    var chips = [ chip(tierName(p.tier||1)), chip('权重 ' + (p.weight||1)), chip(p.exclude ? '已排除' : '参与中') ];
    if (p.must) chips.push(badge('必中', 'primary'));
    if (p.maxCount > 0) chips.push(chip('限中 ' + p.maxCount));
    return card(null, [ {type:'row', children:[ body(p.name, null), {type:'spacer'}, muted('已中 ' + (counts[p.id]||0)), {type:'sizedbox', width:6}, {type:'button', icon:'delete', variant:'outlined', onTap:'remove:' + p.id} ]}, gap(4), {type:'wrap', children: chips.concat([ {type:'sizedbox', width:4}, {type:'button', icon: p.exclude ? 'add':'remove', variant:'outlined', label: p.exclude ? '纳入':'排除', onTap:'toggleExclude:' + p.id}, {type:'sizedbox', width:4}, {type:'button', icon:'star', variant: p.must ? 'tonal':'outlined', label: p.must ? '取消必中':'设必中', onTap:'toggleMust:' + p.id} ]) }]);
  }) : [muted('还没有奖品，先添加几个')];
  return col([ card('添加奖品', [ {type:'row', children:[ {type:'expanded', child:{type:'textfield', key:'pname', label:'奖品名', value:draft.name, onChanged:'setName'}}, {type:'sizedbox', width:6}, {type:'sizedbox', width:60, child:{type:'textfield', key:'pw', label:'权重', value:draft.weight, keyboard:'number', onChanged:'setWeight'}}, {type:'sizedbox', width:6}, {type:'sizedbox', width:72, child:{type:'textfield', key:'pm', label:'限中次数', value:draft.maxCount, keyboard:'number', onChanged:'setMax'}}, {type:'sizedbox', width:6}, {type:'button', icon:'add', label:'加', onTap:'add'} ]}, gap(6), h2('档位'), {type:'segmented', value:'' + (draft.tier||'1'), options:[{value:'1', label:'一等'},{value:'2', label:'二等'},{value:'3', label:'三等'}], onChanged:'setTier'}, gap(4), muted('限中次数：0 = 无限，>0 = 抽满即移出奖池；档位用于多档抽奖') ]), gap(10), card('奖品列表（' + prizes.length + '）', [{type:'button', icon:'delete', variant:'outlined', label:'清空全部', onTap:'clearPrizes'}, gap(6)].concat(list)) ]);
}

function drawTab(){
  var prizes = getPrizes(); var pool = poolInfo(); var batch = Math.min(getBatch(), pool.length);
  var resultKids = lastResults.length ? [{type:'center', child:{type:'column', children: lastResults.map(function(n, i){ return resultText((i+1) + '. ' + n); })}}] : [gap(0)];
  var tierKids = [];
  [1,2,3].forEach(function(t){ var arr = tierResults[t] || []; if (arr.length) { tierKids.push({type:'row', children:[badge(tierName(t), 'primary'), {type:'sizedbox', width:8}, body(arr.join('、'), null)]}); tierKids.push(gap(4)); } });
  var prev = gap(0);
  if (getStrategy() === 'weighted' && pool.length) {
    var total = pool.reduce(function(a, x){ return a + (parseInt(x.weight)||1); }, 0);
    prev = card('中签概率（按权重）', pool.map(function(p){ var frac = total > 0 ? (parseInt(p.weight)||1) / total : 0; var pct = (frac * 100).toFixed(1); return {type:'column', crossAxisAlignment:'stretch', children:[ {type:'row', children:[body(p.name, null), {type:'spacer'}, body(pct + '%', 'primary')]}, gap(3), {type:'progress', value:frac, color:'primary'}, gap(6) ]}; }));
  }
  return col([ card('抽奖设置', [ h2('策略'), gap(4), {type:'segmented', value:getStrategy(), options:[{value:'uniform', label:'均匀随机'},{value:'weighted', label:'按权重'}], onChanged:'setStrategy'}, gap(8), {type:'checkbox', value:getUnique(), label:'不重复抽取（抽中移出奖池）', onChanged:'setUnique'}, gap(8), {type:'row', children:[body('每次抽取个数：'), {type:'sizedbox', width:70, child:{type:'textfield', key:'batch', label:'个数', value:''+getBatch(), keyboard:'number', onChanged:'setBatch'}}]}, (getUnique() || pool.length < prizes.length) ? muted('奖池剩余 ' + pool.length + ' / ' + prizes.length) : gap(0) ]), gap(10), card('普通抽奖', [ {type:'button', icon:'casino', label: pool.length ? '抽取 ' + batch + ' 个' : '奖池为空', onTap:'draw', expanded:true}, gap(8), getUnique() ? {type:'button', icon:'refresh', variant:'outlined', label:'重置奖池与限中', onTap:'resetDrawn'} : gap(0), gap(10) ].concat(resultKids).concat([msg ? body(msg, 'error') : gap(0)])), gap(10), card('多档抽奖（按档位各抽 ' + getBatch() + ' 个）', [ {type:'button', icon:'star', variant:'tonal', label:'按一/二/三等奖各抽', onTap:'drawTiered', expanded:true}, gap(8), muted('从各档位奖品池分别抽取'), gap(10) ].concat(tierKids)), gap(10), prev ]);
}

function rollTab(){
  var names = getNames(); var pool = rollPool(); var batch = Math.min(getRollBatch(), pool.length);
  var resultKids = rollResults.length ? [{type:'center', child:{type:'column', children: rollResults.map(function(n, i){ return resultText((i+1) + '. ' + n); })}}] : [gap(0)];
  var groupKids = rollGroups.length ? [{type:'divider'}, gap(6)].concat(rollGroups.map(function(g, i){ return {type:'row', children:[badge('第 ' + (i+1) + ' 组', 'primary'), {type:'sizedbox', width:8}, body(g.join('、'), null)]}; })) : [];
  return col([ card('点名设置', [ h2('点名策略'), gap(4), {type:'segmented', value:getRollStrategy(), options:[{value:'uniform', label:'均匀'}, {value:'weighted', label:'按权重'}], onChanged:'setRollStrategy'}, gap(8), {type:'checkbox', value:getRollUnique(), label:'不重复点名（本轮点过不再点）', onChanged:'setRollUnique'}, gap(8), {type:'row', children:[body('每次点名人数：'), {type:'sizedbox', width:70, child:{type:'textfield', key:'rbatch', label:'人数', value:''+getRollBatch(), keyboard:'number', onChanged:'setRollBatch'}}]}, pool.length < names.length ? muted('可点 ' + pool.length + ' / ' + names.length) : gap(0), gap(6), {type:'button', icon:'refresh', variant:'outlined', label:'重置点名记录', onTap:'resetRollDrawn'} ]), gap(10), card('随机点名', [ {type:'button', icon:'shuffle', label: pool.length ? '随机点 ' + batch + ' 人' : '名单为空', onTap:'rollCall', expanded:true}, gap(10) ].concat(resultKids).concat([msg ? body(msg, 'error') : gap(0)])), gap(10), card('随机分组', [ {type:'row', children:[body('分成几组：'), {type:'sizedbox', width:70, child:{type:'textfield', key:'gcount', label:'组数', value:'' + (S('rollGroupCount', 2)), keyboard:'number', onChanged:'setGroupCount'}}]}, gap(8), {type:'button', icon:'list', variant:'tonal', label:'随机分组', onTap:'rollGroup', expanded:true}, gap(8) ].concat(groupKids)) ]);
}
function rollListTab(){
  var names = getNames(); var rollDrawn = getRollDrawn();
  var list = names.length ? names.map(function(n){
    var gone = n.leave || (getRollUnique() && rollDrawn.indexOf(n.id) >= 0);
    return card(null, [ {type:'row', children:[ body(n.name, gone ? 'muted' : null), {type:'spacer'}, (parseInt(n.weight)||1) !== 1 ? badge('权重 ' + (n.weight||1), 'primary') : gap(0), n.leave ? badge('请假', 'error') : gap(0), {type:'sizedbox', width:4}, {type:'button', icon:'star', variant:'outlined', label:'' + (n.weight||1), onTap:'cycWeight:' + n.id}, {type:'sizedbox', width:4}, {type:'button', icon: n.leave ? 'add':'remove', variant:'outlined', label: n.leave ? '销假':'请假', onTap:'toggleLeave:' + n.id}, {type:'sizedbox', width:4}, {type:'button', icon:'delete', variant:'outlined', onTap:'removeName:' + n.id} ]} ]);
  }) : [muted('名单为空，添加人员')];
  return col([ card('添加人员', [ {type:'row', children:[ {type:'expanded', child:{type:'textfield', key:'rname', label:'姓名', value:rollDraft, onChanged:'setRollDraft'}}, {type:'sizedbox', width:6}, {type:'button', icon:'add', label:'加', onTap:'addName'} ]}, gap(6), {type:'row', children:[ {type:'expanded', child:{type:'textfield', key:'rbulk', label:'批量输入（逗号或换行分隔）', onChanged:'setBulk'}}, {type:'sizedbox', width:6}, {type:'button', icon:'list', label:'批量加', onTap:'addBulk'} ]} ]), gap(10), card('名单（' + names.length + '）', [{type:'row', children:[ {type:'button', icon:'delete', variant:'outlined', label:'清空名单', onTap:'clearNames'}, {type:'sizedbox', width:6}, {type:'button', icon:'save', variant:'outlined', label:'导出', onTap:'exportNames'}, {type:'sizedbox', width:6}, {type:'button', icon:'add', variant:'outlined', label:'导入', onTap:'importNames'} ]}, gap(6), muted('点星标循环切换权重（1→2→3→1）')].concat(list)) ]);
}
function historyTab(){
  var history = getHistory(); var rollHistory = getRollHistory(); var counts = getCounts(); var prizes = getPrizes();
  var stats = prizes.filter(function(p){ return (counts[p.id]||0) > 0; });
  var maxC = stats.reduce(function(m, p){ return Math.max(m, counts[p.id]||0); }, 1);
  var statRows = stats.length ? stats.map(function(p){ var c = counts[p.id]||0; return {type:'column', crossAxisAlignment:'stretch', children:[ {type:'row', children:[body(p.name, null), {type:'spacer'}, body(c + ' 次', 'primary')]}, gap(2), {type:'progress', value: c/maxC, color:'primary'}, gap(5) ]}; }) : [muted('暂无中签数据')];
  var hRows = history.slice(0,15).map(function(h){ return {type:'row', children:[muted(h.time), {type:'sizedbox', width:8}, body(h.names.join('、'), null)]}; });
  var rRows = rollHistory.slice(0,15).map(function(h){ return {type:'row', children:[muted(h.time), {type:'sizedbox', width:8}, body(h.names.join('、'), null)]}; });
  return col([ card('中签统计（共 ' + history.length + ' 次抽奖）', statRows), gap(10), card('抽奖历史（' + history.length + '）', [{type:'button', icon:'delete', variant:'outlined', label:'清空', onTap:'clearHistory'}, gap(6)].concat(hRows)), gap(10), card('点名历史（' + rollHistory.length + '）', [{type:'button', icon:'delete', variant:'outlined', label:'清空', onTap:'clearRollHistory'}, gap(6)].concat(rRows)) ]);
}
function schemeTab(){
  var schemes = getSchemes();
  var list = schemes.length ? schemes.map(function(s, i){ return card(null, [ {type:'row', children:[ body(s.name + '（' + s.prizes.length + '个奖品）', null), {type:'spacer'}, {type:'button', icon:'list', variant:'outlined', label:'加载', onTap:'loadScheme:' + i}, {type:'sizedbox', width:4}, {type:'button', icon:'delete', variant:'outlined', onTap:'delScheme:' + i} ]} ]); }) : [muted('还没有方案')];
  return col([ card('保存抽奖方案', [ {type:'row', children:[ {type:'expanded', child:{type:'textfield', key:'sn', label:'方案名', onChanged:'setSchemeName'}}, {type:'sizedbox', width:6}, {type:'button', icon:'save', label:'保存', onTap:'saveScheme'} ]}, gap(4), muted('保存当前奖品与抽奖设置') ]), gap(10), card('奖品导入/导出', [ {type:'row', children:[ {type:'expanded', child:{type:'button', icon:'save', variant:'outlined', label:'导出 JSON', onTap:'exportJson'}}, {type:'sizedbox', width:6}, {type:'expanded', child:{type:'button', icon:'add', variant:'outlined', label:'导入 JSON', onTap:'importJson'}} ]} ]), gap(10), card('已存方案（' + schemes.length + '）', list) ]);
}

function col(children){ return {type:'column', crossAxisAlignment:'stretch', children: children}; }
function card(title, children){ var c = []; if (title) { c.push(h2(title)); c.push(gap(6)); } return {type:'card', child:{type:'column', crossAxisAlignment:'stretch', children: c.concat(children)}}; }
function chip(text){ return {type:'card', padding:5, child: muted(text)}; }
function badge(text, color){ return {type:'badge', text: text, color: color || 'primary'}; }

function poolInfo(){ var counts = getCounts(), drawn = getDrawn(); return getPrizes().filter(function(p){ if (p.exclude) return false; if (p.maxCount > 0 && (counts[p.id]||0) >= p.maxCount) return false; if (getUnique() && drawn.indexOf(p.id) >= 0) return false; return true; }); }
function rollPool(){ var rd = getRollDrawn(); return getNames().filter(function(n){ return !n.leave && !(getRollUnique() && rd.indexOf(n.id) >= 0); }); }

var schemeName = '', bulkDraft = '';
function onAction(name, args){
  msg = ''; lastResults = []; tierResults = {}; rollGroups = [];
  if (name.indexOf('goto:') === 0) { tab = name.substring(5); return; }
  if (name === 'setTab') { tab = args.value; return; }
  if (name.indexOf('remove:') === 0) { savePrizes(getPrizes().filter(function(p){ return p.id !== name.substring(7); })); return; }
  if (name.indexOf('toggleExclude:') === 0) { togglePrize(name.substring(14), 'exclude'); return; }
  if (name.indexOf('toggleMust:') === 0) { togglePrize(name.substring(11), 'must'); return; }
  if (name.indexOf('removeName:') === 0) { saveNames(getNames().filter(function(n){ return n.id !== name.substring(11); })); return; }
  if (name.indexOf('toggleLeave:') === 0) { saveNames(getNames().map(function(n){ if (n.id === name.substring(12)) return assign(n, {leave: !n.leave}); return n; })); return; }
  if (name.indexOf('cycWeight:') === 0) { var id = name.substring(10); saveNames(getNames().map(function(n){ if (n.id === id) { var w = (parseInt(n.weight)||1) % 3 + 1; return assign(n, {weight: w}); } return n; })); return; }
  if (name.indexOf('loadScheme:') === 0) { loadScheme(parseInt(name.substring(11))); return; }
  if (name.indexOf('delScheme:') === 0) { var ss = getSchemes(); ss.splice(parseInt(name.substring(10)), 1); starhope.storage.set('schemes', ss); return; }
  switch (name) {
    case 'setName': draft.name = args.value; break;
    case 'setWeight': draft.weight = args.value; break;
    case 'setMax': draft.maxCount = args.value; break;
    case 'setTier': draft.tier = args.value; break;
    case 'add': addPrize(); break;
    case 'clearPrizes': savePrizes([]); starhope.storage.set('drawn', []); starhope.storage.set('counts', {}); starhope.storage.set('history', []); break;
    case 'setStrategy': starhope.storage.set('strategy', args.value); break;
    case 'setUnique': starhope.storage.set('unique', args.value); break;
    case 'setBatch': starhope.storage.set('batch', parseInt(args.value) || 1); break;
    case 'resetDrawn': starhope.storage.set('drawn', []); starhope.storage.set('counts', {}); break;
    case 'draw': draw(); break;
    case 'drawTiered': drawTiered(); break;
    case 'clearHistory': starhope.storage.set('history', []); break;
    case 'setSchemeName': schemeName = args.value; break;
    case 'saveScheme': saveScheme(); break;
    case 'exportJson': starhope.storage.set('__clip__', JSON.stringify(getPrizes())); msg = '已导出 ' + getPrizes().length + ' 个奖品'; break;
    case 'importJson': importJson(); break;
    case 'setRollDraft': rollDraft = args.value; break;
    case 'setBulk': bulkDraft = args.value; break;
    case 'addName': addName(); break;
    case 'addBulk': addBulk(); break;
    case 'clearNames': saveNames([]); starhope.storage.set('rollDrawn', []); starhope.storage.set('rollHistory', []); break;
    case 'setRollUnique': starhope.storage.set('rollUnique', args.value); break;
    case 'setRollBatch': starhope.storage.set('rollBatch', parseInt(args.value) || 1); break;
    case 'setRollStrategy': starhope.storage.set('rollStrategy', args.value); break;
    case 'setGroupCount': starhope.storage.set('rollGroupCount', parseInt(args.value) || 2); break;
    case 'resetRollDrawn': starhope.storage.set('rollDrawn', []); break;
    case 'rollCall': rollCall(); break;
    case 'rollGroup': rollGroup(); break;
    case 'clearRollHistory': starhope.storage.set('rollHistory', []); break;
    case 'exportNames': starhope.storage.set('__clip__', JSON.stringify(getNames().map(function(n){ return {name: n.name, weight: n.weight||1}; }))); msg = '已导出 ' + getNames().length + ' 人'; break;
    case 'importNames': importNames(); break;
  }
}

function addPrize(){ var n = (draft.name || '').trim(); if (!n) { msg = '奖品名不能为空'; return; } var p = getPrizes(); p.push({id: uid(), name: n, weight: parseInt(draft.weight)||1, maxCount: parseInt(draft.maxCount)||0, exclude: false, must: false, tier: parseInt(draft.tier)||1}); savePrizes(p); draft.name = ''; draft.weight = '1'; draft.maxCount = '0'; draft.tier = '1'; }
function togglePrize(id, field){ savePrizes(getPrizes().map(function(x){ if (x.id === id) { var o = {}; o[field] = !x[field]; return assign(x, o); } return x; })); }
function saveScheme(){ if (!schemeName) { msg = '请输入方案名'; return; } var s = getSchemes(); s.push({name: schemeName, prizes: getPrizes().map(function(p){ return assign(p, {}); }), strategy: getStrategy(), unique: getUnique(), batch: getBatch()}); starhope.storage.set('schemes', s); schemeName = ''; }
function loadScheme(i){ var s = getSchemes(); if (i<0||i>=s.length) return; var x = s[i]; savePrizes(x.prizes.map(function(p){ return assign(p, {}); })); starhope.storage.set('strategy', x.strategy||'uniform'); starhope.storage.set('unique', x.unique===true); starhope.storage.set('batch', x.batch||1); starhope.storage.set('drawn', []); starhope.storage.set('counts', {}); }
function importJson(){ var raw = starhope.storage.get('__clip__'); if (!raw) { msg = '剪贴板为空'; return; } try { var arr = JSON.parse(raw); if (!arr || arr.length === undefined) throw 'x'; var p = getPrizes(); arr.forEach(function(x){ p.push({id: uid(), name: x.name||'?', weight: parseInt(x.weight)||1, maxCount: parseInt(x.maxCount)||0, exclude: false, must: false, tier: parseInt(x.tier)||1}); }); savePrizes(p); msg = '已导入 ' + arr.length + ' 个奖品'; } catch(e) { msg = '导入失败：非有效 JSON 数组'; } }
function drawN(pool, n, strategy){ var avail = pool.slice(), winners = []; for (var i = 0; i < n && avail.length; i++) { var idx; if (strategy === 'weighted') { var total = avail.reduce(function(a, p){ return a + (parseInt(p.weight)||1); }, 0); var r = Math.random() * total, acc = 0; idx = avail.length - 1; for (var j = 0; j < avail.length; j++) { acc += (parseInt(avail[j].weight)||1); if (r < acc) { idx = j; break; } } } else { idx = Math.floor(Math.random() * avail.length); } winners.push(avail[idx]); avail.splice(idx, 1); } return winners; }
function recordWinners(winners){ var h = getHistory(); h.unshift({time: nowStr(), names: winners.map(function(p){ return p.name; })}); if (h.length > 100) h = h.slice(0, 100); starhope.storage.set('history', h); var counts = getCounts(), drawn = getDrawn(); winners.forEach(function(p){ counts[p.id] = (counts[p.id]||0) + 1; if (getUnique()) drawn.push(p.id); }); starhope.storage.set('counts', counts); starhope.storage.set('drawn', drawn); }
function draw(){ var pool = poolInfo(); if (!pool.length) { msg = '奖池为空'; return; } var must = pool.filter(function(p){ return p.must; }); var rest = pool.filter(function(p){ return !p.must; }); var batch = Math.min(getBatch(), pool.length); var winners = must.slice(0, batch); var need = batch - winners.length; winners = winners.concat(drawN(rest, need, getStrategy())); lastResults = winners.map(function(p){ return p.name; }); recordWinners(winners); }
function drawTiered(){ var counts = getCounts(), drawn = getDrawn(); var all = getPrizes(); tierResults = {}; var any = false; [1,2,3].forEach(function(t){ var tpool = all.filter(function(p){ return (p.tier||1) === t && !p.exclude && !(p.maxCount > 0 && (counts[p.id]||0) >= p.maxCount) && !(getUnique() && drawn.indexOf(p.id) >= 0); }); if (tpool.length) { var winners = drawN(tpool, Math.min(getBatch(), tpool.length), getStrategy()); tierResults[t] = winners.map(function(p){ return p.name; }); recordWinners(winners); any = true; } }); if (!any) { msg = '无可抽取的档位奖品'; } }

function addName(){ var n = (rollDraft || '').trim(); if (!n) { msg = '姓名不能为空'; return; } var names = getNames(); names.push({id: uid(), name: n, leave: false, weight: 1}); saveNames(names); rollDraft = ''; }
function addBulk(){ var parts = (bulkDraft || '').split(/[，,\n]/).map(function(s){ return s.trim(); }).filter(function(s){ return s; }); if (!parts.length) { msg = '批量输入为空'; return; } var names = getNames(); parts.forEach(function(s){ names.push({id: uid(), name: s, leave: false, weight: 1}); }); saveNames(names); bulkDraft = ''; msg = '已批量添加 ' + parts.length + ' 人'; }
function importNames(){ var raw = starhope.storage.get('__clip__'); if (!raw) { msg = '剪贴板为空'; return; } try { var arr = JSON.parse(raw); if (!arr) throw 'x'; var names = getNames(); (arr.length !== undefined ? arr : [arr]).forEach(function(s){ names.push({id: uid(), name: typeof s === 'string' ? s : (s.name||'?'), leave: false, weight: typeof s === 'object' ? (parseInt(s.weight)||1) : 1}); }); saveNames(names); msg = '已导入 ' + (arr.length !== undefined ? arr.length : 1) + ' 人'; } catch(e) { msg = '导入失败：非有效 JSON'; } }
function rollCall(){ var pool = rollPool(); if (!pool.length) { msg = '可点名单为空'; rollResults = []; return; } var batch = Math.min(getRollBatch(), pool.length); var winners = drawN(pool, batch, getRollStrategy()); rollResults = winners.map(function(n){ return n.name; }); var h = getRollHistory(); h.unshift({time: nowStr(), names: rollResults.slice()}); if (h.length > 100) h = h.slice(0, 100); starhope.storage.set('rollHistory', h); if (getRollUnique()) { var rd = getRollDrawn(); winners.forEach(function(n){ rd.push(n.id); }); starhope.storage.set('rollDrawn', rd); } }
function rollGroup(){ var pool = getNames().filter(function(n){ return !n.leave; }); if (!pool.length) { msg = '名单为空'; rollGroups = []; return; } var gn = S('rollGroupCount', 2); if (gn < 1) gn = 1; var shuffled = pool.slice(); for (var i = shuffled.length - 1; i > 0; i--) { var j = Math.floor(Math.random() * (i + 1)); var tmp = shuffled[i]; shuffled[i] = shuffled[j]; shuffled[j] = tmp; } rollGroups = []; for (var k = 0; k < gn; k++) rollGroups.push([]); shuffled.forEach(function(n, idx){ rollGroups[idx % gn].push(n.name); }); }
