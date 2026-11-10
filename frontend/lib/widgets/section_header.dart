import 'package:flutter/material.dart';

import '../theme.dart';

/// A full-width gray band that heads a group of list rows.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: sectionGray,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(color: lsuPurple, fontWeight: FontWeight.w600),
      ),
    );
  }
}
