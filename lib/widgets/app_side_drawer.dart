import 'package:flutter/material.dart';

typedef DrawerSelect = void Function(String route);

class AppSideDrawer extends StatelessWidget {
  final DrawerSelect onSelect;
  const AppSideDrawer({super.key, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            const ListTile(
              title: Text(
                'Muddy Trails',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              subtitle: Text('Explorar trilhas e navegar'),
            ),
            const Divider(),
            _item(context, Icons.explore, 'Descobrir aqui', '/descobrir'),
            _item(context, Icons.map, 'Mapas offline (futuro)', '/offline'),
            _item(context, Icons.route, 'Rotas (futuro)', '/rotas'),
            _item(context, Icons.settings, 'Configurações (futuro)', '/config'),
          ],
        ),
      ),
    );
  }

  Widget _item(BuildContext ctx, IconData icon, String label, String route) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        Navigator.pop(ctx);
        onSelect(route);
      },
    );
  }
}
