function [ WHOTemplate, HOGTemplate ] = WHOTemplateDecompNonEmptyCell( im, Mu, Gamma, nCellLimit, lambda, padding, hog_cell_threshold)
%WHOTEMPLATEDECOMP Summary of this function goes here
%   Detailed explanation goes here
% Nrow = N1

if nargin < 7
  hog_cell_threshold = 1.5 * 10^0;
end

if nargin < 6
  padding = 50;
end

%%%%%%%% Get HOG template

% create white background padding
paddedIm = padarray(im2double(im), [padding, padding, 0]);
paddedIm(:,1:padding,:) = 1;
paddedIm(:,end-padding+1 : end, :) = 1;
paddedIm(1:padding,:,:) = 1;
paddedIm(end-padding+1 : end, :, :) = 1;

% bounding box coordinate x1, y1, x2, y2
bbox = [1 1 size(im,2) size(im,1)] + padding;

% TODO replace it
HOGTemplate = dwot_initialize_template(paddedIm, bbox, nCellLimit);

%%%%%%%% WHO conversion using matrix decomposition

HOGTemplatesz = size(HOGTemplate);
wHeight = HOGTemplatesz(1);
wWidth = HOGTemplatesz(2);
HOGDim = HOGTemplatesz(3);
nonEmptyCells = (sum(abs(HOGTemplate),3) > hog_cell_threshold);
idxNonEmptyCells = find(nonEmptyCells);
[nonEmptyRows,nonEmptyCols] = ind2sub([wHeight, wWidth], idxNonEmptyCells);

n_non_empty_cells = numel(nonEmptyRows);

sigmaDim = n_non_empty_cells * HOGDim;

Sigma = zeros(sigmaDim);

for cellIdx = 1:n_non_empty_cells
  rowIdx = nonEmptyRows(cellIdx); % sub2ind([wHeight, wWidth],i,j);
  colIdx = nonEmptyCols(cellIdx);
  for otherCellIdx = 1:n_non_empty_cells
    otherRowIdx = nonEmptyRows(otherCellIdx);
    otherColIdx = nonEmptyCols(otherCellIdx);
    gammaRowIdx = abs(rowIdx - otherRowIdx) + 1;
    gammaColIdx = abs(colIdx - otherColIdx) + 1;
    Sigma((cellIdx-1)*HOGDim + 1:cellIdx * HOGDim, (otherCellIdx-1)*HOGDim + 1:otherCellIdx*HOGDim) = ...
        Gamma((gammaRowIdx-1)*HOGDim + 1 : gammaRowIdx*HOGDim , (gammaColIdx - 1)*HOGDim + 1 : gammaColIdx*HOGDim);
  end
end

success = false;
firstTry = true;
while ~success
  if firstTry
      Sigma = Sigma + lambda * eye(size(Sigma));
  else
      Sigma = Sigma + 0.01 * eye(size(Sigma));
  end
  firstTry = false;
  [R, p] = chol(Sigma);
  if p == 0
  	success = true;
  else
  	display('trying decomposition again');
  end
end

muSwapDim = permute(Mu,[2 3 1]);

centeredHOG = bsxfun(@minus, HOGTemplate, muSwapDim);
permHOG = permute(centeredHOG,[3 1 2]); % [HOGDim, Nrow, Ncol] = HOGDim, N1, N2
onlyNonEmptyIdx = cell2mat(arrayfun(@(x) x + (1:HOGDim)', HOGDim * (idxNonEmptyCells - 1),'UniformOutput',false));
nonEmptyHOG = permHOG(onlyNonEmptyIdx);

%%%%%%%%%%%%%%%%%%%%%%%%%%
% nonEmptyCells = (sum(HOGTemplate,3) > hog_cell_threshold);
% centeredWs = bsxfun(@times,bsxfun(@minus,HOGTemplate,muSwapDim),nonEmptyCells);
%%%%%%%%%%%%%%%%%%%%%%%%%%

sigInvCenteredWs = R\(R'\nonEmptyHOG);
WHOTemplate = zeros(prod(HOGTemplatesz),1);
WHOTemplate(onlyNonEmptyIdx) = sigInvCenteredWs;
WHOTemplate =  reshape(WHOTemplate,[HOGDim, wHeight, wWidth]);
WHOTemplate = permute(WHOTemplate,[2,3,1]);


end