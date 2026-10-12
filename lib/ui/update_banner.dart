import 'package:flutter/widgets.dart';

/// No longer used: the "A new version is ready" bar covered the top of the
/// app. Updates now happen quietly (see AppUpdate), with "Update ready" in
/// Profile. Safe to delete this file.
class UpdateBanner extends StatelessWidget {
  final Widget child;
  const UpdateBanner({super.key, required this.child});

  @override
  Widget build(BuildContext context) => child;
}
