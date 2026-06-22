// لینک به TspAgent* از cmd/mobilehost؛ TspAgent.xcframework (استاتیک) — در Xcode: Link + Embed = Do Not Embed
#include "tspagent_api.h"

#if defined(__APPLE__)
#include <TargetConditionals.h>
#endif

#if TARGET_OS_IPHONE
#include <stdlib.h>
#include <string.h>
#include <sys/sysctl.h>
#include <sys/proc.h>
#include <unistd.h>

/// بلافاصله قبل از `TspAgentStart`: Swift ممکن است زودتر از اتصال LLDB اجرا شده باشد؛
/// یا Profile/Release بدون `-DDEBUG`. اینجا دوباره چک می‌کنیم تا `AGENT_SKIP_*` حتماً قبل از Go ست شود.
static void tsp_ios_apply_rasp_bypass_if_needed(void) {
#ifdef DEBUG
  setenv("AGENT_SKIP_EARLY_RASP", "1", 1);
  setenv("AGENT_SKIP_DYNAMIC_RASP", "1", 1);
  setenv("AGENT_MOBILE_HOST_DEV", "1", 1);
  return;
#else
  struct kinfo_proc info;
  memset(&info, 0, sizeof(info));
  size_t size = sizeof(info);
  int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, (int)getpid()};
  if (sysctl(mib, 4, &info, &size, NULL, 0) != 0) {
    return;
  }
  if (info.kp_proc.p_flag & P_TRACED) {
    setenv("AGENT_SKIP_EARLY_RASP", "1", 1);
    setenv("AGENT_SKIP_DYNAMIC_RASP", "1", 1);
    setenv("AGENT_MOBILE_HOST_DEV", "1", 1);
  }
#endif
}
#endif /* TARGET_OS_IPHONE */

typedef char *(*fn_version_t)(void);
typedef char *(*fn_health_t)(void);
typedef char *(*fn_fingerprint_t)(void);
typedef void (*fn_free_t)(char *);
typedef int (*fn_start_t)(const char *, const char *);
typedef int (*fn_setkey_t)(const char *);
typedef int (*fn_setstrict_t)(int);
typedef int (*fn_setattest_t)(const char *);
typedef void (*fn_setnatpath_t)(const char *);
typedef void (*fn_stop_t)(void);
typedef int (*fn_running_t)(void);

typedef struct {
  fn_version_t version;
  fn_health_t health;
  fn_fingerprint_t fingerprint;
  fn_free_t str_free;
  fn_start_t start;
  fn_setkey_t set_key;
  fn_setstrict_t set_strict;
  fn_setattest_t set_attest;
  fn_setnatpath_t set_natpath;
  fn_stop_t stop;
  fn_running_t running;
} tsp_jump_table_t;

static tsp_jump_table_t g_tsp_jt = {0};

__attribute__((noinline)) static void tsp_init_jump_table(void) {
  if (g_tsp_jt.version != 0) {
    return;
  }
  g_tsp_jt.version = &TspAgentVersionString;
  g_tsp_jt.health = &TspAgentHealthJSON;
  g_tsp_jt.fingerprint = &TspAgentFingerprint;
  g_tsp_jt.str_free = &TspAgentFree;
  g_tsp_jt.start = &TspAgentStart;
  g_tsp_jt.set_key = &TspAgentSetPayloadKeyHex;
  g_tsp_jt.set_strict = &TspAgentSetStrictMode;
  g_tsp_jt.set_attest = &TspAgentSetAttestationJSON;
  g_tsp_jt.set_natpath = &TspAgentSetNativeLibPath;
  g_tsp_jt.stop = &TspAgentStop;
  g_tsp_jt.running = &TspAgentIsRunning;
}

const char *tsp_agent_version_cstr(void) {
  tsp_init_jump_table();
  return g_tsp_jt.version();
}

const char *tsp_agent_health_cstr(void) {
  tsp_init_jump_table();
  return g_tsp_jt.health();
}

const char *tsp_agent_fingerprint_cstr(void) {
  tsp_init_jump_table();
  return g_tsp_jt.fingerprint();
}

void tsp_agent_string_free(const char *p) {
  tsp_init_jump_table();
  g_tsp_jt.str_free((char *)p);
}

int tsp_agent_start_paths(const char *configPath, const char *statePathOrNull) {
  tsp_init_jump_table();
#if TARGET_OS_IPHONE
  tsp_ios_apply_rasp_bypass_if_needed();
#endif
  return g_tsp_jt.start(configPath, statePathOrNull);
}

int tsp_agent_set_payload_key_hex(const char *hexKey) {
  tsp_init_jump_table();
  return g_tsp_jt.set_key(hexKey);
}

int tsp_agent_set_strict_mode(int enabled) {
  tsp_init_jump_table();
  return g_tsp_jt.set_strict(enabled);
}

int tsp_agent_set_attestation_json(const char *json) {
  tsp_init_jump_table();
  return g_tsp_jt.set_attest(json);
}

void tsp_agent_set_native_lib_path(const char *path) {
  tsp_init_jump_table();
  g_tsp_jt.set_natpath(path);
}

void tsp_agent_stop_runtime(void) {
  tsp_init_jump_table();
  g_tsp_jt.stop();
}

int tsp_agent_is_runtime_running(void) {
  tsp_init_jump_table();
  return g_tsp_jt.running();
}
