#include "utils.h"

#include <flutter_windows.h>
#include <io.h>
#include <stdio.h>
#include <windows.h>

#include <iostream>

void CreateAndAttachConsole() {
  if (::AllocConsole()) {
    FILE *unused;
    if (freopen_s(&unused, "CONOUT$", "w", stdout)) {
      _dup2(_fileno(stdout), 1);
    }
    if (freopen_s(&unused, "CONOUT$", "w", stderr)) {
      _dup2(_fileno(stderr), 2);
    }
    if (freopen_s(&unused, "CONIN$", "r", stdin)) {
      _dup2(_fileno(stdin), 0);
    }
    std::ios::sync_with_stdio();
    SetConsoleOutputCP(CP_UTF8);
  }
}

std::vector<std::string> GetCommandLineArguments() {
  int argc;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return std::vector<std::string>();
  }

  std::vector<std::string> command_line_arguments;
  command_line_arguments.reserve(argc - 1);
  for (int i = 1; i < argc; ++i) {
    int size_needed = WideCharToMultiByte(CP_UTF8, 0, argv[i], -1, nullptr, 0, nullptr, nullptr);
    std::string arg(size_needed - 1, 0);
    WideCharToMultiByte(CP_UTF8, 0, argv[i], -1, &arg[0], size_needed, nullptr, nullptr);
    command_line_arguments.push_back(arg);
  }

  ::LocalFree(argv);
  return command_line_arguments;
}
