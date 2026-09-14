import 'package:flutter/material.dart';

import '../api/api_exception.dart';
import '../api/health_api.dart';
import '../auth/auth_controller.dart';

enum _ConnectivityState { loading, connected, unavailable }

/// Minimal functional screen for memora-app/spec02-login-google.md — not a
/// designed screen. Visual identity is a separate, still-pending decision.
/// Also keeps the spec01 backend-connectivity indicator, folded into this
/// single home screen instead of a separate route (no navigation stack
/// exists yet, and one combined screen matches "pantalla mínima").
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.healthApi,
    required this.authController,
  });

  final HealthApi healthApi;
  final AuthController authController;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  _ConnectivityState _connectivity = _ConnectivityState.loading;
  String? _connectivityError;

  @override
  void initState() {
    super.initState();
    widget.authController.addListener(_onAuthChanged);
    // Only auto-restore on a fresh controller (status == unknown) — lets
    // tests/callers inject an already-resolved AuthController without
    // triggering a real secure-storage read.
    if (widget.authController.status == AuthStatus.unknown) {
      widget.authController.bootstrap();
    }
    _checkHealth();
  }

  @override
  void dispose() {
    widget.authController.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() => setState(() {});

  Future<void> _checkHealth() async {
    setState(() {
      _connectivity = _ConnectivityState.loading;
      _connectivityError = null;
    });
    try {
      await widget.healthApi.getHealth();
      if (!mounted) return;
      setState(() => _connectivity = _ConnectivityState.connected);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _connectivity = _ConnectivityState.unavailable;
        _connectivityError = error is ApiException
            ? error.message
            : 'Error desconocido';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = widget.authController;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Memora',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                _buildConnectivityIndicator(),
                const SizedBox(height: 32),
                _buildAuthSection(auth),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConnectivityIndicator() {
    final isLoading = _connectivity == _ConnectivityState.loading;
    final isConnected = _connectivity == _ConnectivityState.connected;

    if (isLoading) {
      return const SizedBox(
        height: 16,
        width: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isConnected ? Colors.green : Colors.red,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'Backend: ${isConnected ? "ok" : "no disponible"}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        if (!isConnected && _connectivityError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _connectivityError!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
      ],
    );
  }

  Widget _buildAuthSection(AuthController auth) {
    switch (auth.status) {
      case AuthStatus.unknown:
        return const CircularProgressIndicator();

      case AuthStatus.authenticating:
        return const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Iniciando sesión...'),
          ],
        );

      case AuthStatus.authenticated:
        final user = auth.user;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              user?.name ?? user?.email ?? 'Sesión iniciada',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            if (user?.name != null) ...[
              const SizedBox(height: 4),
              Text(
                user!.email,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: auth.signOut,
              child: const Text('Cerrar sesión'),
            ),
          ],
        );

      case AuthStatus.unauthenticated:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              onPressed: auth.signIn,
              child: const Text('Iniciar sesión con Google'),
            ),
            if (auth.errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                auth.errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.red),
              ),
            ],
          ],
        );
    }
  }
}
