import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';

/// PRD §11.7: About screen.
///
/// Shows app name + version, legal links (Terms, Privacy, Contact),
/// and a small footer. URLs are buyer-replaceable placeholders.
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  PackageInfo? _info;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _info = info);
    });
  }

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $url')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final version = _info != null
        ? '${_info!.version} (build ${_info!.buildNumber})'
        : '—';

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              children: [
                const SizedBox(height: AppSpacing.lg),
                // App identity card
                Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: AppBorderRadius.lg,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.lg,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: AppSpacing.xxxl,
                          height: AppSpacing.xxxl,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: AppBorderRadius.md,
                          ),
                          child: Icon(
                            Icons.account_balance_wallet_outlined,
                            color: theme.colorScheme.onPrimaryContainer,
                            size: AppSpacing.xl,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Homa Finance',
                              style: theme.textTheme.titleLarge,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              version,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                // Legal / support tiles
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Terms of service'),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => _launch('https://homa.finance/terms'),
                ),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Privacy policy'),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => _launch('https://homa.finance/privacy'),
                ),
                ListTile(
                  leading: const Icon(Icons.mail_outline),
                  title: const Text('Contact support'),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => _launch('mailto:support@homa.finance'),
                ),
              ],
            ),
          ),
          // Footer
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xl),
            child: Text(
              '© Homa Finance',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
