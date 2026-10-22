# RFMonitor — Windows

This folder is an independent copy of the Flutter app for desktop development.
The Android/mobile project remains in `flutter_app/`; changes made here do not
modify that source tree.

## Windows setup

Requirements:

- Flutter 3.22.3 or later with Windows desktop support enabled (the minimum
  version declared by `pubspec.yaml`)
- Visual Studio 2022 with the **Desktop development with C++** workload
- Windows 10 or later

From this folder:

```powershell
flutter doctor -v
flutter config --enable-windows-desktop
flutter pub get
flutter run -d windows
```

To create a release package:

```powershell
flutter build windows --release
```

The GitHub Actions workflow in `.github/workflows/build-windows.yml` builds the
Windows release on pushes to `main` or `master`, or when started manually. It
uploads a `RFMonitor-Windows-x64` artifact containing the complete portable
application folder as a ZIP.

The desktop window supports normal Windows resize, minimize, maximize, and
restore actions. The app switches to a vertical navigation rail on wide
windows, and retains the compact navigation bar at narrower sizes.

## Platform differences

- Floating overlay controls are intentionally disabled on Windows.
- The app starts with the RFMonitor splash screen and keeps the navigation
  visible on first launch, including before a server has been configured.
- The Windows executable and taskbar icon use `assets/icon/app_icon.png`.
- SSH terminal input uses the PC keyboard directly; arrow keys move the remote
  terminal cursor. Mobile-only shortcut rows and pinch zoom are not shown.
- Server monitoring still uses the configured Server Agent URL. SSH and SFTP
  remain direct connections to the selected host.

This copy shares the Flutter package configuration with the mobile project.
The workflow produces a portable ZIP, not an installer.
