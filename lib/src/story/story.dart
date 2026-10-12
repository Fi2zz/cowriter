/// 故事层（人机双写）薄接入：一次成功的文件编辑 = 一个补丁。
///
/// 块 = 文件的薄映射：块 id 即文件相对路径。`write_file` / `edit_file` /
/// `apply_patch` 的成功结果各产生一个 [DocPatch]（author: ai）；失败结果
/// 不记。补丁经 [provideDoc] 的引擎提交——装配了 `'sessionLog'` 服务时
/// 同步落 `doc/patch` 会话事件，否则为纯内存故事线。
library;

import 'dart:async';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_doc/conatus_doc.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import 'story_watcher.dart';

/// 产生故事补丁的编辑工具。
const Set<String> kStoryToolNames = <String>{
  'write_file',
  'edit_file',
  'apply_patch',
};

/// 提供故事层：`'doc'` 服务（[DocEngine]）+ 编辑工具观察中间件 +
/// 人的编辑监听（轮询 [watchDir]）。
///
/// [sessionId] 是 `doc/*` 事件的会话归属。装配了 `'sessionLog'` 服务时
/// 先经 [rebuildDocEngine] 从事件流重建（跨重启恢复故事线），否则起新
/// 内存引擎。[watchDir] 缺省取 `'workdir'` 服务；为 null 时不装监听。
/// 中间件与监听都随 [ctx] 卸载撤销；登记失败只记 telemetry
/// （`story.record_failed`），不影响工具调用本身。
Future<DocEngine> provideStory(
  Context ctx, {
  required String sessionId,
  String? watchDir,
  Duration pollInterval = const Duration(milliseconds: 500),
}) async {
  final DocEngine engine = await _restoreEngine(ctx, sessionId);
  ctx.provide('doc', engine);
  final StoryRecorder recorder = StoryRecorder(
    engine: engine,
    fs: ctx.get<FileSystem>('fs'),
    telemetry: ctx.get<Telemetry>('telemetry'),
  );
  ctx.effect(() => ctx.tools.use(recorder.observe, tag: 'story'));
  _startWatcher(
    ctx,
    engine,
    watchDir ?? ctx.get<String>('workdir'),
    pollInterval,
  );
  return engine;
}

/// 恢复引擎：有 `'sessionLog'` 从事件流重建（含 fork 切点映射），没有则
/// 起纯内存引擎（不落事件）。
Future<DocEngine> _restoreEngine(Context ctx, String sessionId) async {
  final SessionLog? log = ctx.get<SessionLog>('sessionLog');
  if (log == null) return DocEngine(PatchLog(), sessionId: sessionId);
  return rebuildDocEngine(log, sessionId);
}

/// 装工作目录监听：轮询间隔即防抖窗；首个 interval 用于建基线。
void _startWatcher(
  Context ctx,
  DocEngine engine,
  String? watchDir,
  Duration interval,
) {
  if (watchDir == null) return;
  final StoryWatcher watcher = StoryWatcher(
    engine: engine,
    dir: watchDir,
    telemetry: ctx.get<Telemetry>('telemetry'),
  );
  ctx.interval(() => unawaited(watcher.scanOnce()), interval);
  ctx.onDispose(watcher.dispose);
}

/// 把成功的编辑工具调用落成补丁（每个变动文件一个 op，整次调用一个补丁）。
class StoryRecorder {
  /// 以目标 [engine] 与可选的 fs / telemetry 缝构造。
  StoryRecorder({required this.engine, this.fs, this.telemetry});

  /// 补丁提交目标。
  final DocEngine engine;

  /// 读回新内容的文件系统缝；缺失时 op 文本为空串。
  final FileSystem? fs;

  /// 降级告警出口。
  final Telemetry? telemetry;

  int _seq = 0;

  /// 工具中间件：先放行，成功后登记补丁；登记失败只告警。
  Future<ToolResult> observe(
    ToolCall call,
    Future<ToolResult> Function() next,
  ) async {
    final ToolResult result = await next();
    if (result.isError || !kStoryToolNames.contains(call.name)) return result;
    try {
      await record(call, result);
    } catch (error) {
      _warn('补丁登记失败：$error');
    }
    return result;
  }

  /// 按本次调用涉及的路径组装一个补丁并提交。
  Future<void> record(ToolCall call, ToolResult result) async {
    final List<String> paths = storyEditedPaths(call, result);
    if (paths.isEmpty) return;
    final List<PatchOp> ops = <PatchOp>[
      for (final String path in paths) await _opFor(path),
    ];
    _seq += 1;
    await engine.commit(
      DocPatch(
        id: 'story-${DateTime.now().microsecondsSinceEpoch}-$_seq',
        author: PatchAuthor.ai,
        ops: ops,
      ),
    );
  }

  /// 单个文件的 op：引擎里已有该块则 Replace，否则 Insert。
  Future<PatchOp> _opFor(String path) async {
    final String text = await _readBack(path);
    final bool recorded = indexOfBlock(engine.state.blocks, path) >= 0;
    if (recorded) return ReplaceBlockOp(blockId: path, text: text);
    return InsertBlockOp(blockId: path, text: text);
  }

  /// 经 fs 缝读回新内容；失败降级为空串并告警（补丁不丢，内容稍后可重建）。
  Future<String> _readBack(String path) async {
    final FileSystem? seam = fs;
    if (seam == null) return '';
    try {
      return await seam.readText(await seam.resolve(path));
    } catch (error) {
      _warn('读回 $path 失败：$error');
      return '';
    }
  }

  void _warn(String message) => telemetry?.emit(
    TelemetryEvent(
      'story.record_failed',
      data: <String, Object?>{'message': message},
    ),
  );
}

/// 取出本次编辑涉及的文件：`write_file` / `edit_file` 在参数里，
/// `apply_patch`（多文件）在结果的 `files` 里（与 lint 同一取法）。
List<String> storyEditedPaths(ToolCall call, ToolResult result) {
  final Object? single = call.arguments['path'];
  if (single is String && single.isNotEmpty) return <String>[single];
  final Object? value = result.value;
  if (value is! Map<String, Object?>) return const <String>[];
  final Object? files = value['files'];
  if (files is! List) return const <String>[];
  return files.whereType<String>().where((String p) => p.isNotEmpty).toList();
}

/// 渲染补丁时间轴（`/story` 输出）：序号、作者、补丁 id、涉及文件、时间。
String renderStoryTimeline(List<DocPatch> patches) {
  if (patches.isEmpty) return '故事线：还没有补丁。';
  final StringBuffer buffer = StringBuffer('故事线（${patches.length} 个补丁）：');
  for (final (int index, DocPatch patch) in patches.indexed) {
    final String author = patch.author == PatchAuthor.ai ? 'AI' : '人';
    final String files = patch.ops.map((PatchOp op) => op.blockId).join(', ');
    buffer.write(
      '\n  ${index + 1}. [$author] ${patch.id}'
      ' — ${files.isEmpty ? '（无文件）' : files}'
      '（${storyPatchTime(patch.id)}）',
    );
  }
  return buffer.toString();
}

/// 从补丁 id（`story-<微秒>-<序号>`）解析落定时间；不可解析时返回 `-`。
String storyPatchTime(String id) {
  final List<String> parts = id.split('-');
  if (parts.length != 3) return '-';
  final int? micros = int.tryParse(parts[1]);
  if (micros == null) return '-';
  final String text = DateTime.fromMicrosecondsSinceEpoch(
    micros,
  ).toLocal().toString();
  return text.substring(0, 19);
}
