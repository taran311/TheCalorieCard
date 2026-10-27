import 'package:flutter/material.dart';
import 'package:namer_app/services/friends_service.dart';
import 'package:namer_app/services/split_service.dart';
import 'package:namer_app/ui/calorie_symbol.dart';
import 'package:namer_app/ui/responsive.dart';

/// What was picked in [SplitSheet]: who with, and your share (a third is
/// 1/3); friends split the rest evenly.
class SplitChoice {
  final List<String> friendIds;
  final double mine;

  const SplitChoice(this.friendIds, this.mine);
}

/// Pick who you shared with and how much was yours (an even split unless
/// you say otherwise); shows everyone's share as you pick. Pops with a
/// [SplitChoice].
///
/// [alreadyLogged]: splitting a food that's already on your card, so the
/// button says yours comes down to your share rather than being added.
class SplitSheet extends StatefulWidget {
  final List<Friend> friends;
  final List<Map<String, dynamic>> items;
  final bool alreadyLogged;

  const SplitSheet({
    super.key,
    required this.friends,
    required this.items,
    this.alreadyLogged = false,
  });

  @override
  State<SplitSheet> createState() => _SplitSheetState();
}

class _SplitSheetState extends State<SplitSheet> {
  final Set<String> _chosen = {};

  /// Your share, if you picked one; otherwise an even split.
  double? _mine;

  /// Shares to pick from, smallest first: the even split, and the usual
  /// "I had less / more" amounts.
  static List<double> _options(int people) {
    final even = 1 / people;
    final out = <double>[even];
    for (final f in const [1 / 4, 1 / 3, 1 / 2, 2 / 3, 3 / 4]) {
      if (out.every((o) => (o - f).abs() > 0.004)) out.add(f);
    }
    return out..sort();
  }

  @override
  Widget build(BuildContext context) {
    final people = _chosen.length + 1;
    final even = 1 / (people < 2 ? 2 : people);
    final mine = _mine ?? even;
    final friends = _chosen.isEmpty ? 1 : _chosen.length;
    // Exactly what each person will log (rounded per item).
    final share = SplitService.caloriesAt(widget.items, mine).round();
    final theirs = SplitService.caloriesAt(
            widget.items, SplitService.friendShare(mine, friends))
        .round();
    final isEven = (mine - even).abs() < 0.004;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Split the bill',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                _chosen.isEmpty
                    ? 'Who did you share it with?'
                    : isEven
                        ? 'Split $people ways: everyone gets $calSym$share'
                        : 'You $calSym$share · '
                            '${friends == 1 ? 'them' : 'each friend'} '
                            '$calSym$theirs',
                style: TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final f in widget.friends)
                      CheckboxListTile(
                        value: _chosen.contains(f.id),
                        title: Text(f.name),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _chosen.add(f.id);
                          } else {
                            _chosen.remove(f.id);
                          }
                        }),
                      ),
                  ],
                ),
              ),
              if (_chosen.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Your share',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: AppColors.ink)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final f in _options(people))
                      ChoiceChip(
                        label: Text((f - even).abs() < 0.004
                            ? 'Even (${SplitService.fractionLabel(f)})'
                            : SplitService.fractionLabel(f)),
                        selected: (f - mine).abs() < 0.004,
                        // "Even" stays even if more friends are picked.
                        onSelected: (_) => setState(() =>
                            _mine = (f - even).abs() < 0.004 ? null : f),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _chosen.isEmpty
                      ? null
                      : () => Navigator.pop(
                          context, SplitChoice(_chosen.toList(), mine)),
                  icon: const Icon(Icons.call_split),
                  label: Text(_chosen.isEmpty
                      ? 'Pick friends'
                      : widget.alreadyLogged
                          ? 'Keep my $calSym$share & send requests'
                          : 'Add my $calSym$share & send requests'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
