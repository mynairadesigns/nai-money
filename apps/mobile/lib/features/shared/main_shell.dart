import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/shapes.dart';
import '../transactions/presentation/add_transaction_sheet.dart';

/// PRD §4.2 bottom tab structure:
///   [Home] [Transactions] [Add (+)] [Reports] [AI Coach]
/// Add is a floating central button that opens a bottom sheet,
/// not a real branch in the StatefulShellRoute.
class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _onTabTapped(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  void _onAddPressed(BuildContext context) {
    // FAB opens a small Add menu: the first three options drop into the
    // Add Transaction modal (type is then picked inside via the
    // SegmentedButton); "Scan receipt" routes to the AI scanner flow
    // (PRD §6.4.1 / §11.4).
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.south_outlined),
              title: const Text('Add expense'),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                showAddTransactionSheet(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.north_outlined),
              title: const Text('Add income'),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                showAddTransactionSheet(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz_outlined),
              title: const Text('Transfer'),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                showAddTransactionSheet(context);
              },
            ),
            const Divider(height: 0),
            ListTile(
              leading: const Icon(Icons.document_scanner_outlined),
              title: const Text('Scan receipt'),
              subtitle: const Text('AI-powered'),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                context.push('/transaction/scan');
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Width at which the bottom bar becomes a side rail (tablets, desktop
  /// browsers). Measured with a LayoutBuilder so it respects the app-wide
  /// max-width wrapper in `main.dart`.
  static const _railBreakpoint = 840.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= _railBreakpoint
          ? _buildWide(context)
          : _buildCompact(context),
    );
  }

  Widget _buildWide(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: _onTabTapped,
            labelType: NavigationRailLabelType.all,
            backgroundColor: theme.colorScheme.surface,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: FloatingActionButton(
                onPressed: () => _onAddPressed(context),
                elevation: 0,
                shape: const RoundedRectangleBorder(
                  borderRadius: AppBorderRadius.lg,
                ),
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                tooltip: 'Add',
                child: const Icon(Icons.add),
              ),
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: Text('Home'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long),
                label: Text('Transactions'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.bar_chart_outlined),
                selectedIcon: Icon(Icons.bar_chart),
                label: Text('Reports'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.auto_awesome_outlined),
                selectedIcon: Icon(Icons.auto_awesome),
                label: Text('AI Coach'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: navigationShell),
        ],
      ),
    );
  }

  Widget _buildCompact(BuildContext context) {
    final theme = Theme.of(context);
    final selected = navigationShell.currentIndex;

    return Scaffold(
      body: navigationShell,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _onAddPressed(context),
        elevation: 2,
        shape: const RoundedRectangleBorder(borderRadius: AppBorderRadius.lg),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        height: 64,
        padding: EdgeInsets.zero,
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        color: theme.colorScheme.surface,
        elevation: 0,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _NavTab(
              icon: Icons.home_outlined,
              selectedIcon: Icons.home,
              label: 'Home',
              isSelected: selected == 0,
              onTap: () => _onTabTapped(0),
            ),
            _NavTab(
              icon: Icons.receipt_long_outlined,
              selectedIcon: Icons.receipt_long,
              label: 'Transactions',
              isSelected: selected == 1,
              onTap: () => _onTabTapped(1),
            ),
            const SizedBox(width: 56), // FAB notch reservation
            _NavTab(
              icon: Icons.bar_chart_outlined,
              selectedIcon: Icons.bar_chart,
              label: 'Reports',
              isSelected: selected == 2,
              onTap: () => _onTabTapped(2),
            ),
            _NavTab(
              icon: Icons.auto_awesome_outlined,
              selectedIcon: Icons.auto_awesome,
              label: 'AI Coach',
              isSelected: selected == 3,
              onTap: () => _onTabTapped(3),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isSelected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isSelected ? selectedIcon : icon, color: color, size: 24),
            const SizedBox(height: 2),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

