import 'dart:async';
import 'dart:ui';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

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
  bool _updateRequired = false;
  String? _updateUrl;
  bool _checkedUpdate = false;

  @override
  void initState() {
    super.initState();
    _initConnectivity();
    // Check for required app updates shortly after startup.
    // This runs once per app launch.
    scheduleMicrotask(_ensureCheckedForUpdate);
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

    if (!isOffline) {
      // If we already have internet on startup, ensure we have
      // checked the remote app update configuration.
      await _ensureCheckedForUpdate();
    }
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
        if (_updateRequired) _buildForceUpdateOverlay(context),
      ],
    );
  }

  Widget _buildOverlay(BuildContext context) {
    return Positioned.fill(
      child: AbsorbPointer(
        absorbing: false,
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

  /// Build a global \"Force Update\" overlay similar to the internet popup.
  Widget _buildForceUpdateOverlay(BuildContext context) {
    return Positioned.fill(
      child: AbsorbPointer(
        absorbing: false,
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
                          Icons.system_update_alt_rounded,
                          size: 48,
                          color: AppColors.primary,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'This app version is outdated. Please update the app to continue.',
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
                            onPressed: _onUpdateNowPressed,
                            style: ElevatedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text(
                              'Update Now',
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

  Future<void> _ensureCheckedForUpdate() async {
    if (_checkedUpdate) return;
    _checkedUpdate = true;

    try {
      debugPrint('[ForceUpdate] Checking app update config...');
      final pkg = await PackageInfo.fromPlatform();
      final currentVersion = pkg.version;
      debugPrint('[ForceUpdate] Current app version: $currentVersion');

      final client = Supabase.instance.client;
      final rows = await client
          .from('app_updates')
          .select()
          .order('created_at', ascending: false)
          .limit(1)
          .then((value) => value as List<dynamic>);

      if (rows.isEmpty) {
        debugPrint('[ForceUpdate] No app_updates rows found.');
        return;
      }

      final response = rows.first as Map<String, dynamic>;
      debugPrint('[ForceUpdate] Loaded config: $response');

      final isActive = response['is_active'] == true;
      final minimumVersion = (response['minimum_version'] ?? '').toString();
      final url = response['update_url']?.toString();

      if (!isActive || minimumVersion.isEmpty) return;

      if (_isVersionLower(currentVersion, minimumVersion)) {
        debugPrint(
            '[ForceUpdate] Update required. minimum=$minimumVersion, current=$currentVersion');
        if (mounted) {
          setState(() {
            _updateRequired = true;
            _updateUrl = url;
          });
        } else {
          _updateRequired = true;
          _updateUrl = url;
        }
      }
    } catch (_) {
      // If anything fails, silently ignore; app continues normally.
    }
  }

  bool _isVersionLower(String current, String minimum) {
    List<int> parse(String v) =>
        v.split('.').map((p) => int.tryParse(p) ?? 0).toList();

    final c = parse(current);
    final m = parse(minimum);
    final maxLen = c.length > m.length ? c.length : m.length;
    for (var i = 0; i < maxLen; i++) {
      final cv = i < c.length ? c[i] : 0;
      final mv = i < m.length ? m[i] : 0;
      if (cv < mv) return true;
      if (cv > mv) return false;
    }
    return false;
  }

  Future<void> _onUpdateNowPressed() async {
    final urlString = _updateUrl;
    if (urlString == null || urlString.isEmpty) {
      debugPrint('[ForceUpdate] Update URL is empty, cannot launch.');
      return;
    }
    final uri = Uri.tryParse(urlString);
    if (uri == null) {
      debugPrint('[ForceUpdate] Invalid update URL: $urlString');
      return;
    }

    final can = await canLaunchUrl(uri);
    debugPrint('[ForceUpdate] Trying to launch $uri, canLaunch=$can');
    if (!can) {
      return;
    }

    final launched =
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    debugPrint('[ForceUpdate] launchUrl result: $launched');
  }
}

