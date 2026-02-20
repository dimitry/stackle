import 'package:flutter/material.dart';

import 'features/main/main_screen.dart';
import 'features/startup/startup_screens.dart';
import 'state/app_controller.dart';
import 'ui/theme/app_theme.dart';

class StackleApp extends StatefulWidget {
  const StackleApp({super.key});

  @override
  State<StackleApp> createState() => _StackleAppState();
}

class _StackleAppState extends State<StackleApp> {
  late final AppController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AppController();
    _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Stackle',
      theme: buildAppTheme(),
      home: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          switch (_controller.startupState) {
            case StartupState.loading:
              return const LoadingScreen();
            case StartupState.needsDatabase:
              return DatabaseSelectionScreen(
                title: 'Choose where your todos live',
                description:
                    'Select a SQLite file path for local-first storage. The file can be in iCloud Drive, Dropbox, or any folder you prefer.',
                primaryLabel: 'Create New Database',
                primaryAction: _controller.createDatabaseWithPicker,
                secondaryLabel: 'Locate Existing Database',
                secondaryAction: _controller.locateExistingDatabaseWithPicker,
                onQuit: _controller.quitApplication,
              );
            case StartupState.missingDatabase:
              return DatabaseSelectionScreen(
                title: 'Database file not found',
                description:
                    'The last selected database is unavailable:\n${_controller.missingPath ?? 'Unknown path'}',
                primaryLabel: 'Locate Existing Database',
                primaryAction: _controller.locateExistingDatabaseWithPicker,
                secondaryLabel: 'Create New Database',
                secondaryAction: _controller.createDatabaseWithPicker,
                onQuit: _controller.quitApplication,
              );
            case StartupState.fatal:
              return DatabaseSelectionScreen(
                title: 'Unable to open database',
                description:
                    _controller.fatalError ?? 'Unknown database error.',
                primaryLabel: 'Retry',
                primaryAction: _controller.retryOpenSavedDatabase,
                secondaryLabel: 'Locate Existing Database',
                secondaryAction: _controller.locateExistingDatabaseWithPicker,
                onQuit: _controller.quitApplication,
              );
            case StartupState.ready:
              return MainScreen(controller: _controller);
          }
        },
      ),
    );
  }
}
