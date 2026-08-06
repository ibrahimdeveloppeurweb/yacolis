import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class HomeDrawer extends StatelessWidget {
  const HomeDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: MediaQuery.of(context).size.width, // Prend tout l'écran
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: CustomScrollView(
          slivers: [
            SliverAppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              pinned: true,
              expandedHeight: 180,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black),
                onPressed: () => Navigator.of(context).pop(),
              ),
              flexibleSpace: LayoutBuilder(
                builder: (context, constraints) {
                  var top = constraints.biggest.height;
                  // On détermine si l'AppBar est réduite (collapsed)
                  bool isCollapsed = top <= kToolbarHeight + MediaQuery.of(context).padding.top + 20;

                  return FlexibleSpaceBar(
                    centerTitle: true,
                    titlePadding: const EdgeInsets.only(bottom: 8),
                    title: isCollapsed
                        ? const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('945427', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
                                  SizedBox(width: 4),
                                  Icon(Icons.check_circle, color: AppColors.secondary, size: 12),
                                ],
                              ),
                              Text('+2250555568405', style: TextStyle(fontSize: 10, color: Colors.grey)),
                            ],
                          )
                        : null,
                    background: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(height: MediaQuery.of(context).padding.top + 10),
                        CircleAvatar(
                          radius: 35,
                          backgroundColor: AppColors.primary.withOpacity(0.1),
                          child: const Icon(Icons.person, size: 40, color: AppColors.primary),
                        ),
                        const SizedBox(height: 8),
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('945427', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black)),
                            SizedBox(width: 4),
                            Icon(Icons.check_circle, color: AppColors.secondary, size: 16),
                          ],
                        ),
                        const Text('+2250555568405', style: TextStyle(fontSize: 14, color: Colors.grey)),
                      ],
                    ),
                  );
                },
              ),
            ),
            SliverToBoxAdapter(
              child: Column(
                children: [
                  const SizedBox(height: 16),

                  // 2. Boutons d'actions rapides
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildQuickAction(Icons.access_time_filled, 'Historique'),
                    _buildQuickAction(Icons.headset_mic, 'Assistance'),
                    _buildQuickAction(Icons.location_on, 'Adresses'),
                    _buildQuickAction(Icons.settings, 'Paramètres'),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // 3. Carte Compléter le Profil
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.05), // Fond bleuté Yacolis
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'COMPLETER LE PROFIL',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                          Row(
                            children: [
                              const Text(
                                'Pourquoi ?',
                                style: TextStyle(color: Colors.grey, fontSize: 13),
                              ),
                              const SizedBox(width: 4),
                              Icon(Icons.help, color: Colors.grey.shade400, size: 16),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(height: 1, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      const Text(
                        '0 sur 2',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.account_circle, size: 28),
                            const SizedBox(width: 12),
                            const Text(
                              'Confirmer votre nom',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Container(width: 6, height: 6, decoration: BoxDecoration(color: Colors.grey.shade400, shape: BoxShape.circle)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 4. Liste des options
              _buildMenuItem(Icons.card_giftcard, 'Réductions', subtitle: 'Saisir un code promotionnel'),
              _buildMenuItem(
                Icons.credit_card,
                'Modes de paiement',
                subtitle: 'Espèces',
                trailing: const Icon(Icons.money, color: Colors.green, size: 28),
              ),

              // Option Conducteur (Style Spécial)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF222222),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(color: AppColors.secondary, shape: BoxShape.circle),
                      child: const Icon(Icons.star, color: Colors.white, size: 20),
                    ),
                    title: const Text(
                      'Travaillez comme conducteur',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    trailing: const Icon(Icons.chevron_right, color: AppColors.secondary),
                  ),
                ),
              ),

              _buildMenuItem(Icons.bookmark, 'Améliorer les cartes', subtitle: 'Ajouter des lieux, corriger des erreurs'),
              _buildMenuItem(Icons.business_center, 'Compte entreprise'),
              _buildMenuItem(Icons.security, 'Sécurité'),
              _buildMenuItem(Icons.cached, 'Top ! Peu d\'annulations', iconColor: Colors.green, subtitle: 'Impacte la vitesse de recherche'),
              _buildMenuItem(Icons.info, 'Informations'),
              
              const SizedBox(height: 20),
            ],
          ),
        ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickAction(IconData icon, String label) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: Color(0xFFF5F5F5),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.primary, size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(IconData icon, String title, {String? subtitle, Widget? trailing, Color iconColor = AppColors.primary}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(icon, color: iconColor, size: 26),
            title: Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.primary),
            ),
            subtitle: subtitle != null
                ? Text(
                    subtitle,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  )
                : null,
            trailing: trailing ?? const Icon(Icons.chevron_right, color: AppColors.primary),
            onTap: () {},
          ),
          const Divider(height: 1, color: Color(0xFFEEEEEE)),
        ],
      ),
    );
  }
}
