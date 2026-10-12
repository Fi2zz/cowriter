/// 人的编辑监听：定期扫描工作目录，把引擎状态之外的文件改动登记为
/// human 补丁（设计文档 §2.4「人的编辑是一等事件」）。
///
/// 选型：**轮询 mtime** 而非 `Directory.watch`——watch 的 recursive 在
/// Linux（inotify）上不支持、FSEvents 在 macOS 上事件粒度粗且CI 时序不稳；
/// 轮询跨平台语义一致，测试可显式 `scanOnce()` 驱动，轮询间隔本身就是
/// 防抖窗（同一路径在窗口内的连续改动合并为一个 op，最终内容归因）。
///
/// 归因：AI 经工具写文件同样触发 mtime 变化，但 AI 补丁已把「写入后内容」
/// 记进引擎状态——扫描时读回内容与引擎一致即跳过，不一致才是人改的。
library;

import 'dart:io';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_doc/conatus_doc.dart';

/// 扫描时跳过的目录（按 basename），与 GlobTool / ListFilesTool 对齐。
const Set<String> kStorySkipDirs = <String>{
  '.git',
  '.nava_cowriter',
  'node_modules',
  '.dart_tool',
  'build',
};

/// 只跟踪这些文本扩展名（读回时再容错一次，双保险）。
const Set<String> kStoryTextExtensions = <String>{
  '.md',
  '.txt',
  '.dart',
  '.json',
  '.yaml',
  '.yml',
  '.toml',
  '.csv',
};

/// 工作目录轮询器：把人的文件改动登记为 `PatchAuthor.human` 补丁。
///
/// 首次 [scanOnce] 只建基线（现状不算编辑）；之后每次扫描把「mtime 变新
/// 且内容与引擎状态不一致」的文件合成一个 human 补丁提交。文件删除 v1
/// 不记（RemoveBlockOp 的接入留给回溯语义一起设计）。
class StoryWatcher {
  /// 以目标 [engine] 与工作目录 [dir] 构造。
  StoryWatcher({required this.engine, required this.dir, this.telemetry});

  /// 补丁提交目标。
  final DocEngine engine;

  /// 被监听的工作目录（绝对路径）。
  final String dir;

  /// 降级告警出口。
  final Telemetry? telemetry;

  /// 基线：相对路径 → (mtime, 长度)。等长同毫秒的连续写入靠长度分辨。
  final Map<String, (DateTime, int)> _mtimes = <String, (DateTime, int)>{};
  int _seq = 0;
  bool _primed = false;
  bool _scanning = false;
  bool _disposed = false;

  /// 扫描一次。首次调用只建基线；重入（上一轮未扫完）直接跳过。
  Future<void> scanOnce() async {
    if (_disposed || _scanning) return;
    _scanning = true;
    try {
      await _scan();
    } finally {
      _scanning = false;
    }
  }

  /// 停止（幂等）；挂起的扫描跑完后自然停止。
  void dispose() => _disposed = true;

  Future<void> _scan() async {
    final Map<String, (DateTime, int)> now = await _snapshot();
    if (!_primed) {
      _primed = true;
      _mtimes.addAll(now);
      return;
    }
    final List<PatchOp> ops = await _diffOps(now);
    _mtimes
      ..clear()
      ..addAll(now);
    if (ops.isEmpty || _disposed) return;
    _seq += 1;
    await engine.commit(
      DocPatch(
        id: 'human-${DateTime.now().microsecondsSinceEpoch}-$_seq',
        author: PatchAuthor.human,
        ops: ops,
      ),
    );
  }

  /// 与基线对比：mtime 变新的文件逐个读回归因，返回本批 ops。
  Future<List<PatchOp>> _diffOps(Map<String, (DateTime, int)> now) async {
    final List<PatchOp> ops = <PatchOp>[];
    for (final MapEntry<String, (DateTime, int)> entry in now.entries) {
      final (DateTime, int)? before = _mtimes[entry.key];
      final bool unchanged = before != null && before == entry.value;
      if (unchanged) continue;
      final PatchOp? op = await _attributeOp(entry.key);
      if (op != null) ops.add(op);
    }
    return ops;
  }

  /// 内容归因：与引擎状态一致 = AI 自己写的（跳过）；块不存在 = 人新建
  /// （Insert）；不一致 = 人修改（Replace）。读回失败（非文本等）跳过。
  Future<PatchOp?> _attributeOp(String path) async {
    final String? text = await _readText(path);
    if (text == null) return null;
    final List<DocBlock> blocks = engine.state.blocks;
    final int at = indexOfBlock(blocks, path);
    if (at < 0) return InsertBlockOp(blockId: path, text: text);
    if (blocks[at].text == text) return null;
    return ReplaceBlockOp(blockId: path, text: text);
  }

  Future<String?> _readText(String path) async {
    try {
      return await File('$dir/$path').readAsString();
    } catch (error) {
      telemetry?.emit(
        TelemetryEvent(
          'story.watch_failed',
          data: <String, Object?>{'message': '读回 $path 失败：$error'},
        ),
      );
      return null;
    }
  }

  /// 当前快照：相对路径（`/` 分隔）→ mtime。目录不可读时跳过该子树。
  Future<Map<String, (DateTime, int)>> _snapshot() async {
    final Map<String, (DateTime, int)> out = <String, (DateTime, int)>{};
    await _walk(Directory(dir), '', out);
    return out;
  }

  Future<void> _walk(
    Directory current,
    String prefix,
    Map<String, (DateTime, int)> out,
  ) async {
    final List<FileSystemEntity> entries;
    try {
      entries = await current.list().toList();
    } catch (_) {
      return;
    }
    for (final FileSystemEntity entity in entries) {
      await _collect(entity, prefix, out);
    }
  }

  Future<void> _collect(
    FileSystemEntity entity,
    String prefix,
    Map<String, (DateTime, int)> out,
  ) async {
    final String name = entity.uri.pathSegments.lastWhere(
      (String s) => s.isNotEmpty,
      orElse: () => '',
    );
    if (entity is Directory) {
      if (!kStorySkipDirs.contains(name)) {
        await _walk(entity, '$prefix$name/', out);
      }
      return;
    }
    if (entity is! File) return;
    await _collectFile(entity, '$prefix$name', name, out);
  }

  Future<void> _collectFile(
    File file,
    String path,
    String name,
    Map<String, (DateTime, int)> out,
  ) async {
    final int dot = name.lastIndexOf('.');
    if (dot < 0 || !kStoryTextExtensions.contains(name.substring(dot))) return;
    try {
      out[path] = (await file.lastModified(), await file.length());
    } catch (_) {
      // 扫描窗口内被删的文件：跳过，删除语义 v1 不记。
    }
  }
}
