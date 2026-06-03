#import "GeneratedPluginRegistrant.h"

const char *tsp_agent_version_cstr(void);
const char *tsp_agent_health_cstr(void);
const char *tsp_agent_fingerprint_cstr(void);
void tsp_agent_string_free(const char *p);
int tsp_agent_start_paths(const char *configPath, const char *statePathOrNull);
int tsp_agent_set_payload_key_hex(const char *hexKey);
int tsp_agent_set_strict_mode(int enabled);
int tsp_agent_set_attestation_json(const char *json);
void tsp_agent_set_native_lib_path(const char *path);
void tsp_agent_stop_runtime(void);
int tsp_agent_is_runtime_running(void);
