#!/usr/bin/env python3
"""Generate a small C contract harness for the function exercises in exam-practice."""
import sys
from pathlib import Path

COMMON = r'''#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <unistd.h>
#define CHECK(x) do { if (!(x)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #x); return 1; } } while (0)
static inline int capture_start(FILE **tmp, int *saved) {
    fflush(stdout); *tmp = tmpfile(); if (!*tmp) return 0;
    *saved = dup(STDOUT_FILENO); if (*saved < 0) return 0;
    return dup2(fileno(*tmp), STDOUT_FILENO) >= 0;
}
static inline int capture_end(FILE *tmp, int saved, char *out, size_t cap) {
    fflush(stdout); if (dup2(saved, STDOUT_FILENO) < 0) return 0;
    close(saved); rewind(tmp); size_t n = fread(out, 1, cap - 1, tmp); out[n] = 0;
    fclose(tmp); return 1;
}
'''

CASES = {
"ft_ft": ("void ft_ft(int *);", r'''int main(void) { int n = -7; ft_ft(&n); CHECK(n == 42); return 0; }'''),
"ft_inc": ("void ft_inc(int *);", r'''int main(void) { int n = -7; ft_inc(&n); CHECK(n == -6); n = 41; ft_inc(&n); CHECK(n == 42); return 0; }'''),
"ft_dec": ("void ft_dec(int *);", r'''int main(void) { int n = 7; ft_dec(&n); CHECK(n == 6); n = -41; ft_dec(&n); CHECK(n == -42); return 0; }'''),
"ft_add": ("void ft_add(int, int *);", r'''int main(void) { int n = 7; ft_add(5, &n); CHECK(n == 12); n = -7; ft_add(5, &n); CHECK(n == -2); return 0; }'''),
"ft_mul": ("void ft_mul(int, int *);", r'''int main(void) { int n = 7; ft_mul(-3, &n); CHECK(n == -21); n = 0; ft_mul(42, &n); CHECK(n == 0); return 0; }'''),
"ft_div": ("void ft_div(int, int *);", r'''int main(void) { int n = 84; ft_div(2, &n); CHECK(n == 42); n = -21; ft_div(3, &n); CHECK(n == -7); return 0; }'''),
"ft_sub": ("void ft_subtract(int, int *);", r'''extern void ft_sub(int, int *) __attribute__((weak));
extern void ft_subtract(int, int *) __attribute__((weak));
int main(void) { int n = 12; if (ft_subtract) ft_subtract(5, &n); else if (ft_sub) ft_sub(5, &n); else return 1; CHECK(n == 7); return 0; }'''),
"ft_subtract": ("void ft_subtract(int, int *);", r'''int main(void) { int n = 12; ft_subtract(5, &n); CHECK(n == 7); return 0; }'''),
"ft_swap": ("void ft_swap(int *, int *);", r'''int main(void) { int a = 4, b = -9; ft_swap(&a, &b); CHECK(a == -9 && b == 4); return 0; }'''),
"ft_strlen": ("int ft_strlen(char *);", r'''int main(void) { CHECK(ft_strlen("") == 0); CHECK(ft_strlen("hello") == 5); CHECK(ft_strlen("a b\t") == 4); return 0; }'''),
"count_alen": ("int count_alen(char *);", r'''int main(void) { CHECK(count_alen("xyzab") == 3); CHECK(count_alen("xyz") == 3); CHECK(count_alen("") == 0); return 0; }'''),
"count_words": ("int count_words(char *);", r'''int main(void) { CHECK(count_words("") == 0); CHECK(count_words(" \t ") == 0); CHECK(count_words("one two\tthree") == 3); CHECK(count_words("one\ntwo") == 1); CHECK(count_words("  one   two  ") == 2); return 0; }'''),
"occ_a": ("int occ_a(char *);", r'''int main(void) { CHECK(occ_a("") == 0); CHECK(occ_a("AbaA") == 2); CHECK(occ_a("xyz") == 0); return 0; }'''),
"occ_z": ("int occ_z(char *);", r'''int main(void) { CHECK(occ_z("") == 0); CHECK(occ_z("ZazZ") == 2); CHECK(occ_z("abc") == 0); return 0; }'''),
"ft_strcmp": ("int ft_strcmp(char *, char *);", r'''int main(void) { CHECK(ft_strcmp("same", "same") == 0); CHECK(ft_strcmp("abc", "abd") < 0); CHECK(ft_strcmp("abd", "abc") > 0); CHECK(ft_strcmp("", "a") < 0); return 0; }'''),
"ft_strcpy": ("char *ft_strcpy(char *, char *);", r'''int main(void) { char d[16]; char *r = ft_strcpy(d, "hello"); CHECK(r == d); CHECK(strcmp(d, "hello") == 0); ft_strcpy(d, ""); CHECK(d[0] == 0); return 0; }'''),
"ft_strrev": ("char *ft_strrev(char *);", r'''int main(void) { char a[] = "abcd", b[] = "x", c[] = ""; CHECK(ft_strrev(a) == a); CHECK(strcmp(a, "dcba") == 0); CHECK(strcmp(ft_strrev(b), "x") == 0); CHECK(strcmp(ft_strrev(c), "") == 0); return 0; }'''),
"swap_cases": ("char *swap_cases(char *);", r'''int main(void) { char s[] = "aB-9 z"; CHECK(swap_cases(s) == s); CHECK(strcmp(s, "Ab-9 Z") == 0); return 0; }'''),
"ft_atoi": ("int ft_atoi(char *);", r'''int main(void) { CHECK(ft_atoi("42") == 42); CHECK(ft_atoi("  -42xyz") == -42); CHECK(ft_atoi("+17") == 17); CHECK(ft_atoi("0") == 0); return 0; }'''),
"ft_itoa": ("char *ft_itoa(int);", r'''int main(void) { char *s = ft_itoa(0); CHECK(s && strcmp(s, "0") == 0); free(s); s = ft_itoa(-42); CHECK(s && strcmp(s, "-42") == 0); free(s); s = ft_itoa(INT_MIN); CHECK(s && strcmp(s, "-2147483648") == 0); free(s); return 0; }'''),
"ft_range": ("int *ft_range(int, int);", r'''static int check(int a, int b, const int *want, int n) { int *p = ft_range(a,b); if (!p) return 0; int ok = 1; for (int i=0;i<n;i++) if (p[i] != want[i]) ok=0; free(p); return ok; }
int main(void) { int a[]={1,2,3}, b[]={0,-1,-2,-3}, c[]={4}; CHECK(check(1,3,a,3)); CHECK(check(0,-3,b,4)); CHECK(check(4,4,c,1)); return 0; }'''),
"ft_rrange": ("int *ft_rrange(int, int);", r'''static int check(int a, int b, const int *want, int n) { int *p = ft_rrange(a,b); if (!p) return 0; int ok = 1; for (int i=0;i<n;i++) if (p[i] != want[i]) ok=0; free(p); return ok; }
int main(void) { int a[]={3,2,1}, b[]={-3,-2,-1,0}, c[]={4}; CHECK(check(1,3,a,3)); CHECK(check(0,-3,b,4)); CHECK(check(4,4,c,1)); return 0; }'''),
"ft_split": ("char **ft_split(char *);", r'''static int eq(char **p, const char **w, int n) { if (!p) return 0; int i=0; for (; i<n && p[i]; i++) if (strcmp(p[i],w[i])) return 0; int ok=(i==n && p[i]==NULL); for (i=0;p[i];i++) free(p[i]); free(p); return ok; }
int main(void) { const char *a[]={"one","two","three"}; const char *b[]={"alpha"}; CHECK(eq(ft_split("  one\ttwo\nthree  "),a,3)); CHECK(eq(ft_split("alpha"),b,1)); CHECK(eq(ft_split(" \t\n "),b,0)); return 0; }'''),
"ft_putstr": ("void ft_putstr(char *);", r'''int main(void) { FILE *f; int fd; char out[64]; CHECK(capture_start(&f,&fd)); ft_putstr("hello\n"); CHECK(capture_end(f,fd,out,sizeof out)); CHECK(strcmp(out,"hello\n")==0); return 0; }'''),
"write_string": ("void write_string(char *);", r'''int main(void) { FILE *f; int fd; char out[64]; CHECK(capture_start(&f,&fd)); write_string("abc"); CHECK(capture_end(f,fd,out,sizeof out)); CHECK(strcmp(out,"abc")==0); return 0; }'''),
"ft_putnbr": ("void ft_putnbr(int);", r'''int main(void) { FILE *f; int fd; char out[64]; CHECK(capture_start(&f,&fd)); ft_putnbr(INT_MIN); CHECK(capture_end(f,fd,out,sizeof out)); CHECK(strcmp(out,"-2147483648")==0); CHECK(capture_start(&f,&fd)); ft_putnbr(0); CHECK(capture_end(f,fd,out,sizeof out)); CHECK(strcmp(out,"0")==0); return 0; }'''),
"sort_list": ("#include \"list.h\"\nt_list *sort_list(t_list *, int (*)(int,int));\nstatic int ascending(int a,int b){return a<=b;}\n", r'''int main(void) { int v[]={4,1,3,1}; t_list n4={v[3],0},n3={v[2],&n4},n2={v[1],&n3},n1={v[0],&n2}; t_list *p=sort_list(&n1,ascending); int w[]={1,1,3,4}; for(int i=0;i<4;i++){CHECK(p!=NULL); CHECK(p->data==w[i]); p=p->next;} CHECK(p==NULL); CHECK(sort_list(NULL,ascending)==NULL); return 0; }'''),
"ft_list_remove_if": ("#include \"ft_list.h\"\nvoid ft_list_remove_if(t_list **, void *, int (*)(void *,void *));\nstatic int cmp(void *a,void *b){return strcmp(a,b);}\n", r'''int main(void) { t_list *c=malloc(sizeof(*c)), *b=malloc(sizeof(*b)), *a=malloc(sizeof(*a)); CHECK(a && b && c); c->data="keep"; c->next=NULL; b->data="drop"; b->next=c; a->data="drop"; a->next=b; t_list *p=a; ft_list_remove_if(&p,"drop",cmp); CHECK(p==c && strcmp(p->data,"keep")==0 && p->next==NULL); ft_list_remove_if(&p,"keep",cmp); CHECK(p==NULL); return 0; }'''),
}

HEADERS = {
    "sort_list": "typedef struct s_list t_list;\nstruct s_list { int data; t_list *next; };\n",
    "ft_list_remove_if": "typedef struct s_list { struct s_list *next; void *data; } t_list;\n",
}

def main():
    if len(sys.argv) != 3:
        return 2
    name, output = sys.argv[1:]
    if name not in CASES:
        return 3
    decl, body = CASES[name]
    out = Path(output)
    out.write_text(COMMON + "\n" + decl + "\n" + body + "\n")
    if name in HEADERS:
        header = "ft_list.h" if name == "ft_list_remove_if" else "list.h"
        (out.parent / header).write_text(HEADERS[name])
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
