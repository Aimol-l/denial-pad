import 'dart:math' as math;

import 'package:denial_flutter_sdk/materials.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

import 'package:denial_flutter_sdk/localization.dart';
import 'package:denial_flutter_sdk/settings.dart';
import 'package:denial_flutter_sdk/state.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_flutter_sdk/wallpaper.dart';
import 'package:denial_flutter_sdk/rendering.dart';

import 'settings_controls.dart';
import 'settings_glass_tuning_controls.dart';
import 'settings_wallpaper_card.dart';

const settingsWallpaperTriggerKey = ValueKey<String>(
  'settings-wallpaper-trigger',
);
const settingsAccentColorTriggerKey = ValueKey<String>(
  'settings-accent-color-trigger',
);
const settingsColorSchemeControlKey = ValueKey<String>(
  'settings-color-scheme-control',
);
const settingsFontFamilyControlKey = ValueKey<String>(
  'settings-font-family-control',
);
const settingsBackdropBlurToggleKey = ValueKey<String>(
  'settings-backdrop-blur-toggle',
);
const settingsBackdropBlurSliderKey = ValueKey<String>(
  'settings-backdrop-blur-slider',
);
const settingsBackdropBlurOpacityThresholdKey = ValueKey<String>(
  'settings-backdrop-blur-opacity-threshold',
);
const settingsCursorSizeSliderKey = ValueKey<String>(
  'settings-cursor-size-slider',
);
const settingsCornerRoundnessSliderKey = ValueKey<String>(
  'settings-corner-roundness-slider',
);
const settingsCardOpacitySliderKey = ValueKey<String>(
  'settings-card-opacity-slider',
);

class SettingsAppearancePage extends StatefulWidget {
  const SettingsAppearancePage({
    required this.settings,
    required this.extractedAccent,
    required this.wallpaper,
    this.wallpaperApps,
    this.wallpaperOutputName,
    required this.onOpenWallpaperSelector,
    required this.onColorSchemePreferenceChanged,
    required this.onAccentSourceChanged,
    required this.onAccentColorChanged,
    required this.onOpenAccentPicker,
    required this.fontFamilies,
    required this.fontCatalogLoading,
    required this.onFontFamilyChanged,
    required this.iconThemes,
    required this.iconThemesLoading,
    required this.onIconThemeChanged,
    required this.onImportIconTheme,
    required this.onRemoveIconTheme,
    required this.onCornerRadiusScaleChanged,
    required this.onPanelOpacityChanged,
    required this.onCardOpacityChanged,
    required this.onTransparencyModeChanged,
    required this.onBackdropBlurLevelChanged,
    required this.onBackdropBlurOpacityThresholdChanged,
    required this.onGlassChanged,
    required this.onApplicationThemingEnabledChanged,
    required this.onReapplyApplicationTheming,
    required this.onFocusedWindowBorderEnabledChanged,
    required this.onFocusedOpacityChanged,
    required this.onUnfocusedOpacityChanged,
    required this.onCursorSizeChanged,
    required this.cursorThemes,
    required this.cursorCatalogLoading,
    required this.onCursorThemeChanged,
    required this.onAllowClientCursorSurfacesChanged,
    required this.onImportCursorZip,
    required this.onRemoveCursorTheme,
    required this.onReset,
    this.mobile = false,
    super.key,
  });

  final ShellAppearanceSettings settings;
  final Color extractedAccent;
  final WallpaperResource wallpaper;
  final List<String>? wallpaperApps;
  final String? wallpaperOutputName;
  final VoidCallback onOpenWallpaperSelector;
  final ValueChanged<DesktopColorSchemePreference>
  onColorSchemePreferenceChanged;
  final ValueChanged<ShellAccentSource> onAccentSourceChanged;
  final ValueChanged<Color> onAccentColorChanged;
  final VoidCallback onOpenAccentPicker;
  final List<String> fontFamilies;
  final bool fontCatalogLoading;
  final ValueChanged<String> onFontFamilyChanged;
  final List<ShellIconThemeData> iconThemes;
  final bool iconThemesLoading;
  final ValueChanged<String> onIconThemeChanged;
  final Future<List<ShellIconThemeData>> Function()? onImportIconTheme;
  final Future<void> Function(ShellIconThemeData) onRemoveIconTheme;
  final ValueChanged<double> onCornerRadiusScaleChanged;
  final ValueChanged<double> onPanelOpacityChanged;
  final ValueChanged<double> onCardOpacityChanged;
  final ValueChanged<ShellTransparencyMode> onTransparencyModeChanged;
  final ValueChanged<ShellBackdropBlurLevel> onBackdropBlurLevelChanged;
  final ValueChanged<double> onBackdropBlurOpacityThresholdChanged;
  final ValueChanged<ShellGlassConfiguration> onGlassChanged;
  final ValueChanged<bool> onApplicationThemingEnabledChanged;
  final VoidCallback onReapplyApplicationTheming;
  final ValueChanged<bool> onFocusedWindowBorderEnabledChanged;
  final ValueChanged<double> onFocusedOpacityChanged;
  final ValueChanged<double> onUnfocusedOpacityChanged;
  final ValueChanged<double> onCursorSizeChanged;
  final List<ShellCursorThemeData> cursorThemes;
  final bool cursorCatalogLoading;
  final ValueChanged<String> onCursorThemeChanged;
  final ValueChanged<bool> onAllowClientCursorSurfacesChanged;
  final Future<ShellCursorThemeData?> Function()? onImportCursorZip;
  final Future<void> Function(ShellCursorThemeData) onRemoveCursorTheme;
  final VoidCallback onReset;

  /// Settings runs on a phone, under the mobile shell.
  final bool mobile;

  @override
  State<SettingsAppearancePage> createState() => _SettingsAppearancePageState();
}

class _SettingsAppearancePageState extends State<SettingsAppearancePage> {
  String? _cursorError;

  Widget _applicationThemingControls(BuildContext context) {
    final l10n = context.l10n;
    return SettingsCardPadding(
      child: SettingsControlRow(
        label: l10n.settingsApplicationThemingEnabled,
        description: l10n.settingsApplicationThemingDescription,
        control: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('settings-application-theming-reapply'),
              onPressed: widget.settings.applicationThemingEnabled
                  ? widget.onReapplyApplicationTheming
                  : null,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(l10n.settingsApplicationThemingReapply),
            ),
            const SizedBox(height: 10),
            SettingsToggle(
              key: const ValueKey('settings-application-theming'),
              label: l10n.settingsApplicationThemingEnabled,
              description: l10n.settingsApplicationThemingDescription,
              showLabel: false,
              value: widget.settings.applicationThemingEnabled,
              onChanged: widget.onApplicationThemingEnabledChanged,
            ),
          ],
        ),
      ),
    );
  }

  void _resetGlassEffects() {
    final glass = widget.settings.glass;
    widget.onGlassChanged(
      const ShellGlassConfiguration().copyWith(
        appearance: glass.appearance,
        opacity: glass.opacity,
        windowOpacity: glass.windowOpacity,
        appPanelOpacity: glass.appPanelOpacity,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SettingsPageLayout(
      icon: Icons.palette_outlined,
      eyebrow: l10n.settingsAppearanceSection,
      title: l10n.settingsAppearanceTitle,
      cardSpacing: 20,
      onReset: widget.onReset,
      footer: SettingsErrorNotice(message: _cursorError),
      children: [
        SettingsWallpaperCard(
          chooseKey: settingsWallpaperTriggerKey,
          wallpaper: widget.wallpaper,
          wallpaperApps: widget.wallpaperApps,
          outputName: widget.wallpaperOutputName,
          onChoose: widget.onOpenWallpaperSelector,
        ),
        SettingsCardGroup(
          key: const ValueKey('appearance-theme-card'),
          title: l10n.settingsAppearanceTheme,
          children: [
            SettingsCardPadding(
              child: SettingsControlRow(
                label: l10n.settingsColorSchemeTitle,
                description:
                    widget.settings.colorSchemePreference ==
                        DesktopColorSchemePreference.noPreference
                    ? l10n.settingsColorSchemeNoPreferenceDescription
                    : l10n.settingsColorSchemeDescription,
                control: SettingsSegmentedControl<DesktopColorSchemePreference>(
                  key: settingsColorSchemeControlKey,
                  value: widget.settings.colorSchemePreference,
                  choices: [
                    SettingsChoice(
                      DesktopColorSchemePreference.preferDark,
                      l10n.settingsColorSchemeDark,
                    ),
                    SettingsChoice(
                      DesktopColorSchemePreference.preferLight,
                      l10n.settingsColorSchemeLight,
                    ),
                    SettingsChoice(
                      DesktopColorSchemePreference.noPreference,
                      l10n.settingsColorSchemeNoPreference,
                    ),
                  ],
                  onChanged: widget.onColorSchemePreferenceChanged,
                ),
              ),
            ),
            SettingsCardPadding(
              child: SettingsControlRow(
                label: l10n.settingsShellAccentTitle,
                description: l10n.settingsShellAccentDescription,
                controlWidth: 360,
                control: SizedBox(
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SettingsSegmentedControl<ShellAccentSource>(
                            value: widget.settings.accentSource,
                            choices: [
                              SettingsChoice(
                                ShellAccentSource.wallpaper,
                                l10n.settingsShellAccentWallpaper,
                              ),
                            ],
                            onChanged: widget.onAccentSourceChanged,
                          ),
                          const SizedBox(width: 10),
                          SettingsColorButton(
                            key: settingsAccentColorTriggerKey,
                            color:
                                widget.settings.accentSource ==
                                    ShellAccentSource.wallpaper
                                ? widget.extractedAccent
                                : widget.settings.customAccentColor,
                            label: l10n.settingsShellAccentChoose,
                            onPressed: () {
                              // Start from the visible colour so the wheel
                              // continues what the row shows.
                              if (widget.settings.accentSource ==
                                  ShellAccentSource.wallpaper) {
                                widget.onAccentColorChanged(
                                  widget.extractedAccent,
                                );
                              }
                              widget.onAccentSourceChanged(
                                ShellAccentSource.custom,
                              );
                              widget.onOpenAccentPicker();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _AccentPresets(
                        selected:
                            widget.settings.accentSource ==
                                ShellAccentSource.wallpaper
                            ? widget.extractedAccent
                            : widget.settings.customAccentColor,
                        onSelected: (color) {
                          widget.onAccentSourceChanged(
                            ShellAccentSource.custom,
                          );
                          widget.onAccentColorChanged(color);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _applicationThemingControls(context),
          ],
        ),
        SettingsCardGroup(
          key: const ValueKey('appearance-typography-card'),
          title: l10n.settingsTypographyTitle,
          children: [
            SettingsCardPadding(
              child: SettingsSelect<String>(
                key: settingsFontFamilyControlKey,
                label: l10n.settingsFontFamily,
                description: widget.fontCatalogLoading
                    ? l10n.settingsFontCatalogLoading
                    : l10n.settingsFontDescription,
                value: widget.settings.fontFamily,
                choices: <SettingsChoice<String>>[
                  SettingsChoice('', l10n.settingsFontSystemDefault),
                  for (final family in _fontFamilyChoices(
                    widget.fontFamilies,
                    widget.settings.fontFamily,
                  ))
                    SettingsChoice(family, _fontFamilyLabel(family)),
                ],
                onChanged: widget.onFontFamilyChanged,
              ),
            ),
          ],
        ),
        SettingsCardGroup(
          key: const ValueKey('appearance-windows-card'),
          title: l10n.settingsAppearanceWindows,
          children: [
            SettingsCardPadding(
              child: SettingsSlider(
                key: settingsCornerRoundnessSliderKey,
                label: l10n.settingsCornerRoundness,
                value: widget.settings.cornerRadiusScale,
                minimum: ShellRoundness.minimum,
                maximum: ShellRoundness.maximum,
                divisions: 40,
                valueLabel: l10n.settingsPercent(
                  (widget.settings.cornerRadiusScale * 100).round(),
                ),
                onChanged: widget.onCornerRadiusScaleChanged,
              ),
            ),
            SettingsCardPadding(
              child: SettingsToggle(
                label: l10n.settingsFocusedWindowBorder,
                description: l10n.settingsFocusedWindowBorderDescription,
                value: widget.settings.focusedWindowBorderEnabled,
                onChanged: widget.onFocusedWindowBorderEnabledChanged,
              ),
            ),
            SettingsDisclosure(
              key: const PageStorageKey('appearance-window-opacity'),
              title: l10n.settingsWindowOpacityTitle,
              description: l10n.settingsWindowOpacityDescription,
              children: [
                SettingsSlider(
                  label: l10n.settingsFocusedWindows,
                  value: widget.settings.focusedWindowOpacity,
                  minimum: 0.35,
                  maximum: 1,
                  divisions: 65,
                  valueLabel: l10n.settingsPercent(
                    (widget.settings.focusedWindowOpacity * 100).round(),
                  ),
                  onChanged: widget.onFocusedOpacityChanged,
                ),
                const SizedBox(height: 12),
                SettingsSlider(
                  label: l10n.settingsUnfocusedWindows,
                  value: widget.settings.unfocusedWindowOpacity,
                  minimum: 0.2,
                  maximum: 1,
                  divisions: 80,
                  valueLabel: l10n.settingsPercent(
                    (widget.settings.unfocusedWindowOpacity * 100).round(),
                  ),
                  onChanged: widget.onUnfocusedOpacityChanged,
                ),
              ],
            ),
          ],
        ),
        _transparencyCard(context),
        SettingsCardGroup(
          key: const ValueKey('appearance-cursor-card'),
          title: l10n.settingsCursorTitle,
          children: [
            _CursorSettings(
              settings: widget.settings,
              themes: widget.cursorThemes,
              catalogLoading: widget.cursorCatalogLoading,
              onThemeChanged: widget.onCursorThemeChanged,
              onSizeChanged: widget.onCursorSizeChanged,
              onAllowClientCursorSurfacesChanged:
                  widget.onAllowClientCursorSurfacesChanged,
              onImport: widget.onImportCursorZip,
              onRemove: widget.onRemoveCursorTheme,
              onError: (error) => setState(() => _cursorError = error),
            ),
          ],
        ),
        SettingsCardGroup(
          key: const ValueKey('appearance-icons-card'),
          title: l10n.settingsIconThemeTitle,
          children: [
            _IconThemeSettings(
              settings: widget.settings,
              themes: widget.iconThemes,
              catalogLoading: widget.iconThemesLoading,
              onThemeChanged: widget.onIconThemeChanged,
              onImport: widget.onImportIconTheme,
              onRemove: widget.onRemoveIconTheme,
            ),
          ],
        ),
      ],
    );
  }

  Widget _transparencyCard(BuildContext context) {
    final l10n = context.l10n;
    final mode = widget.settings.transparencyMode;
    return SettingsCardGroup(
      key: const ValueKey('appearance-transparency-card'),
      title: l10n.settingsAppearanceTransparency,
      children: [
        SettingsCardPadding(
          child: SettingsControlRow(
            label: l10n.settingsTransparencyTitle,
            description: _transparencyDescription(l10n, mode),
            control: SettingsSegmentedControl<ShellTransparencyMode>(
              key: settingsBackdropBlurToggleKey,
              value: widget.settings.transparencyMode,
              choices: <SettingsChoice<ShellTransparencyMode>>[
                SettingsChoice(
                  ShellTransparencyMode.off,
                  l10n.settingsTransparencyOff,
                ),
                SettingsChoice(
                  ShellTransparencyMode.blur,
                  l10n.settingsTransparencyBlur,
                ),
                SettingsChoice(
                  ShellTransparencyMode.glass,
                  l10n.settingsTransparencyGlass,
                ),
              ],
              onChanged: widget.onTransparencyModeChanged,
            ),
          ),
        ),
        if (mode == ShellTransparencyMode.glass) ...[
          SettingsCardPadding(
            child: _GlassControls(
              configuration: widget.settings.glass,
              mobile: widget.mobile,
              onChanged: widget.onGlassChanged,
            ),
          ),
          SettingsCardPadding(
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: SettingsTextButton(
                label: l10n.settingsResetGlassEffects,
                onPressed: _resetGlassEffects,
              ),
            ),
          ),
        ] else ...[
          if (mode == ShellTransparencyMode.blur)
            SettingsCardPadding(
              child: SettingsSlider(
                key: settingsBackdropBlurSliderKey,
                label: l10n.settingsBackdropBlurIntensity,
                value: widget.settings.backdropBlurLevel.index.toDouble(),
                minimum: 0,
                maximum: ShellBackdropBlurLevel.values.length - 1,
                divisions: ShellBackdropBlurLevel.values.length - 1,
                valueLabel: _backdropBlurLevelLabel(
                  l10n,
                  widget.settings.backdropBlurLevel,
                ),
                onChanged: (value) => widget.onBackdropBlurLevelChanged(
                  ShellBackdropBlurLevel.values[value.round()],
                ),
              ),
            ),
          SettingsCardPadding(
            child: Column(
              children: [
                SettingsSlider(
                  label: l10n.settingsPanelOpacity,
                  value: widget.settings.panelOpacity,
                  minimum: ShellOpacity.minimumPanel,
                  maximum: 1,
                  divisions: 95,
                  valueLabel: l10n.settingsPercent(
                    (widget.settings.panelOpacity * 100).round(),
                  ),
                  onChanged: widget.onPanelOpacityChanged,
                ),
                const SizedBox(height: 12),
                SettingsSlider(
                  key: settingsCardOpacitySliderKey,
                  label: l10n.settingsCardOpacity,
                  value: widget.settings.cardOpacity,
                  minimum: ShellOpacity.minimumCard,
                  maximum: 1,
                  divisions: 95,
                  valueLabel: l10n.settingsPercent(
                    (widget.settings.cardOpacity * 100).round(),
                  ),
                  onChanged: widget.onCardOpacityChanged,
                ),
              ],
            ),
          ),
        ],
        if (mode != ShellTransparencyMode.off)
          SettingsDisclosure(
            key: PageStorageKey('appearance-effects-${mode.name}'),
            title: l10n.settingsAppearanceAdvancedEffects,
            description: mode == ShellTransparencyMode.glass
                ? l10n.settingsAppearanceAdvancedEffectsDescription
                : l10n.settingsAppearanceCompositingDescription,
            children: [
              if (mode == ShellTransparencyMode.glass)
                SettingsGlassTuningControls(
                  configuration: widget.settings.glass,
                  onChanged: widget.onGlassChanged,
                  opacityThreshold:
                      widget.settings.backdropBlurOpacityThreshold,
                  onOpacityThresholdChanged:
                      widget.onBackdropBlurOpacityThresholdChanged,
                )
              else
                SettingsSlider(
                  key: settingsBackdropBlurOpacityThresholdKey,
                  label: l10n.settingsBackdropBlurOpacityThreshold,
                  value: widget.settings.backdropBlurOpacityThreshold,
                  minimum: 0,
                  maximum: 1,
                  divisions: 100,
                  valueLabel: l10n.settingsPercent(
                    (widget.settings.backdropBlurOpacityThreshold * 100)
                        .round(),
                  ),
                  onChanged: widget.onBackdropBlurOpacityThresholdChanged,
                ),
            ],
          ),
      ],
    );
  }
}

List<String> _fontFamilyChoices(
  List<String> availableFamilies,
  String selectedFamily,
) {
  if (selectedFamily.isEmpty || availableFamilies.contains(selectedFamily)) {
    return availableFamilies;
  }
  final choices = <String>[...availableFamilies, selectedFamily];
  choices.sort((first, second) {
    final folded = first.toLowerCase().compareTo(second.toLowerCase());
    return folded != 0 ? folded : first.compareTo(second);
  });
  return choices;
}

String _fontFamilyLabel(String family) {
  return family == ShellText.systemBarFontFamily ? 'JetBrains Mono' : family;
}

class _CursorSettings extends StatefulWidget {
  const _CursorSettings({
    required this.settings,
    required this.themes,
    required this.catalogLoading,
    required this.onThemeChanged,
    required this.onSizeChanged,
    required this.onAllowClientCursorSurfacesChanged,
    required this.onImport,
    required this.onRemove,
    required this.onError,
  });

  final ShellAppearanceSettings settings;
  final List<ShellCursorThemeData> themes;
  final bool catalogLoading;
  final ValueChanged<String> onThemeChanged;
  final ValueChanged<double> onSizeChanged;
  final ValueChanged<bool> onAllowClientCursorSurfacesChanged;
  final Future<ShellCursorThemeData?> Function()? onImport;
  final Future<void> Function(ShellCursorThemeData) onRemove;
  final ValueChanged<String?> onError;

  @override
  State<_CursorSettings> createState() => _CursorSettingsState();
}

class _CursorSettingsState extends State<_CursorSettings> {
  bool _busy = false;

  Future<void> _import() async {
    final importer = widget.onImport;
    if (importer == null || _busy) {
      return;
    }
    setState(() {
      _busy = true;
      widget.onError(null);
    });
    try {
      await importer();
    } on CursorThemeException catch (error) {
      if (mounted) {
        widget.onError(error.message);
      }
    } on Object {
      if (mounted) {
        widget.onError(context.l10n.settingsCursorImportFailed);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _remove(ShellCursorThemeData theme) async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      widget.onError(null);
    });
    try {
      await widget.onRemove(theme);
    } on CursorThemeException catch (error) {
      if (mounted) {
        widget.onError(error.message);
      }
    } on Object {
      if (mounted) {
        widget.onError(context.l10n.settingsCursorRemoveFailed);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FocusTraversalGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsCardPadding(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsSlider(
                  key: settingsCursorSizeSliderKey,
                  label: l10n.settingsCursorSize,
                  value: widget.settings.cursorSize,
                  minimum: shellCursorMinimumSize,
                  maximum: shellCursorMaximumSize,
                  divisions:
                      ((shellCursorMaximumSize - shellCursorMinimumSize) / 4)
                          .round(),
                  valueLabel: l10n.settingsPixels(
                    widget.settings.cursorSize.round(),
                  ),
                  onChanged: widget.onSizeChanged,
                ),
                const SizedBox(height: 20),
                SettingsControlRow(
                  label: l10n.settingsCursorTheme,
                  description: '',
                  control: SettingsTextButton(
                    label: _busy
                        ? l10n.settingsCursorImporting
                        : l10n.settingsCursorImport,
                    onPressed: widget.onImport == null || _busy
                        ? null
                        : _import,
                  ),
                ),
                const SizedBox(height: 12),
                if (widget.catalogLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final theme in widget.themes)
                        _CursorThemeCard(
                          theme: theme,
                          selected: theme.id == widget.settings.cursorThemeId,
                          enabled: !_busy,
                          onSelected: () => widget.onThemeChanged(theme.id),
                          onRemove: theme.isImported
                              ? () => _remove(theme)
                              : null,
                        ),
                    ],
                  ),
              ],
            ),
          ),
          Divider(
            height: 1,
            indent: 20,
            endIndent: 20,
            color: context.applicationColors.separator,
          ),
          SettingsDisclosure(
            key: const PageStorageKey('appearance-cursor-advanced'),
            title: l10n.settingsAppearanceCursorAdvanced,
            children: [
              SettingsToggle(
                label: l10n.settingsCursorAllowApplications,
                description: l10n.settingsCursorAllowApplicationsDescription,
                value: widget.settings.allowClientCursorSurfaces,
                onChanged: widget.onAllowClientCursorSurfacesChanged,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CursorThemeCard extends StatefulWidget {
  const _CursorThemeCard({
    required this.theme,
    required this.selected,
    required this.enabled,
    required this.onSelected,
    required this.onRemove,
  });

  final ShellCursorThemeData theme;
  final bool selected;
  final bool enabled;
  final VoidCallback onSelected;
  final VoidCallback? onRemove;

  @override
  State<_CursorThemeCard> createState() => _CursorThemeCardState();
}

class _CursorThemeCardState extends State<_CursorThemeCard> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    final accent = theme.accent;
    final colors = context.applicationColors;
    final enabled = widget.enabled;
    return Semantics(
      button: true,
      selected: widget.selected,
      enabled: enabled,
      label: widget.theme.label,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: enabled
            ? ShellMouseCursors.link
            : SystemMouseCursors.basic,
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              if (enabled) {
                widget.onSelected();
              }
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? widget.onSelected : null,
          child: AnimatedOpacity(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : Motion.tile,
            opacity: enabled ? 1 : 0.52,
            child: AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : Motion.tile,
              width: 250,
              constraints: const BoxConstraints(minHeight: 124),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: widget.selected
                    ? Color.alphaBlend(accent.withAlpha(34), colors.control)
                    : colors.control,
                borderRadius: DenialSurfaceGeometry.borderRadiusOf(context),
                border: Border.all(
                  color: widget.selected
                      ? accent
                      : _hovered || _focused
                      ? colors.foreground
                      : colors.separator,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.theme.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ShellText.cardTitle,
                            ),
                            if (!widget.theme.isImported &&
                                widget.theme.author.trim().isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                widget.theme.author,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: ShellText.base.copyWith(
                                  color: colors.secondary,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (widget.onRemove case final remove?)
                        Tooltip(
                          message: context.l10n.settingsCursorRemove,
                          child: IconButton(
                            onPressed: enabled ? remove : null,
                            icon: const Icon(Icons.delete_outline_rounded),
                            iconSize: 18,
                            visualDensity: VisualDensity.compact,
                          ),
                        )
                      else if (widget.selected)
                        Icon(
                          Icons.check_circle_rounded,
                          size: 18,
                          color: accent,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  RepaintBoundary(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (final kind in const <ShellCursorKind>[
                          ShellCursorKind.normal,
                          ShellCursorKind.link,
                          ShellCursorKind.text,
                          ShellCursorKind.working,
                          ShellCursorKind.busy,
                        ])
                          SizedBox.square(
                            dimension: 34,
                            child: Center(
                              child: ShellCursorArtwork(
                                theme: widget.theme,
                                kind: kind,
                                longestEdge: 28,
                                running: enabled,
                              ),
                            ),
                          ),
                      ],
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

String _transparencyDescription(
  AppLocalizations l10n,
  ShellTransparencyMode mode,
) {
  return switch (mode) {
    ShellTransparencyMode.off => l10n.settingsTransparencyOffDescription,
    ShellTransparencyMode.blur => l10n.settingsTransparencyBlurDescription,
    ShellTransparencyMode.glass => l10n.settingsTransparencyGlassDescription,
  };
}

class _GlassControls extends StatelessWidget {
  const _GlassControls({
    required this.configuration,
    required this.mobile,
    required this.onChanged,
  });

  final ShellGlassConfiguration configuration;

  /// Phone apps never draw glass groups below the appearance's floor, so the
  /// App panels slider starts there instead of showing values that do
  /// nothing. A saved value below it is shown, not rewritten, as the floor.
  final bool mobile;
  final ValueChanged<ShellGlassConfiguration> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    String percent(double value) => l10n.settingsPercent((value * 100).round());
    final appPanelMinimum = mobile ? configuration.mobileAppPanelFloor : 0.0;
    final appPanelOpacity = math.max(
      configuration.appPanelOpacity,
      appPanelMinimum,
    );

    return Column(
      children: [
        SettingsControlRow(
          label: l10n.settingsGlassAppearance,
          description: '',
          control: SettingsSegmentedControl<ShellGlassAppearance>(
            key: const ValueKey('settings-glass-appearance'),
            value: configuration.appearance,
            choices: [
              SettingsChoice(
                ShellGlassAppearance.dark,
                l10n.settingsColorSchemeDark,
              ),
              SettingsChoice(
                ShellGlassAppearance.light,
                l10n.settingsColorSchemeLight,
              ),
            ],
            onChanged: (value) =>
                onChanged(configuration.copyWith(appearance: value)),
          ),
        ),
        const SizedBox(height: 12),
        SettingsSlider(
          key: const ValueKey('settings-glass-shell-opacity'),
          label: l10n.settingsGlassShellOpacity,
          value: configuration.opacity,
          minimum: 0,
          maximum: 1,
          divisions: 100,
          valueLabel: percent(configuration.opacity),
          onChanged: (value) =>
              onChanged(configuration.copyWith(opacity: value)),
        ),
        const SizedBox(height: 8),
        SettingsSlider(
          key: const ValueKey('settings-glass-window-opacity'),
          label: l10n.settingsGlassWindowOpacity,
          value: configuration.windowOpacity,
          minimum: 0,
          maximum: 1,
          divisions: 100,
          valueLabel: percent(configuration.windowOpacity),
          onChanged: (value) =>
              onChanged(configuration.copyWith(windowOpacity: value)),
        ),
        const SizedBox(height: 8),
        SettingsSlider(
          key: const ValueKey('settings-glass-app-panel-opacity'),
          label: l10n.settingsGlassAppPanelOpacity,
          value: appPanelOpacity,
          minimum: appPanelMinimum,
          maximum: 1,
          divisions: ((1 - appPanelMinimum) * 100).round(),
          valueLabel: percent(appPanelOpacity),
          onChanged: (value) =>
              onChanged(configuration.copyWith(appPanelOpacity: value)),
        ),
        const SizedBox(height: 8),
        SettingsSlider(
          label: l10n.settingsGlassFrost,
          value: configuration.blurSigma,
          minimum: ShellGlassConfiguration.minimumBlurSigma,
          maximum: ShellGlassConfiguration.maximumBlurSigma,
          divisions: 30,
          valueLabel: l10n.settingsPixels(configuration.blurSigma.round()),
          onChanged: (value) =>
              onChanged(configuration.copyWith(blurSigma: value)),
        ),
      ],
    );
  }
}

String _backdropBlurLevelLabel(
  AppLocalizations l10n,
  ShellBackdropBlurLevel level,
) {
  return switch (level) {
    ShellBackdropBlurLevel.shitty => l10n.settingsBackdropBlurLevelShitty,
    ShellBackdropBlurLevel.fast => l10n.settingsBackdropBlurLevelFast,
    ShellBackdropBlurLevel.good => l10n.settingsBackdropBlurLevelGood,
    ShellBackdropBlurLevel.best => l10n.settingsBackdropBlurLevelBest,
  };
}

/// A short palette of shell accents, so a colour can be picked without
/// opening the wheel. The wheel stays for anything else.
const _accentPresets = <Color>[
  Color(0xFF11733C),
  Color(0xFF2F9E6F),
  Color(0xFF2F6FEB),
  Color(0xFF7C5CD6),
  Color(0xFFD9822B),
  Color(0xFFD94F4F),
  Color(0xFF1F9E9E),
  Color(0xFFD9538C),
];

class _AccentPresets extends StatelessWidget {
  const _AccentPresets({required this.selected, required this.onSelected});

  final Color selected;
  final ValueChanged<Color> onSelected;

  @override
  Widget build(BuildContext context) {
    final selectedValue = selected.toARGB32();
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: context.l10n.settingsShellAccentPresets,
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final color in _accentPresets)
            Builder(
              builder: (context) {
                final active = color.toARGB32() == selectedValue;
                return Semantics(
                  button: true,
                  selected: active,
                  label: formatOpaqueColorHex(color),
                  child: GestureDetector(
                    onTap: () => onSelected(color),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: active
                              ? context.applicationColors.foreground
                              : context.applicationColors.separator,
                          width: active ? 2 : 1,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// The icon theme grid, with install and remove.
class _IconThemeSettings extends StatefulWidget {
  const _IconThemeSettings({
    required this.settings,
    required this.themes,
    required this.catalogLoading,
    required this.onThemeChanged,
    required this.onImport,
    required this.onRemove,
  });

  final ShellAppearanceSettings settings;
  final List<ShellIconThemeData> themes;
  final bool catalogLoading;
  final ValueChanged<String> onThemeChanged;
  final Future<List<ShellIconThemeData>> Function()? onImport;
  final Future<void> Function(ShellIconThemeData) onRemove;

  @override
  State<_IconThemeSettings> createState() => _IconThemeSettingsState();
}

class _IconThemeSettingsState extends State<_IconThemeSettings> {
  bool _busy = false;
  String? _error;
  String? _status;

  Future<void> _import() async {
    final import = widget.onImport;
    if (import == null || _busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
    });
    try {
      final installed = await import();
      if (!mounted || installed.isEmpty) {
        return;
      }
      setState(() {
        _status = context.l10n.settingsIconThemeInstalled(
          installed.map((theme) => theme.name).join('\u3001'),
        );
      });
      // A theme the user went to the trouble of installing is the one they
      // want to see, so it becomes the choice.
      widget.onThemeChanged(installed.first.id);
    } on IconThemeException catch (error) {
      if (mounted) {
        setState(() {
          _error = context.l10n.settingsIconThemeInstallFailed(
            _reason(context, error.code),
          );
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _error = context.l10n.settingsIconThemeInstallFailed(
            context.l10n.commonError,
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  String _reason(BuildContext context, String code) {
    final l10n = context.l10n;
    return switch (code) {
      'missing' => l10n.settingsIconThemeErrorMissing,
      'empty' => l10n.settingsIconThemeErrorEmpty,
      'too-large' => l10n.settingsIconThemeErrorTooLarge,
      'unsupported' => l10n.settingsIconThemeErrorUnsupported,
      'unsafe' => l10n.settingsIconThemeErrorUnsafe,
      'no-theme' => l10n.settingsIconThemeErrorNoTheme,
      _ => l10n.settingsIconThemeErrorExtract,
    };
  }

  Future<void> _remove(ShellIconThemeData theme) async {
    if (_busy) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.settingsIconThemeDeleteTitle),
        content: Text(context.l10n.settingsIconThemeDeleteBody(theme.name)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.settingsIconThemeDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
    });
    try {
      await widget.onRemove(theme);
      if (widget.settings.iconTheme == theme.id) {
        widget.onThemeChanged('');
      }
      if (mounted) {
        setState(() => _status = null);
      }
    } on IconThemeException catch (error) {
      if (mounted) {
        setState(() {
          _error = context.l10n.settingsIconThemeInstallFailed(
            _reason(context, error.code),
          );
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _error = context.l10n.settingsIconThemeInstallFailed(
            context.l10n.commonError,
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.applicationColors;
    // No stored choice means Denial's default theme is the one in use, so the
    // grid marks it rather than opening with nothing selected.
    final selectedId = widget.settings.iconTheme.isEmpty
        ? defaultIconTheme
        : widget.settings.iconTheme;
    return SettingsCardPadding(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.settingsIconThemeLabel,
                      style: ShellText.cardTitle,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.catalogLoading
                          ? l10n.settingsIconThemeLoading
                          : l10n.settingsIconThemeDescription,
                      style: ShellText.base.copyWith(
                        color: colors.secondary,
                        fontSize: 11.5,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              _IconThemeInstallButton(
                label: l10n.settingsIconThemeInstall,
                busy: _busy,
                enabled: widget.onImport != null && !_busy,
                onPressed: _import,
              ),
            ],
          ),
          if (_error case final error?) ...[
            const SizedBox(height: 12),
            _IconThemeNotice(message: error, error: true),
          ],
          if (_status case final status?) ...[
            const SizedBox(height: 12),
            _IconThemeNotice(message: status, error: false),
          ],
          const SizedBox(height: 14),
          if (widget.catalogLoading && widget.themes.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                const gap = 12.0;
                final columns = (constraints.maxWidth / 262).floor().clamp(
                  2,
                  5,
                );
                final width =
                    (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: <Widget>[
                    for (final theme in widget.themes)
                      _IconThemeCard(
                        title: theme.name,
                        width: width,
                        previews: theme.previews,
                        selected: theme.id == selectedId,
                        enabled: !_busy,
                        onSelected: () => widget.onThemeChanged(theme.id),
                        builtIn: theme.id == defaultIconTheme,
                        onRemove:
                            theme.userInstalled && theme.id != defaultIconTheme
                            ? () => _remove(theme)
                            : null,
                      ),
                  ],
                );
              },
            ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                Icons.info_outline_rounded,
                size: 13,
                color: colors.secondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.settingsIconThemeHint,
                  style: ShellText.base.copyWith(
                    color: colors.secondary,
                    fontSize: 11,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IconThemeInstallButton extends StatelessWidget {
  const _IconThemeInstallButton({
    required this.label,
    required this.busy,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onPressed : null,
        child: AnimatedOpacity(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : Motion.tile,
          opacity: enabled ? 1 : 0.5,
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: theme.accent.withAlpha(26),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: theme.accent.withAlpha(110)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (busy)
                  SizedBox.square(
                    dimension: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.accent,
                    ),
                  )
                else
                  Icon(
                    Icons.file_download_outlined,
                    size: 15,
                    color: theme.accent,
                  ),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: ShellText.base.copyWith(
                    color: theme.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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

class _IconThemeNotice extends StatelessWidget {
  const _IconThemeNotice({required this.message, required this.error});

  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final color = error
        ? context.shellColors.performanceBad
        : context.shellColors.performanceGood;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(70)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            error ? Icons.error_outline_rounded : Icons.check_circle_outline,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: ShellText.base.copyWith(
                color: color,
                fontSize: 11.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One theme in the grid: its sample icons, name, and selected/remove state.
class _IconThemeCard extends StatefulWidget {
  const _IconThemeCard({
    required this.title,
    required this.width,
    required this.previews,
    required this.selected,
    required this.enabled,
    required this.onSelected,
    this.builtIn = false,
    this.onRemove,
  });

  final String title;
  final double width;
  final List<String> previews;
  final bool selected;
  final bool enabled;
  final VoidCallback onSelected;
  final bool builtIn;
  final VoidCallback? onRemove;

  @override
  State<_IconThemeCard> createState() => _IconThemeCardState();
}

class _IconThemeCardState extends State<_IconThemeCard> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    final accent = theme.accent;
    final colors = context.applicationColors;
    final enabled = widget.enabled;
    final previews = widget.previews;
    return Semantics(
      button: true,
      selected: widget.selected,
      enabled: enabled,
      label: widget.title,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: enabled
            ? ShellMouseCursors.link
            : SystemMouseCursors.basic,
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              if (enabled) {
                widget.onSelected();
              }
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? widget.onSelected : null,
          onLongPress: enabled && widget.onRemove != null
              ? widget.onRemove
              : null,
          child: AnimatedOpacity(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : Motion.tile,
            opacity: enabled ? 1 : 0.52,
            child: AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : Motion.tile,
              width: widget.width,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: widget.selected
                    ? Color.alphaBlend(accent.withAlpha(30), colors.control)
                    : colors.control,
                borderRadius: DenialSurfaceGeometry.borderRadiusOf(context),
                border: Border.all(
                  color: widget.selected
                      ? accent
                      : _hovered || _focused
                      ? colors.foreground
                      : colors.separator,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ShellText.cardTitle,
                        ),
                      ),
                      if (widget.builtIn)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: accent.withAlpha(28),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            context.l10n.settingsIconThemeBuiltInBadge,
                            style: ShellText.base.copyWith(
                              color: accent,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      else if (widget.onRemove case final remove?)
                        Tooltip(
                          message: context.l10n.settingsIconThemeDelete,
                          child: IconButton(
                            onPressed: enabled ? remove : null,
                            icon: const Icon(Icons.delete_outline_rounded),
                            iconSize: 18,
                            visualDensity: VisualDensity.compact,
                          ),
                        )
                      else if (widget.selected)
                        Icon(
                          Icons.check_circle_rounded,
                          size: 18,
                          color: accent,
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Stack(
                    children: <Widget>[
                      Container(
                        height: 112,
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: colors.canvas,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          children: <Widget>[
                            for (var row = 0; row < 2; row += 1)
                              Expanded(
                                child: Row(
                                  children: <Widget>[
                                    for (
                                      var column = 0;
                                      column < 3;
                                      column += 1
                                    )
                                      Expanded(
                                        child: Center(
                                          child: SizedBox.square(
                                            dimension: 34,
                                            child: AppIconImage(
                                              iconPath:
                                                  row * 3 + column <
                                                      previews.length
                                                  ? previews[row * 3 + column]
                                                  : null,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (widget.selected && widget.onRemove != null)
                        Positioned(
                          right: 6,
                          top: 6,
                          child: Icon(
                            Icons.check_circle_rounded,
                            size: 17,
                            color: accent,
                          ),
                        ),
                    ],
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
