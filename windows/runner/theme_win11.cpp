#include "theme_win11.h"

void ApplyThemeWin11(HWND hwnd, bool is_dark, bool is_startup) {
  BOOL enable_dark_mode = is_dark ? TRUE : FALSE;
  DwmSetWindowAttribute(hwnd, 20, &enable_dark_mode, sizeof(enable_dark_mode));

  if (is_startup) {
    // Set backdrop type to DWMSBT_TRANSIENTWINDOW (Acrylic = 3)
    int backdrop_type = 3;
    DwmSetWindowAttribute(hwnd, 38, &backdrop_type, sizeof(backdrop_type));

    // Extend frame into client area
    MARGINS margins = { -1, -1, -1, -1 };
    DwmExtendFrameIntoClientArea(hwnd, &margins);
  }
}
