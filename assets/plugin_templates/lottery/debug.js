// node debug v5：抽奖(含多档) + 点名 全量测试
var storage = {};
var starhope = { storage: { get: function(k){ return storage[k]; }, set: function(k, v){ storage[k] = v; } }, log: function(){}, random: function(m){ return Math.floor(Math.random() * m); } };
var sendMessage = function(){};
var fs = require('fs');
var main = fs.readFileSync(__dirname + '/main.js', 'utf8');
var errs = [];
function ok(c, l){ if (c) { console.log('  ok ' + l); } else { console.log('  FAIL ' + l); errs.push(l); } }
var test = '\ntry {\n\
  ok(typeof render === "function", "render");\n\
  ok(typeof drawTiered === "function", "drawTiered");\n\
  ok(render().type === "column", "render column");\n\
  // 多档：一等A B、二等C D、三等E\n\
  [["一等奖A","1"],["一等奖B","1"]].forEach(function(x){ onAction("setName",{value:x[0]}); onAction("setTier",{value:"1"}); onAction("add"); });\n\
  [["二等奖C","2"],["二等奖D","2"]].forEach(function(x){ onAction("setName",{value:x[0]}); onAction("setTier",{value:x[1]}); onAction("add"); });\n\
  onAction("setName",{value:"三等奖E"}); onAction("setTier",{value:"3"}); onAction("add");\n\
  ok(getPrizes().length === 5, "5 prizes");\n\
  ok(getPrizes().filter(function(p){return p.tier===1;}).length === 2, "tier1 x2");\n\
  ok(getPrizes().filter(function(p){return p.tier===2;}).length === 2, "tier2 x2");\n\
  ok(getPrizes().filter(function(p){return p.tier===3;}).length === 1, "tier3 x1");\n\
  onAction("goto:draw",{});\n\
  onAction("setBatch",{value:"1"});\n\
  onAction("drawTiered",{});\n\
  ok((tierResults[1] && tierResults[1].length === 1), "tier1 draw 1");\n\
  ok((tierResults[2] && tierResults[2].length === 1), "tier2 draw 1");\n\
  ok((tierResults[3] && tierResults[3].length === 1), "tier3 draw 1");\n\
  ok(tierResults[1][0].indexOf("一等奖") === 0, "tier1 winner correct");\n\
  ok(tierResults[2][0].indexOf("二等奖") === 0, "tier2 winner correct");\n\
  ok(tierResults[3][0] === "三等奖E", "tier3 winner correct");\n\
  // 普通抽奖仍工作\n\
  onAction("setBatch",{value:"2"});\n\
  onAction("draw",{});\n\
  ok(lastResults.length === 2, "normal draw 2");\n\
  // 不重复多档\n\
  onAction("setUnique",{value:true});\n\
  onAction("resetDrawn",{});\n\
  onAction("drawTiered",{});\n\
  onAction("drawTiered",{});\n\
  ok(getDrawn().length >= 5, "unique tiered accumulates");\n\
  onAction("setUnique",{value:false});\n\
  // 点名\n\
  onAction("goto:rollList",{});\n\
  ["张三","李四","王五"].forEach(function(nm){ onAction("setRollDraft",{value:nm}); onAction("addName",{}); });\n\
  ok(getNames().length === 3, "roll 3 names");\n\
  onAction("goto:roll",{});\n\
  onAction("setRollBatch",{value:"2"});\n\
  onAction("rollCall",{});\n\
  ok(rollResults.length === 2, "roll 2");\n\
  ok(getRollHistory().length >= 1, "roll history");\n\
  // 方案/导入导出\n\
  onAction("setSchemeName",{value:"S"}); onAction("saveScheme",{});\n\
  ok(getSchemes().length === 1, "scheme save");\n\
  onAction("exportJson",{});\n\
  ok(!!starhope.storage.get("__clip__"), "export");\n\
  onAction("clearPrizes",{});\n\
  onAction("importJson",{});\n\
  ok(getPrizes().length === 5, "import 5");\n\
  // tabs\n\
  ["draw","prizes","roll","rollList","history","scheme"].forEach(function(t){ onAction("goto:"+t,{}); ok(!!render(), t+" tab render"); });\n\
  console.log("\\n=== " + (errs.length===0 ? "ALL PASSED ("+errs.length+")" : (errs.length+" FAILED: "+errs.join("; "))) + " ===");\n\
} catch (e) { console.log("EXCEPTION: " + e + (e.stack?"\\n"+e.stack:"")); errs.push("ex"); }\n';
eval(main + test);
process.exit(errs.length > 0 ? 1 : 0);
