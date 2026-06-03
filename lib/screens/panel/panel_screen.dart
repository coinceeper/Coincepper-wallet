import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/client_panel_provider.dart';
import '../../providers/app_provider.dart';
import '../../services/client_auth_service.dart';
import '../../services/secure_storage.dart';
import '../../utils/wallet_identity.dart';
import '../../layout/main_layout.dart';
import '../../utils/theme_helpers.dart';
import '../../theme/app_spacing.dart';
import 'tabs/dashboard_tab.dart';
import 'tabs/bots_tab.dart';
import 'tabs/earnings_tab.dart';
import 'tabs/withdraw_tab.dart';
import 'tabs/referrals_tab.dart';
import 'tabs/notifications_tab.dart';
import 'tabs/how_it_works_tab.dart';

class PanelScreen extends StatefulWidget {
  const PanelScreen({super.key});

  @override
  State<PanelScreen> createState() => _PanelScreenState();
}

class _PanelScreenState extends State<PanelScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabCtrl;
  static const double _kBottomMenuClearance = AppSpacing.bottomNavClearance;

  static const _tabs = [
    (icon: Icons.dashboard_rounded, label: 'panel.tab_dashboard'),
    (icon: Icons.computer_rounded, label: 'panel.tab_bots'),
    (icon: Icons.trending_up_rounded, label: 'panel.tab_earnings'),
    (icon: Icons.account_balance_wallet_rounded, label: 'panel.tab_withdraw'),
    (icon: Icons.group_rounded, label: 'panel.tab_referrals'),
    (icon: Icons.notifications_rounded, label: 'panel.tab_notifications'),
    (icon: Icons.help_outline_rounded, label: 'panel.tab_how'),
  ];

  bool _resolving = true;
  PanelResolveFailure _resolveFailure = PanelResolveFailure.none;
  PanelWalletContext? _panelCtx;

  AppProvider? _appProviderRef;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabCtrl = TabController(length: _tabs.length, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _appProviderRef = context.read<AppProvider>();
      _appProviderRef!.addListener(_onAppWalletChanged);
      _resolveAndBind();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _appProviderRef?.removeListener(_onAppWalletChanged);
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _maybeRefreshWalletBinding();
    }
  }

  Future<void> _onAppWalletChanged() async {
    await _maybeRefreshWalletBinding();
  }

  /// When Home switches active wallet (or app resumes), keep Panel aligned with selected wallet.
  Future<void> _maybeRefreshWalletBinding() async {
    if (!mounted) return;
    final r = await resolvePanelWalletContextDetailed();
    if (!mounted) return;
    if (r.context == null) {
      setState(() {
        _panelCtx = null;
        _resolveFailure = r.failure;
        _resolving = false;
      });
      return;
    }
    final ctx = r.context!;
    final panel = context.read<ClientPanelProvider>();
    if (panel.boundPanelAddress?.toLowerCase() != ctx.panelAddress.toLowerCase()) {
      setState(() {
        _panelCtx = ctx;
        _resolveFailure = PanelResolveFailure.none;
      });
      await panel.bindToResolvedWallet(
        ctx.panelAddress,
        ctx.walletName,
        ctx.userId,
      );
      if (mounted) setState(() {});
    }
  }

  Future<void> _resolveAndBind() async {
    setState(() {
      _resolving = true;
      _resolveFailure = PanelResolveFailure.none;
    });
    final r = await resolvePanelWalletContextDetailed();
    if (!mounted) return;

    if (r.context == null) {
      setState(() {
        _resolving = false;
        _resolveFailure = r.failure;
        _panelCtx = null;
      });
      return;
    }

    setState(() {
      _panelCtx = r.context;
      _resolving = false;
      _resolveFailure = PanelResolveFailure.none;
    });

    await context.read<ClientPanelProvider>().bindToResolvedWallet(
          r.context!.panelAddress,
          r.context!.walletName,
          r.context!.userId,
        );
    if (mounted) setState(() {});
  }

  void _openWalletPicker() {
    final current = _panelCtx;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _PanelWalletPickerSheet(
        current: current,
        onPick: (picked) async {
          Navigator.of(ctx).pop();
          if (!mounted) return;
          setState(() => _panelCtx = picked);
          await context.read<ClientPanelProvider>().bindToResolvedWallet(
                picked.panelAddress,
                picked.walletName,
                picked.userId,
              );
          if (!mounted) return;
          final app = context.read<AppProvider>();
          await SecureStorage.instance.saveSelectedWallet(
            picked.walletName,
            picked.userId,
          );
          await app.selectWallet(picked.walletName);
          setState(() {});
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = appPrimary(context);
    final hasWallet = _resolveFailure == PanelResolveFailure.none &&
        _panelCtx != null;
    return Consumer<ClientPanelProvider>(
      builder: (context, provider, _) {
        return MainLayout(
          child: Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              centerTitle: true,
              iconTheme: const IconThemeData(color: Colors.black),
              toolbarHeight: hasWallet ? 124 : kToolbarHeight,
              titleSpacing: hasWallet ? 0 : 16,
              title: hasWallet
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'panel.title'.tr(),
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: Material(
                            color: const Color(0xFFF0F4F8),
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              onTap: _openWalletPicker,
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.account_balance_wallet_rounded,
                                      size: 20,
                                      color: primary,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _panelCtx!.walletName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.black87,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            shortPanelAddress(
                                                _panelCtx!.panelAddress),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      color: Colors.grey.shade600,
                                      size: 22,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'panel.wallet_switch_hint'.tr(),
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.4,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      'panel.title'.tr(),
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
              bottom: TabBar(
                controller: _tabCtrl,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicatorColor: primary,
                labelColor: primary,
                unselectedLabelColor: Colors.grey,
                labelStyle:
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                unselectedLabelStyle:
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.w400),
                tabs: _tabs
                    .map((t) => Tab(
                          icon: Icon(t.icon, size: 18),
                          text: t.label.tr(),
                        ))
                    .toList(),
              ),
            ),
            body: Padding(
              padding: EdgeInsets.only(
                bottom:
                    _kBottomMenuClearance + MediaQuery.of(context).viewPadding.bottom,
              ),
              child: _buildBody(provider, primary),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody(ClientPanelProvider provider, Color primary) {
    if (_resolving &&
        _panelCtx == null &&
        _resolveFailure == PanelResolveFailure.none) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: primary),
            const SizedBox(height: 16),
            Text('panel.resolving_wallet'.tr(),
                style: const TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (_resolveFailure == PanelResolveFailure.noWallets) {
      return const _EmptyPanelMessage(
        icon: Icons.account_balance_wallet_outlined,
        titleKey: 'panel.no_wallets_in_app',
        subtitleKey: 'panel.no_wallets_in_app_hint',
      );
    }

    if (_resolveFailure == PanelResolveFailure.btcAddressUnavailable) {
      return const _EmptyPanelMessage(
        icon: Icons.currency_bitcoin_rounded,
        titleKey: 'panel.btc_address_unavailable',
        subtitleKey: 'panel.btc_address_unavailable_hint',
      );
    }

    if (provider.authLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: primary),
            const SizedBox(height: 16),
            Text('panel.connecting'.tr(),
                style: const TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (provider.needsInviteCode) {
      return _InviteCodeGate();
    }

    if (!provider.authenticated) {
      return _AuthErrorView(error: provider.authError);
    }

    return TabBarView(
      controller: _tabCtrl,
      children: const [
        DashboardTab(),
        BotsTab(),
        EarningsTab(),
        WithdrawTab(),
        ReferralsTab(),
        NotificationsTab(),
        HowItWorksTab(),
      ],
    );
  }
}

class _EmptyPanelMessage extends StatelessWidget {
  final IconData icon;
  final String titleKey;
  final String subtitleKey;

  const _EmptyPanelMessage({
    required this.icon,
    required this.titleKey,
    required this.subtitleKey,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: Colors.grey.shade600),
            const SizedBox(height: 16),
            Text(
              titleKey.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text(
              subtitleKey.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet: pick another CoinCeeper wallet for Panel (must have mnemonic).
class _PanelWalletPickerSheet extends StatelessWidget {
  final PanelWalletContext? current;
  final ValueChanged<PanelWalletContext> onPick;

  const _PanelWalletPickerSheet({
    required this.current,
    required this.onPick,
  });

  Future<List<PanelWalletContext>> _loadOptions() async {
    final storage = SecureStorage.instance;
    final rows = await storage.getWalletsList();
    final out = <PanelWalletContext>[];
    for (final w in rows) {
      final name = w['walletName'];
      final uid = w['userID'];
      if (name == null || uid == null) continue;
      final addr = await getPanelAddressForWallet(name, uid);
      if (addr == null) continue;
      out.add(PanelWalletContext(
        walletName: name,
        userId: uid,
        panelAddress: addr,
      ));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final primary = appPrimary(context);
    final maxH = MediaQuery.of(context).size.height * 0.55;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'panel.select_wallet_title'.tr(),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'panel.select_wallet_subtitle'.tr(),
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: maxH,
              child: FutureBuilder<List<PanelWalletContext>>(
                future: _loadOptions(),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return Center(
                      child: CircularProgressIndicator(color: primary),
                    );
                  }
                  final items = snap.data!;
                  if (items.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('panel.wallet_secret_missing'.tr()),
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final item = items[i];
                      final isSel = current != null &&
                          current!.panelAddress.toLowerCase() ==
                              item.panelAddress.toLowerCase();
                      return ListTile(
                        leading: Icon(
                          isSel
                              ? Icons.check_circle_rounded
                              : Icons.account_balance_wallet_rounded,
                          color: isSel ? primary : Colors.grey,
                        ),
                        title: Text(item.walletName),
                        subtitle: Text(shortPanelAddress(item.panelAddress)),
                        onTap: isSel ? null : () => onPick(item),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InviteCodeGate extends StatefulWidget {
  @override
  State<_InviteCodeGate> createState() => _InviteCodeGateState();
}

class _InviteCodeGateState extends State<_InviteCodeGate> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  bool _autoTried = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryAutoSubmitStoredInvite());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// One invite per app install: reuse stored code for every new wallet panel account.
  Future<void> _tryAutoSubmitStoredInvite() async {
    if (_autoTried || !mounted) return;
    _autoTried = true;
    final code = await ClientAuthService.instance.loadReferralCode();
    if (code == null || code.isEmpty) return;
    _ctrl.text = code;
    await _submit();
  }

  @override
  Widget build(BuildContext context) {
    final primary = appPrimary(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 20,
                offset: const Offset(0, 10),
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.vpn_key_rounded, size: 40, color: primary),
              ),
              const SizedBox(height: 24),
              Text(
                'panel.invite_required'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                'panel.invite_required_desc'.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _ctrl,
                textCapitalization: TextCapitalization.characters,
                textAlign: TextAlign.center,
                style: const TextStyle(letterSpacing: 4, fontWeight: FontWeight.bold, fontSize: 18),
                decoration: InputDecoration(
                  hintText: 'panel.enter_invite_code'.tr(),
                  hintStyle: const TextStyle(letterSpacing: 0, fontWeight: FontWeight.normal, fontSize: 14),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  contentPadding: const EdgeInsets.symmetric(vertical: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: primary, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _loading
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                      : Text('panel.submit'.tr(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final code = _ctrl.text.trim();
    if (code.isEmpty) return;
    setState(() => _loading = true);
    
    final provider = context.read<ClientPanelProvider>();
    final addr = provider.boundPanelAddress ?? '';
    
    // ذخیره Navigator قبل از اینکه ویجت حذف شود
    final navigator = Navigator.of(context);
    
    final ok = await provider.submitInviteCode(code, addr);
    
    if (ok) {
      // نمایش مودال روی Navigator اصلی (که با Rebuild صفحه بسته نمی‌شود)
      showModalBottomSheet(
        context: navigator.context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => const _SocialMediaSheet(),
      );
    } else {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('panel.invite_parse_empty'.tr()),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  void _showSocialMediaSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _SocialMediaSheet(),
    );
  }
}

class _SocialMediaSheet extends StatelessWidget {
  const _SocialMediaSheet();

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.of(context).padding.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 45,
            height: 5,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)),
          ),
          const SizedBox(height: 32),
          Text(
            'panel.social_modal_title'.tr(),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5),
          ),
          const SizedBox(height: 10),
          Text(
            'panel.social_modal_desc'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 32),
          _SocialItem(
            label: 'panel.social_modal_telegram'.tr(),
            icon: Icons.send_rounded,
            color: const Color(0xFF26A5E4),
            onTap: () => _launch('https://t.me/coinceeper_official_group'),
          ),
          const SizedBox(height: 12),
          _SocialItem(
            label: 'panel.social_modal_instagram'.tr(),
            icon: Icons.camera_alt_rounded,
            color: const Color(0xFFE1306C),
            onTap: () => _launch('https://www.instagram.com/coinceeperofficial?igsh=MW1rZjB0dTl5YWpu'),
          ),
          const SizedBox(height: 12),
          _SocialItem(
            label: 'panel.social_modal_twitter'.tr(),
            icon: Icons.close_rounded,
            color: Colors.black,
            onTap: () => _launch('https://x.com/coinceeper2025?s=21&t=rZCl21dS5zq8iVWs9SSMpQ'),
          ),
          const SizedBox(height: 24),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('panel.social_modal_later'.tr(), style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _SocialItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _SocialItem({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.1), width: 1),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        leading: Icon(icon, color: color, size: 28),
        title: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
        trailing: Icon(Icons.arrow_forward_ios_rounded, color: color.withOpacity(0.5), size: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}

class _AuthErrorView extends StatefulWidget {
  final String? error;
  const _AuthErrorView({this.error});

  @override
  State<_AuthErrorView> createState() => _AuthErrorViewState();
}

class _AuthErrorViewState extends State<_AuthErrorView> {
  final _pinCtrl = TextEditingController();
  bool _pinBusy = false;

  @override
  void dispose() {
    _pinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final panel = context.watch<ClientPanelProvider>();
    final addr = panel.boundPanelAddress;
    final primary = appPrimary(context);

    if (addr == null || addr.isEmpty) {
      return const _EmptyPanelMessage(
        icon: Icons.account_balance_wallet_outlined,
        titleKey: 'panel.no_wallet_bound',
        subtitleKey: 'panel.no_wallet_bound_hint',
      );
    }

    final msgKey = widget.error ?? 'panel.auth_failed';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              msgKey.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
            if (panel.needsWebPin) ...[
              const SizedBox(height: 16),
              Text(
                'panel.web_pin_hint'.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _pinCtrl,
                keyboardType: TextInputType.number,
                maxLength: 8,
                obscureText: true,
                decoration: InputDecoration(
                  hintText: 'panel.web_pin_placeholder'.tr(),
                  counterText: '',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: primary),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _pinBusy
                      ? null
                      : () async {
                          setState(() => _pinBusy = true);
                          await context
                              .read<ClientPanelProvider>()
                              .submitWebPin(_pinCtrl.text, addr);
                          if (mounted) setState(() => _pinBusy = false);
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _pinBusy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          'panel.submit_web_pin'.tr(),
                          style: const TextStyle(color: Colors.white),
                        ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                context.read<ClientPanelProvider>().authenticate(addr);
              },
              style: ElevatedButton.styleFrom(backgroundColor: primary),
              child: Text(
                'panel.retry'.tr(),
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
