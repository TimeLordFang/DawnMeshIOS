import 'package:flutter/material.dart';

import '../../core/transport/lan_discovery.dart';
import '../../l10n/app_strings.dart';
import 'local_address_dialog.dart';

class IosNearbyInvite extends StatelessWidget {
  const IosNearbyInvite({super.key});
  @override
  Widget build(BuildContext context) {
    final english = AppStrings.of(context).isEn;
    return ListTile(
      leading: const Icon(Icons.lan_outlined),
      title: Text(english ? 'Notify a nearby Android phone' : '通知同网安卓设备'),
      subtitle: Text(
        english
            ? 'Enter its IP address so your room appears in its nearby list.'
            : '输入安卓手机的 IP 地址，让本房间出现在对方的附近列表中。',
      ),
      onTap: () async {
        final address = await requestLocalAddress(context, announcing: true);
        if (address == null || !context.mounted) return;
        LanRoomDiscovery.addUnicastTarget(address);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              english
                  ? 'Room invitations will be sent to ${address.address}'
                  : '已开始向 ${address.address} 发送房间发现信息',
            ),
          ),
        );
      },
    );
  }
}
