import 'package:flutter/material.dart';

import 'test_app_log_service.dart';

class TestAppLogPage extends StatelessWidget {
  const TestAppLogPage({super.key});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: TestAppLogService.instance,
    builder: (context, _) {
      final entries = TestAppLogService.instance.entries;
      return Scaffold(
        appBar: AppBar(
          title: Text('应用日志 (${entries.length})'),
          actions: [
            IconButton(
              tooltip: '清空日志',
              onPressed: entries.isEmpty
                  ? null
                  : TestAppLogService.instance.clear,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        body: entries.isEmpty
            ? const Center(child: Text('等待 com_host 消息回调…'))
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: entries.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) =>
                    _TestLogTile(entry: entries[index]),
              ),
      );
    },
  );
}

class _TestLogTile extends StatelessWidget {
  const _TestLogTile({required this.entry});

  final TestAppLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final nativeLevel = switch (entry.level) {
      0 => 'DEBUG',
      1 => 'INFO',
      2 => 'WARN',
      3 => 'ERROR',
      _ => null,
    };
    if (entry.text != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${entry.formattedTime}  ${entry.source}  ${nativeLevel ?? 'LOG'}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            SelectableText(
              entry.text!,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ],
        ),
      );
    }
    final kind = entry.isAck ? 'ACK' : 'MSG';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${entry.formattedTime}  ${entry.source} $kind  ID=0x${entry.messageId.toRadixString(16).padLeft(4, '0').toUpperCase()}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'sender=0x${entry.sender.toRadixString(16).padLeft(2, '0').toUpperCase()}  '
            'seq=${entry.sequence}  len=${entry.dataLength}  '
            'needAck=${entry.needsAck}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          SelectableText(
            entry.dataHex.isEmpty ? '(空 payload)' : entry.dataHex,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ],
      ),
    );
  }
}
