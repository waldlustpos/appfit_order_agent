#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr const wchar_t kSingleInstanceMutexName[] =
    L"Global\\AppfitOrderAgent_SingleInstance_Mutex";
constexpr const wchar_t kWindowTitle[] = L"appfit_order_agent";

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

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Enforce single instance via a named mutex. If the mutex already exists,
  // another instance is running -- surface its window and exit.
  HANDLE single_instance_mutex =
      ::CreateMutexW(nullptr, TRUE, kSingleInstanceMutexName);
  if (single_instance_mutex == nullptr ||
      ::GetLastError() == ERROR_ALREADY_EXISTS) {
    ::EnumWindows(BringExistingWindowToFront,
                  static_cast<LPARAM>(::GetCurrentProcessId()));
    if (single_instance_mutex != nullptr) {
      ::CloseHandle(single_instance_mutex);
    }
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
    ::ReleaseMutex(single_instance_mutex);
    ::CloseHandle(single_instance_mutex);
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();

  ::ReleaseMutex(single_instance_mutex);
  ::CloseHandle(single_instance_mutex);
  return EXIT_SUCCESS;
}
