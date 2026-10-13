import 'dart:io';

import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';

Future<InternetAddress?> requestLocalAddress(
  BuildContext context, {
  bool announcing = false,
}) => showDialog<InternetAddress>(
  context: context,
  builder: (_) => _LocalAddressDialog(
    english: AppStrings.of(context).isEn,
    announcing: announcing,
  ),
);

class _LocalAddressDialog extends StatefulWidget {
  const _LocalAddressDialog({required this.english, required this.announcing});
  final bool english;
  final bool announcing;
  @override
  State<_LocalAddressDialog> createState() => _LocalAddressDialogState();
}

class _LocalAddressDialogState extends State<_LocalAddressDialog> {
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final english = widget.english;
    final announcing = widget.announcing;
    final candidate = InternetAddress.tryParse(controller.text.trim());
    final valid =
        candidate != null &&
        candidate.type == InternetAddressType.IPv4 &&
        !candidate.isLoopback &&
        candidate.address != '0.0.0.0' &&
        candidate.address != '255.255.255.255';
    return AlertDialog(
      title: Text(
        announcing
            ? (english ? 'Notify Android' : '通知安卓设备')
            : (english ? 'Join on the same network' : '通过同网地址加入'),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              english
                  ? (announcing
                        ? 'Enter the Android phone’s IPv4 address on the same network.'
                        : 'Connect both phones to the same Wi-Fi or hotspot, then enter the host’s IPv4 address.')
                  : (announcing
                        ? '输入同一 Wi-Fi 或热点中安卓手机的 IPv4 地址。'
                        : '先连接同一个 Wi-Fi 或热点，再输入房主手机的 IPv4 地址。'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: announcing
                    ? (english ? 'Android IP address' : '安卓设备 IP 地址')
                    : (english ? 'Host IP address' : '房主 IP 地址'),
                hintText: '192.168.1.20',
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (valid) Navigator.pop(context, candidate);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(english ? 'Cancel' : '取消'),
        ),
        FilledButton(
          onPressed: valid ? () => Navigator.pop(context, candidate) : null,
          child: Text(english ? 'Continue' : '继续'),
        ),
      ],
    );
  }
}
