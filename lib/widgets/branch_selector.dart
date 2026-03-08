import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../models/branch.dart';
import '../services/auth_service.dart';

class BranchSelector extends StatelessWidget {
  final Function(Branch)? onBranchChanged;

  const BranchSelector({super.key, this.onBranchChanged});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();
    final branches = authService.userBranches;
    final currentBranch = authService.currentBranch;

    if (branches.isEmpty) {
      return const SizedBox.shrink();
    }

    // If only one branch and not owner, don't show selector
    if (branches.length == 1 && !authService.canViewAllBranches()) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.store, size: 20),
            const SizedBox(width: 8),
            Text(
              currentBranch?.name ?? '',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: DropdownButtonFormField<Branch>(
        isExpanded: true,
        initialValue: currentBranch,
        decoration: InputDecoration(
          labelText: 'Branch',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          isDense: true,
        ),
        selectedItemBuilder: (context) {
          return branches.map((branch) {
            return Row(
              children: [
                const Icon(Icons.store, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${branch.name} - ${branch.location}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            );
          }).toList();
        },
        items: branches.map((branch) {
          return DropdownMenuItem(
            value: branch,
            child: Row(
              children: [
                const Icon(Icons.store, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        branch.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        branch.location,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textTertiary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
        onChanged: (branch) {
          if (branch != null) {
            authService.setCurrentBranch(branch);
            onBranchChanged?.call(branch);
          }
        },
      ),
    );
  }
}

