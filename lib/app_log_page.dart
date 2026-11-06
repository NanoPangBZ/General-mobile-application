import 'package:flutter/material.dart';

import 'app_log_service.dart';

class AppLogPage extends StatelessWidget {
  const AppLogPage({super.key});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: AppLogService.instance,
        builder: (context, _) {
          final entries = AppLogService.instance.entries;
          return Scaffold(
            appBar: AppBar(
              title: Text('应用日志 (${entries.length})'),
              actions: [
                IconButton(
                  tooltip: '清空日志',
                  onPressed: entries.isEmpty ? null : AppLogService.instance.clear,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            body: entries.isEmpty
                ? const Center(child: Text('等待 com_host 消息回调…'))
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) => _LogTile(entry: entries[index]),
                  ),
          );
        },
      );
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.entry});

  final AppLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final kind = entry.isAck ? 'ACK' : 'MSG';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${entry.formattedTime}  $kind  ID=0x${entry.messageId.toRadixString(16).padLeft(4, '0').toUpperCase()}',
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
