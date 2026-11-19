import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../features/admin/admin_repository.dart';
import '../features/admin/admin_view.dart';
import '../features/auth/account_view.dart';
import '../features/auth/session.dart';
import '../features/shopper/shopper_repository.dart';
import '../features/shopper/shopper_view.dart';
import '../features/store_owner/seller_repository.dart';
import '../features/store_owner/seller_view.dart';
import 'widgets.dart';

class MittApp extends StatefulWidget {
  const MittApp({super.key, this.portal = false, this.client});
  final bool portal;
  final ApiClient? client;
  @override
  State<MittApp> createState() => _MittAppState();
}

class _MittAppState extends State<MittApp> {
  late final api = widget.client ?? ApiClient();
  late final session = Session(AuthRepository(api), portal: widget.portal);

  @override
  void initState() {
    super.initState();
    session.restore();
  }

  @override
  void dispose() {
    session.dispose();
    if (widget.client == null) api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const purple = Color(0xff7748ae);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: widget.portal ? 'MITT Management' : 'MITT',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: purple, primary: purple),
        scaffoldBackgroundColor: const Color(0xfff2eff6),
        cardTheme: const CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.symmetric(vertical: 4),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xfff6f0fb),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      home: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          final role = session.user?['role'];
          return Scaffold(
            appBar: AppBar(
              backgroundColor: Colors.white,
              title: Row(
                children: [
                  Image.asset('assets/mitt.png', width: 62, height: 42),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(switch (role) {
                      'store_owner' => 'MITT Store',
                      'admin' => 'MITT Admin',
                      _ => 'MITT',
                    }),
                  ),
                ],
              ),
              actions: [
                if (widget.portal && role != null)
                  IconButton(
                    tooltip: 'Sign out',
                    onPressed: () => perform(context, session.logout),
                    icon: const Icon(Icons.logout),
                  ),
              ],
            ),
            body: session.loading
                ? const Center(child: CircularProgressIndicator())
                : !widget.portal
                ? ShopperView(
                    repository: ShopperRepository(api),
                    session: session,
                  )
                : session.restoreError != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(session.restoreError!),
                        TextButton(
                          onPressed: session.restore,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  )
                : switch (role) {
                    'store_owner' => SellerView(
                      repository: SellerRepository(api),
                    ),
                    'admin' => AdminView(repository: AdminRepository(api)),
                    _ => AccountView(session: session),
                  },
          );
        },
      ),
    );
  }
}
