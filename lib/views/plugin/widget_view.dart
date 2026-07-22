import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/plugin/plugin_runtime.dart';
import '../common/glass.dart';

/// 把插件 render() 返回的 JSON widget 树渲染为 Flutter 组件。
/// 事件（onTap/onChanged）回调插件的 onAction(name, args)。
class PluginWidgetView extends StatefulWidget {
  final PluginRuntime runtime;
  const PluginWidgetView({super.key, required this.runtime});

  @override
  State<PluginWidgetView> createState() => _PluginWidgetViewState();
}

class _PluginWidgetViewState extends State<PluginWidgetView> {
  Map<String, dynamic>? _tree;
  final _controllers = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    widget.runtime.onRerender = _refresh;
    _refresh();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _refresh() {
    final json = widget.runtime.renderJson();
    if (!mounted) return;
    setState(() {
      _tree = json == null ? null : jsonDecode(json) as Map<String, dynamic>;
    });
  }

  void _action(String? name,
      {Map<String, dynamic>? args, bool reRender = true}) {
    if (name == null || name.isEmpty) return;
    if (name == '__exit__') {
      Navigator.of(context).pop();
      return;
    }
    widget.runtime.action(name, args);
    if (reRender) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (_tree == null) {
      return const Center(child: Text('该插件无可渲染界面'));
    }
    return KeyboardListener(
      focusNode: FocusNode(),
      autofocus: true,
      onKeyEvent: (e) {
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.space) {
          widget.runtime.action('__key__', {'key': 'space'});
          _refresh();
        }
      },
      child: _build(_tree!),
    );
  }

  Widget _build(Map<String, dynamic> n) {
    final type = n['type'] as String? ?? 'text';
    switch (type) {
      case 'column':
        return Column(
          crossAxisAlignment: _crossAlign(n['crossAxisAlignment']),
          mainAxisAlignment: _mainAlign(n['mainAxisAlignment']),
          mainAxisSize: MainAxisSize.min,
          children: _kids(n),
        );
      case 'row':
        return Row(
          crossAxisAlignment: _crossAlign(n['crossAxisAlignment']),
          mainAxisAlignment: _mainAlign(n['mainAxisAlignment']),
          children: _kids(n),
        );
      case 'wrap':
        return Wrap(
          alignment: _wrapAlign(n['mainAxisAlignment']),
          spacing: (n['spacing'] as num?)?.toDouble() ?? 4,
          runSpacing: (n['runSpacing'] as num?)?.toDouble() ?? 4,
          children: _kids(n),
        );
      case 'expanded':
        return Expanded(child: _only(n));
      case 'center':
        return Center(child: _only(n));
      case 'padding':
        final e = (n['edge'] as num?)?.toDouble() ?? 12;
        return Padding(padding: EdgeInsets.all(e), child: _only(n));
      case 'sizedbox':
        return SizedBox(
          width: (n['width'] as num?)?.toDouble(),
          height: (n['height'] as num?)?.toDouble(),
          child: n.containsKey('child') ? _build(n['child'] as Map<String, dynamic>) : null,
        );
      case 'card':
        final onTap = n['onTap'] as String?;
        return GlassCard(
          onTap: (onTap != null && onTap.isNotEmpty)
              ? () => _action(onTap)
              : null,
          padding: EdgeInsets.all((n['padding'] as num?)?.toDouble() ?? 12),
          child: n.containsKey('child')
              ? _build(n['child'] as Map<String, dynamic>)
              : (n['children'] != null ? Column(children: _kids(n)) : const SizedBox()),
        );
      case 'text':
        return Text(n['text'] ?? '', style: _textStyle(n));
      case 'icon':
        return Icon(_icon(n['icon']),
            size: (n['size'] as num?)?.toDouble() ?? 20,
            color: _color(n['color']));
      case 'button':
        final filled = n['variant'] != 'outlined';
        final label = _only(n);
        return SizedBox(
          width: n['expanded'] == true ? double.infinity : null,
          child: filled
              ? (n['variant'] == 'tonal'
                  ? FilledButton.tonalIcon(
                      onPressed: () => _action(n['onTap'] as String?),
                      icon: n['icon'] != null ? Icon(_icon(n['icon']), size: 18) : const SizedBox.shrink(),
                      label: label is Text ? label : Text('${n['label'] ?? ''}'))
                  : FilledButton.icon(
                      onPressed: () => _action(n['onTap'] as String?),
                      icon: n['icon'] != null ? Icon(_icon(n['icon']), size: 18) : const SizedBox.shrink(),
                      label: label is Text ? label : Text('${n['label'] ?? ''}')))
              : OutlinedButton.icon(
                  onPressed: () => _action(n['onTap'] as String?),
                  icon: n['icon'] != null ? Icon(_icon(n['icon']), size: 18) : const SizedBox.shrink(),
                  label: label is Text ? label : Text('${n['label'] ?? ''}')),
        );
      case 'textfield':
        final key = (n['key'] as String?) ?? '${n['label'] ?? 'f'}';
        final c = _controllers.putIfAbsent(key, () => TextEditingController(text: '${n['value'] ?? ''}'));
        return TextField(
          controller: c,
          decoration: InputDecoration(
            labelText: n['label'] as String?,
            hintText: n['hint'] as String?,
            isDense: n['dense'] == true,
            border: const OutlineInputBorder(),
          ),
          keyboardType: n['keyboard'] == 'number'
              ? TextInputType.number
              : TextInputType.text,
          onChanged: (v) => _action(n['onChanged'] as String?,
              args: {'value': v}, reRender: false),
        );
      case 'checkbox':
        return Row(mainAxisSize: MainAxisSize.min, children: [
          Checkbox(
            value: n['value'] == true,
            onChanged: (v) => _action(n['onChanged'] as String?, args: {'value': v}),
          ),
          if (n['label'] != null) Text('${n['label']}'),
        ]);
      case 'segmented':
        final opts = (n['options'] as List?) ?? const [];
        final cur = n['value'];
        final segments = <ButtonSegment<dynamic>>[
          for (final o in opts)
            ButtonSegment<dynamic>(
                value: o is Map ? o['value'] : o,
                label: Text('${o is Map ? o['label'] ?? o['value'] : o}')),
        ];
        return SegmentedButton<dynamic>(
          segments: segments,
          selected: cur == null ? <dynamic>{} : <dynamic>{cur},
          showSelectedIcon: false,
          onSelectionChanged: (s) {
            if (s.isNotEmpty) _action(n['onChanged'] as String?, args: {'value': s.first});
          },
        );
      case 'divider':
        return const Divider(height: 1);
      case 'progress':
        final v = ((n['value'] as num?) ?? 0).toDouble().clamp(0.0, 1.0);
        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: v,
            minHeight: (n['height'] as num?)?.toDouble() ?? 8,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            color: _color(n['color']) ?? Theme.of(context).colorScheme.primary,
          ),
        );
      case 'badge':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: _color(n['color']) ?? Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text('${n['text'] ?? ''}',
              style: TextStyle(
                  fontSize: 11,
                  color: n['color'] != null
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSecondaryContainer)),
        );
      case 'spacer':
        return const Spacer();
      case 'slider':
        final slVal = ((n['value'] as num?) ?? 0).toDouble();
        final slMin = ((n['min'] as num?) ?? 0).toDouble();
        final slMax = ((n['max'] as num?) ?? 10).toDouble();
        final slDiv = n['divisions'] as int?;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Expanded(
                child: Slider(
                  value: slVal.clamp(slMin, slMax),
                  min: slMin,
                  max: slMax,
                  divisions: slDiv,
                  label: n['label'] as String? ?? slVal.toStringAsFixed(0),
                  onChanged: (v) => _action(n['onChanged'] as String?,
                      args: {'value': v}, reRender: false),
                  onChangeEnd: (v) =>
                      _action(n['onChanged'] as String?, args: {'value': v}),
                ),
              ),
              SizedBox(
                width: 32,
                child: Text(slVal.toStringAsFixed(0),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary)),
              ),
            ],
          ),
        );
      case 'empty':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_icon(n['icon']),
                  size: 48,
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35)),
              const SizedBox(height: 12),
              Text(n['title'] ?? '',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
              if (n['subtitle'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(n['subtitle'] as String,
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                      textAlign: TextAlign.center),
                ),
              if (n['actionLabel'] != null) ...[
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  onPressed: () => _action(n['action'] as String?),
                  icon: Icon(_icon(n['actionIcon']), size: 18),
                  label: Text(n['actionLabel'] as String),
                ),
              ],
            ],
          ),
        );
      default:
        return const SizedBox();
    }
  }

  List<Widget> _kids(Map<String, dynamic> n) =>
      ((n['children'] as List?) ?? const [])
          .map((c) => _build(c as Map<String, dynamic>))
          .toList();

  Widget _only(Map<String, dynamic> n) => n.containsKey('child')
      ? _build(n['child'] as Map<String, dynamic>)
      : (n['text'] != null
          ? Text('${n['text']}', style: _textStyle(n))
          : const SizedBox());

  TextStyle? _textStyle(Map<String, dynamic> n) {
    final s = n['style'] as Map<String, dynamic>?;
    if (s == null && n['size'] == null && n['weight'] == null) return null;
    final cs = Theme.of(context).colorScheme;
    return TextStyle(
      fontSize: (n['size'] as num?)?.toDouble() ?? (s?['size'] as num?)?.toDouble(),
      fontWeight: n['weight'] == 'bold' || s?['weight'] == 'bold'
          ? FontWeight.bold
          : FontWeight.normal,
      color: _color(n['color']) ?? _color(s?['color']) ?? cs.onSurface,
    );
  }

  CrossAxisAlignment _crossAlign(Object? v) {
    switch (v) {
      case 'center':
        return CrossAxisAlignment.center;
      case 'end':
        return CrossAxisAlignment.end;
      case 'stretch':
        return CrossAxisAlignment.stretch;
      default:
        return CrossAxisAlignment.start;
    }
  }

  MainAxisAlignment _mainAlign(Object? v) {
    switch (v) {
      case 'center':
        return MainAxisAlignment.center;
      case 'end':
        return MainAxisAlignment.end;
      case 'between':
        return MainAxisAlignment.spaceBetween;
      case 'around':
        return MainAxisAlignment.spaceAround;
      default:
        return MainAxisAlignment.start;
    }
  }

  WrapAlignment _wrapAlign(Object? v) {
    switch (v) {
      case 'center':
        return WrapAlignment.center;
      case 'end':
        return WrapAlignment.end;
      case 'between':
        return WrapAlignment.spaceBetween;
      case 'around':
        return WrapAlignment.spaceAround;
      default:
        return WrapAlignment.start;
    }
  }

  IconData _icon(Object? name) {
    switch (name) {
      case 'add':
        return Icons.add;
      case 'remove':
        return Icons.remove;
      case 'delete':
        return Icons.delete_outline;
      case 'casino':
        return Icons.casino;
      case 'history':
        return Icons.history;
      case 'settings':
        return Icons.settings_outlined;
      case 'list':
        return Icons.list;
      case 'play':
        return Icons.play_arrow;
      case 'shuffle':
        return Icons.shuffle;
      case 'refresh':
        return Icons.refresh;
      case 'save':
        return Icons.save_outlined;
      case 'star':
        return Icons.star;
      case 'gift':
        return Icons.card_giftcard;
      default:
        return Icons.extension;
    }
  }

  Color? _color(Object? c) {
    if (c == null) return null;
    switch (c) {
      case 'primary':
        return Theme.of(context).colorScheme.primary;
      case 'error':
        return Theme.of(context).colorScheme.error;
      case 'muted':
        return Theme.of(context).colorScheme.onSurfaceVariant;
      case 'white':
        return Colors.white;
      default:
        if (c is String && c.startsWith('#')) {
          return Color(int.parse(c.substring(1), radix: 16) | 0xFF000000);
        }
        return null;
    }
  }
}
