// StarHope 抽奖 & 点名 (shp.sycamorelost.lottery) v18
// v18：内容超一屏可垂直滚动（render 根包 scroll 节点，widget_view 新增 scroll 类型）。
// v17：导入/导出模板 tab（严格 JSON 格式 + 字段说明 + 复制模板）；中奖/点名结果
//   独立为大号毛玻璃结果框（滚动中翻滚大字，结束后大号显示，焦点位置）。
// 既有：单段式 Tab / 复选框正常字号 / 全局消息条 / 打开数据目录 /
//   多档抽奖 / 多策略(均匀·加权) / 批量 / 权重 / 限中 / 排除 / 必中 / 概率 / 中签统计 /
//   撤销 / 多格式导入 / 模块化快照 / 点名加权·请假·随机分组 / 历史导出。
starhope.title = '抽奖 & 点名';

var draft = { name: '', weight: '1', maxCount: '0', tier: '1' };
var rollDraft = '';
var lastResults = [];
var tierResults = {};
var rollResults = [];
var rollGroups = [];
var lastDrawIds = [];
var rolling = false; // 滚动动画进行中（控制大号结果框显示翻滚态）
var msg = '';
var msgKind = 'info';
var tab = 'draw';
var schemeName = '';
var bulkDraft = '';

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
function notify(t, k){ msg = t; msgKind = k || 'info'; }

function h1(t){ return {type:'text', text:t, size:18, weight:'bold'}; }
function h2(t){ return {type:'text', text:t, size:14, weight:'bold'}; }
function body(t, color){ return {type:'text', text:t, size:13, color: color || null}; }
function muted(t){ return {type:'text', text:t, size:11, color:'muted'}; }
function gap(h){ return {type:'sizedbox', height: h||8}; }
function bigText(t, size){ return {type:'text', text:t, size:size, weight:'bold', color:'primary'}; }

function render(){
  return {type:'scroll', child: col([
    header(), gap(10), tabBar(), gap(14),
    tab === 'prizes' ? prizesTab() :
    tab === 'roll' ? rollTab() :
    tab === 'rollList' ? rollListTab() :
    tab === 'history' ? historyTab() :
    tab === 'scheme' ? schemeTab() :
    tab === 'template' ? templateTab() : drawTab(),
    gap(8),
    msg ? msgBox() : gap(0),
    gap(10)
  ])};
}
function msgBox(){
  var color = msgKind === 'error' ? 'error' : (msgKind === 'success' ? 'primary' : 'muted');
  return {type:'card', padding:10, child: body(msg, color)};
}
function header(){ return {type:'row', children:[ h1('抽奖 & 点名'), {type:'spacer'}, {type:'button', icon:'close', variant:'outlined', label:'退出', onTap:'__exit__'} ]}; }
function tabBar(){
  return {type:'segmented', value: tab, options:[
    {value:'draw', label:'抽奖'}, {value:'prizes', label:'奖品'}, {value:'roll', label:'点名'},
    {value:'rollList', label:'名单'}, {value:'history', label:'历史'}, {value:'scheme', label:'方案'},
    {value:'template', label:'模板'}
  ], onChanged:'setTab'};
}

function prizesTab(){
  var prizes = getPrizes(); var counts = getCounts();
  var list = prizes.length ? prizes.map(function(p){
    var chips = [ chip(tierName(p.tier||1)), chip('权重 ' + (p.weight||1)), chip(p.exclude ? '已排除' : '参与中') ];
    if (p.must) chips.push(badge('必中', 'primary'));
    if (p.maxCount > 0) chips.push(chip('限中 ' + p.maxCount));
    return card(null, [ {type:'row', children:[ body(p.name, null), {type:'spacer'}, muted('已中 ' + (counts[p.id]||0)), {type:'sizedbox', width:6}, {type:'button', icon:'delete', variant:'outlined', onTap:'remove:' + p.id} ]}, gap(6), {type:'wrap', children: chips.concat([ {type:'sizedbox', width:4}, {type:'button', icon: p.exclude ? 'add':'remove', variant:'outlined', label: p.exclude ? '纳入':'排除', onTap:'toggleExclude:' + p.id}, {type:'sizedbox', width:4}, {type:'button', icon:'star', variant: p.must ? 'tonal':'outlined', label: p.must ? '取消必中':'设必中', onTap:'toggleMust:' + p.id} ]) }]);
  }) : [emptyNode('暂无奖品', '在上方添加，或从方案 tab 导入', 'gift', '去添加', 'goto:prizes')];
  return col([ card('添加奖品', [ {type:'textfield', key:'pname', label:'奖品名称', value:draft.name, onChanged:'setName'}, gap(8), h2('档位'), gap(4), {type:'segmented', value:'' + (draft.tier||'1'), options:[{value:'1', label:'一等'},{value:'2', label:'二等'},{value:'3', label:'三等'}], onChanged:'setTier'}, gap(8), {type:'row', children:[ {type:'expanded', child:{type:'textfield', key:'pw', label:'权重', value:draft.weight, keyboard:'number', onChanged:'setWeight'}}, {type:'sizedbox', width:8}, {type:'expanded', child:{type:'textfield', key:'pm', label:'限中次数', value:draft.maxCount, keyboard:'number', onChanged:'setMax'}}, {type:'sizedbox', width:8}, {type:'button', icon:'add', label:'添加', onTap:'add'} ]}, gap(6), muted('限中次数：0 = 无限，>0 = 抽满即移出奖池；档位用于多档抽奖') ]), gap(12), card('奖品列表（' + prizes.length + '）', [{type:'row', children:[ {type:'button', icon:'delete', variant:'outlined', label:'清空全部', onTap:'clearPrizes'} ]}, gap(8)].concat(list)) ]);
}

function drawTab(){
  var prizes = getPrizes(); var pool = poolInfo();
  var tierKids = [];
  [1,2,3].forEach(function(t){ var arr = tierResults[t] || []; if (arr.length) { tierKids.push({type:'row', children:[badge(tierName(t), 'primary'), {type:'sizedbox', width:8}, body(arr.join('、'), null)]}); tierKids.push(gap(4)); } });
  var prev = gap(0);
  if (getStrategy() === 'weighted' && pool.length) {
    var total = pool.reduce(function(a, x){ return a + (parseInt(x.weight)||1); }, 0);
    prev = card('中签概率（按权重）', pool.map(function(p){ var frac = total > 0 ? (parseInt(p.weight)||1) / total : 0; var pct = (frac * 100).toFixed(1); return {type:'column', crossAxisAlignment:'stretch', children:[ {type:'row', children:[body(p.name, null), {type:'spacer'}, body(pct + '%', 'primary')]}, gap(3), {type:'progress', value:frac, color:'primary'}, gap(6) ]}; }));
  }
  return col([
    resultCard(false),
    gap(12),
    card('抽奖设置', [ h2('抽取策略'), gap(4), {type:'segmented', value:getStrategy(), options:[{value:'uniform', label:'均匀随机'},{value:'weighted', label:'按权重'}], onChanged:'setStrategy'}, gap(10), {type:'checkbox', value:getUnique(), size:13, label:'不重复抽取（抽中即移出奖池）', onChanged:'setUnique'}, gap(8), {type:'row', children:[body('每次抽取个数'), {type:'sizedbox', width:8}, {type:'sizedbox', width:72, child:{type:'textfield', key:'batch', label:'个数', value:''+getBatch(), keyboard:'number', onChanged:'setBatch'}}]}, gap(6), (getUnique() || pool.length < prizes.length) ? muted('奖池剩余 ' + pool.length + ' / ' + prizes.length) : gap(0) ]),
    gap(12),
    card('开始抽奖', [ {type:'button', icon:'casino', label: pool.length ? '开始抽奖' : '奖池为空', onTap:'spinDraw', expanded:true}, gap(8), getUnique() ? {type:'button', icon:'refresh', variant:'outlined', label:'重置奖池与限中', onTap:'resetDrawn', expanded:true} : gap(0), lastDrawIds.length ? {type:'button', icon:'undo', variant:'outlined', label:'撤销上次抽奖', onTap:'undoDraw', expanded:true} : gap(0) ]),
    gap(12),
    card('多档抽奖', [ muted('按一/二/三等奖各抽取 ' + getBatch() + ' 个'), gap(8), {type:'button', icon:'star', variant:'tonal', label:'按档位各抽', onTap:'drawTiered', expanded:true}, gap(10) ].concat(tierKids.length ? [{type:'divider'}, gap(8)] : []).concat(tierKids)),
    gap(12),
    prev
  ]);
}

function rollTab(){
  var names = getNames(); var pool = rollPool();
  var groupKids = rollGroups.length ? [{type:'divider'}, gap(8)].concat(rollGroups.map(function(g, i){ return {type:'row', children:[badge('第 ' + (i+1) + ' 组', 'primary'), {type:'sizedbox', width:8}, body(g.join('、'), null)]}; })) : [];
  return col([
    resultCard(true),
    gap(12),
    card('点名设置', [ h2('点名策略'), gap(4), {type:'segmented', value:getRollStrategy(), options:[{value:'uniform', label:'均匀'}, {value:'weighted', label:'按权重'}], onChanged:'setRollStrategy'}, gap(10), {type:'checkbox', value:getRollUnique(), size:13, label:'不重复点名（本轮点过不再点）', onChanged:'setRollUnique'}, gap(8), {type:'row', children:[body('每次点名人数'), {type:'sizedbox', width:8}, {type:'sizedbox', width:72, child:{type:'textfield', key:'rbatch', label:'人数', value:''+getRollBatch(), keyboard:'number', onChanged:'setRollBatch'}}]}, gap(6), pool.length < names.length ? muted('可点 ' + pool.length + ' / ' + names.length) : gap(0), gap(8), {type:'button', icon:'refresh', variant:'outlined', label:'重置点名记录', onTap:'resetRollDrawn', expanded:true} ]),
    gap(12),
    card('随机点名', [ {type:'button', icon:'shuffle', label: pool.length ? '开始点名' : '名单为空', onTap:'spinRoll', expanded:true} ]),
    gap(12),
    card('随机分组', [ {type:'row', children:[body('分成几组'), {type:'sizedbox', width:8}, {type:'sizedbox', width:72, child:{type:'textfield', key:'gcount', label:'组数', value:'' + (S('rollGroupCount', 2)), keyboard:'number', onChanged:'setGroupCount'}}]}, gap(8), {type:'button', icon:'list', variant:'tonal', label:'随机分组', onTap:'rollGroup', expanded:true}, gap(8) ].concat(groupKids))
  ]);
}
function rollListTab(){
  var names = getNames(); var rollDrawn = getRollDrawn();
  var list = names.length ? names.map(function(n){
    var gone = n.leave || (getRollUnique() && rollDrawn.indexOf(n.id) >= 0);
    return card(null, [ {type:'row', children:[ body(n.name, gone ? 'muted' : null), {type:'spacer'}, (parseInt(n.weight)||1) !== 1 ? badge('权重 ' + (n.weight||1), 'primary') : gap(0), n.leave ? badge('请假', 'error') : gap(0), {type:'sizedbox', width:4}, {type:'button', icon:'star', variant:'outlined', label:'' + (n.weight||1), onTap:'cycWeight:' + n.id}, {type:'sizedbox', width:4}, {type:'button', icon: n.leave ? 'add':'remove', variant:'outlined', label: n.leave ? '销假':'请假', onTap:'toggleLeave:' + n.id}, {type:'sizedbox', width:4}, {type:'button', icon:'delete', variant:'outlined', onTap:'removeName:' + n.id} ]} ]);
  }) : [emptyNode('名单为空', '添加人员或批量导入', 'list', '去添加', 'goto:rollList')];
  return col([ card('添加人员', [ {type:'row', children:[ {type:'expanded', child:{type:'textfield', key:'rname', label:'姓名', value:rollDraft, onChanged:'setRollDraft'}}, {type:'sizedbox', width:8}, {type:'button', icon:'add', label:'添加', onTap:'addName'} ]}, gap(8), {type:'row', children:[ {type:'expanded', child:{type:'textfield', key:'rbulk', label:'批量输入（逗号或换行分隔）', onChanged:'setBulk'}}, {type:'sizedbox', width:8}, {type:'button', icon:'list', label:'批量加', onTap:'addBulk'} ]} ]), gap(12), card('名单（' + names.length + '）', [{type:'row', children:[ {type:'button', icon:'delete', variant:'outlined', label:'清空名单', onTap:'clearNames'}, {type:'sizedbox', width:6}, {type:'button', icon:'save', variant:'outlined', label:'导出', onTap:'exportNames'}, {type:'sizedbox', width:6}, {type:'button', icon:'add', variant:'outlined', label:'导入', onTap:'importNames'} ]}, gap(6), muted('点星标循环切换权重（1→2→3→1）')].concat(list)) ]);
}
function historyTab(){
  var history = getHistory(); var rollHistory = getRollHistory(); var counts = getCounts(); var prizes = getPrizes();
  var stats = prizes.filter(function(p){ return (counts[p.id]||0) > 0; });
  var maxC = stats.reduce(function(m, p){ return Math.max(m, counts[p.id]||0); }, 1);
  var statRows = stats.length ? stats.map(function(p){ var c = counts[p.id]||0; return {type:'column', crossAxisAlignment:'stretch', children:[ {type:'row', children:[body(p.name, null), {type:'spacer'}, body(c + ' 次', 'primary')]}, gap(2), {type:'progress', value: c/maxC, color:'primary'}, gap(5) ]}; }) : [muted('暂无中签数据')];
  var hRows = history.slice(0,15).map(function(h){ return {type:'row', children:[muted(h.time), {type:'sizedbox', width:8}, body(h.names.join('、'), null)]}; });
  var rRows = rollHistory.slice(0,15).map(function(h){ return {type:'row', children:[muted(h.time), {type:'sizedbox', width:8}, body(h.names.join('、'), null)]}; });
  return col([ {type:'button', icon:'save', variant:'outlined', label:'导出全部历史到剪贴板', onTap:'exportHistory', expanded:true}, gap(12), card('中签统计（共 ' + history.length + ' 次抽奖）', statRows), gap(12), card('抽奖历史（' + history.length + '）', [{type:'button', icon:'delete', variant:'outlined', label:'清空', onTap:'clearHistory'}, gap(8)].concat(hRows)), gap(12), card('点名历史（' + rollHistory.length + '）', [{type:'button', icon:'delete', variant:'outlined', label:'清空', onTap:'clearRollHistory'}, gap(8)].concat(rRows)) ]);
}
function schemeTab(){
  var schemes = getSchemes();
  var list = schemes.length ? schemes.map(function(s, i){ return card(null, [ {type:'row', children:[ body(s.name + '（' + s.prizes.length + '个奖品）', null), {type:'spacer'}, {type:'button', icon:'list', variant:'outlined', label:'加载', onTap:'loadScheme:' + i}, {type:'sizedbox', width:4}, {type:'button', icon:'delete', variant:'outlined', onTap:'delScheme:' + i} ]} ]); }) : [muted('还没有方案')];
  return col([
    card('数据与存储', [ muted('插件的奖品 / 名单 / 历史等数据存储在你指定的数据目录下'), gap(8), {type:'button', icon:'folder', variant:'outlined', label:'打开存储数据位置', onTap:'openDataDir', expanded:true} ]),
    gap(12),
    card('数据快照（全量导入导出）', [ {type:'button', icon:'save', variant:'tonal', label:'导出完整快照', onTap:'exportSnapshot', expanded:true}, gap(6), {type:'button', icon:'add', variant:'outlined', label:'从快照恢复', onTap:'importSnapshot', expanded:true}, gap(8), muted('快照包含奖品+名单+历史+设置，复制到剪贴板') ]),
    gap(12),
    card('奖品导入 / 导出', [ {type:'row', children:[ {type:'expanded', child:{type:'button', icon:'save', variant:'outlined', label:'导出 JSON', onTap:'exportJson'}}, {type:'sizedbox', width:6}, {type:'expanded', child:{type:'button', icon:'add', variant:'outlined', label:'导入 JSON', onTap:'importJson'}} ]} ]),
    gap(12),
    card('保存抽奖方案', [ {type:'row', children:[ {type:'expanded', child:{type:'textfield', key:'sn', label:'方案名', onChanged:'setSchemeName'}}, {type:'sizedbox', width:6}, {type:'button', icon:'save', label:'保存', onTap:'saveScheme'} ]}, gap(4), muted('保存当前奖品 + 名单 + 抽奖 / 点名设置') ]),
    gap(12),
    card('已存方案（' + schemes.length + '）', list)
  ]);
}

function col(children){ return {type:'column', crossAxisAlignment:'stretch', children: children}; }
function card(title, children){ var c = []; if (title) { c.push(h2(title)); c.push(gap(6)); } return {type:'card', padding:14, child:{type:'column', crossAxisAlignment:'stretch', children: c.concat(children)}}; }
function chip(text){ return {type:'card', padding:5, child: muted(text)}; }
function badge(text, color){ return {type:'badge', text: text, color: color || 'primary'}; }
function emptyNode(title, subtitle, icon, actionLabel, action){ return {type:'empty', title: title, subtitle: subtitle, icon: icon, actionLabel: actionLabel, action: action}; }

// ===== 严格格式模板（导入/导出规范，模板 tab 展示 + 一键复制） =====
var PRIZE_TEMPLATE = '[\n  {"name":"一等奖","weight":1,"maxCount":0,"tier":1},\n  {"name":"二等奖","weight":2,"maxCount":1,"tier":2}\n]';
var NAME_JSON_TEMPLATE = '[\n  {"name":"张三","weight":1},\n  {"name":"李四","weight":3}\n]';
var NAME_CSV_TEMPLATE = '张三,李四,王五\n赵六\n（可选表头：姓名,权重）';
var SNAPSHOT_TEMPLATE = '{\n  "content_type":"lottery_full_snapshot",\n  "prizes":[ ... ],\n  "names":[ ... ],\n  "history":[ ],\n  "rollHistory":[ ],\n  "settings":{\n    "strategy":"uniform","unique":false,"batch":1,\n    "rollStrategy":"uniform","rollUnique":true,"rollBatch":1\n  }\n}';

/// 大号毛玻璃结果框：滚动中翻滚大字，结束后大号显示中签者，空态给提示。
function resultCard(isRoll){
  var results = isRoll ? rollResults : lastResults;
  var label = isRoll ? '点名结果' : '抽奖结果';
  var kids;
  if (rolling && results.length) {
    kids = [gap(10), {type:'center', child: bigText(results[0], 36)}, gap(6), {type:'center', child: muted('滚动中…')}, gap(8)];
  } else if (results.length) {
    var multi = results.length > 1;
    kids = [gap(8)];
    results.forEach(function(n, i){ kids.push({type:'center', child: bigText((multi ? (i+1) + '. ' : '') + n, multi ? 24 : 34)}); });
    kids.push(gap(8));
  } else {
    kids = [gap(12), {type:'center', child: muted(isRoll ? '点击「开始点名」抽取' : '点击「开始抽奖」抽取')}, gap(12)];
  }
  return card(label, kids);
}

function codeBlock(t){ return {type:'card', padding:10, child: {type:'text', text:t, size:12}}; }
function fieldRow(k, v){ return {type:'row', crossAxisAlignment:'start', children:[ {type:'sizedbox', width:92, child:{type:'text', text:k, size:12, weight:'bold', color:'primary'}}, {type:'expanded', child:{type:'text', text:v, size:12}} ]}; }

function templateTab(){
  return col([
    card('奖品 JSON 格式（导入 / 导出）', [
      muted('字段：name 必填；weight / maxCount / tier 可选（默认 1 / 0 / 1）。id / exclude / must 导入时忽略并自动重置。'),
      gap(8), codeBlock(PRIZE_TEMPLATE), gap(8),
      {type:'button', icon:'save', variant:'outlined', label:'复制奖品模板到剪贴板', onTap:'copyPrizeTemplate', expanded:true}
    ]),
    gap(12),
    card('名单格式（导入 / 导出）', [
      muted('支持 JSON 数组、CSV、TXT（逗号 / 换行 / 分号分隔）。JSON 每项可带 weight。'),
      gap(8), h2('JSON'), gap(4), codeBlock(NAME_JSON_TEMPLATE),
      gap(6), h2('CSV / TXT'), gap(4), codeBlock(NAME_CSV_TEMPLATE), gap(8),
      {type:'button', icon:'save', variant:'outlined', label:'复制名单模板到剪贴板', onTap:'copyNameTemplate', expanded:true}
    ]),
    gap(12),
    card('完整快照（全量备份 / 恢复）', [
      muted('content_type 必须为 lottery_full_snapshot；含奖品 + 名单 + 历史 + 设置。建议从「方案」tab 一键导出/恢复，无需手写。'),
      gap(8), codeBlock(SNAPSHOT_TEMPLATE), gap(8),
      {type:'button', icon:'save', variant:'tonal', label:'复制完整快照模板到剪贴板', onTap:'copySnapshotTemplate', expanded:true}
    ]),
    gap(12),
    card('字段说明', [
      fieldRow('name', '名称（奖品名 / 姓名），必填'),
      fieldRow('weight', '权重，正整数，默认 1，越大越易中'),
      fieldRow('maxCount', '限中次数：0=无限，>0 抽满即移出奖池'),
      fieldRow('tier', '档位 1/2/3（一/二/三等奖），默认 1'),
      fieldRow('exclude', 'true=已排除不参与（导出含，导入忽略）'),
      fieldRow('must', 'true=必中（导出含，导入忽略）'),
      fieldRow('leave', 'true=请假（姓名，导出含，导入忽略）')
    ])
  ]);
}

function poolInfo(){ var counts = getCounts(), drawn = getDrawn(); return getPrizes().filter(function(p){ if (p.exclude) return false; if (p.maxCount > 0 && (counts[p.id]||0) >= p.maxCount) return false; if (getUnique() && drawn.indexOf(p.id) >= 0) return false; return true; }); }
function rollPool(){ var rd = getRollDrawn(); return getNames().filter(function(n){ return !n.leave && !(getRollUnique() && rd.indexOf(n.id) >= 0); }); }

function onAction(name, args){
  msg = ''; msgKind = 'info'; tierResults = {}; rollGroups = [];
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
    case 'spinDraw': spinDraw(); break;
    case 'spinRoll': spinRoll(); break;
    case 'undoDraw': undoDraw(); break;
    case '__key__': if (args && args.key === 'space') { if (tab === 'roll') spinRoll(); else spinDraw(); } break;
    case 'exportHistory': exportHistory(); break;
    case 'exportSnapshot': exportSnapshot(); break;
    case 'importSnapshot': importSnapshot(); break;
    case 'clearHistory': starhope.storage.set('history', []); break;
    case 'setSchemeName': schemeName = args.value; break;
    case 'saveScheme': saveScheme(); break;
    case 'exportJson': starhope.storage.set('__clip__', JSON.stringify(getPrizes())); notify('已导出 ' + getPrizes().length + ' 个奖品到剪贴板', 'success'); break;
    case 'importJson': importJson(); break;
    case 'openDataDir': starhope.openDataDir(); notify('已在系统文件管理器打开数据目录', 'info'); break;
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
    case 'exportNames': starhope.storage.set('__clip__', JSON.stringify(getNames().map(function(n){ return {name: n.name, weight: n.weight||1}; }))); notify('已导出 ' + getNames().length + ' 人到剪贴板', 'success'); break;
    case 'importNames': importNames(); break;
    case 'copyPrizeTemplate': starhope.storage.set('__clip__', PRIZE_TEMPLATE); notify('已复制奖品模板到剪贴板', 'success'); break;
    case 'copyNameTemplate': starhope.storage.set('__clip__', NAME_JSON_TEMPLATE); notify('已复制名单模板到剪贴板', 'success'); break;
    case 'copySnapshotTemplate': starhope.storage.set('__clip__', SNAPSHOT_TEMPLATE); notify('已复制完整快照模板到剪贴板', 'success'); break;
  }
}

function addPrize(){ var n = (draft.name || '').trim(); if (!n) { notify('奖品名不能为空', 'error'); return; } var p = getPrizes(); p.push({id: uid(), name: n, weight: parseInt(draft.weight)||1, maxCount: parseInt(draft.maxCount)||0, exclude: false, must: false, tier: parseInt(draft.tier)||1}); savePrizes(p); draft.name = ''; draft.weight = '1'; draft.maxCount = '0'; draft.tier = '1'; }
function togglePrize(id, field){ savePrizes(getPrizes().map(function(x){ if (x.id === id) { var o = {}; o[field] = !x[field]; return assign(x, o); } return x; })); }
function saveScheme(){ if (!schemeName) { notify('请输入方案名', 'error'); return; } var s = getSchemes(); s.push({name: schemeName, prizes: getPrizes().map(function(p){ return assign(p, {}); }), names: getNames().map(function(n){ return assign(n, {}); }), strategy: getStrategy(), unique: getUnique(), batch: getBatch(), rollStrategy: getRollStrategy(), rollUnique: getRollUnique(), rollBatch: getRollBatch()}); starhope.storage.set('schemes', s); schemeName = ''; notify('方案已保存', 'success'); }
function loadScheme(i){ var s = getSchemes(); if (i<0||i>=s.length) return; var x = s[i]; savePrizes(x.prizes.map(function(p){ return assign(p, {}); })); if (x.names) saveNames(x.names.map(function(n){ return assign(n, {}); })); starhope.storage.set('strategy', x.strategy||'uniform'); starhope.storage.set('unique', x.unique===true); starhope.storage.set('batch', x.batch||1); if (x.rollStrategy) starhope.storage.set('rollStrategy', x.rollStrategy); if (x.rollUnique !== undefined) starhope.storage.set('rollUnique', x.rollUnique); if (x.rollBatch) starhope.storage.set('rollBatch', x.rollBatch); starhope.storage.set('drawn', []); starhope.storage.set('counts', {}); starhope.storage.set('rollDrawn', []); notify('已加载方案「' + x.name + '」', 'success'); }
function importJson(){ var raw = starhope.storage.get('__clip__'); if (!raw) { notify('剪贴板为空', 'error'); return; } try { var arr = JSON.parse(raw); if (!arr || arr.length === undefined) throw 'x'; var p = getPrizes(); arr.forEach(function(x){ p.push({id: uid(), name: x.name||'?', weight: parseInt(x.weight)||1, maxCount: parseInt(x.maxCount)||0, exclude: false, must: false, tier: parseInt(x.tier)||1}); }); savePrizes(p); notify('已导入 ' + arr.length + ' 个奖品', 'success'); } catch(e) { notify('导入失败：非有效 JSON 数组', 'error'); } }
function drawN(pool, n, strategy){ var avail = pool.slice(), winners = []; for (var i = 0; i < n && avail.length; i++) { var idx; if (strategy === 'weighted') { var total = avail.reduce(function(a, p){ return a + (parseInt(p.weight)||1); }, 0); var r = Math.random() * total, acc = 0; idx = avail.length - 1; for (var j = 0; j < avail.length; j++) { acc += (parseInt(avail[j].weight)||1); if (r < acc) { idx = j; break; } } } else { idx = Math.floor(Math.random() * avail.length); } winners.push(avail[idx]); avail.splice(idx, 1); } return winners; }
function recordWinners(winners){ var h = getHistory(); h.unshift({time: nowStr(), names: winners.map(function(p){ return p.name; })}); if (h.length > 100) h = h.slice(0, 100); starhope.storage.set('history', h); var counts = getCounts(), drawn = getDrawn(); winners.forEach(function(p){ counts[p.id] = (counts[p.id]||0) + 1; if (getUnique()) drawn.push(p.id); }); starhope.storage.set('counts', counts); starhope.storage.set('drawn', drawn); }
function spinDraw(){
  var pool = poolInfo();
  if (!pool.length) { notify('奖池为空', 'error'); starhope.rerender(); return; }
  rolling = true;
  var spins = 0, maxSpins = 10;
  function step(){ if (spins < maxSpins) { lastResults = [pool[Math.floor(Math.random()*pool.length)].name]; starhope.rerender(); spins++; setTimeout(step, 70 + spins * 20); } else { rolling = false; draw(); starhope.rerender(); } }
  step();
}
function spinRoll(){
  var pool = rollPool();
  if (!pool.length) { notify('可点名单为空', 'error'); rollResults = []; starhope.rerender(); return; }
  rolling = true;
  var spins = 0, maxSpins = 10;
  function step(){ if (spins < maxSpins) { rollResults = [pool[Math.floor(Math.random()*pool.length)].name]; starhope.rerender(); spins++; setTimeout(step, 70 + spins * 20); } else { rolling = false; rollCall(); starhope.rerender(); } }
  step();
}
function draw(){ var pool = poolInfo(); if (!pool.length) { notify('奖池为空', 'error'); return; } var must = pool.filter(function(p){ return p.must; }); var rest = pool.filter(function(p){ return !p.must; }); var batch = Math.min(getBatch(), pool.length); var winners = must.slice(0, batch); var need = batch - winners.length; winners = winners.concat(drawN(rest, need, getStrategy())); lastResults = winners.map(function(p){ return p.name; }); recordWinners(winners); lastDrawIds = winners.map(function(p){ return p.id; }); }
function drawTiered(){ lastDrawIds = []; var counts = getCounts(), drawn = getDrawn(); var all = getPrizes(); tierResults = {}; var any = false; [1,2,3].forEach(function(t){ var tpool = all.filter(function(p){ return (p.tier||1) === t && !p.exclude && !(p.maxCount > 0 && (counts[p.id]||0) >= p.maxCount) && !(getUnique() && drawn.indexOf(p.id) >= 0); }); if (tpool.length) { var winners = drawN(tpool, Math.min(getBatch(), tpool.length), getStrategy()); tierResults[t] = winners.map(function(p){ return p.name; }); recordWinners(winners); winners.forEach(function(p){ lastDrawIds.push(p.id); }); any = true; } }); if (!any) { notify('无可抽取的档位奖品', 'error'); } }

function addName(){ var n = (rollDraft || '').trim(); if (!n) { notify('姓名不能为空', 'error'); return; } var names = getNames(); names.push({id: uid(), name: n, leave: false, weight: 1}); saveNames(names); rollDraft = ''; }
function addBulk(){ var parts = (bulkDraft || '').split(/[，,\n]/).map(function(s){ return s.trim(); }).filter(function(s){ return s; }); if (!parts.length) { notify('批量输入为空', 'error'); return; } var names = getNames(); parts.forEach(function(s){ names.push({id: uid(), name: s, leave: false, weight: 1}); }); saveNames(names); bulkDraft = ''; notify('已批量添加 ' + parts.length + ' 人', 'success'); }
function importNames(){ var raw = starhope.storage.get('__clip__'); if (!raw) { notify('剪贴板为空', 'error'); return; } raw = raw.trim(); var names = getNames(); var added = 0; try { var arr = JSON.parse(raw); if (arr) { (arr.length !== undefined ? arr : [arr]).forEach(function(s){ names.push({id: uid(), name: typeof s === 'string' ? s : (s.name||s['姓名']||'?'), leave: false, weight: typeof s === 'object' ? (parseInt(s.weight)||parseInt(s['权重'])||1) : 1}); added++; }); } } catch(e) { var parts = raw.split(/[，,\n\t;；]/).map(function(s){ return s.trim(); }).filter(function(s){ return s; }); parts.forEach(function(s){ names.push({id: uid(), name: s, leave: false, weight: 1}); added++; }); } saveNames(names); notify('已导入 ' + added + ' 人', 'success'); }
function undoDraw(){
  if (!lastDrawIds.length) { notify('没有可撤销的抽奖', 'error'); return; }
  var counts = getCounts(), drawn = getDrawn();
  lastDrawIds.forEach(function(id){ if ((counts[id]||0) > 0) counts[id]--; var di = drawn.indexOf(id); if (di >= 0) drawn.splice(di, 1); });
  starhope.storage.set('counts', counts); starhope.storage.set('drawn', drawn);
  var h = getHistory(); if (h.length) h.shift(); starhope.storage.set('history', h);
  lastDrawIds = []; lastResults = []; tierResults = {}; notify('已撤销上次抽奖', 'success');
}
function exportHistory(){ var h = getHistory(), rh = getRollHistory(); var lines = ['抽奖历史：']; h.forEach(function(x){ lines.push(x.time + '  ' + x.names.join('、')); }); lines.push('', '点名历史：'); rh.forEach(function(x){ lines.push(x.time + '  ' + x.names.join('、')); }); starhope.storage.set('__clip__', lines.join('\n')); notify('已导出历史 ' + (h.length + rh.length) + ' 条到剪贴板', 'success'); }
function exportSnapshot(){
  var payload = {
    content_type: 'lottery_full_snapshot',
    exported_at: nowStr(),
    prizes: getPrizes(),
    names: getNames(),
    history: getHistory(),
    rollHistory: getRollHistory(),
    settings: { strategy: getStrategy(), unique: getUnique(), batch: getBatch(), rollStrategy: getRollStrategy(), rollUnique: getRollUnique(), rollBatch: getRollBatch() }
  };
  starhope.storage.set('__clip__', JSON.stringify(payload));
  notify('已导出完整快照（奖品 ' + getPrizes().length + ' + 名单 ' + getNames().length + ' + 历史 + 设置）', 'success');
}
function importSnapshot(){
  var raw = starhope.storage.get('__clip__'); if (!raw) { notify('剪贴板为空', 'error'); return; }
  try {
    var data = JSON.parse(raw);
    if (data.content_type !== 'lottery_full_snapshot') { notify('非抽奖快照格式', 'error'); return; }
    if (data.prizes) savePrizes(data.prizes.map(function(p){ return assign(p, {}); }));
    if (data.names) saveNames(data.names.map(function(n){ return assign(n, {}); }));
    if (data.history) starhope.storage.set('history', data.history);
    if (data.rollHistory) starhope.storage.set('rollHistory', data.rollHistory);
    if (data.settings) {
      if (data.settings.strategy) starhope.storage.set('strategy', data.settings.strategy);
      starhope.storage.set('unique', data.settings.unique === true);
      if (data.settings.batch) starhope.storage.set('batch', data.settings.batch);
    }
    starhope.storage.set('drawn', []); starhope.storage.set('counts', {}); starhope.storage.set('rollDrawn', []);
    notify('已恢复完整快照', 'success');
  } catch(e) { notify('恢复失败：非有效快照', 'error'); }
}
function rollCall(){ var pool = rollPool(); if (!pool.length) { notify('可点名单为空', 'error'); rollResults = []; return; } var batch = Math.min(getRollBatch(), pool.length); var winners = drawN(pool, batch, getRollStrategy()); rollResults = winners.map(function(n){ return n.name; }); var h = getRollHistory(); h.unshift({time: nowStr(), names: rollResults.slice()}); if (h.length > 100) h = h.slice(0, 100); starhope.storage.set('rollHistory', h); if (getRollUnique()) { var rd = getRollDrawn(); winners.forEach(function(n){ rd.push(n.id); }); starhope.storage.set('rollDrawn', rd); } }
function rollGroup(){ var pool = getNames().filter(function(n){ return !n.leave; }); if (!pool.length) { notify('名单为空', 'error'); rollGroups = []; return; } var gn = S('rollGroupCount', 2); if (gn < 1) gn = 1; var shuffled = pool.slice(); for (var i = shuffled.length - 1; i > 0; i--) { var j = Math.floor(Math.random() * (i + 1)); var tmp = shuffled[i]; shuffled[i] = shuffled[j]; shuffled[j] = tmp; } rollGroups = []; for (var k = 0; k < gn; k++) rollGroups.push([]); shuffled.forEach(function(n, idx){ rollGroups[idx % gn].push(n.name); }); }
