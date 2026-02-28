#include <flutter/dart_project.h>
#include <flutter/flutter_engine.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <algorithm>
#include <chrono>
#include <cctype>
#include <ctime>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

static std::string GetRunnerLogPath() {
  char* program_data = nullptr;
  size_t len = 0;
  std::string base = "C:\\ProgramData";
  if (_dupenv_s(&program_data, &len, "ProgramData") == 0 &&
      program_data != nullptr && std::string(program_data).size() > 0) {
    base = program_data;
  }
  if (program_data != nullptr) {
    free(program_data);
  }
  const std::string app_dir = base + "\\BackupDatabase";
  const std::string logs_dir = app_dir + "\\logs";
  ::CreateDirectoryA(app_dir.c_str(), nullptr);
  ::CreateDirectoryA(logs_dir.c_str(), nullptr);
  return logs_dir + "\\runner_startup.log";
}

static void AppendRunnerLog(const std::string& message) {
  std::ofstream out(GetRunnerLogPath(), std::ios::out | std::ios::app);
  if (!out.is_open()) {
    return;
  }
  SYSTEMTIME st;
  ::GetLocalTime(&st);
  out << "[" << st.wYear << "-" << st.wMonth << "-" << st.wDay << " "
      << st.wHour << ":" << st.wMinute << ":" << st.wSecond << "."
      << st.wMilliseconds << "] " << message << "\n";
}

static std::string JoinArgs(const std::vector<std::string>& args) {
  std::ostringstream oss;
  oss << "[";
  for (size_t i = 0; i < args.size(); ++i) {
    if (i > 0) {
      oss << ", ";
    }
    oss << args[i];
  }
  oss << "]";
  return oss.str();
}

static std::string ToLowerCopy(std::string value) {
  std::transform(value.begin(), value.end(), value.begin(),
                 [](unsigned char c) { return std::tolower(c); });
  return value;
}

// Returns true if the process should run in headless service mode.
// Layer 1: Session 0 — services always run in Session 0; no GPU/desktop.
// Layer 2: --run-as-service argument (NSSM AppParameters).
// Layer 3: SERVICE_MODE env (NSSM AppEnvironmentExtra).
static bool IsServiceMode(const std::vector<std::string>& args) {
  DWORD session_id = 0;
  if (::ProcessIdToSessionId(::GetCurrentProcessId(), &session_id)) {
    AppendRunnerLog(
        "IsServiceMode: ProcessIdToSessionId succeeded, session_id=" +
        std::to_string(session_id));
    if (session_id == 0) {
      AppendRunnerLog("IsServiceMode: MATCH layer-1 (Session 0)");
      return true;
    }
  } else {
    AppendRunnerLog(
        "IsServiceMode: ProcessIdToSessionId failed, GetLastError=" +
        std::to_string(::GetLastError()));
  }

  for (const auto& arg : args) {
    if (arg == "--run-as-service") {
      AppendRunnerLog("IsServiceMode: MATCH layer-2 (--run-as-service)");
      return true;
    }
  }

  char* env_mode = nullptr;
  size_t env_len = 0;
  if (_dupenv_s(&env_mode, &env_len, "SERVICE_MODE") == 0 &&
      env_mode != nullptr) {
    AppendRunnerLog("IsServiceMode: SERVICE_MODE=" + std::string(env_mode));
    const std::string normalized_env_mode = ToLowerCopy(env_mode);
    const bool is_service_env = normalized_env_mode == "server" ||
                                normalized_env_mode == "1" ||
                                normalized_env_mode == "true";
    free(env_mode);
    if (is_service_env) {
      AppendRunnerLog(
          "IsServiceMode: MATCH layer-3 (SERVICE_MODE=server|1|true)");
      return true;
    }
  } else {
    AppendRunnerLog("IsServiceMode: SERVICE_MODE not set");
  }
  AppendRunnerLog("IsServiceMode: NO MATCH (UI mode)");
  return false;
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  AppendRunnerLog("wWinMain: startup begin");

  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  AppendRunnerLog("wWinMain: COM initialized");

  flutter::DartProject project(L"data");
  std::vector<std::string> command_line_arguments = GetCommandLineArguments();
  project.set_dart_entrypoint_arguments(command_line_arguments);
  AppendRunnerLog("wWinMain: args=" + JoinArgs(command_line_arguments));

  const bool service_mode = IsServiceMode(command_line_arguments);
  AppendRunnerLog(std::string("wWinMain: service_mode=") +
                  (service_mode ? "true" : "false"));

  if (service_mode) {
    AppendRunnerLog("wWinMain: entering headless engine branch");
    flutter::FlutterEngine engine(project);
    if (!engine.Run()) {
      AppendRunnerLog("wWinMain: engine.Run failed");
      ::CoUninitialize();
      return EXIT_FAILURE;
    }
    AppendRunnerLog("wWinMain: engine.Run succeeded");

    ::MSG msg;
    for (;;) {
      if (::PeekMessage(&msg, nullptr, 0, 0, PM_REMOVE)) {
        if (msg.message == WM_QUIT) {
          break;
        }
        ::TranslateMessage(&msg);
        ::DispatchMessage(&msg);
      } else {
        auto delay = engine.ProcessMessages();
        const auto ms = delay.count() > 0
            ? std::min(delay.count() / 1000000, static_cast<int64_t>(100))
            : 1;
        ::Sleep(static_cast<DWORD>(ms));
      }
    }

    AppendRunnerLog("wWinMain: headless loop finished, shutting down engine");
    engine.ShutDown();
    ::CoUninitialize();
    AppendRunnerLog("wWinMain: exit success (headless)");
    return EXIT_SUCCESS;
  }

  AppendRunnerLog("wWinMain: entering UI branch");
  FlutterWindow window(project, false);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);

  if (!window.Create(L"backup_database", origin, size)) {
    AppendRunnerLog("wWinMain: window.Create failed (UI branch)");
    ::CoUninitialize();
    return EXIT_FAILURE;
  }
  AppendRunnerLog("wWinMain: window.Create succeeded (UI branch)");

  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  AppendRunnerLog("wWinMain: exit success (UI)");
  return EXIT_SUCCESS;
}
