# StarHope 开发进度快照（state.md）

> 本文件供新会话读取后立即接续开发。最后更新时间对应会话结束点。
> 项目根目录：`d:\MyProject\Deep-tutor\REF\SH`（已纳入 Deep-tutor monorepo 的 `REF/SH` 子目录；Windows 10 Home China / Flutter 3.44.7 / Dart 3.12.2）。
> StarHope（Flutter 桌面）与 Deep-tutor（Web，backend/frontend/extension）是两个独立技术栈项目；StarHope 作为参考纳入 monorepo，未来计划通过 API 与 Deep-tutor 后端集成。

---

## 一、项目概述
StarHope 是一款**本地优先、离线可用**的跨平台学习助手桌面应用（当前为 Windows 桌面版），三层架构（核心/服务/视图），状态管理 Provider，数据库 sqflite_common_ffi。已能成功构建并运行：`build/windows/x64/runner/Release/starhope.exe`（约 34MB；加 pdfrx/PDFium 后含 `pdfium.dll` ~7MB）。

六大模块均已实现：①用户系统 ②题库管理 ③练习与考试 ④AI 助手 ⑤阅读器+批注 ⑥导出与防伪分享。

## 二、如何构建（⚠️ 必读：6 个必须维持的绕过，否则必失败）

环境已装好：Flutter SDK 在 `D:\MyProject\flutter_sdk\flutter`（已加入用户 PATH）；Git、VS 2022 BuildTools + VC.Tools 已装；中国镜像 `PUB_HOSTED_URL=https://pub.flutter-io.cn`、`FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn` 已持久化到用户环境变量。

构建命令（在 bash 中，flutter 不在 PATH 时手动加）：
```bash
cd "d:/MyProject/Deep-tutor/REF/SH"
export PATH="$PATH:/d/MyProject/flutter_sdk/flutter/bin:/c/Program Files/Git/cmd"
export PUB_HOSTED_URL="https://pub.flutter-io.cn"
export FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"
flutter build windows
```

**必须维持的绕过（详见 `C:\Users\14254\.claude\projects\d--MyProject-SH\memory\starhope-build-workarounds.md`）：**

1. **插件符号链接（未开 Developer Mode）**：已 patch Flutter SDK `packages/flutter_tools/lib/src/flutter_plugins.dart`——`_createPlatformPluginSymlinks` 在符号链接失败时回退到 `_copyDirectory` 拷贝；`refreshPluginsList` 中 `createPluginSymlinks(project, force: true)` 已改为 `force: false`。patch 后必须删除 `flutter/bin/cache/flutter_tools.snapshot` 强制重编译（已删）。**若 `windows/flutter/ephemeral/.plugin_symlinks/` 被清空**，需从 `C:/Users/14254/AppData/Local/Pub/Cache/hosted/pub.flutter-io.cn/` 拷贝各插件版本目录（`flutter_secure_storage_windows-3.1.2`、`sqlite3_flutter_libs-0.5.42`、`jni-1.0.0`、`pdfrx-2.4.5` 等，去掉版本号后缀）。此 patch 同时覆盖 pdfrx 的 Developer Mode 符号链接需求，实测 pdfrx 无需开 Developer Mode。

2. **sqlite3 native-assets 钩子（中国无法访问 github）**：`sqlite3` 默认从 github 下载预编译 DLL。已在 `pubspec.yaml` 配置 `hooks: user_defines: sqlite3: source: system` 跳过下载，运行时由 `sqlite3_flutter_libs`（CMake 源码编译）提供 sqlite3.dll。**注意**：`flutter test` 仍会触发该钩子（中国失败），纯 Dart 测试需用独立临时项目验证。

3. **flutter_secure_storage_windows 依赖 ATL（VS BuildTools 无 ATL 组件且安装失败）**：已 patch 其 C++ 源码（同时 patch pub 缓存源与 `.plugin_symlinks` 副本）：移除 `#include <atlstr.h>`，改用 Win32 `MultiByteToWideChar`/`WideCharToMultiByte`，`cred.TargetName` 处加 `const_cast<LPWSTR>`，并加 `#include <string>`。若 pub get 重新拷贝覆盖，需重新打此补丁。

4. **C++ 源码禁含中文字符**：MSVC 在 GBK(936) 系统下对 runner 的中文注释报 C4819（警告视为错误）。`windows/runner/*.cpp` 中所有注释须为英文 ASCII。

5. **无边框圆角窗口**：`windows/runner/win32_window.cpp` 已改为 `WS_POPUP|WS_THICKFRAME|WS_MINIMIZEBOX|WS_MAXIMIZEBOX|WS_SYSMENU`，加 `WM_NCCALCSIZE`（return 0，全客户区）与 `WM_NCHITTEST`（手动 6px 调整大小边），`ApplyRoundedCorners`（SetWindowRgn 圆角）保留。Flutter 侧 `app.dart` 的 MaterialApp `builder` 全局 `ClipRRect(radius:10)` 让圆角抗锯齿融合。

6. **pdfrx + PDFium（PDF 原生渲染）**：`pubspec.yaml` 加 `pdfrx: ^2.4.4`（解析到 2.4.5，连带 `pdfium_dart 0.2.5`/`pdfium_flutter 0.2.3`/`pdfrx_engine 0.4.4`）。PDFium binary 由 native-assets 钩子在构建时下载——**中国网络实测自动下载成功**（`pdfium.dll` ~7MB 落 `build/windows/x64/runner/Release/`，经 flutter-io.cn 镜像覆盖），无需手动绕过；Developer Mode 需求由绕过 1 patch 覆盖。**若他人环境下载失败**：手动下 [bblanchon/pdfium-binaries](https://github.com/bblanchon/pdfium-binaries/releases) 的 `pdfium-win-x64.tgz`（release `chromium%2F<N>`，`<N>` 以 build CMake 报错路径为准），解压 `bin/pdfium.dll`/`lib/pdfium.dll.lib`/`include/fpdf*.h` 放到 `build/windows/x64/pdfium/chromium%2F<N>/`。注意 [flutter#165463](https://github.com/flutter/flutter/issues/165463) 有时 dll 不自动进 runner/，需手拷。

## 三、当前完成状态（已编译、已运行验证）

- ✅ 全屏切换：F11 全局快捷键（`app.dart` KeyboardListener）+ 标题栏全屏按钮（`WindowService.toggleFullscreen`，win32 真全屏置顶）。
- ✅ 阅读器支持主流文档：pdf/docx/pptx/xlsx/html/txt/md/csv/epub/odt/odp/ods/rtf/log（`reader_viewer_page.dart` 的 `_extractText`，zip+xml 文本提取）。**PDF 已接入 pdfrx 原生逐页渲染**（PdfViewer 连续滚动+缩放），不再是占位。
- ✅ **PDF 原生渲染 + 绘图笔记坐标系重构（待办3 完成）**：`reader_viewer_page.dart` 分叉，PDF 走 `PdfViewer.file`（内置 pan/scale），文本路径不变；绘图笔画存 PDF user-space 坐标（`pageOverlaysBuilder` 线性映射，随缩放对齐），`_drawMode` 切换两套 `PdfViewerParams` 解手势冲突；新格式 `{version:2,cs:pdf,page,strokes}`，旧占位笔画一次性对话框清除。
- ✅ 数据存储到用户指定位置：`StorageConfig`（引导配置在 app support dir，数据根可改）；设置页"数据存储位置"项，复制数据后重启生效。
- ✅ 无边框圆角窗口 + 自定义标题栏（`WindowTitleBar`，拖动/最小化/最大化/全屏/关闭，win32 FFI `window_service.dart`）。
- ✅ **登录页布局重构（待办1 完成）**：整页星空背景（`StarrySky`）+ 左右两个等高毛玻璃面板并排——左侧**银河流行动画**（`galaxy_view.dart`，银河带+密集星点+沿带流光），右侧登录卡（头像→昵称→@账号→密码→登录，账号只读展示，`GlassCard.surfaceColor` 实色提升对比）。已注册用户由 `AuthService.storedUser()`/`AuthProvider.registeredUser` 暴露。
- ✅ StarryButton 灵动按钮（`starry_button.dart`）：悬停时星空环绕高亮+缩放。
- ✅ 设置底部赞赏栏（`_donateBar`，跳转 `https://ifdian.net/a/ilovesl`）。
- ✅ 免责声明（`disclaimer.dart` 的 `kDisclaimer` + `showDisclaimerDialog`，署名「梧桐吾桐」）。
- ✅ 全局防伪标识：`AppConstants.poweredBy = '© Developed and powered by SycamoreLost'`。
- ✅ 用户头像：可从本地选择（≤2MB，`FileStorageService.saveAvatar` 校验）。
- ✅ 错题本为侧边栏顶级菜单（`wrong_book_page.dart`，含按题型/标签/来源分类筛选）。
- ✅ AI 默认空配置；系统提示词 + 文档格式转换能力。
- ✅ **性能优化（待办2 完成）**：`StarrySky` 星点坐标/流星起点按尺寸预生成缓存 + 复用 Paint（消除每帧 `new Random`+坐标重算）；`_AuraPainter` 删除未用的 `Random(7)` 死代码；列表（题库/错题/AI/练习/阅读）主列表已全部 `ListView.builder`。
- ✅ **PDF 绘图撤销/删除同步**：`addNote` 返回 id 关联笔画，撤销/清空/侧栏删除均同步 DB Note。
- ✅ **回车键开关 + 登录跳转加载动画**：设置「回车键发送/确认」开关（控制 AI 回车发送）；`_PostLoginLoader` 加载动画（星空背景 + 脉冲品牌 + 进度）。
- ✅ **登录回车自动 + 模板框调大 + 深色对比度修复**：登录密码框回车始终登录；导入模板对话框 780×640；深色主题 `onSurfaceVariant` 提亮 + FrostedBackground 光斑降透明 + 全项目 12 处 `Colors.grey` → `onSurfaceVariant`。
- ✅ **全项目 lint 清零**：`flutter analyze` 88 → 0 issues（删未用 import/dead code、wildcard→具名、async 加 mounted、补 const、显式 ffi 依赖）。

### 本次完成（阅读器涂鸦翻页跟随 + 选区高亮 + 侧栏跳转，待办 6 落地）

- ✅ **文本路径绘图按页分组**：`_strokes`（平铺）→ `_textStrokesByPage`（Map<int,List<_Stroke>>），`_DrawingPainter` 仅渲染当前页笔画；翻页后笔画随页消失、回到该页重现（原为屏幕绝对坐标平铺、不随页走）。`_loadTextStrokes`/`_saveTextStroke`/`_undo`/`_clearDrawing`/`_deleteNote` 全部改为按页操作。
- ✅ **PDF 文本选区高亮**：非绘图模式 `PdfViewerParams` 开 `textSelectionParams` + `customizeContextMenuItems`（选中文本右键追加"高亮"项）；选中范围经 `getSelectedTextRanges()` 取每字符 `PdfRect`（PDF 坐标系，原点左下 Y 向上）存入 Note payload `{page,rects:[{l,t,r,b}]}`；`pageOverlaysBuilder` 额外加 `_pdfHighlightOverlay`（IgnorePointer + `_PdfHighlightPainter`），按 `page.rotation` 旋转 + Y 翻转映射到叠加层，逐页黄色半透明（`Color(0x55FFC107)`）渲染，翻页跟随。
- ✅ **文本路径高亮笔记**：`SelectionArea.onSelectionChanged` 捕获 `SelectedContent.plainText`（Flutter 文本选区无字符偏移，无法做黄底），工具栏"高亮所选"存为 `NoteType.highlight`（payload 无 rects），侧栏可见 + 点击跳转。
- ✅ **侧栏卡片点击跳转**：`_noteTile` 整卡 `InkWell` + 页头"第 N 页"统一走 `_jumpToPage(page)`（PDF 用 `PdfViewerController.goToPage`，文本用 `PageController.jumpToPage`）。
- ✅ **验证**：`flutter analyze` 0 issues；`flutter build windows` 通过（65.8s）；`timeout 8 ./starhope.exe` 退出码 124（启动正常）。无 schema 变更、无新依赖。托盘（待办 7）按用户决定不做。

### 本次完成（练习/考试/题库大改 + 双格式导入导出 + 全局优化，db v6→v7）

> 分 6 阶段落地，每阶段 analyze+build+timeout8 验证 + 细粒度 commit。共 0 新依赖。

- ✅ **阶段0 DRY**：抽 `widgets/answer_widgets.dart`（QTypeChip/OptionTile/AnswerInput/displayAnswer，选项经 Markdown 渲染支持图片，文本框自管 controller 避免光标跳动）、`answer_card_dialog.dart`（showAnswerCardDialog+EssayScoring，surveyking 式答题卡，练习只读/考试带主观题评分）、`question_picker.dart`（pickQuestionsDialog）；practice/exam 页删除重复方法改用之。
- ✅ **阶段1 v7 迁移**：`practice_sessions +mode`、`questions +practice_count/correct_count/last_practiced_at`、`exam_rules +type_quotas_json/pass_rate`、`exam_results +passed`；`recordCorrect/Wrong` 经 `_bumpQuestionStats` 注入统计；`deleteExamResult`。
- ✅ **阶段2 题库增强**：修复 `wrongFirst`（pickQuestions 读错题表按错次优先，原空转）；`QuestionSortBy`（更新/创建/难度/正确率/最近练习）排序 + "仅薄弱(<60%)"筛选；QuestionTile 显示练次/正确率/最近；题目图片（`markdownImageBuilder` 支持 data:base64 与 file://，编辑器"插入图片"）；手动出处字段。
- ✅ **阶段3 练习增强**：判题模式 SegmentedButton（边练边判/集中判题）+ 自定义选题（pickQuestionsDialog）；集中判题仿考试布局（答题卡导航+上下题+不显对错）→ `finishBatchPractice` 统一判分；单题计时传真实 usedSeconds；`resumePractice` 继续未完成（batch 恢复未提交答案）；完成统计页（总用时+各题型正确率柱条+错题重练）；历史卡 继续/答题卡/导出/删除。
- ✅ **阶段4 考试增强**：`ExamRule.typeQuotas` 题型配额抽题（`pickByQuotas`）+ `effectiveCount` 驱动 totalScore；及格线 `passRate`（编辑弹窗滑块，_autoSubmit/gradeExam 算 passed，成绩单 通过/未通过/待评 徽章）；编辑弹窗题型/标签/关键字/题库夹直接编辑 filter（不再隐式继承题库页）；完成弹窗各题型正确率+"重练错题"；成绩单卡 Popup（答题卡/导出/删除）。
- ✅ **阶段5 严格格式 + 双格式记录导出 + 错题同步**：`QuestionSerializer`（toMarkdown/toCsv/toHtml，与 QuestionImportService 规范严格对应可回导）；`ShareContentType +practiceRecord/examResultRecord`；ExportService 练习/考试记录 starhope 导出导入（id 重映射+来源标记）+ Markdown 可读报告；PracticeSession/ExamResult 补 toJson/fromJson，copyWith 补 id/questionIds/questionId；导入路由按 contentType 分发；题库导出格式选择（starhope/md/csv/html）；记录导出 UI；错题卡显示题目整体正确率（统计同步）。
- ✅ **阶段6 规范/性能/稳健**：全流程 `flutter analyze` 0 issues；无非-builder 变长列表；`allQuestions()` 仅在事件/FutureBuilder（非每帧）；build+timeout8 通过。


### 本会话完成（原第四节 1-4 项待办全部落地，db version 1→4）

- ✅ **数据库迁移机制（基础设施）**：`database.dart` 由 `version:1 + 仅 onCreate` 升级为 `version:4 + _onUpgrade 阶梯式迁移`（此前改 schema 必失败）；`_onCreate` 始终建到最新；`clearAll` 同步新表。各任务 schema 挂载：v2=AI 智能体/附件，v3=题库夹，v4=错题掌握度/分组。
- ✅ **【1·重写级】AI 多智能体 + 附件 + 多模态**：`AIAgent`（名字/头像/系统提示词/关联服务/模型覆盖/temperature/topP/maxTokens）独立管理子页 + sidebar/顶部切换；对话附件——图片走 OpenAI vision content array / Ollama images 识图，纯文本类（txt/md/csv/json/html/log）拼入提问上下文；模型参数透传；`AIConversation.agentId`、`AIMessage.attachments`。**0 新 pub 依赖**。
- ✅ **【2】题库夹多层嵌套**：`QuestionFolder`（parent_id 自引用）+ `Question.folderId`；题库页面包屑+子夹树+题目数角标+移入夹；编辑器 folder 选择（新建默认归当前夹）；`QuestionFilter.folderIds` 多选贯通抽题/考试/练习。
- ✅ **【3】考试自定义选题库**：考试规则编辑器「题库范围」多选 FilterChip，所选 folderIds 写入 `ExamRule.filter`（独立于题库页导航）；练习范围显示当前夹。
- ✅ **【4】错题本分类完善**：`WrongQuestion` 加 mastery/lastPracticedAt/customGroup/consecutiveCorrect + `toJson/fromJson`；掌握度/分组/题型/标签/来源多维筛选 + 按掌握度排序；**答对自动降权**（连续答对 3 次移出错题本）+ 手动掌握度标记 + 自定义分组管理；单题快练（判题+降权）；`exportWrongQuestions` 分类导出 + `restoreBackup` 保真（改用 `saveWrong` 直接写完整字段，不再 recordWrong +1 失真）。

### 第二批需求（阶段 1-4 已完成，db version 4→5；阶段 5 考试大改待续）

- ✅ **【阶段1】题库刷新/批量/导入标签**：`load()` 补 notifyListeners 修复列表不刷新（连带修编辑/恢复后刷新）；导入时统一标签；批量设标签/批量设难度。
- ✅ **【阶段2】错题来源/多选练习**：`WrongQuestion` 加 sourceSessionId/Type/Name + `recordWrong` 带来源（db v5）；错题本按场次筛选（考试/练习/快练）；错题多选 → 练这些错题（新增 `HomeNavProvider` 暴露 Tab 切换，startPractice 后跳练习页）。
- ✅ **【阶段3】摘要主页/登录渐变/热键/清空**：新建 `SummaryPage`（登录后默认首页，聚合用户/题库/文件夹/错题/智能体/考试数）；`_PostLoginLoader` 改 `AnimatedSwitcher` 渐变进入；应用内锁定热键（默认 Ctrl+M，设置内可录制，存 ThemeProvider/secure_storage）+ 一键清空（clearAll+deleteUser+clearAttachments+secure.clearAll+logout）；database 加 deleteUser、secure_storage 加 clearAll。
- ✅ **【阶段4】备份勾选/恢复补全**：`fullBackup` 加 modules 勾选 + 补全 question_folders/wrong_groups/ai_agents/ai_conversations/ai_messages（原遗漏致 clearAll 后恢复丢失）；`restoreBackup` 补全恢复 12 类数据。
- ✅ **【阶段5】考试大改（已完成）**：①主观题 essay 题型（Grader + 7 处 _answerInput/_displayAnswer + 导入 _parseType）；②考试自定义选题（`ExamRule.questionIds`，db v5 已建 question_ids_json 列）；③主客观分项判分 + 考后人工评卷（`ExamResult` 加 objective_score/subjective_score/subjective_total/graded，db v5 已建列）；④强制全屏答题卡布局（WindowService enterExamMode 禁拖 + 左1/5答题卡/右4/5题目 + 标记题目）；⑤考试导入导出（.starhope 防伪 + ShareContentType.exam）。**db v5 迁移已在阶段2一次建好所有 exam 新列，阶段5不再动 schema。**

**应用运行验证**：`timeout 8 ./starhope.exe` 返回 124（被超时杀掉=正常运行未崩溃）。注意：用 `tasklist` 轮询检测进程存活不可靠（误报 DEAD），改用 `timeout` 退出码判断。

## 四、待办（用户提出，未完成）

> 原 1-4 项（AI 多智能体 / 题库夹 / 考试自定义选题库 / 错题本分类）**已全部完成**，详见第三节「本会话完成」段。以下为剩余可选/规划项。

1. **（可选）PDF 文本选择/搜索/缩略图**：pdfrx 支持（`textSelectionParams`、`PdfTextSearcher`、侧栏缩略图 LRU）。当前 MVP 仅渲染+缩放+绘图。
2. **（可选）PDF 绘图坐标系进阶**：若 `pageOverlaysBuilder` 的 `pageRectInViewer` 缩放后非实时，改用 `PdfViewerController` 矩阵推导变换。
3. **（规划）与 Deep-tutor 后端 API 集成**：StarHope 桌面端调用 Deep-tutor backend API（云同步/在线题库等）。两端在 monorepo 内，API 契约可原子化提交。
4. **（可选后续）AI 智能体增强**：附件大图点击放大、历史回放仅近 N 轮带图（省 token）、对话内中途切换 agent、agent 头像预设库。
5. **（可选后续）错题本增强**：按时间分组（今天/昨天/本周/更早）header 展示、掌握度统计仪表、错题分组批量操作。
6. **【已完成】阅读器书签/注释/高亮**：书签（标记当前页 + 侧栏跳转，前序 commit）；注释（便签）；高亮——PDF 选中文本右键"高亮"→ 存 PDF 坐标矩形（`PdfRect`）→ `pageOverlaysBuilder` 逐页黄色叠加层（Y 翻转 + `page.rotation` 对齐），翻页跟随；文本路径选中→工具栏"高亮所选"存为高亮笔记（Flutter 文本选区无字符偏移，不渲染黄底，仅侧栏展示/跳转）。另：文本路径绘图改为按页分组（`_textStrokesByPage`），翻页跟随、回页重现（原为屏幕绝对平铺）；侧栏卡片整体点击跳转所在页（`_jumpToPage`）。无 schema 变更（notes 表 page_index/payload 已够用）。
7. **【用户决定暂不做托盘】关闭最小化到系统托盘**：用户明确「托盘就不做了」。锁定账户部分仍未做（可选后续）。原方案：`tray_manager`/`system_tray` 新依赖（pub get 有覆盖 flutter_secure_storage ATL 补丁风险，需重打绕过3）；涉及 window_title_bar（close 拦截）、window_service、settings。

## 五、关键文件地图

```
lib/
  app.dart                      # MaterialApp、全局 ClipRRect 圆角 + F11 KeyboardListener
  main.dart                     # 入口（init AppDatabase）
  core/
    constants.dart              # AppConstants.poweredBy
    crypto/crypto_service.dart  # PBKDF2 / AES-256-GCM / SHA-256
    starhope_format.dart        # .starhope ZIP 导入导出 + SHA-256 校验
    models/                     # question / user / share_meta / models(含 MaterialFormat 枚举)
  services/
    database/database.dart      # AppDatabase 单例（用 StorageConfig.dataRoot() 定位 DB）
    auth_service.dart           # 注册/登录/主密钥派生/storedUser() 暴露已注册用户
    ai_service.dart             # OpenAI 兼容 + Ollama 流式
    export_service.dart         # 题库/资料/全库备份导出、导入校验
    file_storage_service.dart   # materialsDir() 用 StorageConfig.dataRoot；saveAvatar(≤2MB)
    question_import_service.dart# JSON/CSV/Excel/HTML 解析
    storage_config.dart         # ★ 数据存储位置引导配置
    secure_storage_service.dart # 记住账号/主题（flutter_secure_storage）
    window_service.dart         # ★ win32 FFI：最小化/最大化/关闭/拖动/全屏
  providers/                    # auth(含 registeredUser)/theme/question/practice_exam/ai/reader
  views/
    common/
      theme.dart                # 毛玻璃主题 + FrostedBackground
      glass.dart                # GlassCard(含可选 surfaceColor 实色背景)/GlassAppBar/SourceBadge/PoweredFooter/EmptyState
      window_title_bar.dart     # 自定义标题栏（全屏按钮）
      starry_sky.dart           # ★ 流星星空动画（星点坐标按尺寸预生成缓存）
      galaxy_view.dart          # ★ 银河流行动画（银河带+密集星点+沿带流光，登录页左面板）
      starry_button.dart        # ★ 灵动按钮（悬停星空高亮）
      disclaimer.dart           # 免责声明全文 + 弹窗
      user_avatar.dart          # 头像组件（显示头像或首字母）
    auth/
      auth_gate.dart            # hasUser?LoginPage:RegisterPage / 已登录 HomeShell
      login_page.dart           # ★ 整页星空背景 + 左银河面板 + 右登录卡（头像/昵称/@账号/密码）
      register_page.dart
    home/
      home_shell.dart           # NavigationRail/底部导航
      reader_viewer_page.dart   # ★ 分叉：PDF 走 PdfViewer（pdfrx）+绘图 user-space 坐标；文本走 _extractText/_paginate/PageView
      question_bank_page.dart / practice_page.dart / exam_page.dart / ai_page.dart / reader_page.dart / wrong_book_page.dart / settings_page.dart / ...
windows/runner/win32_window.cpp # ★ 无边框+圆角+NCCALCSIZE+NCHITTEST
test/crypto_test.dart           # 加密往返测试（flutter test 受 sqlite3 钩子限制，纯 Dart 用临时项目验证）
```

## 六、密码与登录说明
- 本地单账户，密码 PBKDF2（120000 次）加盐哈希。登录后 `_masterKey`（AES 密钥）仅存内存。
- 登录态不跨会话持久（每次启动需登录）。数据库默认在 `StorageConfig.dataRoot()`（默认 app support 目录）下的 `starhope.db`。

## 七、立即接续建议
1. 先读 `C:\Users\14254\.claude\projects\d--MyProject-SH\memory\` 下两个 memory 文件（架构 + 构建绕过）。
2. 待办 1/2/3（登录页布局 / 性能 / PDF 渲染）**已全部完成**；接续点转第四节「可选后续」（PDF 文本选择/搜索、登录页深色主题）或「与 Deep-tutor API 集成」。
3. 改动后用第二节命令构建；运行验证用 `timeout 8 ./starhope.exe`（退出码 124=正常）。
4. C++ 改动保持英文注释；pub get 后若 secure_storage 被覆盖需重打 ATL 补丁（绕过 3）；pdfrx/PDFium 正常自动下载（绕过 6），失败才需手动放置 binary。
