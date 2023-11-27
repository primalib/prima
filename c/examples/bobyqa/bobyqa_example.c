// An example to illustrate the use of BOBYQA.

#include "prima/prima.h"
#include <stdio.h>
#include <math.h>

static void fun(const double x[], double *f, const void *data)
{
  const double x1 = x[0];
  const double x2 = x[1];
  *f = 5*(x1-3)*(x1-3)+7*(x2-2)*(x2-2)+0.1*(x1+x2)-10;
  (void)data;
}

int main(int argc, char * argv[])
{
  (void)argc;
  (void)argv;
  const int n = 2;
  double x0[2] = {0.0, 0.0};
  prima_problem problem;
  prima_init_problem(&problem, n);
  problem.x0 = x0;
  problem.calfun = &fun;
  prima_options options;
  prima_init_options(&options);
  options.iprint = PRIMA_MSG_EXIT;
  options.rhoend= 1e-3;
  options.maxfun = 200*n;
  prima_result result;
  const int rc = prima_minimize(PRIMA_BOBYQA, &problem, &options, &result);
  printf("x*={%g, %g} rc=%d msg='%s' evals=%d\n", result.x[0], result.x[1], rc, result.message, result.nf);
  prima_free_problem(&problem);
  prima_free_result(&result);
  return (fabs(result.x[0]-3)>2e-2 || fabs(result.x[1]-2)>2e-2);
}
