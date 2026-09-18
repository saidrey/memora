import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../albums/albums_controller.dart';
import '../albums/drive_thumbnail_service.dart';
import '../albums/screens/accept_invitation_screen.dart';
import '../albums/screens/albums_list_screen.dart';
import '../api/api_exception.dart';
import '../api/health_api.dart';
import '../auth/auth_controller.dart';
import '../auth/drive_reconnect_prompt.dart';
import '../design/design.dart';
import '../photos/photo_upload_controller.dart';

enum _ConnectivityState { loading, connected, unavailable }

/// Home screen (Fase 1 del rediseño visual): an immersive "Welcome"
/// composition when unauthenticated, and a light dashboard once signed in.
/// Same single widget/screen as before (no navigation restructuring for
/// this), same controllers and callbacks (`auth.signIn`, `_openAlbums`,
/// `_openAcceptInvitation`, the photo-upload flow) — only the visual layer
/// changed.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.healthApi,
    required this.authController,
    required this.photoUploadController,
    required this.albumsController,
    required this.driveThumbnailService,
  });

  final HealthApi healthApi;
  final AuthController authController;
  final PhotoUploadController photoUploadController;
  final AlbumsController albumsController;
  final DriveThumbnailService driveThumbnailService;

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
    widget.photoUploadController.addListener(_onAuthChanged);
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
    widget.photoUploadController.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() => setState(() {});

  void _openAlbums() {
    Navigator.of(context).push(
      MemoraPageRoute(
        builder: (_) => AlbumsListScreen(
          controller: widget.albumsController,
          photoUploadController: widget.photoUploadController,
          driveThumbnailService: widget.driveThumbnailService,
          authController: widget.authController,
        ),
      ),
    );
  }

  void _openAcceptInvitation() {
    Navigator.of(context).push(
      MemoraPageRoute(
        builder: (_) => AcceptInvitationScreen(
          controller: widget.albumsController,
          photoUploadController: widget.photoUploadController,
          driveThumbnailService: widget.driveThumbnailService,
          authController: widget.authController,
        ),
      ),
    );
  }

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
    // The hero photo is the Welcome (unauthenticated) backdrop; the
    // authenticated dashboard renders its own header/avatar row on the
    // light Paper canvas, with the "Álbumes" hero as a contained card (see
    // `_AuthenticatedDashboard` class doc — reverted from a full dark-zone
    // background after real-device feedback: "TUS ALBUMES se veia mejor
    // como una tarjeta"). Built entirely by `_AuthenticatedDashboard` itself
    // instead of the shared Stack/SafeArea/header-row scaffolding below
    // (which now only serves the remaining statuses:
    // unauthenticated/unknown/authenticating).
    final showHero = auth.status == AuthStatus.unauthenticated;
    final authenticated = auth.status == AuthStatus.authenticated;

    return Scaffold(
      // `extendBody`: the bottom nav floats with margin (it's not an
      // edge-to-edge bar), so the scrollable dashboard content should be
      // allowed to sit behind it — `_AuthenticatedDashboard` adds its own
      // extra bottom padding (see `_bottomNavClearance`) so real content
      // never ends up hidden underneath the floating bar.
      extendBody: authenticated,
      bottomNavigationBar: authenticated
          ? AuroraBottomNav(
              activeTab: AuroraNavTab.home,
              onTapAlbums: _openAlbums,
              onAddPhotos: () =>
                  widget.photoUploadController.pickAndUploadPhotos(),
            )
          : null,
      body: authenticated
          ? _AuthenticatedDashboard(
              auth: auth,
              photoUploadController: widget.photoUploadController,
              onOpenAlbums: _openAlbums,
              onOpenAcceptInvitation: _openAcceptInvitation,
              onReconnectDriveForPhotos: _reconnectDriveForPhotos,
              // The profile header belongs to the dark upper stage of the
              // reference composition, not to the pale cards below it.
              connectivityBadge: _buildConnectivityBadge(onDark: true),
            )
          : Stack(
              children: [
                // Deliberately NOT inside SafeArea: the hero photo must
                // cover the full screen including the status bar area.
                // SafeArea below is only for the content
                // (wordmark/badge/headline/CTA).
                Positioned.fill(
                  child: showHero
                      ? const _WelcomeHeroBackdrop()
                      : const _AuroraBackdrop(),
                ),
                SafeArea(
                  child: Column(
                    children: [
                      if (!showHero)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            MemoraSpacing.lg,
                            MemoraSpacing.sm,
                            MemoraSpacing.lg,
                            0,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Memora',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(letterSpacing: 0.5),
                              ),
                              _buildConnectivityBadge(onDark: false),
                            ],
                          ),
                        ),
                      Expanded(child: _buildAuthSection(auth)),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  /// [onDark] is true only while the Welcome/hero photo is showing (the
  /// deliberate dark exception) — the badge/spinner need explicit
  /// light-on-dark overrides there instead of their light-canvas defaults,
  /// which is everywhere else this indicator appears (the authenticated
  /// dashboard's light header).
  Widget _buildConnectivityBadge({required bool onDark}) {
    switch (_connectivity) {
      case _ConnectivityState.loading:
        return MemoraLoadingState(
          compact: true,
          color: onDark ? MemoraColors.paper : null,
        );
      case _ConnectivityState.connected:
        return MemoraBadge(
          label: 'Backend: ok',
          dotColor: MemoraColors.semanticSuccess,
          backgroundColor: onDark
              ? MemoraColors.deepInk.withValues(alpha: 0.35)
              : null,
          textColor: onDark ? MemoraColors.paper : null,
          borderColor: onDark
              ? MemoraColors.paper.withValues(alpha: 0.18)
              : null,
        );
      case _ConnectivityState.unavailable:
        return Tooltip(
          message: _connectivityError ?? '',
          child: MemoraBadge(
            label: 'Backend: no disponible',
            dotColor: MemoraColors.semanticError,
            backgroundColor: onDark
                ? MemoraColors.deepInk.withValues(alpha: 0.35)
                : null,
            textColor: onDark ? MemoraColors.paper : null,
            borderColor: onDark
                ? MemoraColors.paper.withValues(alpha: 0.18)
                : null,
          ),
        );
    }
  }

  Widget _buildAuthSection(AuthController auth) {
    switch (auth.status) {
      case AuthStatus.unknown:
        return const MemoraLoadingState();

      case AuthStatus.authenticating:
        return const MemoraLoadingState(label: 'Iniciando sesión...');

      case AuthStatus.authenticated:
        // Unreachable: `build()` renders `_AuthenticatedDashboard` directly
        // for this status (see its class doc) — kept only so this switch
        // stays exhaustive over `AuthStatus`.
        return const SizedBox.shrink();

      case AuthStatus.unauthenticated:
        return _WelcomeSection(auth: auth);
    }
  }

  /// Offers to reconnect Google Drive (spec06-sesion-y-reauth-drive.md,
  /// A1.6) and, on success, retries only the photos that failed with
  /// `DRIVE_REAUTHORIZATION_REQUIRED` in the last batch.
  Future<void> _reconnectDriveForPhotos() async {
    final reconnected = await promptDriveReconnect(
      context,
      widget.authController,
    );
    if (!reconnected || !mounted) return;
    await widget.photoUploadController.retryAfterDriveReconnect();
  }
}

/// The authenticated dashboard's backdrop: the light Paper canvas (60-30-10
/// pivot) with two very soft, low-alpha signature blobs for brand texture.
///
/// **Light-first pivot**: this used to be a full dark (Deep Ink) fill with
/// strong (0.35 alpha) glowing blobs — the authenticated dashboard's own
/// full-bleed dark background, which directly contradicted the pivot (Paper
/// is the 60% dominant canvas everywhere except the deliberate dark
/// exceptions — the Welcome hero photo, `photo_viewer_screen.dart`, and
/// `MemoraCardElevation.ink`). Kept the same brand texture (blurred
/// signature-color blobs) at a much lower alpha (0.12) so it reads as a
/// subtle tint on Paper instead of a moody dark glow.
class _AuroraBackdrop extends StatelessWidget {
  const _AuroraBackdrop();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(painter: _DashboardBackgroundPainter());
  }
}

/// The authenticated home canvas from the new reference: a deep, quiet
/// upper stage for the profile and album hero, dissolving into a pale lower
/// stage for utility actions. Drawing it avoids shipping another background
/// bitmap and keeps the composition responsive at every screen size.
class _DashboardBackgroundPainter extends CustomPainter {
  const _DashboardBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final canvasRect = Offset.zero & size;
    final darkMid = Color.alphaBlend(
      MemoraColors.glassBlue.withValues(alpha: 0.12),
      MemoraColors.deepInk,
    );
    final paleStart = Color.alphaBlend(
      MemoraColors.glassBlue.withValues(alpha: 0.04),
      MemoraColors.paper,
    );
    canvas.drawRect(
      canvasRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            MemoraColors.deepInk,
            darkMid,
            darkMid,
            paleStart,
            MemoraColors.paper,
          ],
          stops: const [0, 0.3, 0.42, 0.64, 0.82],
        ).createShader(canvasRect),
    );

    final glow = Paint()
      ..shader =
          RadialGradient(
            colors: [
              MemoraColors.auraViolet.withValues(alpha: 0.52),
              MemoraColors.auraViolet.withValues(alpha: 0),
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 1.03, size.height * 0.46),
              radius: size.width * 0.62,
            ),
          );
    canvas.drawCircle(
      Offset(size.width * 1.03, size.height * 0.46),
      size.width * 0.62,
      glow,
    );

    final lowerGlow = Paint()
      ..shader =
          RadialGradient(
            colors: [
              MemoraColors.glassBlue.withValues(alpha: 0.28),
              MemoraColors.glassBlue.withValues(alpha: 0),
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(-size.width * 0.08, size.height * 0.94),
              radius: size.width * 0.6,
            ),
          );
    canvas.drawCircle(
      Offset(-size.width * 0.08, size.height * 0.94),
      size.width * 0.6,
      lowerGlow,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Full-screen ornamental background for the unauthenticated login state.
/// The transparent center intentionally leaves room for the supplied logo and
/// login content while the artwork frames the screen edges.
class _WelcomeHeroBackdrop extends StatelessWidget {
  const _WelcomeHeroBackdrop();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: MemoraColors.deepInk),
        Image.asset('references/login_back.png', fit: BoxFit.cover),
      ],
    );
  }
}

/// Login composition from the supplied reference. Authentication remains the
/// existing [AuthController.signIn] callback; this widget only owns layout.
class _WelcomeSection extends StatelessWidget {
  const _WelcomeSection({required this.auth});

  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: MemoraSpacing.lg),
      child: Column(
        children: [
          Expanded(
            flex: 5,
            child: Column(
              children: [
                Expanded(
                  child: Image.asset(
                    'references/login_logo.png',
                    width: 330,
                    fit: BoxFit.contain,
                  ),
                ),
                Text(
                  'Pequeños momentos,',
                  style: textTheme.titleMedium?.copyWith(
                    color: MemoraColors.paper.withValues(alpha: 0.82),
                  ),
                ),
                Text(
                  'grandes recuerdos',
                  style: textTheme.titleMedium?.copyWith(
                    color: MemoraColors.auraViolet,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 1,
            child: Stack(
              alignment: Alignment.center,
              children: [
                _LoginGoogleButton(onPressed: auth.signIn),
                if (auth.errorMessage != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Text(
                      auth.errorMessage!,
                      textAlign: TextAlign.center,
                      style: textTheme.bodySmall?.copyWith(
                        color: MemoraColors.semanticErrorOnDark,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 4,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: MemoraSpacing.sm),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _LoginFeature(
                        icon: Icons.camera_alt_outlined,
                        label: 'Captura\ntus momentos',
                      ),
                      _LoginFeature(
                        icon: Icons.groups_outlined,
                        label: 'Comparte\ncon quienes amas',
                      ),
                      _LoginFeature(
                        icon: Icons.favorite_border,
                        label: 'Revive\nsiempre',
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: MemoraSpacing.sm),
                  child: Column(
                    children: [
                      Text(
                        'MAS QUE FOTOS,\nHISTORIAS QUE SIEMPRE VIVEN',
                        textAlign: TextAlign.center,
                        style: textTheme.labelSmall?.copyWith(
                          color: MemoraColors.paper.withValues(alpha: 0.65),
                          letterSpacing: 2.2,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: MemoraSpacing.sm),
                      const Icon(
                        Icons.favorite,
                        size: 16,
                        color: MemoraColors.auraViolet,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginGoogleButton extends StatelessWidget {
  const _LoginGoogleButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MemoraColors.paper,
      borderRadius: BorderRadius.circular(MemoraRadius.pill),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(MemoraRadius.pill),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              SvgPicture.asset('references/google.svg', width: 23, height: 23),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Continuar con Google',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(color: MemoraColors.deepInk),
                ),
              ),
              const Icon(Icons.chevron_right, color: MemoraColors.auraViolet),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoginFeature extends StatelessWidget {
  const _LoginFeature({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: MemoraColors.deepInk.withValues(alpha: 0.45),
            border: Border.all(
              color: MemoraColors.auraViolet.withValues(alpha: 0.5),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, color: MemoraColors.auraViolet, size: 20),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: MemoraColors.paper.withValues(alpha: 0.82),
            fontSize: 9,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

/// Signed-in dashboard: header (logout + connectivity badge) + avatar row on
/// the light Paper canvas, then the "Álbumes" hero as its own contained dark
/// card, then Unirme/Fotos/nota manuscrita — same navigation/controllers as
/// before.
///
/// **Rediseño post-feedback (sin spec de Kiro)**: the user's own words —
/// "tienes álbumes, Unirme y Fotos ahí como sin un orden lógico, solo
/// puestos ahí como un mal dashboard. Que no parezca un dashboard, las 3
/// opciones pueden estar una debajo de la otra, que ocupen cada una el ancho
/// de la pantalla y que se diferencien no que parezcan 3 tarjetas iguales."
/// Previously: "Álbumes"/"Unirme" were two identical half-width
/// `_QuickAccessCard`s in a `Row`, and "Fotos" was a third, visually
/// unrelated full-width card below — three same-template tiles with no
/// hierarchy. Now: three FULL-WIDTH blocks stacked vertically, each a
/// deliberately different tone/composition (not the same card recolored) —
/// see each block's own doc comment for why it got the tone it did.
///
/// **Revertido tras feedback en dispositivo real (sigue sin spec de Kiro)**:
/// a previous iteration made the "Álbumes" hero's dark radial gradient the
/// background of the ENTIRE top zone (header + avatar row + hero, no white
/// gap between them) — the user saw it on their phone against the original
/// mockup and preferred the earlier look: **"TUS ALBUMES se veia mejor como
/// The authenticated home follows the supplied reference's two-stage
/// composition: a dark upper stage for identity and the album feature, then
/// pale utility cards below. The background is painted in code so its glow
/// remains responsive and no large decorative PNG is required.
class _AuthenticatedDashboard extends StatelessWidget {
  const _AuthenticatedDashboard({
    required this.auth,
    required this.photoUploadController,
    required this.onOpenAlbums,
    required this.onOpenAcceptInvitation,
    required this.onReconnectDriveForPhotos,
    required this.connectivityBadge,
  });

  final AuthController auth;
  final PhotoUploadController photoUploadController;
  final VoidCallback onOpenAlbums;
  final VoidCallback onOpenAcceptInvitation;
  final Future<void> Function() onReconnectDriveForPhotos;

  /// Built by `_HomeScreenState` with `onDark: false` — the header sits on
  /// the light Paper canvas again (see class doc).
  final Widget connectivityBadge;

  @override
  Widget build(BuildContext context) {
    final user = auth.user;
    final textTheme = Theme.of(context).textTheme;

    return CustomPaint(
      painter: const _DashboardBackgroundPainter(),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            MemoraSpacing.lg,
            MemoraSpacing.sm,
            MemoraSpacing.lg,
            // Base bottom padding (`xxl`) + extra clearance for the
            // floating bottom nav (`Scaffold.extendBody: true` lets this
            // scroll view sit behind it) — otherwise the last block/footer
            // would end up partially hidden under the bar.
            MemoraSpacing.xxl + _bottomNavClearance,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: auth.signOut,
                    icon: const Icon(Icons.logout),
                    tooltip: 'Cerrar sesión',
                    color: MemoraColors.paper,
                  ),
                  connectivityBadge,
                ],
              ),
              const SizedBox(height: MemoraSpacing.md),
              Row(
                children: [
                  _InitialsAvatar(name: user?.name, email: user?.email),
                  const SizedBox(width: MemoraSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.name ?? user?.email ?? 'Sesión iniciada',
                          style: textTheme.headlineSmall?.copyWith(
                            color: MemoraColors.paper,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (user?.name != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            user!.email,
                            style: textTheme.bodySmall?.copyWith(
                              color: MemoraColors.paper.withValues(alpha: 0.72),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              // More air above "TUS ÁLBUMES" than the avatar row alone gave
              // it before (post-feedback point 2, kept through the revert).
              const SizedBox(height: MemoraSpacing.xxl),
              _AlbumsHeroCard(onTap: onOpenAlbums),
              const SizedBox(height: MemoraSpacing.md),
              _JoinAlbumActionBlock(onTap: onOpenAcceptInvitation),
              const SizedBox(height: MemoraSpacing.md),
              _PhotosSection(
                controller: photoUploadController,
                onReconnectDrive: onReconnectDriveForPhotos,
              ),
              const SizedBox(height: MemoraSpacing.xl),
              const _ConnectingMemoriesFooter(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Extra bottom clearance reserved in `_AuthenticatedDashboard`'s scroll
/// padding for the floating `_AuroraBottomNav` (see `Scaffold.extendBody`
/// in `_HomeScreenState.build`) — big enough to clear the bar's own height
/// plus its floating margin/shadow.
const double _bottomNavClearance = 104;

/// A closing, warm note near the end of the authenticated dashboard: a
/// handwritten-style line + a small heart, with a soft violet glow behind
/// it — purely decorative brand texture, no interaction. `GoogleFonts
/// .caveat` is used ONLY here (not a system-wide typography change —
/// `MemoraTypography`/`Theme.of(context).textTheme` stay exactly as they
/// are everywhere else).
class _ConnectingMemoriesFooter extends StatelessWidget {
  const _ConnectingMemoriesFooter();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 140,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Same blurred-circle glow pattern as `_AuroraBackdrop`/the
          // albums hero's extra glow spheres, reused here rather than
          // inventing a new effect — a single large, soft violet blob
          // bleeding off the bottom-right edge.
          Positioned(
            bottom: -60,
            right: -50,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 70, sigmaY: 70),
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: MemoraColors.auraViolet.withValues(alpha: 0.3),
                ),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  'Recuerdos que nos conectan',
                  textAlign: TextAlign.center,
                  // Raw `auraViolet` is unreadable directly on the light
                  // Paper canvas this footer sits on (~1.6:1 contrast) —
                  // `auraVioletOnLight` is the token calibrated for exactly
                  // this (see memora_colors.dart's light-first pivot doc).
                  style: GoogleFonts.caveat(
                    fontSize: 32,
                    fontWeight: FontWeight.w600,
                    color: MemoraColors.auraVioletOnLight,
                  ),
                ),
              ),
              const SizedBox(width: MemoraSpacing.xs),
              Icon(
                Icons.favorite,
                size: 20,
                color: MemoraColors.auraVioletOnLight.withValues(alpha: 0.85),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The "Álbumes" hero — back to a self-contained card floating on the light
/// Paper canvas (reverted after real-device feedback, see
/// `_AuthenticatedDashboard`'s class doc: **"TUS ALBUMES se veia mejor como
/// una tarjeta"**). Owns its own rounded clip (`MemoraRadius.hero`), radial
/// gradient background, and glow layer (`_AlbumsHeroGlow`) — all scoped to
/// this card's own bounds, not bleeding into the header/avatar row above it
/// (which sit on plain Paper now). Content is unchanged: a glowing
/// decorative frame icon overflowing the top-right corner, an eyebrow +
/// two-line headline with the last word rendered in the signature gradient,
/// a small circular arrow affordance, and a row of purely decorative
/// pagination dots — matching the exact mockup the user shared
/// (`principal.png`, not in the repo). Sized by its own content
/// (`mainAxisSize.min`, padded) rather than a fixed height — robust to a
/// taller/shorter headline without needing to hand-tune a pixel height.
///
/// The entire card is one tap target (`InkWell`) — the small circular arrow
/// is a visual affordance pulled straight from the mockup, not a second
/// independent tap handler (avoids two overlapping gesture regions firing
/// `onTap` twice).
class _AlbumsHeroCard extends StatelessWidget {
  const _AlbumsHeroCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(MemoraRadius.hero),
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.9, -0.1),
            radius: 1.1,
            colors: [MemoraColors.auraViolet, MemoraColors.deepInk],
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Positioned.fill(child: _AlbumsHeroGlow()),
                Positioned(
                  top: -4,
                  right: -18,
                  child: Opacity(
                    opacity: 0.92,
                    child: Image.asset(
                      'assets/images/principal_asset.png',
                      width: 168,
                      height: 168,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(MemoraSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 100),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'TUS ÁLBUMES',
                              style: textTheme.labelMedium?.copyWith(
                                color: MemoraColors.glassBlue,
                                letterSpacing: 2.4,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: MemoraSpacing.sm),
                            _AlbumsHeadline(textTheme: textTheme),
                          ],
                        ),
                      ),
                      const SizedBox(height: MemoraSpacing.xl),
                      SizedBox(
                        height: 44,
                        child: Stack(
                          children: [
                            const Align(
                              alignment: Alignment.center,
                              child: _PaginationDots(),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: const _CircularArrowGlyph(),
                            ),
                          ],
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
    );
  }
}

/// Extra blurred glow spheres layered on top of `_AlbumsHeroCard`'s base
/// radial gradient — blue/violet, distributed per `principal_fondo.png`'s
/// reference (concentrated near the top-right, a subtle remainder toward
/// the bottom-left). Clipped by the parent card's `ClipRRect`, so nothing
/// bleeds past the card's own rounded bounds.
class _AlbumsHeroGlow extends StatelessWidget {
  const _AlbumsHeroGlow();

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ui.ImageFilter.blur(sigmaX: 60, sigmaY: 60),
      child: Stack(
        children: [
          Positioned(
            top: -40,
            right: -30,
            child: _glow(MemoraColors.glassBlue, 170, 0.5),
          ),
          Positioned(
            top: 20,
            right: 60,
            child: _glow(MemoraColors.auraViolet, 120, 0.4),
          ),
          Positioned(
            bottom: -60,
            left: -40,
            child: _glow(MemoraColors.glassBlue, 150, 0.16),
          ),
        ],
      ),
    );
  }

  Widget _glow(Color color, double size, double alpha) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: alpha),
      ),
    );
  }
}

/// "Un lugar para las historias que *compartes.*" — the last word rendered
/// with the signature gradient as its text color (`ShaderMask`), the same
/// intent as `_HeroHeadline`'s highlighted "contigo" on the Welcome screen
/// (that one uses a flat `auraViolet` fill, not a gradient — there was no
/// existing `ShaderMask` call site to literally copy for a *gradient* text
/// fill, so this introduces the pattern fresh, in the same spirit).
class _AlbumsHeadline extends StatelessWidget {
  const _AlbumsHeadline({required this.textTheme});

  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final style = textTheme.headlineMedium?.copyWith(
      color: MemoraColors.paper,
      height: 1.25,
      shadows: MemoraTypography.legibilityShadows(intensity: 0.6),
    );

    return RichText(
      text: TextSpan(
        style: style,
        children: [
          const TextSpan(text: 'Un lugar para las historias que '),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: ShaderMask(
              shaderCallback: (bounds) =>
                  MemoraColors.signatureGradient.createShader(bounds),
              child: Text('compartes.', style: style),
            ),
          ),
        ],
      ),
    );
  }
}

/// Decorative circular affordance (not its own tap target — see
/// `_AlbumsHeroCard`'s doc comment) hinting "tap the card to open
/// Álbumes". Light/glass background: safe here (unlike the FAB
/// glassmorphism attempt documented in CLAUDE.md, which read as invisible
/// on the flat Paper canvas) because this circle sits on the hero's own
/// dark gradient, which gives it real contrast to blur against.
class _CircularArrowGlyph extends StatelessWidget {
  const _CircularArrowGlyph();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: MemoraColors.paper.withValues(alpha: 0.16),
        border: Border.all(color: MemoraColors.paper.withValues(alpha: 0.35)),
      ),
      child: const Icon(
        Icons.arrow_forward,
        color: MemoraColors.paper,
        size: 20,
      ),
    );
  }
}

/// Purely decorative pagination dots (first one highlighted) copied from
/// the mockup's visual language. **Not a functional carousel** — there is
/// no second/third "page" of content to page through today, this is
/// intentionally just static visual rhythm under the hero card. If a real
/// carousel is ever needed here, this widget should be replaced by an
/// actual `PageView`-driven indicator, not extended in place.
class _PaginationDots extends StatelessWidget {
  const _PaginationDots();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _dot(active: true),
        const SizedBox(width: 6),
        _dot(active: false),
        const SizedBox(width: 6),
        _dot(active: false),
      ],
    );
  }

  Widget _dot({required bool active}) {
    return Container(
      width: active ? 18 : 6,
      height: 6,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(MemoraRadius.pill),
        color: MemoraColors.paper.withValues(alpha: active ? 0.95 : 0.35),
      ),
    );
  }
}

/// Secondary action kept intentionally compact, like a utility row rather
/// than a second competing feature card.
class _JoinAlbumActionBlock extends StatelessWidget {
  const _JoinAlbumActionBlock({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return MemoraCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: MemoraSpacing.md,
        vertical: MemoraSpacing.md,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: MemoraColors.signatureGradient,
            ),
            child: const Icon(
              Icons.group_add_outlined,
              color: MemoraColors.deepInk,
              size: 18,
            ),
          ),
          const SizedBox(width: MemoraSpacing.sm),
          Expanded(
            child: Text('Unirme a un álbum', style: textTheme.titleSmall),
          ),
          const Icon(
            Icons.arrow_forward_ios,
            color: MemoraColors.textTertiary,
            size: 14,
          ),
        ],
      ),
    );
  }
}

class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar({this.name, this.email});

  final String? name;
  final String? email;

  String get _initials {
    final source = (name != null && name!.trim().isNotEmpty)
        ? name!.trim()
        : (email ?? '');
    if (source.isEmpty) return '?';
    final parts = source
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return source.substring(0, source.length >= 2 ? 2 : 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: MemoraColors.signatureGradient,
      ),
      child: Text(
        _initials,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: MemoraColors.deepInk,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Photo import is a functional section with its own quiet surface. The
/// gradient is reserved for its compact icon and CTA, never used as a noisy
/// frame around a variable list of upload states.
class _PhotosSection extends StatelessWidget {
  const _PhotosSection({
    required this.controller,
    required this.onReconnectDrive,
  });

  final PhotoUploadController controller;
  final Future<void> Function() onReconnectDrive;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return MemoraCard(
      elevation: MemoraCardElevation.level2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: MemoraColors.signatureGradient,
                ),
                child: const Icon(
                  Icons.add_photo_alternate_outlined,
                  color: MemoraColors.deepInk,
                  size: 18,
                ),
              ),
              const SizedBox(width: MemoraSpacing.sm),
              Text('Fotos', style: textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: MemoraSpacing.md),
          MemoraSecondaryButton(
            label: controller.isRunning ? 'Subiendo...' : 'Agregar fotos',
            icon: Icons.add_photo_alternate_outlined,
            onPressed: controller.isRunning
                ? null
                : () => controller.pickAndUploadPhotos(),
          ),
          if (controller.items.isNotEmpty) ...[
            const SizedBox(height: MemoraSpacing.md),
            ...controller.items.map((item) => _PhotoItemRow(item: item)),
            const SizedBox(height: MemoraSpacing.sm),
            if (!controller.isRunning)
              Text(_summaryText(controller), style: textTheme.bodySmall),
          ],
          if (controller.batchErrorMessage != null) ...[
            const SizedBox(height: MemoraSpacing.sm),
            Text(
              controller.batchErrorMessage!,
              style: textTheme.bodySmall?.copyWith(
                color: MemoraColors.semanticError,
              ),
            ),
          ],
          if (controller.hasDriveReauthFailures) ...[
            const SizedBox(height: MemoraSpacing.md),
            MemoraSecondaryButton(
              label: 'Reconectar Google Drive',
              onPressed: controller.isRunning ? null : onReconnectDrive,
            ),
          ],
        ],
      ),
    );
  }

  String _summaryText(PhotoUploadController controller) {
    final done = controller.items
        .where((item) => item.status == PhotoUploadStatus.done)
        .length;
    final failed = controller.items
        .where((item) => item.status == PhotoUploadStatus.error)
        .length;
    return '$done foto(s) subida(s), $failed con error';
  }
}

class _PhotoItemRow extends StatelessWidget {
  const _PhotoItemRow({required this.item});

  final PhotoUploadItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: MemoraSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: AnimatedSwitcher(
              duration: MemoraMotion.quick,
              switchInCurve: MemoraMotion.enterCurve,
              switchOutCurve: MemoraMotion.exitCurve,
              child: switch (item.status) {
                PhotoUploadStatus.done => const Icon(
                  Icons.check,
                  key: ValueKey('done'),
                  size: 16,
                  color: MemoraColors.semanticSuccess,
                ),
                PhotoUploadStatus.error => const Icon(
                  Icons.error_outline,
                  key: ValueKey('error'),
                  size: 16,
                  color: MemoraColors.semanticError,
                ),
                _ => const MemoraLoadingState(
                  key: ValueKey('progress'),
                  compact: true,
                ),
              },
            ),
          ),
          const SizedBox(width: MemoraSpacing.sm),
          Expanded(
            child: Text(
              _statusLabel(item),
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(PhotoUploadItem item) {
    switch (item.status) {
      case PhotoUploadStatus.queued:
        return 'En espera';
      case PhotoUploadStatus.optimizing:
        return 'Optimizando...';
      case PhotoUploadStatus.uploading:
        return 'Subiendo...';
      case PhotoUploadStatus.registering:
        return 'Registrando...';
      case PhotoUploadStatus.done:
        return 'Lista';
      case PhotoUploadStatus.error:
        return item.errorMessage ?? 'Error';
    }
  }
}

// The bottom navigation bar now lives in `AuroraBottomNav`
// (`lib/design/widgets/aurora_bottom_nav.dart`), shared with
// `AlbumsListScreen` — see that file's class doc.
