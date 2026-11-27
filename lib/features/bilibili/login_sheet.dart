import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme.dart';
import 'bili_auth.dart';
import 'bili_models.dart';

/// 扫码登录弹层。
class LoginSheet extends StatefulWidget {
  const LoginSheet({
    super.key,
    required this.auth,
    this.onSuccess,
  });

  final BiliAuthService auth;
  final Future<void> Function()? onSuccess;

  @override
  State<LoginSheet> createState() => _LoginSheetState();
}

class _LoginSheetState extends State<LoginSheet> {
  QrChallenge? _challenge;
  String _status = '正在生成二维码…';
  String? _error;
  Timer? _timer;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final QrChallenge challenge = await widget.auth.createQr();
      if (!mounted) return;
      setState(() {
        _challenge = challenge;
        _status = '打开 B 站 App 扫码，并在手机上确认登录';
        _error = null;
      });
      _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _describe(e));
    }
  }

  Future<void> _poll() async {
    final QrChallenge? challenge = _challenge;
    if (challenge == null || _polling) return;
    _polling = true;
    try {
      final QrPollResult result = await widget.auth.pollQr(challenge.key);
      if (!mounted) return;
      switch (result.status) {
        case QrPollStatus.waiting:
          setState(() => _status = '等待扫码…');
        case QrPollStatus.scanned:
          setState(() => _status = '已扫码，请在手机上确认');
        case QrPollStatus.expired:
          _timer?.cancel();
          setState(() {
            _status = '二维码已过期';
            _error = '请关闭后重新打开登录窗口';
          });
        case QrPollStatus.failure:
          _timer?.cancel();
          setState(() => _error = result.message ?? '登录失败');
        case QrPollStatus.success:
          _timer?.cancel();
          setState(() => _status = '登录成功');
          await widget.onSuccess?.call();
          if (mounted) Navigator.of(context).pop(true);
      }
    } catch (e) {
      _timer?.cancel();
      if (mounted) setState(() => _error = _describe(e));
    } finally {
      _polling = false;
    }
  }

  String _describe(Object error) {
    if (error is BiliException) return error.friendly;
    return '登录请求失败：$error';
  }

  @override
  Widget build(BuildContext context) {
    final QrChallenge? challenge = _challenge;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text(
            '扫码登录 B 站',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          const Text(
            '登录后可使用账号权限获取更高码率音轨',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: challenge == null
                ? const SizedBox(
                    width: 200,
                    height: 200,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : QrImageView(
                    data: challenge.url,
                    size: 200,
                    backgroundColor: Colors.white,
                    padding: EdgeInsets.zero,
                  ),
          ),
          const SizedBox(height: 16),
          Text(
            _status,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Color(0xFFE2725B)),
            ),
          ],
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }
}
