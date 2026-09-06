/* The page's expander never runs out of memory in a way it can recover from:
   an allocation failure traps instead of unwinding. */
#ifndef OLLIN_SHIM_SETJMP_H
#define OLLIN_SHIM_SETJMP_H
typedef int jmp_buf[1];
static inline int setjmp(jmp_buf env) { (void)env; return 0; }
static inline void longjmp(jmp_buf env, int value) { (void)env; (void)value; __builtin_trap(); }
#endif
