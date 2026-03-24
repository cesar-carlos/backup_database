#define WIN32_LEAN_AND_MEAN

#include <windows.h>

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>

namespace fs = std::filesystem;

namespace {

bool IsSkippedProfileDir(const wchar_t* name) {
  static const wchar_t* kSkipped[] = {L"Public", L"Default", L"Default User",
                                      L"All Users"};
  for (const wchar_t* s : kSkipped) {
    if (_wcsicmp(name, s) == 0) {
      return true;
    }
  }
  return false;
}

bool SqliteHeaderValid(const fs::path& db_path) {
  std::error_code ec;
  const auto sz = fs::file_size(db_path, ec);
  if (ec || sz < 16) {
    return false;
  }
  std::ifstream f(db_path, std::ios::binary);
  if (!f) {
    return false;
  }
  char buf[16];
  f.read(buf, 16);
  if (f.gcount() < 16) {
    return false;
  }
  static const char kSig[] = "SQLite format 3\0";
  return std::memcmp(buf, kSig, 16) == 0;
}

bool LegacyFolderHasSqliteDb(const fs::path& legacy_dir) {
  std::error_code ec;
  if (!fs::is_directory(legacy_dir, ec) || ec) {
    return false;
  }
  static const wchar_t* kBases[] = {L"backup_database", L"backup_database_client"};
  for (const wchar_t* base : kBases) {
    const fs::path db = legacy_dir / (std::wstring(base) + L".db");
    if (fs::is_regular_file(db, ec) && !ec && SqliteHeaderValid(db)) {
      return true;
    }
  }
  return false;
}

std::string WideToUtf8(std::wstring_view w) {
  if (w.empty()) {
    return {};
  }
  const int n = WideCharToMultiByte(CP_UTF8, 0, w.data(),
                                    static_cast<int>(w.size()), nullptr, 0,
                                    nullptr, nullptr);
  if (n <= 0) {
    return {};
  }
  std::string out(static_cast<size_t>(n), '\0');
  WideCharToMultiByte(CP_UTF8, 0, w.data(), static_cast<int>(w.size()),
                      out.data(), n, nullptr, nullptr);
  return out;
}

void AppendJsonEscapedUtf8(std::string& out, const std::string& utf8) {
  for (const unsigned char c : utf8) {
    switch (c) {
      case '"':
        out += "\\\"";
        break;
      case '\\':
        out += "\\\\";
        break;
      case '\b':
        out += "\\b";
        break;
      case '\f':
        out += "\\f";
        break;
      case '\n':
        out += "\\n";
        break;
      case '\r':
        out += "\\r";
        break;
      case '\t':
        out += "\\t";
        break;
      default:
        if (c < 0x20U) {
          char tmp[8];
          snprintf(tmp, sizeof(tmp), "\\u%04x", c);
          out += tmp;
        } else {
          out += static_cast<char>(c);
        }
    }
  }
}

bool ScanProfiles(std::vector<std::wstring>* legacy_paths) {
  const fs::path users_dir(L"C:\\Users");
  std::error_code ec;
  if (!fs::is_directory(users_dir, ec) || ec) {
    return true;
  }
  const fs::directory_iterator end;
  fs::directory_iterator it(users_dir, ec);
  if (ec) {
    return true;
  }
  for (; it != end; it.increment(ec)) {
    if (ec) {
      return false;
    }
    const fs::directory_entry& entry = *it;
    if (!entry.is_directory(ec) || ec) {
      continue;
    }
    const std::wstring name = entry.path().filename().wstring();
    if (IsSkippedProfileDir(name.c_str())) {
      continue;
    }
    const fs::path legacy =
        entry.path() / L"AppData" / L"Roaming" / L"Backup Database";
    if (LegacyFolderHasSqliteDb(legacy)) {
      legacy_paths->push_back(legacy.wstring());
    }
  }
  std::sort(legacy_paths->begin(), legacy_paths->end());
  legacy_paths->erase(std::unique(legacy_paths->begin(), legacy_paths->end()),
                      legacy_paths->end());
  return true;
}

void WriteIso8601UtcZ(char* buf, size_t buf_size) {
  SYSTEMTIME st = {};
  GetSystemTime(&st);
  snprintf(buf, buf_size, "%04u-%02u-%02uT%02u:%02u:%02u.%03uZ",
           static_cast<unsigned>(st.wYear), static_cast<unsigned>(st.wMonth),
           static_cast<unsigned>(st.wDay), static_cast<unsigned>(st.wHour),
           static_cast<unsigned>(st.wMinute), static_cast<unsigned>(st.wSecond),
           static_cast<unsigned>(st.wMilliseconds));
}

}  // namespace

int wmain(int argc, wchar_t* argv[]) {
  if (argc < 2) {
    return 2;
  }
  const fs::path out_path(argv[1]);
  std::error_code ec;
  fs::create_directories(out_path.parent_path(), ec);

  std::vector<std::wstring> paths;
  if (!ScanProfiles(&paths)) {
    return 3;
  }

  char iso[40] = {};
  WriteIso8601UtcZ(iso, sizeof(iso));

  std::string json;
  json.reserve(320 + paths.size() * 120);
  json += "{\"schemaVersion\":1,\"paths\":[";
  for (size_t i = 0; i < paths.size(); ++i) {
    if (i > 0) {
      json += ',';
    }
    json += '"';
    AppendJsonEscapedUtf8(json, WideToUtf8(paths[i]));
    json += '"';
  }
  json += "],\"scannedAtUtc\":\"";
  json += iso;
  json += "\"}";

  fs::path tmp_path = out_path;
  tmp_path += L".tmp";
  {
    std::ofstream out(tmp_path, std::ios::binary | std::ios::trunc);
    if (!out) {
      return 4;
    }
    out.write(json.data(), static_cast<std::streamsize>(json.size()));
    if (!out) {
      return 4;
    }
  }
  std::error_code rename_ec;
  fs::remove(out_path, rename_ec);
  fs::rename(tmp_path, out_path, rename_ec);
  if (rename_ec) {
    fs::remove(tmp_path, rename_ec);
    return 5;
  }
  return 0;
}
