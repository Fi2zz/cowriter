/// 排队消息轮内注入：busy 时排队的消息在 Agent Loop 组下一次模型请求前
/// 经 steering 缝注入会话；注入后队列清空、轮末不重复发送；Esc 打断时已
/// 注入的消息留在会话。
library;

import 'dart:async';

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:cowriter/tui.dart';
import 'package:test/test.dart';

/// 第一次请求返回工具调用（工具等 [toolGate] 放行），第二次请求收口
/// （[hangSecond] 时等 [secondGate]，供 Esc 用例把轮次挂住）。
class _SteeringProvider implements LlmProvider {
  final Completer<void> toolGate = Completer<void>();
  final Completer<void> secondGate = Completer<void>();
  final List<List<LlmMessage>> calls = <List<LlmMessage>>[];
  bool hangSecond = false;

  @override
  String get name => 'steering';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    calls.add(List<LlmMessage>.of(messages));
    if (calls.length == 1) {
      return const LlmResult(
        content: '',
        provider: 'steering',
        model: 'm',
        toolCalls: <LlmToolCall>[LlmToolCall(id: 'c1', name: 'echo')],
      );
    }
    if (hangSecond) await secondGate.future;
    return const LlmResult(content: '收口', provider: 'steering', model: 'm');
  }

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) => const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}
}

Future<(ConatusTuiController, Context, _SteeringProvider)> _build({
  bool hangSecond = false,
}) async {
  final Context app = Context.root();
  provideTools(app);
  final _SteeringProvider provider = _SteeringProvider()
    ..hangSecond = hangSecond;
  provideLlm(app, llm: FallbackLlm(<LlmProvider>[provider]));
  app.tools.fn(
    'echo',
    description: '等门后回显',
    handler: (ToolContext ctx) async {
      await provider.toolGate.future;
      return ToolResult.success('ok');
    },
  );
  final SessionStore sessions = provideSessions(app);
  final ConatusTuiController controller = ConatusTuiController(
    app: app,
    sessions: sessions,
    name: 'test',
    modelLabel: 'mock',
    onExit: () {},
  );
  await controller.start();
  return (controller, app, provider);
}

/// 轮询直到 [cond] 成立（超时上限 2s）。
Future<void> _until(bool Function() cond) async {
  for (int i = 0; i < 400 && !cond(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(cond(), isTrue, reason: '条件未在超时内成立');
}

void main() {
  test('busy 时排队的消息在下一次请求边界注入，队列清空、轮末不重复发送', () async {
    final (controller, app, provider) = await _build();
    addTearDown(app.dispose);

    final Future<void> first = controller.handleLine('开始干活');
    await _until(() => provider.calls.isNotEmpty && controller.busy);

    await controller.handleLine('中途插话');
    expect(controller.queuedCount, 1);
    provider.toolGate.complete(); // 放行工具 → step 1 边界注入
    await _until(() => provider.calls.length >= 2);

    // 第二次请求的消息序列：tool 结果之后跟着注入的 user 插话。
    final List<LlmMessage> second = provider.calls[1];
    expect(second.last.role, 'user');
    expect(second.last.content, '中途插话');
    expect(second[second.length - 2].role, 'tool');
    expect(controller.queuedCount, 0);

    await first;
    await _until(() => !controller.busy);
    // 轮末 _drainQueue 对空队列无操作：模型调用总数停在 2，不重复发送。
    expect(provider.calls.length, 2);
  });

  test('Esc 打断时已注入的插话留在会话（说出去的话不收回）', () async {
    final (controller, app, provider) = await _build(hangSecond: true);
    addTearDown(app.dispose);

    final Future<void> first = controller.handleLine('开始干活');
    await _until(() => provider.calls.isNotEmpty && controller.busy);
    await controller.handleLine('插话留存');
    provider.toolGate.complete();
    await _until(() => provider.calls.length >= 2); // 已注入，第二次请求挂起

    controller.interrupt();
    await _until(() => !controller.busy);
    provider.secondGate.complete();
    await first;

    // 注入的插话作为 user 事件已上屏（会话事件在，不被打断收回）。
    expect(
      controller.transcript.messages.any(
        (TuiMessage m) => m.role == TuiRole.user && m.text == '插话留存',
      ),
      isTrue,
    );
    expect(controller.queuedCount, 0);
  });
}
