import 'package:flutter/material.dart';

/// Consistent notification and settings actions for every main section.
List<Widget> buildSharedAppBarActions(BuildContext context) {
  return [
    IconButton(
      tooltip: 'Notifications',
      onPressed: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No new notifications'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      icon: const Icon(Icons.notifications_none_rounded),
    ),
    IconButton(
      tooltip: 'Settings',
      onPressed: () => Navigator.pushNamed(context, '/settings'),
      icon: const Icon(Icons.settings_outlined),
    ),
  ];
}
