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
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 64, color: AppColors.textSecondary),
                  const SizedBox(height: AppConstants.spacing16),
                  Text(
                    'Aucune generation recente',
                    style: AppTextStyles.title.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppConstants.spacing8),
                  Text(
                    'Vos creations apparaitront ici',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            )
          : ListView.separated(
              itemCount: history.length,
              separatorBuilder: (_, __) => Divider(color: AppColors.divider),
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
