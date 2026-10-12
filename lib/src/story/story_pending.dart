/// 待应用补丁通道（第二通道）：模型在 ```` ```ops ```` 围栏块里**提议**修改，
/// 人审阅后 `/story apply <i>` 才生效。
///
/// pending 是临时态：不落 story-log，随会话子上下文释放。应用成功才走
/// 正常 `DocEngine.commit` 落 `doc/patch` 事件。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_doc/conatus_doc.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

/// 编译助手文本里的 ops 块；无块或编译失败（普通回复里自然出现的
/// ```` ``` ```` 块）都返回空——绝不因此炸会话。
List<PatchOp> tryCompileOps(String text) {
  try {
    return compileOpsBlock(text);
  } on FormatException {
    return const <PatchOp>[];
  } on ArgumentError {
    return const <PatchOp>[];
  }
}

/// 会话级的待应用补丁列表。
class StoryPending {
  final List<DocPatch> _patches = <DocPatch>[];
  int _seq = 0;

  /// 待应用补丁（追加序）。
  List<DocPatch> get patches => List<DocPatch>.unmodifiable(_patches);

  /// 喂入一条助手回复；编译出非空 ops 时存为一个待应用补丁。
  void feed(String text) {
    final List<PatchOp> ops = tryCompileOps(text);
    if (ops.isEmpty) return;
    _seq += 1;
    _patches.add(
      DocPatch(
        id: 'pending-${DateTime.now().microsecondsSinceEpoch}-$_seq',
        author: PatchAuthor.ai,
        ops: ops,
      ),
    );
  }

  /// 应用第 [index] 个（1 起）：逐 op 经 fs 缝写文件，全部成功后 commit
  /// 进引擎并从 pending 移除。返回面向用户的说明文本。
  Future<String> apply(int index, DocEngine engine, FileSystem? fs) async {
    if (index < 1 || index > _patches.length) {
      return '没有第 $index 个待应用补丁（/story pending 查看列表）。';
    }
    final DocPatch patch = _patches[index - 1];
    final String? refusal = _unsupportedOp(patch, index);
    if (refusal != null) return refusal;
    final FileSystem? seam = fs;
    if (seam == null) return 'fs 缝不可用，无法应用。';
    return _writeAndCommit(index, patch, engine, seam);
  }

  /// v1 只支持 Insert / Replace（写文件语义）；Remove / Move 拒绝整个补丁。
  String? _unsupportedOp(DocPatch patch, int index) {
    for (final PatchOp op in patch.ops) {
      if (op is InsertBlockOp || op is ReplaceBlockOp) continue;
      return '第 $index 个补丁含 ${op.runtimeType} '
          '（删除/移动块），v1 不支持应用，请手动处理后驳回。';
    }
    return null;
  }

  Future<String> _writeAndCommit(
    int index,
    DocPatch patch,
    DocEngine engine,
    FileSystem fs,
  ) async {
    for (final PatchOp op in patch.ops) {
      final String text = switch (op) {
        InsertBlockOp() => op.text,
        ReplaceBlockOp() => op.text,
        _ => '',
      };
      await fs.writeText(await fs.resolve(op.blockId), text);
    }
    _patches.removeAt(index - 1);
    await engine.commit(
      DocPatch(
        id: 'story-${DateTime.now().microsecondsSinceEpoch}-a$index',
        author: PatchAuthor.ai,
        ops: patch.ops,
      ),
    );
    return '已应用第 $index 个补丁（${patch.ops.length} 个文件），并入故事线。';
  }
}

/// 渲染待应用列表（`/story pending` 输出）。
String renderStoryPending(List<DocPatch> patches) {
  if (patches.isEmpty) return '没有待应用补丁。';
  final StringBuffer buffer = StringBuffer('待应用补丁（${patches.length}）：');
  for (final (int index, DocPatch patch) in patches.indexed) {
    final String ops = patch.ops
        .map((PatchOp op) => '${op.runtimeType}(${op.blockId})')
        .join(', ');
    buffer.write('\n  ${index + 1}. $ops');
  }
  return buffer.toString();
}

/// 订阅会话的助手消息事件，把含 ops 块的回复喂进 [pending]。
/// 返回撤销函数（随会话子上下文释放）。
Disposer bindStoryPending(Context ctx, Session session, StoryPending pending) {
  ctx.provide('storyPending', pending);
  return session.onEvent((SessionEvent event) {
    if (event.type != kAssistantMessageEvent) return;
    pending.feed(_assistantText(event.data));
  });
}

String _assistantText(Object? data) {
  if (data is! Map) return '';
  final Object? text = data['text'];
  return text is String ? text : '';
}
