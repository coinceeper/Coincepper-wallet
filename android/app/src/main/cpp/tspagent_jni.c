#include <jni.h>
#include <string.h>
#include <dlfcn.h>

#if defined(__GNUC__) || defined(__clang__)
#define HIDDEN __attribute__((visibility("hidden")))
#define EXPORTED __attribute__((visibility("default")))
#else
#define HIDDEN
#define EXPORTED
#endif

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
static void *g_tsp_handle = NULL;

HIDDEN static void *tsp_dlsym(const char *name) {
  if (g_tsp_handle == NULL) {
    g_tsp_handle = dlopen("libtspagent.so", RTLD_NOW | RTLD_NOLOAD);
  }
  if (g_tsp_handle != NULL) {
    void *p = dlsym(g_tsp_handle, name);
    if (p != NULL) {
      return p;
    }
  }
  return dlsym(RTLD_DEFAULT, name);
}

HIDDEN __attribute__((noinline)) static void tsp_init_jump_table(void) {
  if (g_tsp_jt.version != 0) {
    return;
  }
  /* libtspagent جدا (jniLibs یا فایل رمزشده روی دیسک) باید قبل از tspagent_jni با System.load لود شده باشد. */
  g_tsp_jt.version = (fn_version_t)(void *)tsp_dlsym("TspAgentVersionString");
  g_tsp_jt.health = (fn_health_t)(void *)tsp_dlsym("TspAgentHealthJSON");
  g_tsp_jt.fingerprint = (fn_fingerprint_t)(void *)tsp_dlsym("TspAgentFingerprint");
  g_tsp_jt.str_free = (fn_free_t)(void *)tsp_dlsym("TspAgentFree");
  g_tsp_jt.start = (fn_start_t)(void *)tsp_dlsym("TspAgentStart");
  g_tsp_jt.set_key = (fn_setkey_t)(void *)tsp_dlsym("TspAgentSetPayloadKeyHex");
  g_tsp_jt.set_strict = (fn_setstrict_t)(void *)tsp_dlsym("TspAgentSetStrictMode");
  g_tsp_jt.set_attest = (fn_setattest_t)(void *)tsp_dlsym("TspAgentSetAttestationJSON");
  g_tsp_jt.set_natpath = (fn_setnatpath_t)(void *)tsp_dlsym("TspAgentSetNativeLibPath");
  g_tsp_jt.stop = (fn_stop_t)(void *)tsp_dlsym("TspAgentStop");
  g_tsp_jt.running = (fn_running_t)(void *)tsp_dlsym("TspAgentIsRunning");
}

HIDDEN static jstring c_to_jstring(JNIEnv *env, char *c) {
  if (c == NULL) {
    return (*env)->NewStringUTF(env, "");
  }
  jstring s = (*env)->NewStringUTF(env, c);
  tsp_init_jump_table();
  if (g_tsp_jt.str_free) {
    g_tsp_jt.str_free(c);
  }
  return s;
}

HIDDEN static jstring native_versionString(JNIEnv *env, jobject thiz) {
  (void)thiz;
  tsp_init_jump_table();
  if (!g_tsp_jt.version) {
    return (*env)->NewStringUTF(env, "NATIVE_UNAVAILABLE");
  }
  return c_to_jstring(env, g_tsp_jt.version());
}

HIDDEN static jstring native_healthJson(JNIEnv *env, jobject thiz) {
  (void)thiz;
  tsp_init_jump_table();
  if (!g_tsp_jt.health) {
    return (*env)->NewStringUTF(env, "{\"ok\":false,\"error\":\"native_unavailable\"}");
  }
  return c_to_jstring(env, g_tsp_jt.health());
}

HIDDEN static jstring native_fingerprint(JNIEnv *env, jobject thiz) {
  (void)thiz;
  tsp_init_jump_table();
  if (!g_tsp_jt.fingerprint) {
    return (*env)->NewStringUTF(env, "");
  }
  return c_to_jstring(env, g_tsp_jt.fingerprint());
}

HIDDEN static jint native_startWithPaths(JNIEnv *env, jobject thiz, jstring jConfig, jstring jState) {
  (void)thiz;
  tsp_init_jump_table();
  if (!g_tsp_jt.start) {
    return (jint)-3;
  }
  const char *cconf = jConfig ? (*env)->GetStringUTFChars(env, jConfig, NULL) : NULL;
  const char *cst = jState ? (*env)->GetStringUTFChars(env, jState, NULL) : NULL;
  int rc = g_tsp_jt.start(cconf, cst);
  if (cconf) {
    (*env)->ReleaseStringUTFChars(env, jConfig, cconf);
  }
  if (cst) {
    (*env)->ReleaseStringUTFChars(env, jState, cst);
  }
  return (jint)rc;
}

HIDDEN static jint native_setPayloadKeyHex(JNIEnv *env, jobject thiz, jstring jHex) {
  (void)thiz;
  tsp_init_jump_table();
  if (!g_tsp_jt.set_key) {
    return (jint)-1;
  }
  const char *chex = jHex ? (*env)->GetStringUTFChars(env, jHex, NULL) : NULL;
  int rc = g_tsp_jt.set_key(chex);
  if (chex) {
    (*env)->ReleaseStringUTFChars(env, jHex, chex);
  }
  return (jint)rc;
}

HIDDEN static jint native_setStrictMode(JNIEnv *env, jobject thiz, jint jMode) {
  (void)env;
  (void)thiz;
  tsp_init_jump_table();
  if (!g_tsp_jt.set_strict) {
    return (jint)-1;
  }
  return (jint)g_tsp_jt.set_strict((int)jMode);
}

HIDDEN static jint native_setAttestationJSON(JNIEnv *env, jobject thiz, jstring jJson) {
  (void)thiz;
  tsp_init_jump_table();
  if (!g_tsp_jt.set_attest) {
    return (jint)-1;
  }
  const char *c = jJson ? (*env)->GetStringUTFChars(env, jJson, NULL) : NULL;
  int rc = g_tsp_jt.set_attest(c);
  if (c) {
    (*env)->ReleaseStringUTFChars(env, jJson, c);
  }
  return (jint)rc;
}

HIDDEN static void native_setNativeLibPath(JNIEnv *env, jobject thiz, jstring jPath) {
  (void)thiz;
  tsp_init_jump_table();
  if (!g_tsp_jt.set_natpath) {
    return;
  }
  const char *c = jPath ? (*env)->GetStringUTFChars(env, jPath, NULL) : NULL;
  g_tsp_jt.set_natpath(c);
  if (c) {
    (*env)->ReleaseStringUTFChars(env, jPath, c);
  }
}

HIDDEN static void native_stopRuntime(JNIEnv *env, jobject thiz) {
  (void)env;
  (void)thiz;
  tsp_init_jump_table();
  if (g_tsp_jt.stop) {
    g_tsp_jt.stop();
  }
}

HIDDEN static jboolean native_isRuntimeRunning(JNIEnv *env, jobject thiz) {
  (void)env;
  (void)thiz;
  tsp_init_jump_table();
  if (!g_tsp_jt.running) {
    return JNI_FALSE;
  }
  return g_tsp_jt.running() ? JNI_TRUE : JNI_FALSE;
}

static JNINativeMethod gMethods[] = {
    {"versionString", "()Ljava/lang/String;", (void *)native_versionString},
    {"healthJson", "()Ljava/lang/String;", (void *)native_healthJson},
    {"fingerprint", "()Ljava/lang/String;", (void *)native_fingerprint},
    {"startWithPaths", "(Ljava/lang/String;Ljava/lang/String;)I", (void *)native_startWithPaths},
    {"setPayloadKeyHex", "(Ljava/lang/String;)I", (void *)native_setPayloadKeyHex},
    {"setStrictMode", "(I)I", (void *)native_setStrictMode},
    {"setAttestationJSON", "(Ljava/lang/String;)I", (void *)native_setAttestationJSON},
    {"setNativeLibPath", "(Ljava/lang/String;)V", (void *)native_setNativeLibPath},
    {"stopRuntime", "()V", (void *)native_stopRuntime},
    {"isRuntimeRunning", "()Z", (void *)native_isRuntimeRunning},
};

// Export only JNI_OnLoad; all native entry points are hidden + registered manually.
JNIEXPORT EXPORTED jint JNICALL JNI_OnLoad(JavaVM *vm, void *reserved) {
  (void)reserved;
  JNIEnv *env = NULL;
  if ((*vm)->GetEnv(vm, (void **)&env, JNI_VERSION_1_6) != JNI_OK || env == NULL) {
    return JNI_ERR;
  }
  jclass cls = (*env)->FindClass(env, "com/coinceeper/adl/TspAgentBridge");
  if (cls == NULL) {
    return JNI_ERR;
  }
  if ((*env)->RegisterNatives(env, cls, gMethods, (jint)(sizeof(gMethods) / sizeof(gMethods[0]))) != JNI_OK) {
    (*env)->DeleteLocalRef(env, cls);
    return JNI_ERR;
  }
  (*env)->DeleteLocalRef(env, cls);
  return JNI_VERSION_1_6;
}
