// IMPORTANTE: winsock2.h DEVE vir ANTES de windows.h para evitar conflitos
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <cstring>
#include <string>

#include "flutter_window.h"
#include "utils.h"

#pragma comment(lib, "ws2_32.lib")

static HANDLE g_hMutex = nullptr;

std::wstring GetExistingInstanceUser() {
  WSADATA wsaData;
  if (WSAStartup(MAKEWORD(2, 2), &wsaData) != 0) {
    return L"";
  }
  
  for (int attempt = 0; attempt < 3; attempt++) {
    SOCKET sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (sock == INVALID_SOCKET) {
      if (attempt < 2) {
        Sleep(200);
        continue;
      }
      WSACleanup();
      return L"";
    }
    
    sockaddr_in addr;
    addr.sin_family = AF_INET;
    addr.sin_port = htons(58724);
    InetPtonA(AF_INET, "127.0.0.1", &addr.sin_addr);
    
    DWORD timeout = 1000;
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, reinterpret_cast<const char*>(&timeout), sizeof(timeout));
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, reinterpret_cast<const char*>(&timeout), sizeof(timeout));
    
    if (connect(sock, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) == 0) {
      const char* request = "GET_USER_INFO";
      send(sock, request, static_cast<int>(strlen(request)), 0);
      
      char buffer[256] = {0};
      int bytesReceived = recv(sock, buffer, sizeof(buffer) - 1, 0);
      
      closesocket(sock);
      WSACleanup();
      
      if (bytesReceived > 0) {
        buffer[bytesReceived] = '\0';
        std::string response(buffer);
        if (response.find("USER_INFO:") == 0) {
          std::string username = response.substr(10);
          int size_needed = MultiByteToWideChar(CP_UTF8, 0, username.c_str(), -1, NULL, 0);
          if (size_needed > 0) {
            std::wstring wusername(size_needed - 1, 0);
            MultiByteToWideChar(CP_UTF8, 0, username.c_str(), -1, &wusername[0], size_needed);
            return wusername;
          }
        }
      }
      
      return L"";
    }
    
    closesocket(sock);
    
    if (attempt < 2) {
      Sleep(200);
    }
  }
  
  WSACleanup();
  return L"";
}

void ShowInstanceBlockedMessage(const std::wstring& existingUser) {
  wchar_t currentUsername[256];
  DWORD usernameSize = 256;
  
  if (GetUserNameW(currentUsername, &usernameSize) == 0) {
    wcscpy_s(currentUsername, 256, L"Desconhecido");
  }
  
  std::wstring message = L"O aplicativo Backup Database já está em execução em outro usuário ou sessão do Windows.\n\n";
  message += L"Usuário atual: ";
  message += currentUsername;
  if (!existingUser.empty()) {
    message += L"\nUsuário da instância existente: ";
    message += existingUser;
  }
  message += L"\n\n";
  message += L"Não é permitido executar múltiplas instâncias do aplicativo simultaneamente em diferentes usuários do mesmo computador.\n\n";
  message += L"Por favor, feche a instância existente antes de tentar abrir novamente.";
  
  MessageBoxW(
    nullptr,
    message.c_str(),
    L"Instância Já em Execução - Backup Database",
    MB_OK | MB_ICONWARNING | MB_TOPMOST
  );
}

void NotifyExistingInstance() {
  WSADATA wsaData;
  if (WSAStartup(MAKEWORD(2, 2), &wsaData) != 0) {
    return;
  }
  
  // Tentar conectar até 5 vezes com delay de 200ms cada
  // Isso garante que o IPC server tenha tempo de inicializar
  for (int attempt = 0; attempt < 5; attempt++) {
    SOCKET sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (sock == INVALID_SOCKET) {
      if (attempt < 4) {
        Sleep(200);
        continue;
      }
      WSACleanup();
      return;
    }
    
    sockaddr_in addr;
    addr.sin_family = AF_INET;
    addr.sin_port = htons(58724);
    InetPtonA(AF_INET, "127.0.0.1", &addr.sin_addr);
    
    // Configurar timeout de conexão (1 segundo)
    DWORD timeout = 1000;
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, reinterpret_cast<const char*>(&timeout), sizeof(timeout));
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, reinterpret_cast<const char*>(&timeout), sizeof(timeout));
    
    if (connect(sock, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) == 0) {
      const char* message = "SHOW_WINDOW";
      send(sock, message, static_cast<int>(strlen(message)), 0);
      closesocket(sock);
      WSACleanup();
      return; // Sucesso!
    }
    
    closesocket(sock);
    
    // Aguardar antes de tentar novamente
    if (attempt < 4) {
      Sleep(200);
    }
  }
  
  WSACleanup();
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Verificar instância única usando Named Mutex
  // Usar "Global\" para garantir que funcione em sessões diferentes do Windows
  const wchar_t* mutexName = L"Global\\BackupDatabaseMutex_{A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5D}";
  
  // Limpar erro anterior para garantir leitura correta
  SetLastError(0);
  
  // Criar mutex nomeado
  // TRUE = queremos ownership imediato do mutex criado
  g_hMutex = ::CreateMutexW(nullptr, TRUE, mutexName);
  
  // Verificar erro IMEDIATAMENTE após CreateMutex (antes de qualquer outra operação)
  DWORD lastError = GetLastError();
  
  // Se o mutex já existir, outra instância está rodando
  if (lastError == ERROR_ALREADY_EXISTS) {
    // Outra instância já está rodando - fechar handle e sair
    if (g_hMutex != nullptr) {
      ::CloseHandle(g_hMutex);
      g_hMutex = nullptr;
    }
    
    // Obter usuário atual
    wchar_t currentUsername[256];
    DWORD usernameSize = 256;
    std::wstring currentUser;
    if (GetUserNameW(currentUsername, &usernameSize) != 0) {
      currentUser = currentUsername;
    }
    
    // Tentar obter usuário da instância existente via IPC
    std::wstring existingUser = GetExistingInstanceUser();
    
    // Só mostrar mensagem se for usuário diferente ou se não conseguir obter informação
    // Se for o mesmo usuário, apenas encerrar silenciosamente
    bool isDifferentUser = !existingUser.empty() && existingUser != currentUser;
    bool couldNotDetermineUser = existingUser.empty();
    
    if (isDifferentUser || couldNotDetermineUser) {
      // Mostrar mensagem informativa ao usuário apenas se for outro usuário
      ShowInstanceBlockedMessage(existingUser);
    }
    
    // Tentar notificar instância existente via IPC
    NotifyExistingInstance();
    
    // ENCERRAR IMEDIATAMENTE - não inicializar nada
    return EXIT_SUCCESS;
  }
  
  // Se não conseguiu criar o mutex (erro), também encerrar
  if (g_hMutex == nullptr) {
    // Erro crítico ao criar mutex - encerrar
    return EXIT_SUCCESS;
  }
  
  // Sucesso! Somos a primeira instância e temos o mutex

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
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"backup_database", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  // Liberar mutex ao sair
  if (g_hMutex != nullptr) {
    ::ReleaseMutex(g_hMutex);
    ::CloseHandle(g_hMutex);
    g_hMutex = nullptr;
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
