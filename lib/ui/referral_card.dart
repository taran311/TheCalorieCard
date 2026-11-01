import 'package:flutter/material.dart';
import 'package:namer_app/services/referrals.dart';
import 'package:namer_app/ui/profile_editors.dart' show formatGoalDate;
import 'package:namer_app/ui/responsive.dart';

/// A quiet "Invite a friend: a free month each" line under your friends,
/// with how invites are getting on only when there's something to show.
/// [onShare] shares your invite link.
class ReferralCard extends StatelessWidget {
  final VoidCallback onShare;

  const ReferralCard({super.key, required this.onShare});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ReferralStatus?>(
      valueListenable: Referrals.status,
      builder: (context, s, _) {
        final st = s ?? const ReferralStatus();
        final need = st.daysNeeded;
        final lines = <String>[];

        final me = st.invitedBy;
        if (me != null && me.pending) {
          final left = (need - me.days).clamp(1, need);
          lines.add('Log food on $left more day${left == 1 ? '' : 's'} and '
              'you and ${me.name} both get ${st.rewardLabel} free.');
        }
        for (final f in st.friends) {
          lines.add(f.rewarded
              ? '${f.name}: ${st.rewardLabel} each, earned'
              : '${f.name}: ${f.days.clamp(0, need)} of $need days');
        }
        final until = st.bonusUntil;
        if (until != null) {
          lines.add('Free Premium until ${formatGoalDate(until)}');
        }

        final muted = TextStyle(fontSize: 12.5, color: AppColors.muted);
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: onShare,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.card_giftcard_rounded,
                          size: 18, color: AppText.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Invite a friend: ${st.rewardLabel} of Premium '
                          'each once they\'ve logged $need days',
                          style: TextStyle(
                              fontSize: 13.5, color: AppColors.gray700),
                        ),
                      ),
                      Icon(Icons.ios_share_rounded,
                          size: 18, color: AppText.primary),
                    ],
                  ),
                ),
              ),
              for (final l in lines)
                Padding(
                  padding: const EdgeInsets.fromLTRB(30, 0, 4, 4),
                  child: Text(l, style: muted),
                ),
            ],
          ),
        );
      },
    );
  }
}
