import 'dart:io';

import 'package:flutter/material.dart';

import 'navigation/tool_catalog.dart';
import 'screens/files_page.dart';
import 'services/theme_preferences.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends SickPdfApp {
  const MyApp({super.key});
}

/// Root widget. Loads the persisted appearance preference before building so
/// the first frame already uses the saved theme (default: light).
class SickPdfApp extends StatefulWidget {
  const SickPdfApp({super.key});

  @override
  State<SickPdfApp> createState() => _SickPdfAppState();
}

class _SickPdfAppState extends State<SickPdfApp> {
  final _prefs = ThemePreferences();
  ThemeMode? _themeMode;

  @override
  void initState() {
    super.initState();
    _prefs.load().then((mode) {
      if (mounted) setState(() => _themeMode = mode);
    });
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    await _prefs.save(mode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'sickPDF',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      // Defaults to light until the saved preference resolves.
      themeMode: _themeMode ?? ThemeMode.light,
      home: AppShell(onThemeModeChanged: _setThemeMode),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, this.onThemeModeChanged});

  final ValueChanged<ThemeMode>? onThemeModeChanged;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    // IndexedStack keeps each tab's state alive so switching tabs never
    // loses in-progress work or forces rebuilds. Files is told when it
    // becomes visible so it reloads the library from storage instead of
    // showing the list it read at startup.
    final pages = <Widget>[
      const HomePage(),
      FilesPage(active: _selectedIndex == 1),
      SettingsPage(onThemeModeChanged: widget.onThemeModeChanged),
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(index: _selectedIndex, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: 'Files',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

/// Home: purpose, primary actions, and all tools grouped by intent.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final groups = kGroupedTools;
    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(child: _HomeHeader()),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screen,
            AppSpacing.md,
            AppSpacing.screen,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: _SectionTitle(
              title: 'All tools',
              subtitle: 'Everything works offline on your device.',
              trailing: '${kTools.length} tools',
            ),
          ),
        ),
        for (final entry in groups.entries) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screen,
              AppSpacing.lg,
              AppSpacing.screen,
              AppSpacing.xxs,
            ),
            sliver: SliverToBoxAdapter(
              child: _GroupLabel(label: entry.key.label),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
            sliver: SliverToBoxAdapter(
              child: _ToolGroupList(tools: entry.value),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
      ],
    );
  }
}

/// One group rendered as a container of rows — clean list, not a grid of
/// identical icon tiles. Light theme uses a soft shadow; dark theme keeps a
/// visible hairline border.
class _ToolGroupList extends StatelessWidget {
  const _ToolGroupList({required this.tools});

  final List<ToolDefinition> tools;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = theme.colorScheme.outlineVariant;
    final isLight = theme.brightness == Brightness.light;
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: isLight ? null : Border.all(color: border),
        boxShadow: isLight
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < tools.length; i++) ...[
            if (i > 0) Divider(height: 1, color: border),
            _ToolRow(tool: tools[i]),
          ],
        ],
      ),
    );
  }
}

class _ToolRow extends StatelessWidget {
  const _ToolRow({required this.tool});

  final ToolDefinition tool;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: '${tool.name}. ${tool.description}',
      child: InkWell(
        onTap: () => Navigator.of(context).push(tool.route()),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 2,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tool.effectiveAccent().withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(
                  tool.icon,
                  size: 22,
                  color: tool.effectiveAccent(),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tool.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      tool.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.teal.withValues(alpha: 0.08),
            AppColors.teal.withValues(alpha: 0.0),
          ],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(AppRadius.lg)),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screen,
        AppSpacing.lg,
        AppSpacing.screen,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Wordmark(),
              _OfflineBadge(),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Your PDFs, handled.',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              height: 1.15,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Merge, split, sign, and protect — offline, on your device. '
            'Files are never uploaded.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Text-only wordmark: precise, monochrome-safe, no decorative container.
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return Text.rich(
      TextSpan(
        text: 'sick',
        style: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
          color: onSurface,
        ),
        children: [
          TextSpan(
            text: 'PDF',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
      semanticsLabel: 'sickPDF',
    );
  }
}

class _OfflineBadge extends StatelessWidget {
  const _OfflineBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lock_outline,
            size: 13,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            'Offline',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

/// A single tool entry point kept for external callers (tests, previews).
class ToolCard extends StatelessWidget {
  const ToolCard({super.key, required this.tool});

  final ToolDefinition tool;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: '${tool.name}. ${tool.description}',
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: () => Navigator.of(context).push(tool.route()),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(tool.icon, size: 22, color: theme.colorScheme.primary),
                const Spacer(),
                Text(
                  tool.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Flexible(
                  child: Text(
                    tool.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Settings tab: appearance, privacy promise, app identity, and version.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, this.onThemeModeChanged});

  final ValueChanged<ThemeMode>? onThemeModeChanged;

  static const _points = <(IconData, String, String)>[
    (
      Icons.lock_outline,
      'Private by design',
      'No accounts, ads, or analytics. Nothing is uploaded.',
    ),
    (
      Icons.wifi_off_outlined,
      'Works offline',
      'All processing runs locally on your device.',
    ),
    (
      Icons.file_copy_outlined,
      'Your originals are safe',
      'Tools read your files and save a new copy.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = theme.colorScheme.outlineVariant;
    final docsDir = Platform.isAndroid || Platform.isIOS;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screen,
        AppSpacing.lg,
        AppSpacing.screen,
        AppSpacing.xxl,
      ),
      children: [
        Row(
          children: [
            const _Wordmark(),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Offline PDF toolkit',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Semantics(
          header: true,
          child: Text(
            'Appearance',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: border),
          ),
          child: ListTile(
            leading: Icon(
              MediaQuery.platformBrightnessOf(context) == Brightness.dark
                  ? Icons.dark_mode_outlined
                  : Icons.light_mode_outlined,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            title: const Text('Dark theme'),
            subtitle: const Text('Light theme is used by default.'),
            trailing: Switch(
              value: Theme.of(context).brightness == Brightness.dark,
              onChanged: (dark) =>
                  onThemeModeChanged?.call(dark ? ThemeMode.dark : ThemeMode.light),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Semantics(
          header: true,
          child: Text(
            'Privacy',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < _points.length; i++) ...[
                if (i > 0) Divider(height: 1, color: border),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _points[i].$1,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _points[i].$2,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _points[i].$3,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Semantics(
          header: true,
          child: Text(
            'About',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              const ListTile(
                leading: Icon(Icons.badge_outlined),
                title: Text('Version'),
                subtitle: Text('1.0.0'),
              ),
              Divider(height: 1, color: border),
              ListTile(
                leading: const Icon(Icons.folder_copy_outlined),
                title: const Text('Library location'),
                subtitle: Text(
                  docsDir
                      ? 'App documents folder ("library"), private to sickPDF.'
                      : 'App documents folder, private to sickPDF.',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
