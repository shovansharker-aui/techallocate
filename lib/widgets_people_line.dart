import 'package:flutter/material.dart';
import 'utils/app_colors.dart';

/// JO(s) and CF(s) on one line — "<JO icon> name · name  <CF icon> name"
/// — shared by every place a task's assigned people are shown (Live
/// Activity Grid tiles, the completed-task detail sheet, ...) so the
/// same icon-plus-dot-joined-names treatment reads identically
/// everywhere, rather than each screen growing its own slightly
/// different version.
///
/// Built as one Text.rich (not two Rows sharing a line) so the whole
/// thing ellipsizes together if it doesn't fit, instead of the JO half
/// pushing the CF half off into nowhere.
class PeopleLine extends StatelessWidget {
  final List<String> technicianNames;
  final List<String> helperNames;
  final int maxLines;

  const PeopleLine(this.technicianNames, this.helperNames, {super.key, this.maxLines = 1});

  static const _iconSize = 13.0;
  static const _nameStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.w500);

  @override
  Widget build(BuildContext context) {
    if (technicianNames.isEmpty && helperNames.isEmpty) {
      return const Row(children: [
        Icon(Icons.engineering_outlined, size: _iconSize, color: AppColors.muted),
        SizedBox(width: 4),
        Text('No JO', style: TextStyle(fontSize: 12, color: AppColors.muted)),
      ]);
    }
    return Text.rich(
      TextSpan(children: [
        const WidgetSpan(alignment: PlaceholderAlignment.middle, child: Icon(Icons.engineering_outlined, size: _iconSize, color: AppColors.muted)),
        const WidgetSpan(child: SizedBox(width: 4)),
        if (technicianNames.isEmpty)
          const TextSpan(text: 'No JO', style: TextStyle(fontSize: 12, color: AppColors.muted))
        else
          ..._dotJoinedSpans(technicianNames),
        if (helperNames.isNotEmpty) ...[
          // A brief blank spacer between the two groups, not another dot
          // — the dot is reserved for separating names within one group.
          const WidgetSpan(child: SizedBox(width: 14)),
          const WidgetSpan(alignment: PlaceholderAlignment.middle, child: Icon(Icons.handyman_outlined, size: _iconSize, color: AppColors.muted)),
          const WidgetSpan(child: SizedBox(width: 4)),
          ..._dotJoinedSpans(helperNames),
        ],
      ]),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }

  // Names joined by a bold middle dot — bold so the separator reads as a
  // deliberate divider rather than a stray punctuation mark at this font
  // size.
  List<InlineSpan> _dotJoinedSpans(List<String> names) {
    const dotStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.w900);
    final spans = <InlineSpan>[];
    for (var i = 0; i < names.length; i++) {
      spans.add(TextSpan(text: names[i], style: _nameStyle));
      if (i != names.length - 1) spans.add(const TextSpan(text: ' · ', style: dotStyle));
    }
    return spans;
  }
}
