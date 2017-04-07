function [F,N,G,L] = rparse(r,spec,rate,filename)
%RPARSE URDME reaction propensity parser.
%   F = RPARSE(R,SPEC,RATE) constructs a valid code F for the
%   reactions R with species SPEC and rate-constants RATE.
%
%   R is a cell-vector containing reactions on the form
%      'X+Y+... > F(...) > U+V+...'
%   The left (right) side is the initial (final) state and the propensity is
%   written in between the '>'-signs. The special symbol '@' is reserved for
%   the empty set. For example,
%     R = {'X+Y > mu*X*Y > Z' 'Z > k*Z > X+Y'}
%   expresses a reversible bimolecular reaction.
%
%   SPEC contains the names of the involved species, for example,
%     SPEC = {'X' 'Y' 'Z'}.
%
%   RATE contains the names of the rate-constants followed by their
%   values, for example,
%     RATE = {'k' 1 'mu' 0.5e-7}.
%
%   F = RPARSE(R,SPEC,RATE,FILENAME) also writes the result to the
%   file FILENAME (a string). This file, if already existing, is only
%   overwritten provided that is was originally created by RPARSE. The
%   resulting C-file is ready to be compiled and linked with any of
%   the solvers in URDME.
%
%   [F,N,G] = RPARSE(...) additionally outputs the stoichiometric
%   matrix N and the dependency graph G, to be placed in the fields
%   umod.N and umod.G of the URDME structure.
%
%   [F,N,G,L] = RPARSE(...) additionally outputs a LaTeX-code L for
%   the reactions.
%
%   Note: this is a utility function and limited error-checking is
%   performed.
%
%   Examples:
%     % linear birth-death example
%     C1 = rparse({'@ > k*vol > X' 'X > mu*X > @' },{'X'},{'k' 1 'mu' 1e-3});
%
%     % 2 reacting species
%     [C2,N,G,L] = rparse({'@ > k*vol > X' ...
%                          '@ > k*vol > Y' ...
%                          'X > mu*X > @' ...
%                          'Y > mu*Y > @' ...
%                          'X+Y > kk*X*Y/vol > @'}, ...
%                         {'X' 'Y'},{'k' 1 'mu' 1e-3 'kk' 1e-4});
%
%   See also RPARSE_INLINE, URDME, NSM.

% S. Engblom 2017-03-01 (URDME 1.3)
% S. Engblom 2016-01-07 (empty default rate)
% S. Engblom 2007-04-06

r = reshape(r,1,[]);
spec = reshape(spec,1,[]);
rate = reshape(rate,1,[]);
ratedef = rate(2:2:end);
rate = rate(1:2:end);

% some checks
if ~all(cellfun('isclass',spec,'char'))
  error('Species must be specified in a cell-vector of strings.');
elseif any(size(rate) ~= size(ratedef)) || ...
      ~all(cellfun('isclass',rate,'char')) || ...
      ~all(cellfun('isclass',ratedef,'double'))
  error('Rates must be specified as property/value-pairs.');
elseif size(unique(spec),2) ~= size(spec,2) || ...
      size(unique(rate),2) ~= size(rate,2)
  error('Species and rates must consist of unique names.');
elseif ~isempty(intersect(spec,rate))
  error('Species and rates must use different names.');
end
reserved = {'xstate' 'time' 'vol' 'ldata' 'gdata' 'sd'};
res1 = intersect(spec,reserved);
res2 = intersect(rate,reserved);
if ~isempty(res1)
  error(sprintf(['Species should not clash with propensity ' ...
                 'input arguments: ''%s''.'],res1{1}));
elseif ~isempty(res2)
  error(sprintf(['Rates should not clash with propensity ' ...
                 'input arguments: ''%s''.'],res2{1}));
end

N = sparse(size(spec,2),size(r,2));
H = sparse(size(spec,2),size(r,2));
for i = 1:size(r,2)
  % separate reaction r{i} according to 'from > propensity > dest'
  ixgt1 = find(r{i} == '>',1);
  ixgt2 = find(r{i} == '>',1,'last');
  if isempty(ixgt1) || isempty(ixgt2) || ixgt1 == ixgt2
    error('Each reaction must contain exactly 2 ''>''.');
  end
  from = r{i}(1:ixgt1-1);
  prop = r{i}(ixgt1+1:ixgt2-1);
  dest = r{i}(ixgt2+1:end);

  % remove spaces and the empty set
  from = from(from ~= ' ' & from ~= '@');
  prop = prop(prop ~= ' ');
  dest = dest(dest ~= ' ' & dest ~= '@');

  % split from and dest into 'spec1 + spec2 + ..'
  from = l_split(from,'+');
  dest = l_split(dest,'+');

  % assign each species its number according to the ordering in spec
  [foo,ifrom] = ismember(from,spec);
  [foo,idest] = ismember(dest,spec);
  if any(ifrom == 0)
    error(['Unknown species ''' char(from{find(ifrom == 0,1,'first')}) ...
           ''' in reaction #' num2str(i) '.']);
  end
  if any(idest == 0)
    error(['Unknown species ''' char(dest{find(idest == 0,1,'first')}) ...
           ''' in reaction #' num2str(i) '.']);
  end

  % the corresponding column of the stoichiometric matrix is now known
  N(:,i) = sparse(ifrom,1,-1,size(spec,2),1)+ ...
           sparse(idest,1,1,size(spec,2),1);

  % search for species and rates in the propensity, rewrite as
  % 'xstate[<species>]', but keep rate constants
  [rprop{i},dep] = l_rewriteprop(prop,spec,rate);

  % the contribution to the dependency graph is now known
  H(:,i) = sparse(dep,1,1,size(spec,2),1);
end

% after finding out the stoichiometric matrix we can converge on G
G = [H' H'*abs(N)]; % [diffusion reaction]-parts of G
G = double(G ~= 0);

% heading
F= ['/* [Remove/modify this line not to overwrite this file] */\n'];
F = [F '/* Generated by RPARSE ' datestr(now,'yyyy-mm-dd HH:MM') ' */\n\n'];
F = [F '/* Reactions:\n'];
for i = 1:size(r,2)
  F = [F '     ' char(r{i}) '\n'];
end
F = [F '*/\n\n'];

% includes
F = [F '#include "propensities.h"\n' '#include "report.h"\n\n'];

% species enum
if size(spec,2) > 0
  F = [F 'enum Species {'];
  for i = 1:size(spec,2)
    F = [F sprintf('\n  %s,',char(spec{i}))];
  end
  F(end) = [];
  F = [F '\n};\n\n'];
end

% number of reactions
F = [F sprintf('const int NR = %d; /* number of reactions */\n\n', ...
               size(N,2))];

% rate constants
F = [F '/* rate constants */\n'];
for i = 1:size(rate,2)
  F = [F sprintf('const double %s = %g;\n',rate{i},ratedef{i})];
end
F = [F '\n'];

% declaration of propensity functions
F = [F '/* forward declaration */\n'];
for i = 1:size(r,2)
  F = [F sprintf(['double rFun%d(const int *xstate,double time,double vol,\n' ...
                  '             const double *ldata,' ...
                  'const double *gdata,int sd);\n'],i)];
end
F = [F '\n'];

% static propensity vector
F = [F '/* static propensity vector */\n'];
F = [F 'static PropensityFun ptr[] = {'];
for i = 1:size(r,2)
  F = [F sprintf('rFun%d,',i)];
end
F(end) = [];
F = [F '};\n\n'];

% definition of propensities
F = [F '/* propensity definitions */\n'];
for i = 1:size(r,2)
  F = [F sprintf(['double rFun%d(const int *xstate,double time,double vol,\n' ...
                  '             const double *ldata,' ...
                  'const double *gdata,int sd)\n{\n'],i)];
  F = [F sprintf('  return %s;\n}\n\n',rprop{i})];
end

% allocation/deallocation
F = [F '/* URDME solver interface */\n'];
F = [F 'PropensityFun *ALLOC_propensities(size_t Mreactions)\n'];
F = [F '{\n'];
F = [F '  if (Mreactions > NR) PERROR("Wrong number of reactions.");\n'];
F = [F '  return ptr;\n}\n\n'];

F = [F 'void FREE_propensities(PropensityFun *ptr)\n'];
F = [F '{ /* do nothing since a static array was used */ }\n\n'];

if nargin > 3
  % check if file already exists
  if exist(filename,'file')
    [fid,msg] = fopen(filename,'rt');
    if fid == -1, error(msg); end
    s = fgets(fid);
    if ~strncmp(s,'/* [Remove/modify this line not to overwrite this file] */',58)
      warning('Will not overwrite existing file if not created by RPARSE');
      filename = '';
    end
    fclose(fid);
  end

  % write to file
  if ~isempty(filename)
    [fid,msg] = fopen(filename,'wt');
    if fid == -1, error(msg); end
    fprintf(fid,F);
    fclose(fid);
  end
end

F = sprintf(F);

% LaTeX output
if nargout > 3
  L = ['\\begin{align}\n' ...
       '  \\left. \\begin{array}{rcl}\n'];
  for i = 1:size(r,2)
    ixgt = find(r{i} == '>');
    from = r{i}(1:ixgt(1)-1);
    prop = r{i}(ixgt(1)+1:ixgt(2)-1);
    dest = r{i}(ixgt(2)+1:end);
    from = strrep(from,'@','\\emptyset');
    dest = strrep(dest,'@','\\emptyset');
    L = [L '    ' from ' & \\xrightarrow{' prop '} & ' dest '\t\\\\\n'];
  end

  L = [L '  \\end{array} \\right\\}.\n' ...
       '\\end{align}'];
  L = sprintf(L);
end

%---------------------------------------------------------------------------
function c = l_split(s,d)
%L_SPLIT Split string.
%   C = L_SPLIT(S,D) splits the string S at each occurrence of the character
%   D and returns all intermediate strings in the cell-vector C.
%  
%   Example:
%     l_split('A+B/C + D','+') returns {'A' 'B/C ' ' D'}

% handle empty case
if isempty(s), c = {}; return; end

ii = [0 find(s == d) size(s,2)+1];
c = cell(1,size(ii,2)-1);
for i = 1:size(ii,2)-1
  c{i} = s(ii(i)+1:ii(i+1)-1);
end

%---------------------------------------------------------------------------
function [prop,dep] = l_rewriteprop(prop,spec,rate)
%L_REWRITEPROP Rewrite propensity.
%   [RPROP,DEP] = L_REWRITEPROP(PROP,SPEC,RATE) rewrites the
%   propensity PROP by replacing all species by 'xstate[SPEC{j}]'
%   where j is the numbering in SPEC. On return, DEP contains all
%   species upon which the propensity depends.

% switch to an intermediate representation using '$[.]', replacing
% larger strings first in order to avoid changing e.g., 'BA' with
% '$[1]A' whenever 'B' and 'BA' are two different species/rates
symbols = [spec; ...
           mat2cell(1:size(spec,2),1,ones(1,size(spec,2)))];
% rates have a negative sign:
symbols = [symbols [rate; ...
                    mat2cell(-(1:size(rate,2)),1,ones(1,size(rate,2)))]];
[foo,i] = sort(cellfun('prodofsize',symbols(1,:)));
symbols = symbols(:,i);
dep = zeros(1,0);
for j = size(symbols,2):-1:1
  if strfind(prop,symbols{1,j})
    if symbols{2,j} > 0
      % dependent on species
      dep = [dep symbols{2,j}];
    end
    % replace with $[<nn>]
    prop = strrep(prop,symbols{1,j},['$[' num2str(symbols{2,j}) ']']);
  end
end

% replace back names (an enum is used for the species in the C-code,
% for rates this is just a declared constant)
offset = 1;
while 1
  % find prop(i:j) = '$[<nn>]'
  i = find(prop(offset:end) == '$',1);
  if isempty(i), break; end
  i = i+offset-1;
  j = find(prop(i+2:end) == ']',1);
  j = j+i+2-1;
  n = str2num(prop(i+2:j-1));
  if n > 0
    % species
    prop = [prop(1:i+1) spec{n} prop(j:end)];
    offset = i+2;
  else
    % rates
    prop = [prop(1:i-1) rate{-n} prop(j+1:end)];
    offset = i;
  end
end

% final replace
prop = strrep(prop,'$','xstate');

%---------------------------------------------------------------------------
