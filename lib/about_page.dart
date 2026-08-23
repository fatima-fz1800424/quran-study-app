import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';


import 'motion.dart';

/// Profile links shown under "Built by".
///
/// GitHub is the account behind this repository's `origin` remote; LinkedIn was
/// given to us directly. Both are exact, never inferred - a profile link that
/// lands on the wrong person is worse on an About screen than no link at all,
/// because this is the page where someone decides whether to trust the app.
const List<_Link> _kProfileLinks = [
  _Link('GitHub', 'https://github.com/fatima-fz1800424', Icons.code_rounded),
  _Link(
    'LinkedIn',
    'https://www.linkedin.com/in/fatima-zakaria/',
    Icons.work_outline_rounded,
  ),
];

/// Kept in step with `version:` in pubspec.yaml by hand. There is no
/// package_info_plus in the dependency list and one string is not worth adding
/// a plugin for.
const String kAppVersion = '1.0.0';

/// Who built this, what it draws on, and what it will not do.
///
/// Deliberately plain: a single column, one idea per panel, no gradient behind
/// running text. Someone reads this page to decide whether to trust the app
/// with something that matters to them, and a busy page is not reassuring.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('About'),
      ),
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  EntranceFade(
                    child: GestureDetector(
                      onTap: () {
                        showDialog<void>(
                          context: context,
                          builder: (_) => Dialog(
                            clipBehavior: Clip.antiAlias,
                            child: InteractiveViewer(
                              minScale: 1,
                              maxScale: 3,
                              child: Image.asset(
                                'assets/quran_about_illustration.png',
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        );
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: Image.asset(
                            'assets/quran_about_illustration.png',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Quran Study',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(fontSize: 27),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'A Quran reader with a study assistant that finds verses '
                    'by meaning.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 26),
                  const _BuiltByPanel(),
                  const SizedBox(height: 14),
                  const _FeaturesPanel(),
                  const SizedBox(height: 14),
                  const _StudyAidPanel(),
                  const SizedBox(height: 14),
                  const _CreditsPanel(),
                  const SizedBox(height: 22),
                  Text(
                    'Version $kAppVersion',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BuiltByPanel extends StatelessWidget {
  const _BuiltByPanel();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Built by',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 12,
              letterSpacing: 0.4,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Fatima Zakaria',
            style: theme.textTheme.titleMedium?.copyWith(fontSize: 19),
          ),
          const SizedBox(height: 3),
          Text(
            'Qatar University',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final profile in _kProfileLinks)
                _LinkButton(
                  icon: profile.icon ?? Icons.north_east_rounded,
                  label: profile.label,
                  url: profile.url,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FeaturesPanel extends StatelessWidget {
  const _FeaturesPanel();

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Explore the app',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap a feature to learn how it supports your study.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: const [
              _FeatureCard(
                icon: Icons.menu_book_rounded,
                title: 'Read',
                description:
                    'Browse surahs and read Arabic text with translation.',
              ),
              _FeatureCard(
                icon: Icons.auto_awesome_rounded,
                title: 'Study assistant',
                description:
                    'Ask questions and discover relevant verses by meaning.',
              ),
              _FeatureCard(
                icon: Icons.headphones_rounded,
                title: 'Listen',
                description:
                    'Play verse-by-verse or complete-surah recitations.',
              ),
              _FeatureCard(
                icon: Icons.bookmark_rounded,
                title: 'Save',
                description:
                    'Bookmark verses so you can return to them later.',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 245,
      child: Material(
        color: theme.colorScheme.primary.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            showDialog<void>(
              context: context,
              builder: (_) => AlertDialog(
                title: Row(
                  children: [
                    Icon(icon, color: theme.colorScheme.primary),
                    const SizedBox(width: 10),
                    Text(title),
                  ],
                ),
                content: Text(description),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 13,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The honest note. Placed above the credits, not buried under them: it is the
/// most important thing on the page.
class _StudyAidPanel extends StatelessWidget {
  const _StudyAidPanel();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Amber, the app's advisory colour, rather than error red. This is a
    // boundary being stated plainly, not a warning that something is wrong.
    final tone = theme.colorScheme.tertiary;

    return _Panel(
      background: tone.withOpacity(
        theme.brightness == Brightness.light ? 0.07 : 0.13,
      ),
      border: tone.withOpacity(0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 19, color: tone),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'A study aid, not a scholarly source',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 16,
                    color: tone,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Text(
            'The assistant answers only from the sources bundled with the app, '
            'and it names the source of every answer. Where it finds nothing '
            'relevant, it says so instead of guessing.',
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
          ),
          const SizedBox(height: 10),
          Text(
            'It does not give religious rulings. Questions about what is '
            'permitted, about the validity of worship, or about family and '
            'personal matters belong with a qualified scholar or your local '
            'imam. Please treat what you read here as a starting point for '
            'study, and check it against people who know.',
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
          ),
        ],
      ),
    );
  }
}

class _CreditsPanel extends StatelessWidget {
  const _CreditsPanel();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Credits',
            style: theme.textTheme.titleMedium?.copyWith(fontSize: 17),
          ),
          const SizedBox(height: 4),
          const _Credit(
            title: 'Quran text and translation',
            body:
                'The Tanzil Project, whose Uthmani Arabic text and English '
                'translation by Abdullah Yusuf Ali are bundled verbatim. '
                'Tanzil also supplies the surah names, ayah counts and '
                'revelation places, under Creative Commons Attribution 3.0.',
            // Not a courtesy link. Tanzil's terms require that its text be
            // attributed and that a link to tanzil.net be shown, so users can
            // follow changes to the text. Do not remove this.
            links: [_Link('tanzil.net', 'https://tanzil.net')],
          ),
          const _Credit(
            title: 'Recitation audio',
            body:
                'Verse-by-verse recitation streams from Quran.com. '
                'Whole-surah recordings come from mp3quran.net. Neither is '
                'bundled with the app; both are fetched as you listen.',
            links: [
              _Link('quran.com', 'https://quran.com'),
              _Link('mp3quran.net', 'https://mp3quran.net'),
            ],
          ),
          const _Credit(
            title: 'Arabic type',
            body:
                'Amiri Quran, by Khaled Hosny, released under the SIL Open '
                'Font License 1.1. The interface is set in Roboto.',
          ),
          const _Credit(
            title: 'Patterns and illustrations',
            body:
                'Every ornament in the app - the star tiling on the cards, the '
                'open mushaf above - is drawn in code rather than loaded as an '
                'image, so there is nothing here whose licence could come into '
                'question later.',
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _Credit extends StatelessWidget {
  const _Credit({
    required this.title,
    required this.body,
    this.links = const [],
    this.isLast = false,
  });

  final String title;
  final String body;
  final List<_Link> links;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Text(
          title,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          body,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 14,
            height: 1.55,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (links.isNotEmpty) ...[
          const SizedBox(height: 9),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final link in links)
                _LinkButton(
                  icon: Icons.north_east_rounded,
                  label: link.label,
                  url: link.url,
                  compact: true,
                ),
            ],
          ),
        ],
        if (!isLast) ...[
          const SizedBox(height: 14),
          Divider(height: 1, color: theme.colorScheme.outline.withOpacity(0.6)),
        ],
      ],
    );
  }
}

class _Link {
  const _Link(this.label, this.url, [this.icon]);

  final String label;
  final String url;

  /// Only the profile links carry one; source links all use the same arrow.
  final IconData? icon;
}

/// An outward link. Nothing opens in place, so the arrow is always shown and
/// the label is always the host, never a verb.
class _LinkButton extends StatelessWidget {
  const _LinkButton({
    required this.icon,
    required this.label,
    required this.url,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final String url;
  final bool compact;

  Future<void> _open() async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OutlinedButton.icon(
      onPressed: _open,
      icon: Icon(icon, size: compact ? 14 : 17),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: theme.colorScheme.primary,
        side: BorderSide(color: theme.colorScheme.outline),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 16,
          vertical: compact ? 8 : 12,
        ),
        textStyle: TextStyle(
          fontSize: compact ? 12.5 : 14,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

/// The page's one container shape, matching the settings sheet's sections so
/// About does not look like it came from a different app.
class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.background, this.border});

  final Widget child;
  final Color? background;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: background ?? theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: border ?? theme.colorScheme.outline.withOpacity(0.4),
        ),
      ),
      child: child,
    );
  }
}
