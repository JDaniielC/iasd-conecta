import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// As quatro paradas fixas do app — a barra aparece nelas e só nelas.
///
/// `notifications`, não `Novidades`: Novidades é changelog (o que mudou no
/// app), Notificações é aviso pessoal (o que aconteceu com você — convite,
/// denúncia resolvida...). A barra é para o que se consulta toda hora; o
/// changelog continua alcançável pela Home, que é onde se lê uma vez.
enum AppTab { myGroups, groups, actions, notifications }

const _routeByTab = {
  AppTab.myGroups: '/meus-grupos',
  AppTab.groups: '/grupos',
  AppTab.actions: '/acoes',
  AppTab.notifications: '/notificacoes',
};

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({super.key, required this.current});

  final AppTab current;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      // 64, não os 80 padrão do Material: em `/acoes` a faixa de destaque já
      // usa a dobra do celular inteira (destaque_acoes_test.dart mede isso a
      // 1px). Cada pixel de chrome novo tem que vir de algum lugar.
      height: 64,
      selectedIndex: AppTab.values.indexOf(current),
      // `go`, não `push`: as quatro paradas são destinos irmãos, não uma
      // pilha — trocar de aba não deve empilhar tela sobre tela.
      onDestinationSelected: (index) =>
          context.go(_routeByTab[AppTab.values[index]]!),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.checklist_outlined),
          selectedIcon: Icon(Icons.checklist),
          label: 'Meus Grupos',
        ),
        NavigationDestination(
          icon: Icon(Icons.groups_outlined),
          selectedIcon: Icon(Icons.groups),
          label: 'Grupos',
        ),
        NavigationDestination(
          icon: Icon(Icons.event_outlined),
          selectedIcon: Icon(Icons.event),
          label: 'Ações',
        ),
        NavigationDestination(
          icon: Icon(Icons.notifications_outlined),
          selectedIcon: Icon(Icons.notifications),
          label: 'Notificações',
        ),
      ],
    );
  }
}
