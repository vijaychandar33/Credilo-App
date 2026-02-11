import 'dart:async';
import 'dart:ui';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_colors.dart';
import '../services/auth_service.dart';

class InternetStatusOverlay extends StatefulWidget {
  final Widget child;

  const InternetStatusOverlay({super.key, required this.child});

  @override
  State<InternetStatusOverlay> createState() => _InternetStatusOverlayState();
}

class _InternetStatusOverlayState extends State<InternetStatusOverlay> {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _isOffline = false;
  bool _isChecking = false;
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _initConnectivity();
    _subscription = _connectivity.onConnectivityChanged.listen((result) {
      final current = result.isNotEmpty ? result.first : ConnectivityResult.none;
      final wasOffline = _isOffline;
      final offline = current == ConnectivityResult.none;
      if (mounted) {
        setState(() {
          _isOffline = offline;
        });
      }
      if (wasOffline && !offline) {
        _onReconnected();
      }
    });
  }

  Future<void> _initConnectivity() async {
    final result = await _connectivity.checkConnectivity();
    if (!mounted) return;
    final isOffline = result.isEmpty ||
        result.every((r) => r == ConnectivityResult.none);
    setState(() {
      _isOffline = isOffline;
    });
  }

  Future<void> _checkStatusNow() async {
    if (_isChecking) return;
    setState(() {
      _isChecking = true;
    });
    try {
      final result = await _connectivity.checkConnectivity();
      if (!mounted) return;
      final isOffline = result.isEmpty ||
          result.every((r) => r == ConnectivityResult.none);
      setState(() {
        _isOffline = isOffline;
      });
      if (!isOffline) {
        _onReconnected();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isChecking = false;
        });
      }
    }
  }

  Future<void> _onReconnected() async {
    // When internet comes back, refresh user and branch data so that
    // profile, branches, and permissions are up to date.
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        await _authService.refreshUserData();
        await _authService.refreshBranches();
      }
    } catch (_) {
      // Ignore errors here; individual screens will handle their own failures.
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_isOffline) _buildOverlay(context),
      ],
    );
  }

  Widget _buildOverlay(BuildContext context) {
    return Positioned.fill(
      child: AbsorbPointer(
        absorbing: true,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Container(
            color: Colors.black.withValues(alpha: 0.6),
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Material(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(16),
                  elevation: 8,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.wifi_off_rounded,
                          size: 48,
                          color: AppColors.error,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Internet is not connected. Please connect to the internet.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _checkStatusNow,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: _isChecking
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text(
                                    'Check Status Now',
                                    style: TextStyle(fontSize: 16),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

