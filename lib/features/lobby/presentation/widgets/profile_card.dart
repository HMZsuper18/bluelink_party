import 'package:flutter/material.dart';

import '../../../../core/theme/acrylic.dart';
import '../../../../core/theme/app_colors.dart';

/// Player identity card: editable name + session short id.
class ProfileCard extends StatefulWidget {
  const ProfileCard({
    super.key,
    required this.name,
    required this.playerId,
    required this.onSaved,
  });

  final String name;
  final String playerId;
  final ValueChanged<String> onSaved;

  @override
  State<ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<ProfileCard> {
  late final TextEditingController _controller;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.name);
    _controller.addListener(_onChanged);
  }

  void _onChanged() {
    final dirty = _controller.text.trim() != widget.name;
    if (dirty != _dirty) {
      setState(() => _dirty = dirty);
    }
  }

  @override
  void didUpdateWidget(covariant ProfileCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.name != widget.name) {
      if (_controller.text != widget.name) {
        _controller.text = widget.name;
      }
      _onChanged();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final value = _controller.text.trim();
    if (value.isNotEmpty) {
      widget.onSaved(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.person_rounded,
                    color: AppColors.accent, size: 18),
              ),
              const SizedBox(width: 10),
              const Text(
                'Player Profile',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                '#${widget.playerId}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            textCapitalization: TextCapitalization.words,
            maxLength: 16,
            style: const TextStyle(
                color: AppColors.textPrimary, fontSize: 14.5),
            decoration: const InputDecoration(
              hintText: 'Enter your player name',
              counterText: '',
              prefixIcon: Icon(Icons.edit_rounded,
                  size: 18, color: AppColors.textMuted),
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 8),
          if (_dirty)
            Align(
              alignment: Alignment.centerRight,
              child: GlassButton(
                label: 'Save Name',
                compact: true,
                background: AppColors.accent.withValues(alpha: 0.12),
                onPressed: _save,
              ),
            ),
        ],
      ),
    );
  }
}
