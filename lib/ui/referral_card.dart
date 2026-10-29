import 'package:flutter/material.dart';
import 'package:namer_app/services/referrals.dart';
import 'package:namer_app/ui/profile_editors.dart' show formatGoalDate;
import 'package:namer_app/ui/responsive.dart';

/// "Invite a friend, you both get a month of Premium", with how your
/// invites are getting on. [onShare] shares your invite link.
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
        final lines = <Widget>[];

        final me = st.invitedBy;
        if (me != null && me.pending) {
          final left = (need - me.days).clamp(1, need);
          lines.add(_line(
            Icons.hourglass_bottom_rounded,
            'You joined with ${me.name}. Log food on $left more '
            'day${left == 1 ? '' : 's'} and you both get ${st.rewardLabel} '
            'of Premium.',
          ));
        }
        for (final f in st.friends) {
          lines.add(_line(
            f.rewarded ? Icons.check_circle_rounded : Icons.person_outline,
            f.rewarded
                ? '${f.name}: ${st.rewardLabel} each, earned'
                : '${f.name}: ${f.days.clamp(0, need)} of $need days logged',
            done: f.rewarded,
          ));
        }
        final until = st.bonusUntil;
        if (until != null) {
          lines.add(_line(Icons.auto_awesome_rounded,
              'Free Premium until ${formatGoalDate(until)}',
              done: true));
        }

        return Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          decoration: AppDecor.card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2, right: 10),
                    child: Text('🎁', style: TextStyle(fontSize: 22)),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Invite a friend, you both get ${st.rewardLabel} '
                          'of Premium',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Once they\'ve joined and logged food on $need '
                          'different days.',
                          style:
                              TextStyle(fontSize: 13, color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (lines.isNotEmpty) ...[
                const SizedBox(height: 10),
                ...lines,
              ],
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onShare,
                  icon: const Icon(Icons.ios_share_rounded, size: 18),
                  label: const Text('Share my invite link'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static Widget _line(IconData icon, String text, {bool done = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon,
              size: 18,
              color: done ? AppText.emerald600 : AppColors.gray600),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 13.5, color: AppColors.gray700)),
          ),
        ],
      ),
    );
  }
}
