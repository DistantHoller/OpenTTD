/* Opt-in development fixture, added 2026-10-12. GPL-2.0-only. */
#ifndef MODERN_SHOWCASE_H
#define MODERN_SHOWCASE_H
bool ModernBuildShowcase(bool world_gallery = false, bool city_gallery = false);
void ModernSaveShowcaseReport(const std::string &stem);
void ModernInspectScene(const std::string &stem);
#endif
