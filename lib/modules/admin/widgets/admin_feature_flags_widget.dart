import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:markaai/core/theme/app_colors.dart';
import 'package:markaai/modules/admin/services/admin_service.dart';

class AdminFeatureFlagsWidget extends StatefulWidget {
  const AdminFeatureFlagsWidget({super.key});

  @override
  State<AdminFeatureFlagsWidget> createState() => _AdminFeatureFlagsWidgetState();
}

class _AdminFeatureFlagsWidgetState extends State<AdminFeatureFlagsWidget> {
  final _adminService = AdminService();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final cardColor = cs.surface;
    final borderColor = cs.onSurface.withValues(alpha: 0.1);

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client.from('feature_flags').stream(primaryKey: ['id']).order('label'),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final flags = snapshot.data!;

        return ListView.builder(
          padding: const EdgeInsets.all(24),
          itemCount: flags.length,
          itemBuilder: (context, index) {
            final flag = flags[index];
            final plans = List<String>.from(flag['enabled_for_plans'] ?? []);

            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              color: cardColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: borderColor),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(flag['label'], 
                                   overflow: TextOverflow.ellipsis,
                                   maxLines: 1,
                                   style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              Text(flag['flag_key'], 
                                   overflow: TextOverflow.ellipsis,
                                   maxLines: 1,
                                   style: TextStyle(color: cs.primary, fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        Switch(
                          value: flag['enabled_global'] ?? false,
                          onChanged: (v) async {
                            final admin = Supabase.instance.client.auth.currentUser;
                            await _adminService.updateFeatureFlag(flag['id'], {'enabled_global': v}, admin!.id);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text('Habilitado para os planos:', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6))),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: ['free', 'starter', 'plus', 'pro'].map((plan) {
                        final isEnabled = plans.contains(plan);
                        return FilterChip(
                          label: Text(plan.toUpperCase(), style: TextStyle(fontSize: 10, color: isEnabled ? cs.onPrimary : cs.onSurface)),
                          selected: isEnabled,
                          selectedColor: cs.primary,
                          onSelected: (selected) async {
                            final admin = Supabase.instance.client.auth.currentUser;
                            final newPlans = List<String>.from(plans);
                            if (selected) {
                              newPlans.add(plan);
                            } else {
                              newPlans.remove(plan);
                            }
                            await _adminService.updateFeatureFlag(flag['id'], {'enabled_for_plans': newPlans}, admin!.id);
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
