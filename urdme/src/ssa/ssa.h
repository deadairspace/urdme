/* ssa.h - Header file for SSA-solver. */

/* S. Engblom 2017-02-22 */

#ifndef SSA_H
#define SSA_H

#include "report.h"

void ssa(const PropensityFun *rfun,
	 const int *u0,
	 const size_t *irN,const size_t *jcN,const int *prN,
	 const size_t *irG,const size_t *jcG,
	 const double *tspan,const size_t tlen,int *U,
	 const double *vol,const double *ldata,const double *gdata,
	 const int *sd,const size_t Ncells,
	 const size_t Mspecies,const size_t Mreactions,
	 const size_t dsize,
	 int report_level,
	 const double *K,const int *I,
	 const size_t *jcS,const int *prS,const size_t M1
	 );

#endif /* SSA_H */
