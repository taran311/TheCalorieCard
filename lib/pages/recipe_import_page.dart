import 'package:flutter/material.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/food_resolver.dart';
import 'package:namer_app/services/recipe_import.dart';
import 'package:namer_app/ui/responsive.dart';

/// Turning recipe screenshots or photos into ingredients, in three steps:
/// read the images, let the person check what was read, then look each
/// one up and compare our calories with the screenshot's.
///
/// Pops with the `List<ImportedIngredient>` to add (or nothing). The
/// recipe's title and servings, if the image showed them, are passed to
/// [onDetails] so the recipe page can fill in empty fields.
class RecipeImportPage extends StatefulWidget {
  final List<({List<int> bytes, String mime})> images;
  final void Function(String title, double? servings)? onDetails;

  const RecipeImportPage({super.key, required this.images, this.onDetails});

  @override
  State<RecipeImportPage> createState() => _RecipeImportPageState();
}

enum _Stage { reading, review, lookingUp, compare, failed }

class _Line {
  final TextEditingController query;
  final ImportedLine read;
  ResolvedFood? found;

  /// Use the screenshot's calories (with our macro split) for this line.
  bool useShown = false;

  _Line(this.read) : query = TextEditingController(text: read.query);

  int? get shown => read.shownKcal;
  bool get canMatch => shown != null;

  Macros get ours => found == null
      ? Macros.zero
      : Macros(
          calories: found!.calories,
          protein: found!.protein,
          carbs: found!.carbs,
          fat: found!.fat,
        );

  /// What goes into the recipe for this line, or null to leave it out.
  Macros? get chosen {
    if (found == null) {
      // Not found: the screenshot's calories are all we have.
      return shown == null ? null : Macros(calories: shown!.toDouble());
    }
    if (useShown && shown != null) {
      return RecipeImport.matchCalories(ours, shown!.toDouble());
    }
    return ours;
  }
}

class _RecipeImportPageState extends State<RecipeImportPage> {
  _Stage _stage = _Stage.reading;
  String _error = '';
  final List<_Line> _lines = [];
  int _done = 0;

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void dispose() {
    for (final l in _lines) {
      l.query.dispose();
    }
    super.dispose();
  }

  Future<void> _read() async {
    setState(() {
      _stage = _Stage.reading;
      _error = '';
    });
    try {
      final r = await RecipeImport.read(widget.images);
      if (!mounted) return;
      if (r.lines.isEmpty) {
        setState(() {
          _stage = _Stage.failed;
          _error = "We couldn't find an ingredient list in "
              '${widget.images.length == 1 ? 'that image' : 'those images'}. '
              'Try a clearer screenshot of just the ingredients.';
        });
        return;
      }
      widget.onDetails?.call(r.title, r.servings);
      setState(() {
        _lines.addAll(r.lines.map(_Line.new));
        _stage = _Stage.review;
      });
    } on RecipeImportException catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.failed;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.failed;
        _error = "Couldn't read that. Check your connection and try again.";
      });
    }
  }

  List<_Line> get _kept =>
      _lines.where((l) => l.query.text.trim().isNotEmpty).toList();

  Future<void> _lookUp() async {
    final lines = _kept;
    if (lines.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _stage = _Stage.lookingUp;
      _done = 0;
      for (final l in _lines) {
        if (!lines.contains(l)) l.query.dispose();
      }
      _lines
        ..clear()
        ..addAll(lines);
    });
    final queries = [for (final l in lines) l.query.text.trim()];
    try {
      final results = await FoodResolver.resolveAll(
        queries,
        onProgress: (done, _) {
          if (mounted) setState(() => _done = done);
        },
      );
      if (!mounted) return;
      setState(() {
        for (var i = 0; i < lines.length && i < results.length; i++) {
          lines[i].found = results[i];
          lines[i].useShown = false;
        }
        _stage = _Stage.compare;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.review;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Couldn't look those up. Try again?")));
    }
  }

  void _finish() {
    final out = <ImportedIngredient>[];
    for (final l in _lines) {
      final m = l.chosen;
      if (m == null) continue;
      out.add(ImportedIngredient(
        name: l.query.text.trim(),
        macros: m,
        portion: l.found?.portion ?? '',
      ));
    }
    Navigator.of(context).pop(out);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_stage == _Stage.compare
            ? 'Check against your screenshot'
            : 'Import a recipe'),
      ),
      body: SafeArea(child: _body()),
      bottomNavigationBar: _bottomBar(),
    );
  }

  Widget? _bottomBar() {
    Widget bar(String label, VoidCallback? onPressed) => SafeArea(
          minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48)),
            onPressed: onPressed,
            child: Text(label),
          ),
        );
    switch (_stage) {
      case _Stage.review:
        final n = _kept.length;
        return bar('Look up $n ingredient${n == 1 ? '' : 's'}',
            n == 0 ? null : _lookUp);
      case _Stage.compare:
        final n = _lines.where((l) => l.chosen != null).length;
        return bar('Add $n ingredient${n == 1 ? '' : 's'} to recipe',
            n == 0 ? null : _finish);
      default:
        return null;
    }
  }

  Widget _body() {
    switch (_stage) {
      case _Stage.reading:
        return _waiting('Reading your recipe…',
            'This takes about 10 seconds.');
      case _Stage.lookingUp:
        return _waiting('Looking up ingredients…',
            '$_done of ${_lines.length} done');
      case _Stage.failed:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.image_not_supported_outlined, size: 48),
                const SizedBox(height: 12),
                Text(_error, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Back'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _read,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      case _Stage.review:
        return _review();
      case _Stage.compare:
        return _compare();
    }
  }

  Widget _waiting(String title, String subtitle) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(title,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(color: AppColors.muted)),
          ],
        ),
      );

  // ── Step 1: check what was read ────────────────────────────────────────

  Widget _review() {
    final unclear = _lines.where((l) => l.read.unclear).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text(
          'Here’s what we read. Fix anything that’s wrong, then we’ll '
          'look each one up. Adding brands and grams makes it more accurate.',
          style: TextStyle(color: AppColors.muted),
        ),
        if (unclear > 0) ...[
          const SizedBox(height: 12),
          _note(
            Icons.help_outline,
            AppColors.amber700,
            '$unclear ${unclear == 1 ? 'line was' : 'lines were'} hard to '
            'read. Check the ones marked below.',
          ),
        ],
        const SizedBox(height: 12),
        for (var i = 0; i < _lines.length; i++) _reviewRow(i),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add an ingredient'),
            onPressed: () => setState(() => _lines.add(
                _Line(const ImportedLine(query: '', asWritten: '')))),
          ),
        ),
      ],
    );
  }

  Widget _reviewRow(int i) {
    final l = _lines[i];
    final written = l.read.asWritten;
    final showWritten = written.isNotEmpty &&
        written.toLowerCase() != l.query.text.trim().toLowerCase();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: l.query,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                isDense: true,
                helperText: l.read.unclear
                    ? 'Hard to read: we took “$written” as this'
                    : showWritten
                        ? 'Shown as “$written”'
                        : null,
                helperMaxLines: 2,
                helperStyle: l.read.unclear
                    ? TextStyle(color: AppColors.amber700)
                    : null,
                prefixIcon: l.read.unclear
                    ? Icon(Icons.help_outline, color: AppColors.amber700)
                    : null,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.close),
            onPressed: () => setState(() {
              _lines.removeAt(i).query.dispose();
            }),
          ),
        ],
      ),
    );
  }

  // ── Step 2: compare with the screenshot ────────────────────────────────

  Widget _compare() {
    final comparable = _lines.where((l) => l.found != null && l.canMatch);
    final allMatched =
        comparable.isNotEmpty && comparable.every((l) => l.useShown);
    final missing = _lines.where((l) => l.found == null).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _totals(),
        if (comparable.isNotEmpty) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: Icon(allMatched ? Icons.undo : Icons.straighten),
            label: Text(allMatched
                ? 'Use our numbers for all'
                : 'Match all to screenshot'),
            onPressed: () => setState(() {
              for (final l in comparable) {
                l.useShown = !allMatched;
              }
            }),
          ),
          const SizedBox(height: 6),
          Text(
            'Matching the screenshot keeps our protein, carbs and fat split, '
            'just scaled up or down to its calories.',
            style: TextStyle(color: AppColors.muted, fontSize: 12.5),
          ),
        ],
        if (missing > 0) ...[
          const SizedBox(height: 12),
          _note(
            Icons.info_outline,
            AppColors.amber700,
            "$missing ${missing == 1 ? "ingredient wasn't" : "ingredients weren't"} "
            'found. Where the screenshot showed calories we’ve used those; '
            'otherwise it’s left out. You can add it on the recipe page.',
          ),
        ],
        const SizedBox(height: 12),
        for (final l in _lines) _compareRow(l),
      ],
    );
  }

  Widget _totals() {
    var ours = 0.0;
    var shown = 0;
    var chosen = 0.0;
    var anyShown = false;
    for (final l in _lines) {
      ours += l.ours.calories;
      if (l.shown != null) {
        shown += l.shown!;
        anyShown = true;
      }
      chosen += l.chosen?.calories ?? 0;
    }
    final match = anyShown ? RecipeImport.compare(ours, shown) : ImportMatch.none;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _stat('Our lookup', '${ours.round()} kcal')),
                if (anyShown)
                  Expanded(child: _stat('Screenshot', '$shown kcal')),
              ],
            ),
            if (anyShown) ...[
              const SizedBox(height: 8),
              _badge(match, ours, shown),
            ],
            const Divider(height: 20),
            _stat('Going into your recipe', '${chosen.round()} kcal'),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
          Text(value,
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        ],
      );

  Widget _compareRow(_Line l) {
    final f = l.found;
    final chosen = l.chosen;
    final match = RecipeImport.compare(l.ours.calories, l.shown);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.query.text.trim(),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            if (f != null && f.name.isNotEmpty)
              Text(
                '${f.name}${f.portion.isNotEmpty ? ' · ${f.portion}' : ''}'
                '${f.fromDatabase ? '' : ' · AI estimate'}',
                style: TextStyle(color: AppColors.muted, fontSize: 12.5),
              ),
            const SizedBox(height: 6),
            Text(
              [
                f == null ? 'Ours: not found' : 'Ours ${l.ours.calories.round()}',
                if (l.shown != null) 'Screenshot ${l.shown}',
              ].join(' · '),
            ),
            if (f != null && l.shown != null) ...[
              const SizedBox(height: 6),
              _badge(match, l.ours.calories, l.shown!),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('Ours')),
                  ButtonSegment(value: true, label: Text('Screenshot')),
                ],
                selected: {l.useShown},
                onSelectionChanged: (s) =>
                    setState(() => l.useShown = s.first),
              ),
            ],
            if (chosen != null) ...[
              const SizedBox(height: 8),
              Text(
                'Adding ${chosen.calories.round()} kcal · '
                'P ${chosen.protein.round()}g · C ${chosen.carbs.round()}g · '
                'F ${chosen.fat.round()}g',
                style: TextStyle(color: AppColors.muted, fontSize: 12.5),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Left out',
                    style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _badge(ImportMatch match, double ours, int shown) {
    final pct = RecipeImport.percentDifference(ours, shown);
    final pctText = pct == null ? '' : '${pct > 0 ? '+' : ''}$pct%';
    final (IconData icon, Color color, String text) = switch (match) {
      ImportMatch.close => (Icons.check_circle, AppColors.emerald700, 'Close'),
      ImportMatch.off => (
          Icons.info_outline,
          AppColors.amber700,
          'Ours is $pctText vs the screenshot'
        ),
      ImportMatch.veryDifferent => (
          Icons.warning_amber_rounded,
          AppColors.red600,
          'Very different ($pctText). Check the amount or brand'
        ),
      ImportMatch.none => (Icons.remove, AppColors.muted, ''),
    };
    if (text.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(text,
              style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  Widget _note(IconData icon, Color color, String text) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
      );
}
