import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import 'apply_patch.dart';
import 'list_files.dart';

/// 注册 cowriter 的通用写作工具，返回已注册的工具。
///
/// 依赖：
/// - `'tools'`：工具注册（必需）
/// - `'fs'`：文件系统接缝（必需）
///
/// 注册撤销由上下文生命周期统一管理。
List<Tool> provideCodeTools(
  Context ctx, {
  ToolRegistry? tools,
  FileSystem? fs,
}) {
  final ToolRegistry registry = tools ?? ctx.tools;
  final FileSystem resolvedFs = fs ?? ctx.require<FileSystem>('fs');
  final List<Tool> registered = <Tool>[
    ListFilesTool(fs: resolvedFs),
    ApplyPatchTool(fs: resolvedFs),
  ];
  for (final Tool tool in registered) {
    ctx.effect(() => registry.register(tool));
  }
  return registered;
}
