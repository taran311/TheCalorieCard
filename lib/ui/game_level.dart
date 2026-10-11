import 'package:flutter/material.dart';
import 'package:namer_app/services/games_service.dart';
import 'package:namer_app/ui/responsive.dart';

/// Your Games level: badge, title and progress to the next level.
class LevelCard extends StatelessWidget {
  final GamesProgress progress;

  /// Smaller, for the end of a round.
  final bool compact;

  const LevelCard({super.key, required this.progress, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final level = progress.level;
    final white = Colors.white.withValues(alpha: 0.92);
    return Semantics(
      container: true,
      label: 'Level ${level.level}, ${level.title}. '
          '${level.toNext} XP to level ${level.level + 1}.',
      child: ExcludeSemantics(
        child: Container(
          padding: EdgeInsets.all(compact ? 14 : 18),
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: BorderRadius.circular(AppDecor.radius),
          ),
          child: Row(
            children: [
              _Badge(level: level, size: compact ? 52 : 64),
              SizedBox(width: compact ? 12 : 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Level ${level.level} · ${level.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 16 : 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: level.progress,
                        minHeight: 8,
                        color: Colors.white,
                        backgroundColor: Colors.white.withValues(alpha: 0.25),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${level.toNext} XP to level ${level.level + 1}'
                      '${compact ? '' : ' · ${progress.monthXp} XP this month'}',
                      style: TextStyle(
                        color: white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final GameLevel level;
  final double size;
  const _Badge({required this.level, required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.6), width: 2),
            ),
            child: Text(level.emoji, style: TextStyle(fontSize: size * 0.46)),
          ),
          Positioned(
            right: -4,
            bottom: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${level.level}',
                style: const TextStyle(
                  color: AppColors.primaryDark,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "+8 XP", for the moment a guess is revealed.
class XpPill extends StatelessWidget {
  final int xp;
  const XpPill(this.xp, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.violet50,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '+$xp XP',
        style: TextStyle(
          color: AppText.violet600,
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
      ),
    );
  }
}

/// Celebrates a level up (does nothing otherwise).
Future<void> celebrateLevelUp(BuildContext context, XpResult result) async {
  if (!result.levelledUp || !context.mounted) return;
  final before = Levels.of(result.before);
  final after = result.level;
  final newTitle = after.title != before.title;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Text(after.emoji, style: const TextStyle(fontSize: 48)),
      title: Text('Level ${after.level}!', textAlign: TextAlign.center),
      content: Text(
        newTitle
            ? "You're now a ${after.title}. Your calorie sense is getting "
                'sharp.'
            : 'Nice work. ${after.needed} XP to the next level.',
        textAlign: TextAlign.center,
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Keep going'),
        ),
      ],
    ),
  );
}

/// The rules, from the Games page's ⓘ button.
void showXpRules(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      Widget line(String emoji, String text) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                    width: 30,
                    child: Text(emoji, style: const TextStyle(fontSize: 18))),
                Expanded(
                  child: Text(text,
                      style: TextStyle(
                          fontSize: 14, height: 1.35, color: AppColors.ink)),
                ),
              ],
            ),
          );
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('How XP works',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: AppColors.ink)),
              const SizedBox(height: 12),
              line('🎯',
                  'Every guess earns up to 10 XP. The closer you are, the more you get.'),
              line('📅',
                  'Daily challenge: finish all ${GamesService.dailyRounds} for +${Xp.dailyBonus} XP. One go a day, the same foods for everyone.'),
              line('🍽️',
                  'Guess the Meal: your first ${Xp.mealRoundsPerDay} rounds each day earn XP. Play as much as you like after that for practice.'),
              line('🏆',
                  'Friend games: XP for your guesses, plus ${Xp.winBonus} for a win or ${Xp.drawBonus} for a draw.'),
              line('📈',
                  'Each level needs a little more XP than the last. Your level is on your Games page, never on your card.'),
              const SizedBox(height: 6),
              Text(
                'Calories use UK labels and standard portions. Real meals '
                'vary, so treat them as a guide.',
                style: TextStyle(fontSize: 12.5, color: AppColors.muted),
              ),
            ],
          ),
        ),
      );
    },
  );
}
