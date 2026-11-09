import 'dart:async';

import 'package:flutter/material.dart';

import 'com_host_service.dart';
import 'device_page.dart';
import 'ega_status.dart';

/// EGA guitar amplifier page, sharing the base device connection lifecycle.
class EgaDevicePage extends DevicePage {
  const EgaDevicePage({super.key});

  @override
  String get pageTitle => '电吉他音箱';

  @override
  Widget buildDeviceContent(BuildContext context) => const _EgaDeviceContent();
}

class _EgaDeviceContent extends StatefulWidget {
  const _EgaDeviceContent();

  @override
  State<_EgaDeviceContent> createState() => _EgaDeviceContentState();
}

class _EgaDeviceContentState extends State<_EgaDeviceContent> {
  static const _subscriptionRefreshInterval = Duration(seconds: 2);

  StreamSubscription<ComHostMessage>? _statusSubscription;
  Timer? _subscriptionTimer;
  EgaStatus? _status;
  String? _error;

  @override
  void initState() {
    super.initState();
    _statusSubscription = ComHostService.instance.messages.listen(
      _handleMessage,
      onError: _handleStreamError,
    );
    _sendStatusSubscription();
    _subscriptionTimer = Timer.periodic(
      _subscriptionRefreshInterval,
      (_) => _sendStatusSubscription(),
    );
  }

  void _sendStatusSubscription() {
    try {
      final sequence = ComHostService.instance.send(
        EgaStatus.subscriptionMessageId,
        EgaStatus.buildSubscriptionPayload(),
        needAck: true,
      );
      if (sequence < 0) {
        throw StateError('com_host 发送失败：$sequence');
      }
    } catch (error) {
      if (mounted) setState(() => _error = '状态订阅失败：$error');
    }
  }

  void _handleMessage(ComHostMessage message) {
    if (message.id == EgaStatus.subscriptionMessageId && message.isAck) {
      _handleSubscriptionAck(message);
      return;
    }
    if (message.id != EgaStatus.pushMessageId || message.isAck) return;
    try {
      final status = EgaStatus.fromBytes(message.data);
      if (mounted) {
        setState(() {
          _status = status;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '状态解析失败：$error');
    }
  }

  void _handleSubscriptionAck(ComHostMessage message) {
    final result = message.data.isEmpty ? null : message.data.first;
    if (result == 0) {
      if (mounted && _error?.startsWith('状态订阅') == true) {
        setState(() => _error = null);
      }
      return;
    }
    if (mounted) {
      setState(() {
        _error = result == null ? '状态订阅应答为空' : '状态订阅被设备拒绝，结果码：$result';
      });
    }
  }

  void _handleStreamError(Object error) {
    if (mounted) setState(() => _error = '状态接收失败：$error');
  }

  @override
  void dispose() {
    _subscriptionTimer?.cancel();
    _statusSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return ColoredBox(
      color: const Color(0xff101113),
      child: status == null
          ? _WaitingStatus(error: _error)
          : _StatusDashboard(status: status, error: _error),
    );
  }
}

class _WaitingStatus extends StatelessWidget {
  const _WaitingStatus({required this.error});

  final String? error;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            error == null ? Icons.graphic_eq : Icons.error_outline,
            color: error == null ? const Color(0xffffb43b) : Colors.redAccent,
            size: 52,
          ),
          const SizedBox(height: 16),
          Text(
            error ?? '等待 EGA 状态推送…',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ],
      ),
    ),
  );
}

class _StatusDashboard extends StatelessWidget {
  const _StatusDashboard({required this.status, required this.error});

  final EgaStatus status;
  final String? error;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(status: status),
        if (error != null) ...[
          const SizedBox(height: 12),
          _ErrorBanner(message: error!),
        ],
        const SizedBox(height: 12),
        _PresetPanel(status: status),
        const SizedBox(height: 12),
        _SectionCard(
          title: '连接状态',
          icon: Icons.hub_outlined,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusPill(
                icon: Icons.bluetooth,
                label: 'BLE',
                enabled: status.bleEnabled,
                active: status.bleConnected,
              ),
              _StatusPill(
                icon: Icons.podcasts,
                label: 'UHF',
                enabled: status.uhfEnabled,
                active: status.uhfConnected,
              ),
              _StatusPill(
                icon: Icons.usb,
                label: 'USB',
                enabled: true,
                active: status.usbConnected,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _DrummerPanel(status: status),
        const SizedBox(height: 12),
        _SectionCard(
          title: '系统',
          icon: Icons.memory,
          child: Row(
            children: [
              Expanded(
                child: _Metric(
                  label: 'CPU 负载',
                  value: _cpuLoadName(status.cpuLoad),
                  color: _cpuLoadColor(status.cpuLoad),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Metric(
                  label: '预设状态',
                  value: status.currentPresetDirty ? '未保存' : '已保存',
                  color: status.currentPresetDirty
                      ? const Color(0xffffb43b)
                      : const Color(0xff55d68b),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  static String _cpuLoadName(int value) => switch (value) {
    0 => '轻',
    1 => '一般',
    2 => '较大',
    3 => '紧急',
    _ => '未知',
  };

  static Color _cpuLoadColor(int value) => switch (value) {
    0 => const Color(0xff55d68b),
    1 => const Color(0xffffd166),
    2 => const Color(0xffff9f43),
    _ => const Color(0xffff5c5c),
  };
}

class _Header extends StatelessWidget {
  const _Header({required this.status});

  final EgaStatus status;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xffffb43b),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.electric_bolt, color: Colors.black, size: 25),
      ),
      const SizedBox(width: 12),
      const Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'EGA',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
            Text(
              'ELECTRIC GUITAR AMPLIFIER',
              style: TextStyle(color: Colors.white54, fontSize: 10),
            ),
          ],
        ),
      ),
      _BatteryBadge(status: status),
    ],
  );
}

class _BatteryBadge extends StatelessWidget {
  const _BatteryBadge({required this.status});

  final EgaStatus status;

  @override
  Widget build(BuildContext context) {
    final color = status.batteryPercent <= 15
        ? const Color(0xffff5c5c)
        : const Color(0xff55d68b);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            status.batteryCharging
                ? Icons.battery_charging_full
                : Icons.battery_std,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 5),
          Text(
            '${status.batteryPercent}%',
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _PresetPanel extends StatelessWidget {
  const _PresetPanel({required this.status});

  final EgaStatus status;

  @override
  Widget build(BuildContext context) {
    final valid =
        status.currentPresetIndex >= 1 && status.currentPresetIndex <= 20;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xff29251d), Color(0xff1b1c1f)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xff51472f)),
      ),
      child: Row(
        children: [
          Container(
            width: 88,
            height: 88,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xffffb43b),
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x44ffb43b),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Text(
              valid
                  ? status.currentPresetIndex.toString().padLeft(2, '0')
                  : '--',
              style: const TextStyle(
                color: Colors.black,
                fontSize: 42,
                height: 1,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CURRENT PRESET',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
                const SizedBox(height: 5),
                Text(
                  valid ? 'Preset ${status.currentPresetIndex}' : '无效预设',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      status.currentPresetDirty
                          ? Icons.edit_note
                          : Icons.check_circle_outline,
                      color: status.currentPresetDirty
                          ? const Color(0xffffb43b)
                          : const Color(0xff55d68b),
                      size: 18,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      status.currentPresetDirty ? '有未保存修改' : '已保存',
                      style: TextStyle(
                        color: status.currentPresetDirty
                            ? const Color(0xffffb43b)
                            : const Color(0xff55d68b),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DrummerPanel extends StatelessWidget {
  const _DrummerPanel({required this.status});

  final EgaStatus status;

  @override
  Widget build(BuildContext context) {
    final validType = status.drummerType >= 1 && status.drummerType <= 20;
    final bpm = status.bpmRaw <= 220 ? status.bpmRaw + 40 : null;
    return _SectionCard(
      title: '鼓机',
      icon: Icons.music_note,
      trailing: _LiveBadge(active: status.drummerPlaying),
      child: Row(
        children: [
          Expanded(
            child: _Metric(
              label: '节奏类型',
              value: validType ? '${status.drummerType}' : '--',
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _Metric(
              label: 'BPM',
              value: bpm?.toString() ?? '--',
              color: const Color(0xffffb43b),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _Metric(
              label: '音量',
              value: '${status.drummerVolume}%',
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xff1b1c1f),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xff303237)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, color: const Color(0xffffb43b), size: 19),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: 14),
        child,
      ],
    ),
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.active,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? const Color(0xff55d68b)
        : enabled
        ? const Color(0xffffb43b)
        : Colors.white38;
    final state = active
        ? '已连接'
        : enabled
        ? '未连接'
        : '未启用';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 7),
          Text(
            '$label  $state',
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xff24262a),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xff55d68b) : Colors.white38;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 7, color: color),
          const SizedBox(width: 5),
          Text(
            active ? '播放中' : '已停止',
            style: TextStyle(color: color, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.redAccent.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline, color: Colors.redAccent, size: 19),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: Colors.redAccent, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}
