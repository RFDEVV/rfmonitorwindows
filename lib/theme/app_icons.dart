/// Kumpulan SVG icon custom (bukan Material Icons) — dipakai di AppHeaderBar
/// tiap layar supaya tiap section (Dashboard, PM2, Service, Speedtest,
/// Server, Settings, Terminal) punya lambang sendiri, senada dengan gaya
/// icon di bottom nav (glass_bottom_nav.dart) dan referensi desain
/// "EFW Monitor" / "PM2 Process Monitor".
class AppIcons {
  AppIcons._();

  static const dashboard =
      '<svg viewBox="0 0 24 24"><path d="M3 13h8V3H3v10zm0 8h8v-6H3v6zm10 0h8V11h-8v10zm0-18v6h8V3h-8z" fill="currentColor"/></svg>';

  /// Layered diamond — mirip referensi "PM2 PROCESS MONITOR"
  static const pm2 =
      '<svg viewBox="0 0 24 24"><path d="M12 2 21 7 12 12 3 7z" fill="currentColor"/><path d="M3 12l9 5 9-5" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/><path d="M3 17l9 5 9-5" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" opacity="0.55"/></svg>';

  static const service =
      '<svg viewBox="0 0 24 24"><path d="M12 2 3 6v6c0 5 4 9 9 10 5-1 9-5 9-10V6l-9-4z" fill="none" stroke="currentColor" stroke-width="1.6"/><path d="M9 12l2 2 4-4" stroke="currentColor" stroke-width="1.6" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>';

  static const power =
      '<svg viewBox="0 0 24 24"><path d="M13 2 3 14h7l-1 8 10-12h-7l1-8z" fill="currentColor"/></svg>';

  /// Server rack dengan lampu indikator
  static const server =
      '<svg viewBox="0 0 24 24"><rect x="4" y="4" width="16" height="6" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.6"/><rect x="4" y="14" width="16" height="6" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.6"/><circle cx="7.5" cy="7" r="1" fill="currentColor"/><circle cx="7.5" cy="17" r="1" fill="currentColor"/></svg>';

  static const speedtest =
      '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" stroke-width="2"/><path d="M12 12 17 7" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>';

  static const settings =
      '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="3" fill="currentColor"/><path d="M19 12a7 7 0 0 0-.1-1.2l2-1.6-2-3.4-2.4 1a7 7 0 0 0-2-1.2L14 3h-4l-.5 2.6a7 7 0 0 0-2 1.2l-2.4-1-2 3.4 2 1.6A7 7 0 0 0 5 12c0 .4 0 .8.1 1.2l-2 1.6 2 3.4 2.4-1a7 7 0 0 0 2 1.2L10 21h4l.5-2.6a7 7 0 0 0 2-1.2l2.4 1 2-3.4-2-1.6c.1-.4.1-.8.1-1.2z" fill="none" stroke="currentColor" stroke-width="1.4"/></svg>';

  /// Prompt terminal ">_" — mirip referensi "EFW MONITOR"
  static const terminal =
      '<svg viewBox="0 0 24 24"><rect x="2" y="4" width="20" height="16" rx="3" fill="none" stroke="currentColor" stroke-width="1.6"/><path d="M6 9l4 3-4 3" stroke="currentColor" stroke-width="1.8" fill="none" stroke-linecap="round" stroke-linejoin="round"/><path d="M12 15h6" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>';

  static const logs =
      '<svg viewBox="0 0 24 24"><rect x="4" y="3" width="16" height="18" rx="2" fill="none" stroke="currentColor" stroke-width="1.6"/><path d="M8 8h8M8 12h8M8 16h5" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>';
}
