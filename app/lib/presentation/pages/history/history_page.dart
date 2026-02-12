import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../state/history_provider.dart';
import '../previews/previews_page.dart';

/// History Page - Shows previous generations
class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  @override
  Widget build(BuildContext context) {
    final history = ref.watch(historyProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Historique')),
      body: history.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppConstants.spacing32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Illustration (MOBILE.md §2 — Empty State)
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.music_note_rounded,
                        size: 40,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: AppConstants.spacing24),
                    // Title
                    Text(
                      'Aucune creation recente',
                      style: AppTextStyles.title,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppConstants.spacing8),
                    // Explanation
                    Text(
                      'Enregistrez un morceau de piano\npour voir vos creations ici',
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppConstants.spacing24),
                    // CTA
                    ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.mic),
                      label: const Text('Enregistrer'),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              itemCount: history.length,
              separatorBuilder: (_, __) =>
                  const Divider(color: AppColors.divider),
              itemBuilder: (context, index) {
                final item = history[index];
                final title = item.identifiedTitle ?? 'Session ${item.jobId}';
                final subtitle = item.identifiedArtist ?? item.timestamp;
                return ListTile(
                  title: Text(title, style: AppTextStyles.body),
                  subtitle: Text(subtitle, style: AppTextStyles.caption),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PreviewsPage(
                          levels: item.levels,
                          isUnlocked: true,
                          trackTitle: item.identifiedTitle,
                          trackArtist: item.identifiedArtist,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
