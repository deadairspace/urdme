function aem
%AEM URDME All Events Method solver.
%   The URDME AEM solver is an implementation of the "All Events
%   Method" [1] and hence has the ability to compare trajectories
%   under parameter perturbations in a strong sense.
%
%   The AEM solver supports the same arguments as the NSM solver, see
%   NSM.
%
%   Example:
%     % a 1D linear birth-death model in 3 volumes
%     clear umod;
%
%     % diffusion
%     umod.D = sparse([-1 1 0; 1 -2 1; 0 1 -1])';
%
%     % scaling
%     umod.vol = ones(1,3);
%     umod.sd = ones(1,3);
%
%     % linear birth-death model
%     [K,I,N,G] = rparse_inline({'@ > k > X','X > mu > @'}, ...
%                               {'X'},{'k' 1e2 'mu' 1e1});
%     umod.N = N;
%     umod.G = G;
%     umod.solverargs = {'K' K 'I' I};
%
%     % initial state u0 and time interval
%     umod.u0 = zeros(1,3);
%     umod.tspan = linspace(0,1,100);
%
%     % compile and solve once...
%     umod = urdme(umod,'solver','aem','seed',123);
%     U1 = umod.U;
%
%     % ...solve twice with a perturbation
%     umod.solverargs{2} = umod.solverargs{2}*1.01; % 1% perturbation
%     umod.compile = 0;
%     umod = urdme(umod);
%     U2 = umod.U;
%
%     % plot total number of molecules
%     figure, stairs(umod.tspan,sum(U1),'b'), hold on,
%     stairs(umod.tspan,sum(U2),'r');
%
%   See also NSM, RPARSE_INLINE.
%
%   References:
%     [1] P. Bauer and S. Engblom: "Sensitivity estimation and inverse
%     problems in spatial stochastic models of chemical kinetics",
%     pp. 519--527 in A. Abdulle, S. Deparis, D. Kressner, F. Nobile
%     and M. Picasso (editors): "Numerical Mathematics and Advanced
%     Applications: ENUMATH 2013", vol 103 of Lecture Notes in
%     Computational Science and Engineering, Springer (2015).
                
% S. Engblom 2017-02-24

error('This file should not be called directly.');
