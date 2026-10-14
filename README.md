# cowriter

> 终端人机双写协同写作 Agent，基于 [conatus](https://github.com/Fi2zz/conatus) 运行时。

## 是什么

cowriter 把「和 AI 一起写东西」当成两个人对**同一份文档**的协同编辑，而不是一问一答的聊天：

- **文档即会话**：产出是文件本身，不是聊天记录。
- **编辑即对话**：AI 不靠「说」表达意图，靠对文件打补丁；你直接改文件，也是一等事件。
- **故事即历史**：每个会话就是你和 AI 的编辑故事——补丁只追加，可回顾、可回退、可分叉。

它不是「能帮你改文件的聊天机器人」。在聊天范式里，改文件是聊天的副作用；在这里，编辑就是交互的原语：AI 提议一个补丁、你接受或驳回、你手动改一处 AI 下一轮就能看见。两个作者，一种原语（补丁），一个产物（故事）。

cowriter 从终端编码智能体 fork 而来，保留了不少面向代码仓库的能力——`rg` 检索、项目上下文（`AGENTS.md`）、lint-on-edit、检查点。它们对「写东西」同样有用：搜资料、查引用、交付前跑一遍校验。

> 完整范式推演见 conatus 根仓 `docs/人机双写范式设计文档.md`。**本包落地的是该范式的薄实现**：
> 补丁时间轴、事前审阅、diff 即反馈、人的编辑入故事、`/rewind` 回滚。锚点批注、supersede、
> prompt 即补丁、patch 级 traveling 等尚未实现，见「[人机双写故事层](#人机双写故事层)」的已知边界。

## 特性

- 📜 **故事层（人机双写）**：编辑即补丁、事前审阅、diff 即反馈、`/story` 时间轴与分叉
- ⏪ **检查点与回滚**：每轮快照工作区，`/rewind` 连文件带对话一起回退
- 🖥️ **终端交互**：内置 TUI，斜杠命令、会话面板、计划面板、团队泳道
- 🔍 **文件读写与搜索**：read_file / write_file / edit_file / rg / glob / list_files / apply_patch
- 🧠 **技能与记忆**：反复出现的工具序列可沉淀为命名技能；`/remember` 直记；`/cron` 定时任务
- 🤝 **子 Agent 与团队**：`spawn_agent` 隔离委托；成员泳道实时总览
- 🔒 **审批与沙箱**：高危操作走审批；默认 Seatbelt 进程沙箱 + 文件 jail
- 🗺️ **计划闭环**：plan_write 建计划、update_plan 执行中推进、计划面板实时渲染
- 🩹 **失败自愈**：工具失败自动反思重试，可按需重规划
- ⏱️ **预算护栏**：每轮墙钟 + 上下文 token 估算 + 成本跟踪
- 🌐 **接入面**：OpenAI 兼容提供商、MCP server、hooks、技能包

## 快速开始

需要先装 [Dart SDK](https://dart.dev/get-dart) 3.6+（`dart --version` 确认）。从源码运行：

```bash
git clone https://github.com/Fi2zz/cowriter.git
cd cowriter
dart pub get
dart run bin/cowriter.dart
```

**工作目录**：cowriter 把「当前目录」当作工作区（沙箱根）——要在你的文稿目录里
启动它，而不是在 cowriter 源码目录里。在别处启动时用 `--config` 指向配置，或在
config.toml 里设 `[agent] workdir = "/你的/文稿/目录"`。

首次运行会在 `~/.nava_cowriter/config.toml` 生成配置模板，并弹出 provider 面板引导你添加模型（见[配置](#配置)）。

## 打包成可执行文件

```bash
bash tool/build_binary.sh
```

产出 `dist/cowriter`（自包含：内嵌 Dart runtime，目标机器不需要装 Dart SDK）。
装到 PATH 的两种方式：

```bash
# 1. 软链到 PATH 上的目录
ln -s "$PWD/dist/cowriter" /usr/local/bin/cowriter

# 2. 或把 dist/ 加进 PATH
export PATH="$PWD/dist:$PATH"
```

之后直接 `cowriter` 启动，`cowriter --help` 看用法。脚本默认写到
`<包根>/dist/cowriter`；第一个参数可覆盖输出路径，例如把产物写到
`/tmp/cowriter`。

注意：OS 沙箱后端（launcher）仍在运行时从 pub 缓存定位，换机器或清理 pub
缓存后沙箱会 fail-closed（命令执行被禁用，文件 jail 保留），这与源码运行
时的行为一致。

## 配置

首次运行会读取 `~/.nava_cowriter/config.toml`（`COWRITER_HOME` / `--config` 可覆盖路径）。
**文件不存在时自动生成模板，并弹出 provider 面板引导添加**（会话内 `/provider`
也可随时新增，写回 config.toml）。自动生成的模板很精简；下面是常用配置项的全貌：

```toml
[credentials]
ARK_API_KEY = "sk-..."        # 非模型 Key 也放这里（TAVILY_API_KEY 等）

[llm]
default_model = "ark/doubao-seed-1-8-251228"   # provider/model
# fallback_models = ["deepseek/deepseek-chat"]  # 回退链（按序）
# max_attempts = 4            # 单个提供商总尝试次数（含首次）；1 = 关闭重试
# retry_base_ms = 500         # 首次退避，此后按 2 的幂翻倍
# retry_max_ms = 30000        # 单次退避上限（Retry-After 也受此约束）

[providers.ark]
api_key = "ark-..."
base_url = "https://ark.cn-beijing.volces.com/api/v3"   # 方舟普通端点
type = "openai"

# 可选：给 `/model` 浮层预置候选清单（不配则从 models.dev 拉取该 provider 的清单）
# [models."ark/doubao-seed-1-8-251228"]
# capabilities = ["tool_use"]
# max_context_size = 256000

[providers.deepseek]
api_key = "sk-..."
base_url = "https://api.deepseek.com/v1"
type = "openai"

[agent]
max_steps = 8                 # 单轮最大模型步数
workdir = "/path/to/project"  # 工作目录（沙箱根）；缺省当前目录
# subagent_permission = "inherit"  # 子代理默认权限：inherit/readonly/ask/auto（模型只能收紧）
# project_dir = ".cowriter"   # 项目数据目录（会话/记忆/数据库/检查点）；缺省不放工作区，
                              # 落 ~/.nava_cowriter/projects/<编码工作区路径>；显式设置才
                              # 相对工作目录（旧行为，工作区会出现该目录；勿用 `.conatus`，
                              # 那是框架的技能发现根）

[approval]
mode = "ask_when_needed"      # always_ask / ask_when_needed / never_ask

[sandbox]
enabled = true                # Layer 2：OS 级沙箱（命令执行）；默认开启
fs_jail = true                # Layer 1：应用层文件 jail（防误操作）；默认开启
preset = "workspace_write"    # workspace_write / danger_full_access（无 OS 沙箱）
allow_network = false         # true = 全部命令放行网络（默认拒绝，见 network_allowlist）
network_allowlist = ["git fetch", "git pull"]
allowed_executables = ["npx"] # 与内置默认白名单合并（扩展语义，只增不减）
writable_paths = []           # 额外可写路径（~ 展开、相对基于工作目录）
command_timeout_ms = 120000
max_output_bytes = 64000

[budget]
max_turn_seconds = 600        # 单轮墙钟上限（秒）；0 = 不限
max_turn_tokens = 200000      # 单轮上下文 token 估算上限；0 = 不限

[checkpoint]
enabled = true                # 每轮收口后对工作区做文件快照（/rewind 回滚）
keep = 5                      # 回滚点数（含 turn 0 全量 base；0 = 不限）
# ignore = ["app/build"]      # 额外忽略的相对路径前缀（内置已排 build / .dart_tool /
                              # node_modules 顶层前缀、任意层级的 .git、project_dir 整树）

[background]
# keep_alive_on_exit = false  # true = 退出时不杀后台任务（脱离 /background 管理）
# max_running_tasks = 4       # 后台任务并发上限（0 = 不限）

# MCP server：工具经 `server__tool` 前缀接入，高危按审批模式询问。
# [mcp.servers.filesystem]
# type = "stdio"              # stdio 用 command；http / sse 用 url
# command = "npx"
# args = ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]
# [mcp.servers.remote]
# type = "http"
# url = "https://mcp.example.com/mcp"
# headers = { Authorization = "Bearer ${REMOTE_TOKEN}" }
```

## 人机双写故事层

故事层是 cowriter 与普通「能改文件的 Agent」的分界。它把每次编辑记成一条**补丁**，
并让 AI 与人共用同一条编辑历史。

### 块与补丁

- **块 = 段落**：文件按空行切段，每个段落是一个块，块 id 为
  `路径#<内容 sha1 前 8 位>`（同文件重复段落加 `-2`/`-3` 后缀）。超过 512 段的
  文件整体退化为 `路径#full` 单块（LCS 对齐是 O(n·m)，超长文件的段落级故事也没有可读性）。
- **一次成功的编辑 = 一个补丁**：`write_file` / `edit_file` / `apply_patch` 的**成功**
  结果各产生一条补丁（作者＝AI）；失败的工具调用不记。跨文件的 `apply_patch` 是
  「一个补丁含多个 op」。
- **修改 = 删除旧段 + 插入新段**：两段文字之间的差异由 LCS 对齐如实记为
  remove + insert，不虚构成 replace。
- **补丁随会话装配**：装配了 `sessionLog` 服务时每次提交同步落 `doc/patch` 会话事件，
  重启后用 `rebuildDocEngine` 从事件流重建整条故事线。

### 一轮协同怎么走

```
你：把这段开头改得更直接一些
AI：（调用 edit_file）→ 被审阅门拦下，登记为待定补丁，不落盘
    结果回给模型「编辑已登记为待定补丁 #1（1 个文件），待人审阅生效」
你：/story pending         ← 看待定补丁列表
你：/story apply 1         ← 接受，写盘并入故事线
    或 /story reject 1     ← 丢弃，文件原样不动
```

AI 不会因为「没写进去」就重试——它收到的是「已登记」，可以继续推进或等你审阅。

### 三条入故事的通道

1. **AI 工具编辑（受事前审阅）**：交互模式下 `write_file` / `edit_file` / `apply_patch`
   不即时落盘——先算出「执行后的内容」登记为待定补丁，你经 `/story apply` 接受才写盘。
   算不出执行结果的调用（`edit_file` 的 old 串找不到、patch 上下文不适用、参数不全）
   **fail-open 放行**给真实工具报错——拦一个注定失败的编辑只会把真实错误藏起来。
   headless 不拦截（没有人审，文件必须真写）。
2. **人的编辑（轮询 + 内容归因）**：你在编辑器里直接改工作目录下的文件，watcher 轮询
   （缺省 500ms，轮询间隔本身即防抖窗）把它登记为 **human 补丁**。归因靠内容对比：
   磁盘内容与引擎 fold 一致 → 是 AI 自己写的（apply 后已在盘上），跳过；不一致 → 人改的。
   AI 尚未 apply 的待定补丁不在盘上，由 pending 通道持有，不参与这里比对。
3. **`ops` 围栏块提议（第二通道）**：模型除文件工具外，还可以用 ```` ```ops ```` 围栏块
   提议修改（JSON 数组的块操作）。提议只进会话级待定列表（不落盘、不自动生效），
   同样经 `/story apply` 审阅应用。

### 该用哪个命令

- **丢掉还没落盘的改动** → `/story reject <n>`（待定列表里的第 n 个；文件未改动）。
- **回退已经入时间轴的改动** → `/story discard <n>`（时间轴里的第 n 个；会写回文件）。

### diff 即反馈

人改文件的同时，watcher 生成一条**摘要通报**（每文件 `+N/-M` 行数，不带全文），
经 steering 缝在 AI 组下一次模型请求前注入会话——AI 工作途中就能看到你改了哪些文件、
改了多少，需要细节自己 `read_file`。AI 的写入、`/story discard` 的写回、待定补丁的
apply 写回都经内容归因，不会误报成「人改了」。

> 为什么不带全文：通报是**提示**不是**任务**。对齐工具结果驱逐的「预览 + 路径」哲学，
> 需要细节让模型自己去读，避免把整段正文灌进上下文。

### `/story` 子命令

`preview` / `discard` / `fork` 取**时间轴序号**（`/story` 列表里的 1、2、3）；`apply` /
`reject` 取**待定序号**（`/story pending` 列表里的 1、2、3）。两套编号各自独立，
别混用。

| 子命令 | 作用 |
|--------|------|
| `/story` | 补丁时间轴：序号、作者（人/AI）、补丁 id、涉及文件、落定时间 |
| `/story preview <n>` | 预览前 n 个补丁时刻的文档状态（段落重组后逐文件列出） |
| `/story discard <n>` | 驳回第 n 个补丁并**把触及文件写回 fold 后内容**；fold 后消失的文件保守保留不删 |
| `/story fork <n>` | 从前 n 个补丁分叉新会话并自动切换（会话层 fork 复制事件前缀，切过去后故事线经 rebuild 恢复） |
| `/story pending` | 列出待定补丁（序号 + 来源 + ops 摘要） |
| `/story apply <i>` | 接受第 i 个待定补丁：写盘并入故事线 |
| `/story reject <i>` | 丢弃第 i 个待定补丁（不落盘，文件未改动） |

### 冲突：双版本落盘

待定补丁登记时会记下每个目标文件的**基底内容**。`apply` 时若磁盘内容已不等于基底
（你在等待期间又改了那个文件），cowriter 不会覆盖、也不会静默失败——它写一份
git 式 marker 的双版本合并文本，**人的版本在上、AI 待定内容在下**，等你人工合并。
干净的文件照常写入，一次 apply 只落一条补丁。

### 与 `/rewind` 的分工

故事层管**文档内**的补丁历史（段落粒度、以编辑为单位）；`/rewind` 管**工作区级**的
时间回溯（文件快照 + 对话回滚，见[检查点与回滚](#检查点与回滚rewind)）。两者是不同
粒度、不同用途的两层：`/story` 回答「这段文字是怎么变成现在这样的」，`/rewind` 回答
「把整个工作区退回三轮前」。

### 已知边界（v1）

- **文件删除不记 human 补丁**：watcher 只处理「mtime 变新且内容不一致」的文件，删除
  留待与回溯语义一起设计。
- **`apply` 只支持 Insert / Replace**：含 Remove / Move 块的待定补丁 v1 拒绝应用
  （提示手动处理后驳回）。
- **不做分支间自动合并**：`/story fork` 出的分支是草稿线，合并靠人主导的三方对照编辑
  ——散文语义的冲突没有可靠的自动解。
- **旧会话的文件粒度块不迁移**：早期会话的补丁块 id 是整路径（无 `#`），与新的段落块
  共存不冲突，但不重写。
- **故事层未持久化时不能 fork**：没有 `sessionLog` 服务时 `/story fork` 会提示不可用。
- **事前审阅没有独立开关**：交互模式下写工具一律先登记待定补丁；`headless`（`-p`）
  直写不拦截。要「改完立刻落盘」目前只能在 headless 下跑。
- 范式设计里的**锚点批注、supersede、prompt 即补丁、patch 级 traveling 尚未实现**——
  本包是薄接入，不是完整范式。

> 完整命令清单、键盘快捷键、配置速查与排查表见 [docs/使用指南.md](docs/使用指南.md)。

## 检查点与回滚（`/rewind`）

每轮收口后对工作区文件做快照：**turn 0 全量 base + 各轮相对 base 的差量**
（只打包变化/新增文件，删除记入清单），**每个检查点压缩成单个无扩展名归档
文件**（`<项目数据目录>/checkpoints/<会话>/<sha256 哈希名>`**——项目数据目录
缺省是 `~/.nava_cowriter/projects/<编码工作区路径>`（不在工作区建目录），**文件名不可读、
无 `.gz` 扩展名、不暴露轮次时间线**，轮次只记录在归档头与会话级 gzip `index`
里；内容非明文、不保留目录结构；`dart:io` 内置 GZipCodec 自定义容器格式，零新
依赖；旧版目录树检查点读时兼容、索引缺失自动重建）。清单记录快照时刻的对话
切点事件 id。`/rewind [N]` 把工作区恢复到 N 轮前（缺省 1）的文件状态，**并同步
把对话回滚到该轮**：从切点事件 `Session.fork` 出新会话（append-only 不变式，
旧会话保留为记录），`/rewind list` 查看本会话可用检查点。快照/恢复走应用级
dart:io，不受 fs jail 约束；`/rewind` 是用户命令，不挂审批。

- 快照时机：会话绑定（turn 0）+ 每轮收口后；保留 base + 最近 `keep-1` 个差量。
- 排除：内置 `build` / `.dart_tool` / `node_modules`（顶层前缀）、任意层级的
  `.git`、以及 `project_dir` 整树，外加 `[checkpoint] ignore` 用户配置；读写全程流式
  （清单头单独读、条目按 chunk 过 gzip），大工作区快照内存 ≈ 最大单文件。
- 恢复语义：base 铺底 + 差量覆盖/删除 + 删当前多余（rsync 式）。
- 变化检测：相对 base 的 mtime+size + SHA-256 哈希（stat 相同也兜底）。
- 对话切点：`lastEventId` 为 null（全新会话的 turn 0）时切到全新空会话。
- 关闭：`[checkpoint] enabled = false`（/rewind 提示不可用）。

## 后台任务（`/background`）

`run_command_background` 在沙箱中后台启动命令（不阻塞对话），返回 `bg-<n>`；
`list_background_tasks` / `background_output` / `background_kill` 管理之。
`/background [list|output <id>|kill <id>]` 是用户侧入口。任务走 `'shell'` 缝的
`start()`，照常受沙箱 CommandPolicy 裁决；并发上限读 `[background]
max_running_tasks`（缺省 4）。缺省 `keep_alive_on_exit = false`：cowriter 退出时
终止所有在跑任务；置 `true` 则退出时不杀、任务保活脱离——**脱离后不再受
`/background` 管理**（list/output/kill 找不到它），且输出管道随进程退出关闭，
子进程继续大量写输出可能被 SIGPIPE 杀死。

## 消息队列

busy 时输入框保持可编辑（「思考中」动画在状态栏）：回车自动排队（上限
20 条），占位提示显示已排队条数。排队的消息**不等轮末**：Agent Loop 组
下一次模型请求前经 steering 缝取走注入会话——AI 工作途中即可看到插话；
注入后队列即时清空，轮末的出队投递是兜底路径。`Esc` 打断会**清空队列**
并提示条数（已注入的插话留在会话里——说出去的话不收回）；切换会话同样
清空。cron/提醒的投递不受影响（busy 时仍由调度器重试）。

## `/doctor`

- `/doctor`：体检——配置 / 提供商 / 回退链 / 模型窗口与费率 / 沙箱（Layer 1/2）/
  工具表 / MCP / rg 逐项 ✓/✗ + 修复提示，自查用。

## `/trace` 复盘

```
你 › 把 checkpoint 的存储后端加上 git 选项
思考 › 先看存储实现是怎么选后端的
✓ rg › lib/src/checkpoint/checkpoint_backend.dart:24（+11 行）
✗ edit_file › OS Error: Path does not exist, path = .../nope.dart
助手 › 路径写错了，改用 checkpoint_backend.dart
```

回答「模型当时看到了什么、为什么那么判断」——屏上只有结论，复盘给的是过程。
`/trace` 渲染最近一轮，`/trace 3` 看最近三轮。

不新建埋点：会话日志本就是可读 JSONL、事件都在盘上，`/trace` 只把
`Session.events` 摊成时间线：

- 失败项标 `✗` 并带出原因——模型为什么停下、哪一步炸了
- 工具结果只取首行但**报出总行数**：`rg` 命中 12 处和 1 处是不同的信息，
  砍到首行不能把条数也丢了
- 不可读的事件（`agent/round` / `plan/updated` 等）跳过，不产生噪声行
- 压缩事件标出来（压缩失败也会显式提示）

`/doctor` 查的是**装配**（配置、沙箱、工具表）；`/trace` 查的是**这一轮发生了什么**。

## `/export` 导出

`/export [路径]` 把当前会话导出为 markdown —— 存档、贴给同事、喂给别的工具
分析。缺省落在项目数据目录的 `exports/`，给路径则照写（支持 `~` 展开）。

```
# cowriter 会话 session_abc123

- 会话：`session_abc123`
- 模型：ark/doubao-seed-1-8-251228
- 工作目录：`/Users/fitz/REPO/conatus`
- 事件：42 条
- 成本：$0.0873（models.dev 口径，非账单）

## 你
给 checkpoint 加上 git 存储后端

<details><summary>思考</summary>
先看 openCheckpointStore 怎么选后端的
</details>

### ✗ edit_file
OS Error: Path does not exist, path = 'lib/…/nope.dart'
```

与 `/trace` 的分工：`/trace` 回答「刚才那轮发生了什么」（只管屏上能读的一屏，
会截断）；`/export` 回答「把这次会话留下来」，**内容不截断**——截断是显示层的事。
只有单条工具结果超过 8000 字符才截，且**显式标注被截了多少**（静默截断会让读
的人以为那就是全部）。

思考折叠进 `<details>`，内部事件（`agent/round` / `plan/updated`）不进导出。
**不放工作区**——与会话 / 检查点同一取舍，导出是工具产物，不该往代码仓库留垃圾。

## `!` 快捷 shell 与 lint-on-edit

- `!<命令>`：直接执行 shell 命令（**不进模型、不烧 token**），走沙箱缝；
  `!!` 重跑上一条。
- **shell 模式**（与 OpenCode 一致）：在**空提示符**打 `!` 进入 shell 模式——
  输入框前缀变 `!`（黄）、占位提示「输入 shell 命令，Esc 退出」、状态栏提示
  `[Enter] 执行 | [Esc] 退出`；`Esc` 不执行直接退出；执行完自动退出回对话模式
  （一次性）。shell 模式里 `/` 与 `@` 交给 shell 解释，不弹补全面板。
- lint-on-edit：模型编辑文件后自动跑 linter（`[lint]` 可配置：
  `enabled` / `command` 覆盖 / `debounce_seconds`），告警追加进工具结果
  当场闭环；按项目类型自动探测（pubspec→`dart analyze`、package.json→
  `eslint .`、go.mod→`go vet ./...`、Cargo.toml→`cargo check`）。

## Hooks（`[hooks]`）

config.toml `[hooks]` 表：`pre_tool_use`（任一非零退出即拒绝该工具）、
`post_tool_use`（失败追加提示）、`stop`（轮次收口，失败只提示）。hook 命令
经 `/bin/sh -c` 直连运行（**不走** `'shell'` 沙箱缝）；注入环境变量
`NAVA_HOOK_EVENT` / `NAVA_HOOK_TOOL` / `NAVA_HOOK_ARGS_JSON`。

```toml
[hooks]
pre_tool_use = ["echo 工具前钩子 >> /tmp/cowriter-hook.log"]
# post_tool_use = []
# stop = []
```

## MCP（`/mcp`）

`[mcp.servers.<名字>]` 表声明 MCP server，启动时逐台挂载、**单台连接失败提示并
跳过**（不阻塞启动）。工具以 `server__tool` 前缀进工具表（`/tools` 可见），
风险映射后按当前权限模式走审批；`/mcp` 查看已接入的 server（就绪状态 / 工具数）。

- `type`：`stdio`（本地子进程，`command` + `args`）/ `http` / `sse`（远程端点 `url`）。
- `env` / `headers` 支持 `${KEY}` 占位符，经凭据服务（`[credentials]` / 环境变量）
  解析；**解析结果不得写进日志**。
- **安全边界**：MCP server 是用户在配置里显式声明的受信端，其 stdio 子进程
  **不走** Layer 2 OS 沙箱（沙箱管的是模型临时写出的命令，二者风险面不同）。
- 接入第三方插件（Markdown 技能包 / MCP server / CLI 脚本 / 纯库）的分档指南：
  [docs/plugin-integration.md](docs/plugin-integration.md)。

## 模型提供商（`/provider` / `/model`）

提供商在 `~/.nava_cowriter/config.toml` 的 `[providers.<名字>]` 表里定义
（实现 `lib/src/providers/`，公开入口 `lib/providers.dart`）；`[llm]
default_model = "provider/model"` 同时定当前提供商与默认模型。

- `/provider`：展示注册表；`/provider add` 或面板里 `[ Add New Platform ]`
  新增（表单只填 **base_url / model**，`name` 可选留空自动从 base_url 推导、
  `type` 固定 `openai`，写回 config.toml；**第一个** provider 会同时设为
  `default_model`）；删除与切换默认仍直接编辑 config.toml
- `/model`：打开当前提供商的模型选择浮层——候选优先取 config.toml 的
  `[models."<provider>/<model>"]` 清单（kimi 兼容格式；`/model <片段>` 预填搜索框，
  搜索过滤后 Enter 切换）；配置无清单时从 models.dev 拉取该 provider 的清单兜底
  （缓存 24h，失败仅展示配置内模型）；没有候选也照常打开浮层
- 未配置任何 provider 时启动进入引导：TUI 照常启动并自动弹出 provider 面板，
  模型调用会提示先用 `/provider` 添加或编辑 config.toml——**没有缺省回退链**
  （回退链需在 config.toml `[llm] fallback_models` 里显式声明）

```toml
[providers.my-gateway]
api_key = "sk-..."      # 可省略；空时构造期报缺凭据
base_url = "https://my-gateway.example/v1"   # OpenAI 兼容端点根地址（必填）
type = "openai"         # openai→chat/completions；kimi→responses（缺省 openai）
# [providers.my-gateway.oauth]   # 保留字段：OAuth 未实现，仅提示不可用
# key = "oauth-key-name"
```

- `type` 决定请求形态：`openai` 走 `chat/completions`，`kimi` 走 `responses`。
- `oauth` 子表：字段保留（`key`）但**不实现** OAuth 调用；配了 `oauth.key` 且
  未配 `api_key` 的提供商启动时提示不可用，其余照常。
- 以代码装配：`provideProviders(app, providers: <ProviderProfile>[...],
currentName: ..., credentials: ...)` 把注册表挂到 `'providers'` 服务，
  `registry.buildLlm(name, model: ...)` 按 profile 构造 OpenAI 兼容
  `LlmProvider`。Key 解析顺序：配置内 `apiKey` → 注入的凭据服务（缺省
  `EnvCredentials`）。

```dart
import 'package:cowriter/providers.dart';

final ProviderRegistry registry = provideProviders(
  app,
  providers: <ProviderProfile>[
    const ProviderProfile(
      name: 'ark',
      baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
    ),
  ],
  currentName: 'ark',
);
final LlmProvider? llm = registry.buildLlm('ark', model: 'doubao-seed-1-8-251228');
```

**Plan 端点只认订阅后生成的专属 Key**：`provider` 名与 `base_url` 由你自定，例如
订阅方舟 Agent Plan 就写 `[providers.arkcli-agent-plan]` + `base_url =
".../api/plan/v3"`，它的 Key 是订阅后生成的专属 Key（如
`ARK_AGENT_PLAN_API_KEY`）；普通方舟 Key（`ARK_API_KEY`）打 plan 端点会返回 401。
内置预设 `volcengine-coding-plan`（`.../api/coding/v3`）同理，对应
`ARK_CODING_PLAN_API_KEY`。

## LLM 韧性（重试 / 退避 / 回退链）

一次网络抖动不该让整轮失败。链路分两层，各自独立生效：

1. **退避重试**（同一提供商内）——限流（429）、5xx、超时、连接失败按指数退避
   重试，缺省 4 次 / 500ms 起翻倍 / 单次封顶 30s，带 ±25% 抖动。服务端给了
   `Retry-After` 就照它等。
2. **回退链**（换提供商）——上面重试耗尽后，按 `[llm] fallback_models` 换下一
   个候选。

只对**可重试**的错误重试：401 / 403、缺 API Key、400 这类重试无意义的失败一次
就上抛，直接进入回退（换一个 Key 正确的提供商才是出路）。

- 装配形状是两层嵌套：`FallbackLlm(RetryingLlm(主), RetryingLlm(备), …)`。
  先在原提供商上把能救的失败救回来，避免一次抖动就换模型、让回答风格在一次会话
  里来回跳。
- **流式重试只在尚未产出任何增量时生效**：已经 yield 出去的文本收不回来，静默
  重来只会让用户看到重复内容（回退链同理）。
- 配错的回退项（provider 不存在 / 重复）**跳过而不是整体失败**，并在 `/doctor`
  的「模型回退链」里列出；配错一条备用模型不该让主模型都用不了。
- 重试与回退都**实时上屏**（`· ark 触发限流，1.0s 后重试（2/4）`、
  `· ark 不可用，已切到 deepseek`）——退避可能静默 30 秒，没有提示在用户眼里
  就是卡死。`/doctor` 另报出候选链与最近一次回退。
- `/model` 切换主模型时**重建整条链**，回退项仍然跟随——否则一次切模型就顺手
  关掉了容错。

```toml
[llm]
default_model = "ark/doubao-seed-1-8-251228"
fallback_models = ["deepseek/deepseek-chat", "openai/gpt-4o-mini"]
max_attempts = 4
```

框架侧（`conatus_llm`）的入口是 `RetryingLlm` / `RetryPolicy` / `LlmErrorKind`
与 `FallbackLlm`，任何宿主都能单独取用。

## 子 Agent（`spawn_agent`）

把一个自包含的子任务委托给隔离子 Agent（独立 `Session` + 受限工具白名单），
只把结论回传主链路。**每一步实时上屏**——子 Agent 一次能跑几十秒，屏上如果
完全静止就既判断不了它有没有跑偏，也不敢中途打断：

```
◆ 子 Agent：调研 checkpoint 存储的实现
  · 第 1 轮 思考中（工具已 0 次）
  → rg
  ✓ rg
  · 第 2 轮 输出 380 字符
  → read_file
  ✗ read_file
✓ 子 Agent success：3 轮 （rg、read_file）
```

（`TuiRole.stage` 暗色行，不污染助手正文的排版。）

**默认只读白名单**：不传 `tools` 时子 Agent 拿到 `get_time` / `echo` /
`read_file` / `rg` / `glob` / `list_files`——够调研，
但不给写 / 执行类。显式传 `tools` 也**排除 high 风险**（双保险：写 / 执行类即便
被点名也要过审批）。

**工具调用复用宿主管线**：子注册表复制主注册表的守卫与环绕中间件，**审批、工具
结果驱逐、hooks / lint 对子 Agent 的工具调用同样生效**。所以子 Agent 读大文件也会
落盘成预览（不再把 20 万字符直接灌进子历史），写操作照样弹审批。

**历史照样压缩**：子 Agent 接上上下文的 `'compaction'`；配合上面的结果驱逐，长调研
不会顶爆模型窗口直接失败。

**权限模式（`permissionMode`）**：子代理级策略，对齐 Claude Code。宿主在
`[agent] subagent_permission` 设默认（`inherit` / `readonly` / `ask` / `auto`），
模型可在
`spawn_agent` 的 `permission_mode` 请求，但**只能收紧**：

- `inherit`（默认）：走宿主同一条审批管线。
- `readonly`：仅 low 风险工具，medium/high 直接拒（不弹审批）。
- `ask`：每个子工具调用都要确认（阈值 low）。
- `auto`：子调用免审批（仍在 Layer 2 沙箱内；high 工具仍被白名单风险上限挡掉）。

无审批人时（headless 不装审批服务）`ask` **退化为只读**：写 / 执行类拒绝，低风险
读取照常，而不是把所有子工具静默拒掉。

**Esc 打断会收掉在跑子 Agent**：子 Agent 跑在自己的 `Session`、不参与主轮次的取消
竞速，`Esc` 只丢主轮次结果的话它会在后台继续烧 token；现在 `Esc` 一并把在途子
Agent 取消，收敛为 `status=failed`。

**独立预算**：子 Agent 用自己计数的 `BudgetedLlmProvider`，不共用主轮次的
token 额度——否则它那十几轮调用会把**主**轮次撞爆 `max_turn_tokens` 提前收口，
而子 Agent 的半截结论会被当成结论回传。成本仍记进同一个 costTracker（那部分
是真实花费）。

## 团队泳道（`/team`）

多 agent 的**实时总览**。每个成员一条泳道，边跑边显示它在调什么工具、说了什么：

```
◐ researcher  [执行中]
  · 第 1 轮
  → rg
  ✓ rg · 12 处匹配
  → read_file
  ✗ read_file
◆ swarm-1
  → read_file
  ✓ 收口：3 轮 （read_file、rg）
```

- `spawn_teammate` 起的成员与 `spawn_agent` 起的子 Agent **同处一个视图**
  （后者带 `swarm-` 前缀，标 `◆`）——两套委托机制语义不同但视图统一。
- 每条泳道保留最近 12 行（`kTeamLaneMaxLines`），连续正文会合并成一行，
  否则一条长回答就能刷掉整个泳道。
- `Esc` 或 `Ctrl+T` 返回对话。`Ctrl+T` 在对话视图下才是展开 TODO 列表。
- 任务板在泳道之后（没有任务时不渲染）。
- 状态栏显示团队人数 / 任务完成数 / 成本（成本取共用的 costTracker 真实费率）。

**已知边界**：泳道视图是**独占**的——切过去就没有对话区，不能「边看边聊」。

## headless（`-p`）与安全姿态

`cowriter -p <任务>` 跑**无人值守的单轮**：装配完整运行时（工具 / 沙箱 / MCP /
预算）但不启动 TUI，输出回复即退出（`--output-format text|json`）。

**为什么不装审批链**：审批需要一个能应答的人——`AskUserApproval` 依赖 TUI
浮层，headless 里没有任何东西能回答它，超时还会一律判拒（fail-closed），
等于把每个 high 调用都卡死。所以 headless 干脆不挂审批中间件，模型调用
`high` 工具直接执行。这带来一个必须写明的推论：

> **headless 的安全兜底只剩 OS 沙箱（Layer 2）。** `[approval]` 整段配置
> （包括显式加严的 `always_ask`）在 `-p` 下都不生效——启动时会在 stderr
> 提示，而不是静默丢弃。

因此启动期设了一道闸门（`validateHeadlessSafety`）：

- 沙箱照常（`enabled = true` 且 `preset = "workspace_write"`）→ 正常启动；
- `enabled = false` 或 `preset = "danger_full_access"`（两者最终都让命令
  回本地直执）→ **拒绝启动**，退出码 2：无人值守 + 无审批 + 无沙箱 =
  模型可无人监督执行任意命令，交互模式能接受的配置在这里不能；
- 确知风险要在无沙箱环境跑 headless（如已受控的容器），显式传
  `--allow-unsafe-headless` 放行——把「危险」变成调用方当场做出的决定，
  而不是配置文件里一处早已遗忘的设置。

同理，未声明风险的 MCP 工具缺省提级 `high`（见 conatus_mcp 的
`mcpToolRisk`）：stdio 子进程不经本地沙箱，审批是未知风险的唯一防线，
缺省必须进得去审批阈值。

沙箱（`lib/src/sandbox/`）分两层，各自独立开关、独立失败语义：

- **Layer 1 · 应用层文件 jail**（`fs_jail`，默认开启）：
  `JailedFileSystem` 把 conatus `FileSystem` 接上 `dart_io_sandbox` 的 bound
  jail，读写限定在沙箱根内，越界映射为 `sandboxDenied`。纯应用层防误操作，
  **不依赖 OS 后端**，任何平台可用。
- **Layer 2 · OS 级沙箱**（`enabled`，默认开启，仅 macOS）：
  `CommandPolicy` 裁决命令形状（管道 / 重定向放行；`&&`、`;`、`$()` 触发
  review，TUI 内经人工复核裁决、headless 按拒绝），再由
  `SandboxedShellExecutor` 直调系统
  `/usr/bin/sandbox-exec` + 自建的 Seatbelt profile 执行：deny-default 基线、
  可写根经 `-D` 参数注入（工作区、/tmp 真实路径、常用 HOME 缓存、`writable_paths`），
  `/dev/null` 按字符设备放行，mach-lookup 收敛为系统服务白名单，最小环境变量、
  不继承父进程环境。设计对齐 OpenAI Codex CLI / Claude Code 的 seatbelt 方案。

**fail-closed 只作用于 Layer 2 后端**：sandbox-exec / Seatbelt 不可用时，
命令执行被拒斥执行器禁用（不降级为本地 shell），应用照常启动、Layer 1 文件
jail 继续生效。Layer 1 与 Layer 2 可独立关闭；`preset = "danger_full_access"`
显式关闭 OS 沙箱回本地直执（Layer 1 与命令策略仍生效）。

已知边界：

- `sandbox-exec` 在 macOS 上标记 deprecated 但系统自带可用；启动预检会 smoke
  试跑，失败时命令执行禁用（stderr 会提示，可在 config.toml 设
  `[sandbox] enabled = false` 关闭 Layer 2，保留 Layer 1 文件 jail）。
- 沙箱定位是防 LLM 乱跑命令的**护栏**：写默认限定在工作区 + 缓存目录，网络
  默认拒绝，读不限面（与 Codex / Claude Code 同姿态）；对抗决心攻击者不是其目标。
- mach-lookup 白名单按需扩展：工具若因缺系统服务报错，把服务名加进
  `seatbeltMachAllowlist`（TLS 所需的 trustd/ocspd 已内置）。
- CommandPolicy 的 REVIEW 已接线人工复核：TUI 内经选项浮层征询（NeverAsk
  视同放行），批准后在 seatbelt 内照常执行；headless 无浮层，REVIEW 仍按
  拒绝处理（fail-closed）。白名单/路径越界这类确定性违规不受复核豁免，
  优先按 deny 拒绝。
- Layer 2 仅支持 macOS：其他平台命令执行会禁用，请显式设
  `[sandbox] enabled = false`。

## 预算护栏

一轮 = 你的一次提交到模型收口（空闲 2 分钟自动划分新一轮）；一轮内模型每循环
一次算一步（一次模型请求 + 工具执行），步数上限是 `[agent] max_steps`。

每轮默认 10 分钟墙钟 + 上下文 token 护栏；
超限时模型收到收口提示而非直接报错。估算按约 4 字符 1 token 的粗口径
（`estimateMessagesTokens`），**只作护栏，不用于计费**。

**token 封顶跟模型窗口走**：已知窗口时取 `窗口 × 0.75`（余下 1/4 留给模型
输出与工具回填）与 `[budget] max_turn_tokens` 的较小者。只看固定阈值会让
32k 窗口的模型等不到这条闸门（请求先被 API 拒掉），1M 窗口的模型又过早收口。
窗口来自 models.dev（见下）。

## 成本与上下文窗口（models.dev）

`ModelProfileStore` 把 models.dev 的上下文窗口与真实单价收成一份可查档案，
供 `/cost` 与状态栏使用：

- **`/cost`**：按当前模型的真实费率算，输入/输出/缓存命中 token 分列，并
  讲清费率来源。**费率查不到就明说「未知」并按 0 计**——不猜一个假数字。
- **状态栏 `ctx`**：分母是真实窗口。有一轮真实用量后，分子也换成接口返回的
  `prompt_tokens`（正是下一次请求要发的全部内容，含 system prompt、工具定义
  与工具结果），比按屏上记录 chars/4 猜准得多；首轮之前没有真实数据时前缀加
  `~` 表示是估算。
- **`/doctor`** 新增「模型窗口 / 费率」项。
- `/model` 切换后费率与窗口自动跟着换；provider 名对不上时按模型 id 跨
  provider 查（窗口与价格是模型属性）。

数据源离线且无缓存时全部显示「未知」，**不影响模型正常调用**。

## 开发

默认（独立使用）：`pubspec.yaml` 用 git 依赖引 conatus 仓库，clone 后直接
`dart pub get` 即可。

在 [conatus](https://github.com/Fi2zz/conatus) 仓库内开发时，本仓库作为
submodule 挂在 `packages/cowriter`。该仓库的 `tool/setup_code_filter.sh`
会：

- 装一个 git clean/smudge filter，让 `pubspec.yaml` 里的 `resolution:
  workspace` 在工作区保持生效 —— 本包成为 conatus pub workspace 的
  成员，依赖解析到本地 `packages/*`，改框架对这里立即生效，不必先推送；
  而 `git add` 时该行会被自动注释掉，推送出去的内容因此不带
  `resolution`；
- 生成一个本地 `pubspec_overrides.yaml`（已进 `.gitignore`），清空
  `pubspec.yaml` 的 `dependency_overrides` —— workspace 内禁止 override
  成员包。

未装 filter 的 clone（例如直接 clone 本仓库）拿到的是注释态、且 override
原样生效，行为与上面「独立使用」一致。

**开发 conatus 侧的改动时**：改完在 `packages/cowriter` 下跑
`bash tool/build_binary.sh` 重建 `dist/cowriter`；只改源码不重建、或交付旧
二进制，视为改动未完成。

## 依赖

- [conatus](https://github.com/Fi2zz/conatus) — 框架
- Dart 3.6+；在 conatus 仓库内开发时需 3.11+（workspace 的 glob 语法要求）

## 与 conatus 的关系

cowriter 是 conatus 的**上层应用**，不是框架的一部分；fork 自终端编码智能体
conatus_code，产品方向转为**人机双写协同写作**。相对上游的差异：

- **编码工具面已剥离**：`git_*` / `run_command` / `run_tests` / `run_code` 工具与
  `/commit` / `/review` 命令已移除；模型侧保留文件读写、搜索、`apply_patch`、
  后台任务等通用工具面。
- **接入故事层**：基于 conatus_doc 的文档补丁引擎，把文件编辑映射为补丁（见
  [人机双写故事层](#人机双写故事层)）。
- 框架侧（Agent Loop、工具系统、技能沉淀、会话、MCP、沙箱缝）原样复用；TUI、
  文件工具、提供商注册表原为 conatus 的独立包，现并入本包，入口分别为
  `lib/tui.dart` / `lib/fs_tools.dart` / `lib/providers.dart`。

## CI

`.github/workflows/test.yml` 在每次 push / PR 跑：静态检查（`--fatal-infos`）
→ 全部测试 → 打包二进制。跑在 `macos-latest`——沙箱 Layer 2 只在 macOS 可用，
`test/sandbox/` 下两个测试文件没有跳过保护，放到 ubuntu 上要么必红、要么被迫
跳过最有价值的那批。

CI 验的是**独立形态**：checkout 拿到的是提交态 pubspec（`resolution:
workspace` 被 git filter 注释掉，依赖经 git 拉 conatus master），也就是
「用户 clone 本仓库后拿到的东西」。conatus 工作区内的跨仓集成由 conatus
仓库的 CI 负责。

本仓库的 lint 规则因此**自包含**在 `analysis_options.yaml`（不像兄弟包那样
`include ../../analysis_options.yaml`）——独立形态下那个路径不存在。规则与
conatus 仓库根保持一致，改一处请同步另一处。

## 许可证

MIT
