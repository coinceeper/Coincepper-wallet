/* C symbols exported from github.com/tsp-platform/agent/cmd/mobilehost (c-shared build).
   Keep aligned with agent/include/tspagent_api.h. */
#ifndef TSPAGENT_API_H
#define TSPAGENT_API_H

#ifdef __cplusplus
extern "C" {
#endif

char *TspAgentVersionString(void);
char *TspAgentHealthJSON(void);
char *TspAgentFingerprint(void);
void TspAgentFree(char *p);
/* 0=ok, -1=bad path, -2=already running, -3=config, -4=RASP, -5=device-bound key required (TEE) */
int TspAgentStart(const char *configPath, const char *statePathOrEmpty);
/* same as AGENT_STRICT_MODE=1 before Version/Start (optional) */
int TspAgentSetStrictMode(int enabled);
int TspAgentSetAttestationJSON(const char *json);
void TspAgentSetNativeLibPath(const char *absolutePathOrEmpty);
/* 64 hex chars, returns 0 on success, -1 invalid */
int TspAgentSetPayloadKeyHex(const char *hexKey);
void TspAgentStop(void);
int TspAgentIsRunning(void);

#ifdef __cplusplus
}
#endif

#endif
