// Счётчик живых и созданных GL-объектов (Linux): gcc -O1 -shared -fPIC -o gl_count.so tools/gl_count.c -ldl;
// LD_PRELOAD=./gl_count.so GLSTATS=/tmp/glstats.txt godot ... — каждый кадр пишет «объект живых создано» в файл.
// Нашёл потоки буферов/VAO по ~90 штук на кадр из HUD (см. README, «Вылет на третьем бою (2.5)»).
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdatomic.h>
#include <stdint.h>
typedef unsigned int GLuint; typedef int GLsizei; typedef unsigned int GLenum; typedef intptr_t GLsizeiptr;
enum { TEX, BUF, VAO, FBO, RBO, PROG, SHADER, QUERY, SAMPLER, TFB, N };
static const char *NAMES[N] = {"tex","buf","vao","fbo","rbo","prog","shader","query","sampler","tfb"};
static atomic_long live[N], total[N];
static atomic_long bufbytes_alloc;
static void *(*real_dlsym)(void *, const char *);
static void *(*real_glx)(const char *);
static void *(*real_glxarb)(const unsigned char *);
static void *(*real_egl)(const char *);
static void *r[64];
#define GEN(nm, T, REAL) \
 static void (*REAL)(GLsizei, GLuint *); \
 static void w_##nm(GLsizei n, GLuint *p) { REAL(n, p); atomic_fetch_add(&live[T], n); atomic_fetch_add(&total[T], n); }
#define DEL(nm, T, REAL) \
 static void (*REAL)(GLsizei, const GLuint *); \
 static void w_##nm(GLsizei n, const GLuint *p) { int c = 0; for (int i = 0; i < n; i++) if (p[i]) c++; REAL(n, p); atomic_fetch_sub(&live[T], c); }
GEN(glGenTextures, TEX, rGenTex) DEL(glDeleteTextures, TEX, rDelTex)
GEN(glGenBuffers, BUF, rGenBuf) DEL(glDeleteBuffers, BUF, rDelBuf)
GEN(glGenVertexArrays, VAO, rGenVao) DEL(glDeleteVertexArrays, VAO, rDelVao)
GEN(glGenFramebuffers, FBO, rGenFbo) DEL(glDeleteFramebuffers, FBO, rDelFbo)
GEN(glGenRenderbuffers, RBO, rGenRbo) DEL(glDeleteRenderbuffers, RBO, rDelRbo)
GEN(glGenQueries, QUERY, rGenQ) DEL(glDeleteQueries, QUERY, rDelQ)
GEN(glGenSamplers, SAMPLER, rGenSam) DEL(glDeleteSamplers, SAMPLER, rDelSam)
GEN(glGenTransformFeedbacks, TFB, rGenTfb) DEL(glDeleteTransformFeedbacks, TFB, rDelTfb)
static GLuint (*rCreateProg)(void); static GLuint w_glCreateProgram(void) { atomic_fetch_add(&live[PROG], 1); atomic_fetch_add(&total[PROG], 1); return rCreateProg(); }
static void (*rDelProg)(GLuint); static void w_glDeleteProgram(GLuint p) { if (p) atomic_fetch_sub(&live[PROG], 1); rDelProg(p); }
static GLuint (*rCreateSh)(GLenum); static GLuint w_glCreateShader(GLenum t) { atomic_fetch_add(&live[SHADER], 1); atomic_fetch_add(&total[SHADER], 1); return rCreateSh(t); }
static void (*rDelSh)(GLuint); static void w_glDeleteShader(GLuint p) { if (p) atomic_fetch_sub(&live[SHADER], 1); rDelSh(p); }
static void (*rBufData)(GLenum, GLsizeiptr, const void *, GLenum);
static void w_glBufferData(GLenum t, GLsizeiptr s, const void *d, GLenum u) { atomic_fetch_add(&bufbytes_alloc, s); rBufData(t, s, d, u); }
static void dump(void) {
  const char *path = getenv("GLSTATS"); if (!path) path = "/tmp/glstats.txt";
  FILE *f = fopen(path, "w"); if (!f) return;
  for (int i = 0; i < N; i++) fprintf(f, "%s %ld %ld\n", NAMES[i], (long)live[i], (long)total[i]);
  fprintf(f, "bufdata_mb_total %ld\n", (long)(bufbytes_alloc / 1048576));
  fclose(f);
}
static void (*rSwap)(void *, unsigned long); static int frames;
static void w_glXSwapBuffers(void *d, unsigned long w) { if ((++frames % 5) == 0) dump(); rSwap(d, w); }
typedef struct { const char *n; void *w; void **real; } E;
static E TAB[] = {
 {"glGenTextures", w_glGenTextures, (void**)&rGenTex}, {"glDeleteTextures", w_glDeleteTextures, (void**)&rDelTex},
 {"glGenBuffers", w_glGenBuffers, (void**)&rGenBuf}, {"glDeleteBuffers", w_glDeleteBuffers, (void**)&rDelBuf},
 {"glGenVertexArrays", w_glGenVertexArrays, (void**)&rGenVao}, {"glDeleteVertexArrays", w_glDeleteVertexArrays, (void**)&rDelVao},
 {"glGenFramebuffers", w_glGenFramebuffers, (void**)&rGenFbo}, {"glDeleteFramebuffers", w_glDeleteFramebuffers, (void**)&rDelFbo},
 {"glGenRenderbuffers", w_glGenRenderbuffers, (void**)&rGenRbo}, {"glDeleteRenderbuffers", w_glDeleteRenderbuffers, (void**)&rDelRbo},
 {"glGenQueries", w_glGenQueries, (void**)&rGenQ}, {"glDeleteQueries", w_glDeleteQueries, (void**)&rDelQ},
 {"glGenSamplers", w_glGenSamplers, (void**)&rGenSam}, {"glDeleteSamplers", w_glDeleteSamplers, (void**)&rDelSam},
 {"glGenTransformFeedbacks", w_glGenTransformFeedbacks, (void**)&rGenTfb}, {"glDeleteTransformFeedbacks", w_glDeleteTransformFeedbacks, (void**)&rDelTfb},
 {"glCreateProgram", w_glCreateProgram, (void**)&rCreateProg}, {"glDeleteProgram", w_glDeleteProgram, (void**)&rDelProg},
 {"glCreateShader", w_glCreateShader, (void**)&rCreateSh}, {"glDeleteShader", w_glDeleteShader, (void**)&rDelSh},
 {"glBufferData", w_glBufferData, (void**)&rBufData}, {"glXSwapBuffers", w_glXSwapBuffers, (void**)&rSwap},
};
static void *wrap(const char *name, void *real) {
  for (unsigned i = 0; i < sizeof(TAB) / sizeof(TAB[0]); i++) if (!strcmp(name, TAB[i].n)) { if (real) *TAB[i].real = real; return real ? TAB[i].w : real; }
  return real;
}
void *glXGetProcAddress(const char *n) { if (!real_glx) real_glx = real_dlsym(RTLD_NEXT, "glXGetProcAddress"); return wrap(n, real_glx(n)); }
void *glXGetProcAddressARB(const unsigned char *n) { if (!real_glxarb) real_glxarb = real_dlsym(RTLD_NEXT, "glXGetProcAddressARB"); return wrap((const char *)n, real_glxarb(n)); }
void *eglGetProcAddress(const char *n) { if (!real_egl) real_egl = real_dlsym(RTLD_NEXT, "eglGetProcAddress"); return wrap(n, real_egl(n)); }
void *dlsym(void *h, const char *name) {
  if (!real_dlsym) real_dlsym = dlvsym(RTLD_NEXT, "dlsym", "GLIBC_2.2.5");
  if (!strcmp(name, "glXGetProcAddress")) { real_glx = real_dlsym(h, name); return real_glx ? (void *)glXGetProcAddress : 0; }
  if (!strcmp(name, "glXGetProcAddressARB")) { real_glxarb = real_dlsym(h, name); return real_glxarb ? (void *)glXGetProcAddressARB : 0; }
  if (!strcmp(name, "eglGetProcAddress")) { real_egl = real_dlsym(h, name); return real_egl ? (void *)eglGetProcAddress : 0; }
  void *p = real_dlsym(h, name);
  return wrap(name, p);
}
