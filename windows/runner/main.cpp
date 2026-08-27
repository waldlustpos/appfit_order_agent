#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

// Single-instance identity. Unified across korea and japan builds: the region
// is a runtime concept, so both share one mutex name and window title within
// a brand. Only one instance of the app runs on a machine per brand.
//
// Brand axis - see windows/CMakeLists.txt (APPFIT_BRAND_MAMMOTH). Common
// keeps the exact legacy values (no regression for the existing fleet).
//
// Each brand also carries a Local\ fallback name. Creating an object in the
// Global\ namespace requires SeCreateGlobalPrivilege, which a standard user
// account does not hold, so CreateMutexW returns null there. Session-local
// scope is good enough for a single-operator POS PC. Both names are listed in
// the installer's AppMutex so Setup can still detect a running instance
// either way.
#if defined(APPFIT_BRAND_MAMMOTH)
constexpr const wchar_t kSingleInstanceMutexName[] =
    L"Global\\AppfitOrderAgent_Mammoth_SingleInstance_Mutex";
constexpr const wchar_t kSingleInstanceMutexNameLocal[] =
    L"Local\\AppfitOrderAgent_Mammoth_SingleInstance_Mutex";
constexpr const wchar_t kWindowTitle[] = L"appfit_order_agent_mammoth";
#else
constexpr const wchar_t kSingleInstanceMutexName[] =
    L"Global\\AppfitOrderAgent_SingleInstance_Mutex";
constexpr const wchar_t kSingleInstanceMutexNameLocal[] =
    L"Local\\AppfitOrderAgent_SingleInstance_Mutex";
constexpr const wchar_t kWindowTitle[] = L"appfit_order_agent";
#endif

// Brings the already-running instance's window to the foreground.
BOOL CALLBACK BringExistingWindowToFront(HWND hwnd, LPARAM lparam) {
  DWORD process_id = 0;
  ::GetWindowThreadProcessId(hwnd, &process_id);
  if (process_id == static_cast<DWORD>(lparam)) {
    return TRUE;
  }
  wchar_t title[256] = {0};
  ::GetWindowTextW(hwnd, title, 256);
  if (wcscmp(title, kWindowTitle) == 0) {
    if (::IsIconic(hwnd)) {
      ::ShowWindow(hwnd, SW_RESTORE);
    } else {
      ::ShowWindow(hwnd, SW_SHOW);
    }
    ::SetForegroundWindow(hwnd);
    return FALSE;
  }
  return TRUE;
}

// Takes the single-instance mutex, falling back to the session-local
// namespace when the global one is refused.
//
// A failure to CREATE the mutex must never be confused with the mutex
// ALREADY EXISTING. The previous code checked both in one condition, so a
// standard user -- who cannot create Global\ objects -- was treated as a
// duplicate launch and the process exited with no window and no error
// message at all.
//
// Returns the handle, or null when no mutex could be created in either
// namespace. |already_running| reports whether another instance owns it.
HANDLE AcquireSingleInstanceMutex(bool *already_running) {
  *already_running = false;

  HANDLE mutex = ::CreateMutexW(nullptr, TRUE, kSingleInstanceMutexName);
  if (mutex != nullptr) {
    *already_running = (::GetLastError() == ERROR_ALREADY_EXISTS);
    return mutex;
  }

  mutex = ::CreateMutexW(nullptr, TRUE, kSingleInstanceMutexNameLocal);
  if (mutex != nullptr) {
    *already_running = (::GetLastError() == ERROR_ALREADY_EXISTS);
    return mutex;
  }

  // Both namespaces refused. Start anyway: a second window is a far smaller
  // failure than a store PC where clicking the icon does nothing.
  return nullptr;
}

// Counterpart of AcquireSingleInstanceMutex. Tolerates a null handle, which
// is the "no mutex could be created" case.
void ReleaseSingleInstanceMutex(HANDLE mutex) {
  if (mutex == nullptr) {
    return;
  }
  ::ReleaseMutex(mutex);
  ::CloseHandle(mutex);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Enforce single instance via a named mutex. If the mutex already exists,
  // another instance is running -- surface its window and exit.
  bool already_running = false;
  HANDLE single_instance_mutex = AcquireSingleInstanceMutex(&already_running);
  if (already_running) {
    ::EnumWindows(BringExistingWindowToFront,
                  static_cast<LPARAM>(::GetCurrentProcessId()));
    ::CloseHandle(single_instance_mutex);
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  // Initial logical client size. Dart-side WindowsBubbleService resizes to
  // the actual target (1280x720 on FHD+, smaller on low-res screens) via
  // setSize/setBounds. This initial value is INTENTIONALLY different from
  // any likely target so WM_SIZE fires after Flutter engine startup,
  // which is required for the D3D swapchain to present its first frame;
  // otherwise the window appears blank.
  Win32Window::Size size(1200, 675);
  if (!window.Create(kWindowTitle, origin, size)) {
    ReleaseSingleInstanceMutex(single_instance_mutex);
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();

  ReleaseSingleInstanceMutex(single_instance_mutex);
  return EXIT_SUCCESS;
}
