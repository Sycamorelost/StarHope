// node debug v18：抽奖(多档) + 点名(加权/分组) + 文件导入导出 + 模板剪贴板 全量测试
var storage = {};
var starhope = { storage: { get: function(k){ return storage[k]; }, set: function(k, v){ storage[k] = v; } }, log: function(){}, random: function(m){ return Math.floor(Math.random() * m); }, rerender: function(){}, openDataDir: function(){}, saveText: function(f, t){ storage._lastSave = t; if (typeof onSaved === 'function') onSaved(true); }, pickTextFile: function(){ if (typeof onImportFile === 'function') onImportFile('[{"name":"导入奖品A"}]'); }, clipboard: { setText: function(t){ storage._clip = t; } } };
var sendMessage = function(){};
var fs = require('fs');
var main = fs.readFileSync(__dirname + '/main.js', 'utf8');
var errs = [];
function ok(c, l){ if (c) console.log('  ok ' + l); else { console.log('  FAIL ' + l); errs.push(l); } }
var test = '\ntry {\n\
  ok(typeof render === "function", "render");\n\
  ok(typeof rollGroup === "function", "rollGroup");\n\
  ok(render().type === "scroll" && render().child.type === "column", "render scroll+column");\n\
  // 抽奖多档\n\
  [["一等奖A","1"],["一等奖B","1"]].forEach(function(x){ onAction("setName",{value:x[0]}); onAction("setTier",{value:x[1]}); onAction("add"); });\n\
  onAction("setName",{value:"二等奖C"}); onAction("setTier",{value:"2"}); onAction("add");\n\
  onAction("goto:draw",{}); onAction("setBatch",{value:"1"}); onAction("drawTiered",{});\n\
  ok(tierResults[1] && tierResults[1].length === 1, "tier1");\n\
  ok(tierResults[2] && tierResults[2].length === 1, "tier2");\n\
  // 点名加权\n\
  onAction("goto:rollList",{});\n\
  ["甲","乙","丙","丁","戊","己"].forEach(function(nm){ onAction("setRollDraft",{value:nm}); onAction("addName",{}); });\n\
  ok(getNames().length === 6, "6 names");\n\
  // 设甲权重 3\n\
  onAction("cycWeight:" + getNames()[0].id, {});\n\
  onAction("cycWeight:" + getNames()[0].id, {});\n\
  ok(parseInt(getNames()[0].weight) === 3, "weight cyc to 3");\n\
  // 加权点名\n\
  onAction("goto:roll",{});\n\
  onAction("setRollStrategy",{value:"weighted"});\n\
  onAction("setRollBatch",{value:"1"});\n\
  onAction("rollCall",{});\n\
  ok(rollResults.length === 1, "weighted roll 1");\n\
  // 分组\n\
  onAction("setGroupCount",{value:"3"});\n\
  onAction("rollGroup",{});\n\
  ok(rollGroups.length === 3, "3 groups");\n\
  var total = rollGroups.reduce(function(a,g){ return a + g.length; }, 0);\n\
  ok(total === 6, "all 6 in groups");\n\
  // 普通点名\n\
  onAction("setRollStrategy",{value:"uniform"});\n\
  onAction("setRollBatch",{value:"2"});\n\
  onAction("rollCall",{});\n\
  ok(rollResults.length === 2, "uniform roll 2");\n\
  // 请假\n\
  var nid = getNames()[1].id;\n\
  onAction("toggleLeave:" + nid, {});\n\
  ok(getNames()[1].leave === true, "leave");\n\
  // 统计\n\
  onAction("goto:history",{});\n\
  ok(!!render(), "history stats render");\n\
  // 历史单个/批量操作 + 统计单个清零\n\
  ok(getHistory().length >= 1 && getHistory()[0].id, "history entry has id");\n\
  var hid = getHistory()[0].id; onAction("histDel:draw:" + hid, {}); ok(!getHistory().some(function(h){return h.id===hid;}), "del single history");\n\
  var spid = ""; var cs = getCounts(); for (var kk in cs) { if (cs[kk] > 0) { spid = kk; break; } }\n\
  if (spid) { onAction("resetCount:" + spid, {}); ok(getCounts()[spid] === 0, "reset single count"); }\n\
  onAction("histMode:draw", {}); ok(drawHistMode === true, "enter select mode");\n\
  onAction("histAll:draw", {}); ok(Object.keys(drawHistSel).length > 0, "select all");\n\
  onAction("histDelSel:draw", {}); ok(getHistory().length === 0, "batch delete selected");\n\
  ok(Object.keys(drawHistSel).length === 0, "selection cleared after delete");\n\
  onAction("histMode:draw", {}); ok(drawHistMode === false, "exit select mode");\n\
  // tabs\n\
  ["draw","prizes","roll","rollList","history","scheme","template"].forEach(function(t){ onAction("goto:"+t,{}); ok(!!render(), t+" render"); });\n\
  onAction("goto:template",{}); onAction("copyPrizeTemplate",{}); ok(!!storage._clip, "copy template to clipboard");\n\
  onAction("goto:scheme",{}); onAction("exportJson",{}); ok(!!storage._lastSave && storage._lastSave.indexOf("一等奖A")>=0, "export to file");\n\
  onAction("importJson",{}); ok(getPrizes().some(function(p){return p.name==="导入奖品A";}), "import from file");\n\
  onAction("openDataDir",{}); ok(typeof starhope.openDataDir === "function", "openDataDir");\n\
  console.log("\\n=== " + (errs.length===0 ? "ALL PASSED" : (errs.length+" FAILED: "+errs.join("; "))) + " ===");\n\
} catch (e) { console.log("EXCEPTION: " + e + (e.stack?"\\n"+e.stack:"")); errs.push("ex"); }\n';
eval(main + test);
process.exit(errs.length > 0 ? 1 : 0);
